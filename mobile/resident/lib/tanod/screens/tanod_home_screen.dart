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
import '../../theme.dart';
import '../../widgets/figma_ui.dart';
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
  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final s = context.ts;

    return Scaffold(
      bottomNavigationBar: const TanodNavBar(current: TanodTab.home),
      body: Stack(
        children: [
          const FigmaTexture(),
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: _load,
              color: context.colors.navy,
              child: ListView(
                // Figma HOME - TANOD: the bell's top at y=33, cards 352
                // wide at x=30.
                padding: EdgeInsets.fromLTRB(30, figmaTop(context, 33), 30, 24),
                children: [
                  // The logo box (308x236 at x=47, y=55) overlaps the bell
                  // row, and the greeting starts 236 below the bell's top
                  // edge (y=269), inside the logo box's transparent margin
                  // — the same arrangement as the resident Home.
                  SizedBox(
                    height: 236,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 22,
                          height: 236,
                          child: Center(
                            child: Transform.translate(
                              offset: const Offset(-5, 0),
                              child: SizedBox(
                                width: 308,
                                height: 236,
                                child: Image.asset(
                                  'assets/images/home-wordmark.png',
                                  fit: BoxFit.contain,
                                  semanticLabel: 'SmartSumbong',
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: -2,
                          child: _NotificationBell(
                            onTap: () => Navigator.of(context)
                                .pushNamed('/t/notifications'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 13),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _loading || _firstName == null
                              ? s.homeWelcome
                              : s.homeWelcomeName(_firstName!),
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w800,
                            fontSize: 28,
                            height: 34 / 28,
                            color: context.colors.navy,
                          ),
                        ),
                        Text(
                          s.homeHowAreYou,
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            height: 21.84 / 14,
                            color: context.colors.navy,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    Text(_error!,
                        style: TextStyle(
                            fontSize: 12, color: context.colors.hint)),
                    const SizedBox(height: 12),
                  ],
                  _IncomingCard(
                    loading: _loading,
                    tickets: _incoming,
                    onOpen: _open,
                  ),
                ],
              ),
            ),
          ),
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
      title: context.ts.homeIncomingDispatch,
      child: loading
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          : tickets.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    context.ts.homeIncomingEmpty,
                    style: TextStyle(
                        fontSize: 12, height: 1.4, color: context.colors.muted),
                  ),
                )
              // The whole queue, at full height: on branch B the queue is
              // Home, so it scrolls with the page instead of in a window.
              : Column(
                  children: [
                    for (var i = 0; i < tickets.length; i++) ...[
                      if (i > 0) const SizedBox(height: 16),
                      _DispatchRow(
                        ticket: tickets[i],
                        onOpen: () => onOpen(tickets[i]),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _DispatchRow extends StatelessWidget {
  const _DispatchRow({required this.ticket, required this.onOpen});

  final Ticket ticket;
  final VoidCallback onOpen;

  // Figma "Group 301": the 20x25 clipboard at 18 in, the line 14/600 with
  // the complaint in red, the date and time 10/500, and under them the
  // 128x30 green View Details pill.
  @override
  Widget build(BuildContext context) {
    final ink = context.colors.navy;
    return Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Icon(Icons.assignment, size: 25, color: ink),
              ),
              const SizedBox(width: 22),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          height: 15 / 14,
                          color: ink,
                        ),
                        children: [
                          TextSpan(text: context.ts.homeAssignedTo),
                          TextSpan(
                            text: ticket.trackingId,
                            style: const TextStyle(color: kFigmaRed),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _date(context, ticket.assignedAt),
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                        height: 15.6 / 10,
                        color: ink,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _time(ticket.assignedAt),
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                    color: ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 21),
            child: _GreenPill(
              label: context.ts.homeViewDetails,
              onPressed: onOpen,
            ),
          ),
        ],
      ),
    );
  }

  static String _date(BuildContext context, DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    return '${context.ts.monthFull(l.month)} ${l.day}, ${l.year}';
  }

  static String _time(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final mm = l.minute.toString().padLeft(2, '0');
    return '$h:$mm ${l.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ---------- shared bits ----------------------------------------

/// The frame's green (#058F00): View Details, Responded.
const _green = Color(0xFF058F00);

/// The frame's rule under a card title: #6C6C6C at 50%.
Color _rule(BuildContext context) =>
    const Color(0xFF6C6C6C).withValues(alpha: 0.5);

/// Figma "Frame 934/935": 352 wide, #FBFBFB, 1px ink edge, radius 25, the
/// design shadow; the title 18/700 at 20 in and 13 down, then a rule.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 13, 20, 18),
      decoration: BoxDecoration(
        color: context.colors.field,
        border: Border.all(color: context.colors.navy),
        borderRadius: BorderRadius.circular(25),
        boxShadow: kFigmaShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              text: title,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                height: 1.5,
                color: context.colors.navy,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, thickness: 1, color: _rule(context)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// The frame's 128x30 green pill: #058F00, 1px #F3F3F3 edge, the design
/// shadow, 14/700 label and a chevron.
class _GreenPill extends StatelessWidget {
  const _GreenPill({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(50)),
        boxShadow: kFigmaShadow,
      ),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _green,
          foregroundColor: const Color(0xFFF3F3F3),
          minimumSize: const Size(128, 30),
          maximumSize: const Size(220, 30),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
          side: const BorderSide(color: Color(0xFFF3F3F3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ],
        ),
      ),
    );
  }
}

/// The frame's bell: a 39x38 ink circle with the design's own bell glyph
/// (25x25 at 7,6), tinted from the theme so dark mode still reads.
class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: context.ts.notificationsTitle,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(19),
        child: Container(
          width: 39,
          height: 38,
          padding: const EdgeInsets.only(left: 7, top: 6),
          alignment: Alignment.topLeft,
          decoration: BoxDecoration(
            color: context.colors.navy,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Image.asset(
            'assets/images/icon-bell.png',
            width: 25,
            height: 25,
            color: context.colors.bg,
          ),
        ),
      ),
    );
  }
}
