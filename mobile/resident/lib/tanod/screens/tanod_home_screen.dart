// SmartSumbong — Tanod home (branch B).
//
// Figma: HOME - TANOD, reworked on branch B. Incoming Dispatch is the
// core of Home now: who you are, then the queue, at full height rather
// than a 260-tall window. Duty status moved to the middle of the nav bar
// (duty.dart, widgets/duty_sheet.dart) and Activity History to its own
// tab (history_screen.dart).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../duty.dart';
import '../tanod_strings.dart';
import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../../d/flood_watch.dart';
import '../widgets/tanod_nav_bar.dart';
import 'dispatch_order.dart';
import '../../screens/launch_gate.dart' show gateCacheKey;
import 'tickets_screen.dart';

class TanodHomeScreen extends StatefulWidget {
  const TanodHomeScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<TanodHomeScreen> createState() => _TanodHomeScreenState();
}

class _TanodHomeScreenState extends State<TanodHomeScreen> {
  String? _firstName;

  List<Ticket> _incoming = const [];

  bool _loading = true;
  String? _error;

  // Live updates (8 Sep 2026 — mirrors resident's home_screen.dart /
  // reports_screen.dart). Home shows Incoming Dispatch and Alert
  // History straight off `dispatches`, and until now this screen only
  // ever reloaded on initState or a manual pull — an admin dispatch, an
  // accept elsewhere, or an expiry sat unseen until the tanod happened
  // to pull down. `dispatches` has been in the realtime publication
  // since 0004 for the admin map, so this rides along for free at the
  // database level; the only new cost is the one open channel while
  // Home is on screen.
  FloodReading? _flood;
  Timer? _floodTimer;

  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _readFlood();
    _floodTimer = Timer.periodic(const Duration(minutes: 10), (_) => _readFlood());
  }

  Future<void> _readFlood() async {
    final r = await FloodReading.read();
    if (mounted) setState(() => _flood = r);
  }

  @override
  void dispose() {
    _floodTimer?.cancel();
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

  /// Last time's name and queue, shown at once (branch B).
  Future<void> _showSaved() async {
    final c = await JsonCache.read('home');
    if (c is! Map || !mounted || !_loading) return;
    setState(() {
      _firstName = c['first_name'] as String?;
      _incoming = [
        for (final r in (c['open'] as List? ?? const []))
          Ticket.fromRow(Map<String, dynamic>.from(r as Map)),
      ];
      _loading = false;
    });
  }

  Future<void> _load() async {
    if (_loading) await _showSaved();
    final hadSaved = !_loading;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

      _subscribeLive(uid);

      // The name and the live queue (what is waiting for a response or
      // already accepted) together: neither needs the other.
      final got = await Future.wait<Object?>([
        // With the account's standing (branch B): the loading screen now
        // sends a tanod here on the last check it saw, so this is where
        // the checks it used to hold the launch for are made.
        client
            .from('users')
            .select('full_name, verification_status, is_suspended, '
                'is_retired, must_change_password')
            .eq('id', uid)
            .single(),
        client
            .from('dispatches')
            .select('id, report_id, state, accept_due_at, assigned_at, '
                'admin_instructions, '
                'reports(tracking_id, subject, description, due_at)')
            .eq('tanod_id', uid)
            .inFilter('state', ['assigned', 'accepted'])
            .order('assigned_at', ascending: false),
        client.rpc('my_role'),
      ], eagerError: true);
      final me = got[0] as Map<String, dynamic>;
      final open = got[1] as List<Map<String, dynamic>>;
      final role = got[2] as String?;

      // In the loading screen's order: suspended, retired, verification,
      // temporary password, then "is this a tanod at all".
      final String? away = me['is_suspended'] == true
          ? '/account-suspended'
          : me['is_retired'] == true
              ? '/account-retired'
              : me['verification_status'] == 'rejected'
                  ? '/verification-rejected'
                  : me['verification_status'] != 'verified'
                      ? '/verification-pending'
                      : me['must_change_password'] == true
                          ? '/change-password'
                          : role != 'tanod'
                              ? '/' // not a tanod: the launch gate re-decides
                              : null;
      // The launch gate's own saved check (branch C, one app).
      unawaited(JsonCache.write(gateCacheKey, {
        'verified': me['verification_status'] == 'verified',
        'suspended': me['is_suspended'] == true,
        'retired': me['is_retired'] == true,
        'must_change': me['must_change_password'] == true,
        'role': role,
      }));
      if (away != null) {
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil(away, (_) => false);
        }
        return;
      }

      if (!mounted) return;
      final name = (me['full_name'] as String? ?? '').trim();
      unawaited(JsonCache.write('home', {
        'first_name': name.isEmpty ? null : name.split(' ').first,
        'open': open,
      }));
      setState(() {
        _error = null;
        _firstName = name.isEmpty ? null : name.split(' ').first;
        _incoming = [
          for (final r in open) Ticket.fromRow(r),
        ];
        _loading = false;
      });

      // A push tapped while the app was fully closed. The tanod app has
      // no single-ticket route, so it lands on Notifications, the same
      // place a tap on a running app goes (main.dart).
      if (PushNotifications.takePendingReport() != null && mounted) {
        unawaited(Navigator.of(context).pushNamed('/t/notifications'));
      }

      // The status and its location sharing live app-wide now; Home only
      // makes sure they are read after sign-in.
      unawaited(DutyController.instance.load());
    } on PostgrestException catch (e) {
      // The session outlived the account or its token is unusable (was
      // the loading screen's AuthRequiredException): sign in again.
      if (e.code == 'PGRST301' || e.message.toLowerCase().contains('jwt')) {
        await widget.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
        }
        return;
      }
      // Named rather than swallowed. A malformed select or a policy
      // refusal both land here, and "could not load" tells whoever is
      // testing nothing at all.
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.ts.homeLoadError(e.message);
      });
    } catch (_) {
      if (!mounted) return;
      // No signal, but the saved queue is on screen: keep it.
      if (hadSaved) return;
      setState(() {
        _loading = false;
        _error = context.ts.homeLoadOffline;
      });
    }
  }

  Future<void> _open(Ticket t) async {
    // A card over this screen, not a push. TANOD - VIEW DISPATCH draws
    // Home still visible behind it.
    if (await showDispatchOrder(context, t)) await _load();
  }

  // Branch D: the resident Home's layout in the tanod's ink — the bell,
  // the wordmark, the greeting, the flood watch, then one card per
  // dispatch waiting for an answer (with the time left to accept) and a
  // card for the ones already accepted. No activity history here; that
  // is the History tab.
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    final waiting = [for (final t in _incoming) if (t.awaitingResponse) t];
    final working = [for (final t in _incoming) if (!t.awaitingResponse) t];
    return DPage(
      fullContour: true,
      bottomBar: const TanodNavBar(current: TanodTab.home),
      child: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _readFlood();
        },
        color: d.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            SizedBox(
              height: 168,
              child: Stack(children: [
                Positioned.fill(
                  top: 30,
                  child: Center(
                    child: Image.asset('assets/images/home-wordmark.png', width: 250, fit: BoxFit.contain, semanticLabel: 'SmartSumbong'),
                  ),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: DBell(unread: 0, onTap: () => Navigator.of(context).pushNamed('/t/notifications')),
                ),
              ]),
            ),
            Text(_loading || _firstName == null ? s.homeWelcome : s.homeWelcomeName(_firstName!), style: DType.h1(d.ink)),
            const SizedBox(height: 2),
            Text(s.homeHowAreYou, style: DType.body(d.muted)),
            const SizedBox(height: 16),
            DFloodCard(reading: _flood),
            const SizedBox(height: 14),
            if (_error != null) ...[
              DSheet(
                borderColor: DColors.red.withValues(alpha: .5),
                child: Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
              ),
              const SizedBox(height: 14),
            ],
            if (_loading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
            else ...[
              if (waiting.isEmpty)
                DCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(context.tr('INCOMING DISPATCH', 'PAPASOK NA DISPATCH'), style: DType.label(Colors.white.withValues(alpha: .8))),
                    const SizedBox(height: 8),
                    Text(s.homeIncomingEmpty, style: DType.body(Colors.white.withValues(alpha: .9), size: 13.5)),
                  ]),
                )
              else
                for (final t in waiting) ...[
                  _IncomingCard(ticket: t, onOpen: () => _open(t)),
                  const SizedBox(height: 14),
                ],
              if (waiting.isEmpty) const SizedBox(height: 14),
              DCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.tr('Your assigned reports', 'Mga naka-assign sa iyo'), style: DType.h3(Colors.white).copyWith(fontSize: 19)),
                  const SizedBox(height: 6),
                  Text(
                    working.isEmpty
                        ? context.tr('Nothing in progress. Accepted dispatches show here.', 'Walang isinasagawa. Dito lalabas ang mga tinanggap na dispatch.')
                        : context.tr('${working.length} ${working.length == 1 ? 'dispatch' : 'dispatches'} in progress. Open one to update it or send your field report.',
                            '${working.length} dispatch ang isinasagawa. Buksan ang isa para i-update o ipadala ang ulat.'),
                    style: DType.body(Colors.white.withValues(alpha: .86), size: 13),
                  ),
                  const SizedBox(height: 14),
                  DButton(context.tr('View assigned reports', 'Tingnan ang mga naka-assign'),
                      small: true, kind: DButtonKind.white, onTap: () => Navigator.of(context).pushReplacementNamed('/t/reports')),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One dispatch waiting for this tanod: the pulsing label, what and where,
/// the time left to accept counting down, View Details.
class _IncomingCard extends StatefulWidget {
  const _IncomingCard({required this.ticket, required this.onOpen});

  final Ticket ticket;
  final VoidCallback onOpen;

  @override
  State<_IncomingCard> createState() => _IncomingCardState();
}

class _IncomingCardState extends State<_IncomingCard> with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final due = t.acceptDueAt;
    final left = due?.difference(DateTime.now());
    String? clock;
    if (left != null) {
      final sec = left.inSeconds.clamp(0, 359999);
      clock = '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';
    }
    return DCard(
      onTap: widget.onOpen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FadeTransition(
            opacity: Tween(begin: 1.0, end: .25).animate(_pulse),
            child: Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: DColors.orange)),
          ),
          const SizedBox(width: 8),
          Text(context.tr('INCOMING DISPATCH', 'PAPASOK NA DISPATCH'), style: DType.label(Colors.white.withValues(alpha: .85))),
        ]),
        const SizedBox(height: 8),
        Text(t.subject, style: DType.h3(Colors.white).copyWith(fontSize: 19)),
        const SizedBox(height: 2),
        Text(t.trackingId, style: DType.mono(Colors.white.withValues(alpha: .8), size: 12.5)),
        if (clock != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Text(context.tr('Accept within', 'Tanggapin sa loob ng'), style: DType.body(Colors.white.withValues(alpha: .85), size: 13)),
            const Spacer(),
            Text(clock, style: DType.mono(left!.inMinutes < 2 ? const Color(0xFFFFB4A8) : Colors.white, size: 20)),
          ]),
        ],
        const SizedBox(height: 12),
        DButton(context.ts.homeViewDetails, small: true, onTap: widget.onOpen),
      ]),
    );
  }
}
