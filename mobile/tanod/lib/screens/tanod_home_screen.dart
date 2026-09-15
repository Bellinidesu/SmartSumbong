// SmartSumbong — Tanod home.
//
// Figma: HOME - TANOD, HOME - TANOD - RESPONDED, HOME - TANOD - MISSED.
//
// Three things on one screen: who you are, whether you are available,
// and what is waiting. Duty status is a dropdown here rather than its
// own tab, which is the design's call and a good one — a tanod checks
// their queue far more often than they change shift, and burying the
// dispatch list behind a tab would put the queue one tap further away
// than the thing that only happens twice a day.
//
// The Submit button is kept rather than applying on selection. Going
// off duty by mistap costs the barangay a responder without anyone
// noticing; an extra tap is cheap against that.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/tanod_nav_bar.dart';
import 'dispatch_order.dart';
import 'tickets_screen.dart';

/// Mirrors `public.duty_state` in 0001.
enum DutyState {
  onDuty('on_duty', 'On Duty'),
  breakTime('break', 'Break'),
  lunch('lunch', 'Lunch'),
  offline('offline', 'Offline');

  const DutyState(this.wire, this.label);

  final String wire;
  final String label;

  static DutyState? parse(String? w) {
    for (final s in DutyState.values) {
      if (s.wire == w) return s;
    }
    return null;
  }
}

/// Which half of Activity History a past dispatch belongs to.
///
/// Responded and Missed are not opinions — they are dispatch states.
/// accepted and resolved mean the tanod answered; expired means the
/// accept window elapsed with no response and 0006 alerted the admin.
/// A rerouted ticket is neither: it was answered, with a reason, and it
/// belongs in neither column.
enum ActivityKind { responded, missed }

class TanodHomeScreen extends StatefulWidget {
  const TanodHomeScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<TanodHomeScreen> createState() => _TanodHomeScreenState();
}

class _TanodHomeScreenState extends State<TanodHomeScreen> {
  String? _firstName;
  DutyState? _status;
  DutyState? _picked;

  List<Ticket> _incoming = const [];
  List<_ActivityEntry> _activity = const [];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _locationNote;

  // Found during a QA pass on the "robust GIS" this app leans on:
  // _pushLocation() only ever ran once, at the moment duty flipped on.
  // location_is_fresh() (0005) discards anything older than 15 minutes,
  // so a tanod who stayed on duty without reopening this exact screen
  // silently dropped out of nearest_available_tanod's candidate pool —
  // no error, no warning, just never dispatched. This re-pushes on a
  // timer for as long as Home stays open and the tanod is on duty. It is
  // NOT a background fix: closing the app or locking the screen still
  // stops it, the same as before. A real background fix needs a
  // foreground service (flutter_foreground_task or equivalent), which
  // this pass deliberately did not add unverified — see the deploy
  // notes for why.
  //
  // Cadence tightened 15 Sep 2026 (10 minutes -> 30 seconds) for live
  // admin-side tanod tracking (0059): update_my_location() now also
  // appends to tanod_locations for the admin map's live layer and
  // pathing heatmap, so the interval this fires at is the resolution of
  // both. Still on-duty-only and still foreground-only — same envelope
  // as before, just finer-grained inside it.
  Timer? _locationTimer;

  // Live updates (8 Sep 2026 — mirrors resident's home_screen.dart /
  // reports_screen.dart). Home shows Incoming Dispatch and Alert
  // History straight off `dispatches`, and until now this screen only
  // ever reloaded on initState or a manual pull — an admin dispatch, an
  // accept elsewhere, or an expiry sat unseen until the tanod happened
  // to pull down. `dispatches` has been in the realtime publication
  // since 0004 for the admin map, so this rides along for free at the
  // database level; the only new cost is the one open channel while
  // Home is on screen.
  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _liveDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    super.dispose();
  }

  /// One channel per tanod, opened once the first successful [_load]
  /// confirms who they are — never re-opened by a later, live-triggered
  /// [_load], since [_liveChannel] is already set by then.
  void _subscribeLive(String uid) {
    if (_liveChannel != null) return;
    _liveChannel = Supabase.instance.client
        .channel('tanod-home-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dispatches',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tanod_id',
          value: uid,
        ),
        callback: (_) => _scheduleLiveReload(),
      )
      ..subscribe();
  }

  /// A single dispatch action (accept, resolve, expire) can touch more
  /// than one row in the same transaction — debounced so that lands as
  /// one reload, not several. Same 400ms window resident uses.
  void _scheduleLiveReload() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  void _syncLocationTimer() {
    if (_status == DutyState.onDuty) {
      _locationTimer ??= Timer.periodic(
        const Duration(seconds: 30),
        (_) => _pushLocation(),
      );
    } else {
      _locationTimer?.cancel();
      _locationTimer = null;
    }
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

      _subscribeLive(uid);

      final me = await client
          .from('users')
          .select('full_name, duty_status')
          .eq('id', uid)
          .single();

      // Live queue: what is waiting for a response or already accepted.
      final open = await client
          .from('dispatches')
          .select('id, report_id, state, accept_due_at, assigned_at, '
              'admin_instructions, '
              'reports(tracking_id, subject, description, due_at)')
          .eq('tanod_id', uid)
          .inFilter('state', ['assigned', 'accepted'])
          .order('assigned_at', ascending: false);

      // Activity History, "in the past 7 days" per the frame. Carries
      // field_report_text and dispatch_media now (9 Sep 2026) so a
      // responded row can show what the tanod actually submitted, not
      // just that they submitted something — see _ActivityEntry below.
      final since = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 7))
          .toIso8601String();
      // No resident name. The frame shows one, but users_self_read is
      // `id = auth.uid() or is_admin()` — a tanod cannot read anyone
      // else's row, so the join would return null in production and
      // errors here. Showing the ticket number instead identifies the
      // case without identifying a person, which is what the anonymous
      // filing option required anyway. Putting names back means
      // loosening that policy, and that is a privacy decision for the
      // barangay rather than a display one.
      final past = await client
          .from('dispatches')
          .select('id, state, assigned_at, accepted_at, resolved_at, '
              'field_report_text, '
              'reports(tracking_id, subject, is_anonymous), '
              'dispatch_media(media_url, mime_type)')
          .eq('tanod_id', uid)
          .inFilter('state', ['accepted', 'resolved', 'expired'])
          .gte('assigned_at', since)
          .order('assigned_at', ascending: false);

      if (!mounted) return;
      final name = (me['full_name'] as String? ?? '').trim();
      setState(() {
        _firstName = name.isEmpty ? null : name.split(' ').first;
        _status = DutyState.parse(me['duty_status'] as String?);
        _picked = _status;
        _incoming = [
          for (final r in open) Ticket.fromRow(r as Map<String, dynamic>),
        ];
        _activity = [
          for (final r in past)
            _ActivityEntry.fromRow(r as Map<String, dynamic>),
        ];
        _loading = false;
      });

      if (_status == DutyState.onDuty) await _pushLocation();
      _syncLocationTimer();
    } on PostgrestException catch (e) {
      // Named rather than swallowed. A malformed select or a policy
      // refusal both land here, and "could not load" tells whoever is
      // testing nothing at all.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.s.homeLoadError(e.message);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.s.homeLoadOffline;
      });
    }
  }

  Future<void> _submitStatus() async {
    final next = _picked;
    if (next == null || _saving) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;
      await client
          .from('users')
          .update({'duty_status': next.wire}).eq('id', uid);

      if (!mounted) return;
      setState(() {
        _status = next;
        _saving = false;
      });

      // After the column is written, never before: update_my_location()
      // only matches rows where duty_status is already 'on_duty'.
      if (next == DutyState.onDuty) {
        await _pushLocation();
      } else if (mounted) {
        setState(() => _locationNote = null);
      }
      _syncLocationTimer();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message.toLowerCase().contains('duty_only_for_tanod')
            ? context.s.homeNotTanod
            : context.s.homeStatusUpdateFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.s.homeStatusUpdateFailed;
      });
    }
  }

  /// Being on duty is not the same as being dispatchable, and neither is
  /// the same as being rankable. nearest_available_tanod() sorts by
  /// distance and location_is_fresh() discards a stale fix, so a tanod
  /// with no position sits in the queue invisible to it. Said out loud
  /// rather than swallowed.
  Future<void> _pushLocation() async {
    if (!mounted) return;
    setState(() => _locationNote = context.s.homeLocationSharing);

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          !await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationNote = context.s.homeLocationOff);
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 15));

      final client = Supabase.instance.client;
      await client.rpc('update_my_location',
          params: {'p_lat': pos.latitude, 'p_lon': pos.longitude});

      // Read it back. The RPC returns void and filters on duty_status,
      // so a no-op is indistinguishable from a success at the call site.
      final uid = client.auth.currentUser!.id;
      final row = await client
          .from('users')
          .select('last_location_at')
          .eq('id', uid)
          .single();
      final ok = (row['last_location_at'] as String?) != null;

      if (!mounted) return;
      setState(() => _locationNote =
          ok ? context.s.homeLocationShared : context.s.homeLocationShareFailed);
    } catch (_) {
      if (mounted) {
        setState(() => _locationNote = context.s.homeLocationShareFailed);
      }
    }
  }

  Future<void> _open(Ticket t) async {
    // A card over this screen, not a push. TANOD - VIEW DISPATCH draws
    // Home still visible behind it.
    if (await showDispatchOrder(context, t)) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      bottomNavigationBar: const TanodNavBar(current: TanodTab.home),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: Image.asset(
                'assets/images/texture.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _load,
              color: context.colors.navy,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(26, 12, 26, 24),
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _NotificationBell(
                        onTap: () =>
                            Navigator.of(context).pushNamed('/notifications'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.68,
                      child: Image.asset(
                        'assets/images/logo-wordmark.png',
                        semanticLabel: 'SmartSumbong',
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    _loading || _firstName == null
                        ? s.homeWelcome
                        : s.homeWelcomeName(_firstName!),
                    style: t.headlineLarge?.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 2),
                  Text(s.homeHowAreYou,
                      style: t.bodyMedium?.copyWith(fontSize: 12)),
                  const SizedBox(height: 16),

                  _StatusCard(
                    picked: _picked,
                    saving: _saving,
                    onPick: (v) => setState(() => _picked = v),
                    onSubmit: _submitStatus,
                    note: _locationNote,
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(
                            fontSize: 12, color: context.colors.hint)),
                  ],
                  const SizedBox(height: 16),

                  // HOME - TANOD shows Incoming Dispatch; the
                  // RESPONDED and MISSED frames show Alert History
                  // directly under the status card with no Incoming
                  // above it. So the queue takes the space when there is
                  // one, and history fills it when there is not —
                  // rather than stacking both and pushing history off
                  // the fold on a busy day.
                  if (_loading || _incoming.isNotEmpty) ...[
                    _IncomingCard(
                      loading: _loading,
                      tickets: _incoming,
                      onOpen: _open,
                    ),
                    const SizedBox(height: 16),
                  ],

                  _ActivityHistoryCard(loading: _loading, entries: _activity),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- status ---------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.picked,
    required this.saving,
    required this.onPick,
    required this.onSubmit,
    this.note,
  });

  final DutyState? picked;
  final bool saving;
  final ValueChanged<DutyState?> onPick;
  final VoidCallback onSubmit;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _Card(
      title: s.homeStatusQuestion,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DutyState>(
                  initialValue: picked,
                  isExpanded: true,
                  hint: Text(s.homeSelectStatus),
                  items: [
                    for (final d in DutyState.values)
                      DropdownMenuItem(
                          value: d, child: Text(s.dutyStateLabel(d.wire))),
                  ],
                  onChanged: saving ? null : onPick,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 92,
                height: 42,
                child: FilledButton(
                  onPressed: saving || picked == null ? null : onSubmit,
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  child: saving
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: context.colors.bg),
                        )
                      : Text(s.homeSubmit),
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!,
                style: TextStyle(
                    fontSize: 11.5, height: 1.35, color: context.colors.muted)),
          ],
        ],
      ),
    );
  }
}

// ---------- incoming dispatch ----------------------------------

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.loading,
    required this.tickets,
    required this.onOpen,
  });

  final bool loading;
  final List<Ticket> tickets;
  final ValueChanged<Ticket> onOpen;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: context.s.homeIncomingDispatch,
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          : tickets.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    context.s.homeIncomingEmpty,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: context.colors.muted),
                  ),
                )
              // Bounded and scrolled within the card, as the frame
              // draws it — a tanod with eight tickets should not have
              // to scroll past all of them to reach Alert History.
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(right: 10),
                      itemCount: tickets.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 16, color: context.colors.divider),
                      itemBuilder: (_, i) => _DispatchRow(
                        ticket: tickets[i],
                        onOpen: () => onOpen(tickets[i]),
                      ),
                    ),
                  ),
                ),
    );
  }
}

class _DispatchRow extends StatelessWidget {
  const _DispatchRow({required this.ticket, required this.onOpen});

  final Ticket ticket;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.assignment_outlined,
              size: 26, color: Color(0xFF14181D)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: TextStyle(
                      fontSize: 12, height: 1.35, color: context.colors.navy),
                  children: [
                    TextSpan(text: context.s.homeAssignedTo),
                    TextSpan(
                      text: ticket.trackingId,
                      style: const TextStyle(
                        color: Color(0xFFFF4949),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _date(context, ticket.assignedAt),
                style: TextStyle(fontSize: 10, color: context.colors.muted),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: 28,
                child: FilledButton(
                  onPressed: onOpen,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1FA84E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.s.homeViewDetails),
                      const SizedBox(width: 4),
                      const Icon(Icons.chevron_right, size: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            _time(ticket.assignedAt),
            style: TextStyle(fontSize: 10, color: context.colors.muted),
          ),
        ),
      ],
    );
  }

  static String _date(BuildContext context, DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${context.s.monthFull(l.month)} ${l.day}, ${l.year}';
  }

  static String _time(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final mm = l.minute.toString().padLeft(2, '0');
    return '$h:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ---------- activity history -------------------------------------
//
// Replaced 9 Sep 2026 (CAPSTONE G12 feedback): this card used to be
// "Alert History" — a tracking ID and a timestamp per row, nothing about
// what the tanod actually did. It carried no trace of a submitted update
// anywhere else in the app either. This is the same list of the tanod's
// own past dispatches, but a responded row now expands to show the
// field report text and any photo/video proof they attached — the same
// data submit_field_report() and dispatch_media already store, read
// back through RLS the tanod already has (dispatch_media_read admits
// `d.tanod_id = auth.uid()`).

class _ActivityEntry {
  _ActivityEntry({
    required this.kind,
    required this.who,
    required this.trackingId,
    required this.at,
    required this.reportText,
    required this.media,
  });

  final ActivityKind kind;
  final String who;
  final String trackingId;
  final DateTime? at;

  /// What the tanod wrote in submit_field_report(). Empty for a missed
  /// (expired) dispatch — nothing was ever submitted for those.
  final String reportText;
  final List<({String url, bool isVideo})> media;

  factory _ActivityEntry.fromRow(Map<String, dynamic> d) {
    final r = (d['reports'] ?? const {}) as Map<String, dynamic>;
    final subject = (r['subject'] as String? ?? '').trim();
    final ticket = r['tracking_id'] as String? ?? '';
    final missed = (d['state'] as String?) == 'expired';
    final rawMedia = (d['dispatch_media'] as List?) ?? const [];

    return _ActivityEntry(
      kind: missed ? ActivityKind.missed : ActivityKind.responded,
      who: subject.isEmpty ? ticket : '$ticket — $subject',
      trackingId: ticket,
      // A resolved dispatch reports back on when it was resolved, not
      // when it was first assigned — that is the moment the activity
      // actually happened. Missed and still-accepted rows have no
      // resolved_at, so they fall back to assigned_at as before.
      at: DateTime.tryParse((d['resolved_at'] ?? d['assigned_at']) as String? ?? ''),
      reportText: (d['field_report_text'] as String? ?? '').trim(),
      media: [
        for (final m in rawMedia)
          (
            url: (m as Map<String, dynamic>)['media_url'] as String,
            isVideo: isVideoMime(m['mime_type'] as String?),
          ),
      ],
    );
  }
}

class _ActivityHistoryCard extends StatefulWidget {
  const _ActivityHistoryCard({required this.loading, required this.entries});

  final bool loading;
  final List<_ActivityEntry> entries;

  @override
  State<_ActivityHistoryCard> createState() => _ActivityHistoryCardState();
}

class _ActivityHistoryCardState extends State<_ActivityHistoryCard> {
  ActivityKind? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final shown = _filter == null
        ? widget.entries
        : widget.entries.where((a) => a.kind == _filter).toList();

    final s = context.s;
    return _Card(
      title: s.homeActivityHistory,
      trailing: s.homeAlertHistoryTrailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Tab(
                label: s.homeTabAll,
                active: _filter == null,
                colour: context.colors.navy,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 18),
              _Tab(
                label: s.homeTabResponded,
                active: _filter == ActivityKind.responded,
                colour: const Color(0xFF1FA84E),
                onTap: () =>
                    setState(() => _filter = ActivityKind.responded),
              ),
              const SizedBox(width: 18),
              _Tab(
                label: s.homeTabMissed,
                active: _filter == ActivityKind.missed,
                colour: const Color(0xFFFF4949),
                onTap: () => setState(() => _filter = ActivityKind.missed),
              ),
            ],
          ),
          Divider(height: 16, color: context.colors.divider),

          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                s.homeAlertHistoryEmpty,
                style: TextStyle(fontSize: 12, color: context.colors.muted),
              ),
            )
          else
            for (final a in shown) _ActivityRow(entry: a),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.colour,
    required this.onTap,
  });

  final String label;
  final bool active;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: colour.withValues(alpha: active ? 1 : 0.55),
            decoration: active ? TextDecoration.underline : null,
            decorationColor: colour,
          ),
        ),
      ),
    );
  }
}

/// A responded entry expands to show the field report text and any
/// attached photo/video — the "activity" this card is now named for.
/// A missed entry has nothing to expand into (nothing was ever
/// submitted), so it stays a single row, same as before.
class _ActivityRow extends StatefulWidget {
  const _ActivityRow({required this.entry});

  final _ActivityEntry entry;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final responded = entry.kind == ActivityKind.responded;
    final colour =
        responded ? const Color(0xFF1FA84E) : const Color(0xFFFF4949);
    final expandable =
        responded && (entry.reportText.isNotEmpty || entry.media.isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: expandable ? () => setState(() => _open = !_open) : null,
            child: Row(
              children: [
                // Not handsets. The frame draws phone icons, which made
                // sense when these rows were imagined as calls — but
                // they are dispatch outcomes: accepted or resolved
                // against expired. Nobody phoned anyone, and an icon
                // that says otherwise is a small lie repeated on every
                // row.
                Icon(
                  responded ? Icons.check_circle : Icons.cancel_outlined,
                  size: 20,
                  color: colour,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.who,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: colour,
                        ),
                      ),
                      Text(
                        _DispatchRow._date(context, entry.at),
                        style: TextStyle(
                            fontSize: 10, color: context.colors.muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  _DispatchRow._time(entry.at),
                  style: TextStyle(fontSize: 10, color: context.colors.muted),
                ),
                if (expandable) ...[
                  const SizedBox(width: 4),
                  Icon(_open ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: context.colors.muted),
                ],
              ],
            ),
          ),

          if (_open && expandable)
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4, right: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.reportText.isEmpty
                        ? context.s.homeActivityNoText
                        : '${context.s.homeActivityFieldReportLabel}'
                            '“${entry.reportText}”',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontStyle: entry.reportText.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: context.colors.navy),
                  ),
                  if (entry.media.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: entry.media.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) =>
                            _ActivityThumb(item: entry.media[i]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityThumb extends StatelessWidget {
  const _ActivityThumb({required this.item});

  final ({String url, bool isVideo}) item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (item.isVideo) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => VideoPlayerScreen(url: item.url),
            ),
          );
        } else {
          showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: InteractiveViewer(
                child: CachedNetworkImage(imageUrl: item.url),
              ),
            ),
          );
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: item.isVideo
            ? Container(
                width: 52,
                height: 52,
                color: Colors.black87,
                child: const Icon(Icons.play_circle_fill,
                    size: 24, color: Colors.white70),
              )
            : CachedNetworkImage(
                imageUrl: item.url,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  width: 52,
                  height: 52,
                  color: context.colors.field,
                ),
                errorWidget: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  color: context.colors.field,
                  child: Icon(Icons.broken_image_outlined,
                      size: 18, color: context.colors.muted),
                ),
              ),
      ),
    );
  }
}

// ---------- shared bits ----------------------------------------

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child, this.trailing});

  final String title;
  final String? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: context.colors.bg,
        border: Border.all(color: context.colors.navy),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: context.colors.navy,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    trailing!,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFFFF4949)),
                  ),
                ),
              ],
            ],
          ),
          Divider(height: 14, color: context.colors.divider),
          child,
        ],
      ),
    );
  }
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 39,
        height: 38,
        decoration: BoxDecoration(
          color: context.colors.navy,
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.notifications_none_rounded,
            color: context.colors.bg, size: 22),
      ),
    );
  }
}
