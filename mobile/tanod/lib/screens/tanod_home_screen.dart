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

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Which half of Alert History a past dispatch belongs to.
///
/// Responded and Missed are not opinions — they are dispatch states.
/// accepted and resolved mean the tanod answered; expired means the
/// accept window elapsed with no response and 0006 alerted the admin.
/// A rerouted ticket is neither: it was answered, with a reason, and it
/// belongs in neither column.
enum AlertKind { responded, missed }

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
  List<_Alert> _alerts = const [];

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _locationNote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

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

      // Alert History, "in the past 7 days" per the frame.
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
              'reports(tracking_id, subject, is_anonymous)')
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
        _alerts = [
          for (final r in past) _Alert.fromRow(r as Map<String, dynamic>),
        ];
        _loading = false;
      });

      if (_status == DutyState.onDuty) await _pushLocation();
    } on PostgrestException catch (e) {
      // Named rather than swallowed. A malformed select or a policy
      // refusal both land here, and "could not load" tells whoever is
      // testing nothing at all.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your dashboard. (${e.message})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your dashboard. Check your connection.';
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
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message.toLowerCase().contains('duty_only_for_tanod')
            ? 'This account is not registered as a barangay tanod.'
            : 'Could not update your status. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not update your status. Please try again.';
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
    setState(() => _locationNote = 'Sharing your location\u2026');

    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever ||
          !await Geolocator.isLocationServiceEnabled()) {
        if (mounted) {
          setState(() => _locationNote =
              'Location is off. You are on duty but cannot be sent '
              'nearby complaints until you turn it on.');
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
      setState(() => _locationNote = ok
          ? 'Location shared. You can be sent nearby complaints.'
          : 'Could not share your location. Submit On Duty again to retry.');
    } catch (_) {
      if (mounted) {
        setState(() => _locationNote =
            'Could not share your location. Submit On Duty again to retry.');
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
              color: Tokens.navy,
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
                        ? 'Welcome!'
                        : 'Welcome, $_firstName!',
                    style: t.headlineLarge?.copyWith(fontSize: 22),
                  ),
                  const SizedBox(height: 2),
                  Text('How are you doing today?',
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
                        style: const TextStyle(
                            fontSize: 12, color: Tokens.hint)),
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

                  _AlertHistoryCard(loading: _loading, alerts: _alerts),
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
    return _Card(
      title: 'What\u2019s your status?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DutyState>(
                  initialValue: picked,
                  isExpanded: true,
                  hint: const Text('Select a Status'),
                  items: [
                    for (final s in DutyState.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Tokens.bg),
                        )
                      : const Text('Submit'),
                ),
              ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 8),
            Text(note!,
                style: const TextStyle(
                    fontSize: 11.5, height: 1.35, color: Tokens.muted)),
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
      title: 'Incoming Dispatch',
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          : tickets.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Nothing assigned to you right now. Set yourself On '
                    'Duty and share your location to be sent nearby '
                    'complaints.',
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: Tokens.muted),
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
                          const Divider(height: 16, color: Tokens.divider),
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
                  style: const TextStyle(
                      fontSize: 12, height: 1.35, color: Tokens.navy),
                  children: [
                    const TextSpan(text: 'You have been assigned to '),
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
                _date(ticket.assignedAt),
                style: const TextStyle(fontSize: 10, color: Tokens.muted),
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
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('View Details'),
                      SizedBox(width: 4),
                      Icon(Icons.chevron_right, size: 14),
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
            style: const TextStyle(fontSize: 10, color: Tokens.muted),
          ),
        ),
      ],
    );
  }

  static String _date(DateTime? d) {
    if (d == null) return '';
    const m = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final l = d.toLocal();
    return '${m[l.month - 1]} ${l.day}, ${l.year}';
  }

  static String _time(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final mm = l.minute.toString().padLeft(2, '0');
    return '$h:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ---------- alert history --------------------------------------

class _Alert {
  _Alert({
    required this.kind,
    required this.who,
    required this.trackingId,
    required this.at,
  });

  final AlertKind kind;
  final String who;
  final String trackingId;
  final DateTime? at;

  factory _Alert.fromRow(Map<String, dynamic> d) {
    final r = (d['reports'] ?? const {}) as Map<String, dynamic>;
    final subject = (r['subject'] as String? ?? '').trim();
    final ticket = r['tracking_id'] as String? ?? '';

    return _Alert(
      kind: (d['state'] as String?) == 'expired'
          ? AlertKind.missed
          : AlertKind.responded,
      who: subject.isEmpty ? ticket : '$ticket \u2014 $subject',
      trackingId: r['tracking_id'] as String? ?? '',
      at: DateTime.tryParse(d['assigned_at'] as String? ?? ''),
    );
  }
}

class _AlertHistoryCard extends StatefulWidget {
  const _AlertHistoryCard({required this.loading, required this.alerts});

  final bool loading;
  final List<_Alert> alerts;

  @override
  State<_AlertHistoryCard> createState() => _AlertHistoryCardState();
}

class _AlertHistoryCardState extends State<_AlertHistoryCard> {
  AlertKind? _filter; // null = All

  @override
  Widget build(BuildContext context) {
    final shown = _filter == null
        ? widget.alerts
        : widget.alerts.where((a) => a.kind == _filter).toList();

    return _Card(
      title: 'Alert History',
      trailing: 'in the past 7 days',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Tab(
                label: 'All',
                active: _filter == null,
                colour: Tokens.navy,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 18),
              _Tab(
                label: 'Responded',
                active: _filter == AlertKind.responded,
                colour: const Color(0xFF1FA84E),
                onTap: () =>
                    setState(() => _filter = AlertKind.responded),
              ),
              const SizedBox(width: 18),
              _Tab(
                label: 'Missed',
                active: _filter == AlertKind.missed,
                colour: const Color(0xFFFF4949),
                onTap: () => setState(() => _filter = AlertKind.missed),
              ),
            ],
          ),
          const Divider(height: 16, color: Tokens.divider),

          if (widget.loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shown.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Nothing in the past seven days.',
                style: TextStyle(fontSize: 12, color: Tokens.muted),
              ),
            )
          else
            for (final a in shown) _AlertRow(alert: a),
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

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});

  final _Alert alert;

  @override
  Widget build(BuildContext context) {
    final responded = alert.kind == AlertKind.responded;
    final colour =
        responded ? const Color(0xFF1FA84E) : const Color(0xFFFF4949);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          // Not handsets. The frame draws phone icons, which made sense
          // when these rows were imagined as calls — but they are
          // dispatch outcomes: accepted or resolved against expired.
          // Nobody phoned anyone, and an icon that says otherwise is a
          // small lie repeated on every row.
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
                  alert.who,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: colour,
                  ),
                ),
                Text(
                  _DispatchRow._date(alert.at),
                  style: const TextStyle(fontSize: 10, color: Tokens.muted),
                ),
              ],
            ),
          ),
          Text(
            _DispatchRow._time(alert.at),
            style: const TextStyle(fontSize: 10, color: Tokens.muted),
          ),
        ],
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
        color: Tokens.bg,
        border: Border.all(color: Tokens.navy),
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
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Tokens.navy,
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
          const Divider(height: 14, color: Tokens.divider),
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
        decoration: const BoxDecoration(
          color: Tokens.navy,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.notifications_none_rounded,
            color: Tokens.bg, size: 22),
      ),
    );
  }
}
