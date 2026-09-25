// SmartSumbong — Home.
//
// Figma node 2117:72.
//
// Three cards and a greeting. The greeting uses the resident's first
// name, which means one query on entry — and that query doubles as a
// standing check: an account suspended while the app was open should not
// keep browsing. The launch gate catches that at startup; this catches it
// mid-session.
//
// The notification bell shows an unread count from public.notifications,
// which is where complaint status updates already land (0002's
// sweep functions write there) and where announcements would go if the
// barangay ever wants in-app broadcast. It is read on entry and on
// resume, same as before —
//
// PLUS, since 29 Aug 2026, live: a channel on public.notifications
// (0046) filtered to this resident's own user_id keeps the badge
// current while Home is open, no pull or resume needed. This reverses
// the old "not a live feed" call this file used to make for the exact
// same badge — see 0046's own header for why the calculus changed
// (notifications holds no identity data the way users does, and a
// resident with an open report is exactly the seconds-matter case that
// call was carving an exception for). The resume-based reload stays as
// a fallback: a socket can drop or never open at all (older build, no
// notification permission), and this badge should still be right the
// next time the resident looks at this screen either way.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/resident_nav_bar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _firstName;
  int _unread = 0;
  bool _loading = true;

  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _liveDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    super.dispose();
  }

  /// One channel per resident, opened once the first successful [_load]
  /// confirms who they are — never re-opened by a later, live-triggered
  /// [_load], since [_liveChannel] is already set by then.
  void _subscribeLive(String uid) {
    if (_liveChannel != null) return;
    _liveChannel = Supabase.instance.client
        .channel('home-notifications-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: uid,
        ),
        callback: (_) => _scheduleLiveReload(),
      )
      ..subscribe();
  }

  /// A status change often writes more than one notifications row (and
  /// a report update alongside it, on other screens) in the same
  /// transaction — debounced so that lands as one reload, not several.
  void _scheduleLiveReload() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      _bounce('/login');
      return;
    }

    try {
      final profile = await client
          .from('users')
          .select('full_name, verification_status, is_suspended, '
              'id_image_url, id_type, ocr_rescan_requested_at')
          .eq('id', uid)
          .maybeSingle();

      if (profile == null) {
        _bounce('/login');
        return;
      }

      // Standing can change while the app is open. An admin who suspends
      // an account mid-session should not leave the resident browsing a
      // home screen where every action will fail against RLS.
      if (profile['is_suspended'] == true) {
        _bounce('/account-suspended');
        return;
      }
      if (profile['verification_status'] != 'verified') {
        _bounce('/verification-pending');
        return;
      }

      _subscribeLive(uid);

      // A push tapped while the app was fully closed (see
      // PushNotifications.takePendingReport). Opened here rather than at
      // launch because this is where the account has just been confirmed
      // verified and not suspended.
      final pendingReport = PushNotifications.takePendingReport();
      if (pendingReport != null && mounted) {
        unawaited(Navigator.of(context)
            .pushNamed('/report', arguments: pendingReport));
      }

      // Migration 0050: an admin asked for this account's already-
      // uploaded ID photo to be re-scanned (it predates on-device OCR,
      // or its first read flagged something worth a second look).
      // Fire-and-forget — this is advisory triage for the admin, same
      // as the original registration-time OCR pass, and must never
      // hold up or interrupt the resident's own screen.
      if (profile['ocr_rescan_requested_at'] != null &&
          profile['id_image_url'] != null) {
        unawaited(_maybeRescanId(
          imageUrl: profile['id_image_url'] as String,
          fullName: profile['full_name'] as String? ?? '',
          idTypeWire: profile['id_type'] as String?,
        ));
      }

      final unread = await client
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', uid)
          .eq('is_read', false);

      if (!mounted) return;
      setState(() {
        _firstName = _firstNameOf(profile['full_name'] as String?);
        _unread = unread;
        _loading = false;
      });
    } catch (_) {
      // Offline. Show the screen anyway — the cards are static and the
      // buttons still work; only the greeting and badge are missing.
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Downloads this resident's own already-uploaded ID photo and runs
  /// the same on-device OCR pass registration does, then submits it —
  /// which also clears `ocr_rescan_requested_at` (AuthService.
  /// submitIdOcrResult). A failed download (offline, dropped mid-scan)
  /// leaves the request pending for the next app open rather than
  /// recording a false result — see runIdOcrFromUrl's own doc comment.
  Future<void> _maybeRescanId({
    required String imageUrl,
    required String fullName,
    required String? idTypeWire,
  }) async {
    try {
      final result = await runIdOcrFromUrl(imageUrl, enteredFullName: fullName);
      if (result == null) return;
      final selected = AuthService.idDocumentTypeFromWire(idTypeWire);
      await widget.auth.submitIdOcrResult(
        selected == null ? result : result.withSelectedType(selected),
      );
    } catch (_) {
      // Advisory only, same framing as the rest of this feature.
    }
  }

  void _bounce(String route) {
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(route, (_) => false);
  }

  static String? _firstNameOf(String? full) {
    if (full == null || full.trim().isEmpty) return null;
    return full.trim().split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.home),
      body: Stack(
        children: [
          // The contour texture from the design, edge to edge behind
          // everything. Exported at one frame's size (412x917), so it
          // covers rather than tiles — on a taller handset the bottom
          // is cropped, which is the right failure for a background
          // whose whole job is to not be looked at.
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
                // Figma HOME - RESIDENT (2117:72), a 412-wide frame: content
                // at x=30, and the bell's top edge 33 from the top of the
                // screen — measured from the screen, so the status bar the
                // SafeArea already clears is taken off that 33.
                padding: EdgeInsets.fromLTRB(
                  30,
                  (33 - MediaQuery.paddingOf(context).top).clamp(8.0, 33.0),
                  30,
                  24,
                ),
                children: [
                  // The logo box (308x236 at x=47, y=55) overlaps the bell
                  // row, and the greeting starts 236 below the bell's top
                  // edge (y=269), inside the logo box's transparent margin.
                  SizedBox(
                    height: 236,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // 5 left of centre, as in the frame (x=47 in 412,
                        // where centred would be 52) — measured from the
                        // centre so it stays balanced on other widths.
                        // `contain` so a very narrow phone scales it down
                        // rather than squashing it.
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
                                  // The wordmark carries the brand; a screen
                                  // reader should hear the name, not "image".
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
                            unread: _unread,
                            onTap: () => Navigator.of(context)
                                .pushNamed('/notifications'),
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
                          _loading
                              ? s.homeWelcomeGeneric
                              : (_firstName == null
                                  ? s.homeWelcomeGeneric
                                  : s.homeWelcomeNamed(_firstName!)),
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w800,
                            fontSize: 28,
                            // Subtitle starts 34 below the greeting's top.
                            height: 34 / 28,
                            color: context.colors.navy,
                          ),
                        ),
                        Text(
                          s.homeSubtitle,
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
                  const SizedBox(height: 33),

                  // Gaps and the first card's 16 bottom padding are the
                  // frame's own per-card values, kept as drawn.
                  _ActionCard(
                    title: s.homeEmergencyTitle,
                    body: s.homeEmergencyBody,
                    gap: 15,
                    bottomPadding: 16,
                    actions: [
                      _CardAction(
                        label: s.homeEmergencyLabel,
                        width: 172,
                        onTap: () => Navigator.of(context)
                            .pushReplacementNamed('/emergency'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),

                  _ActionCard(
                    title: s.homeReportTitle,
                    body: s.homeReportBody,
                    gap: 17,
                    actions: [
                      _CardAction(
                        label: s.homeReportIssue,
                        width: 140,
                        onTap: () =>
                            Navigator.of(context).pushNamed('/submit-report'),
                      ),
                      _CardAction(
                        label: s.homeViewReports,
                        width: 140,
                        onTap: () => Navigator.of(context)
                            .pushReplacementNamed('/reports'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 11),

                  _ActionCard(
                    title: s.homeMapTitle,
                    body: s.homeMapBody,
                    gap: 12,
                    actions: [
                      _CardAction(
                        label: s.homeViewMap,
                        width: 120,
                        onTap: () =>
                            Navigator.of(context).pushReplacementNamed('/map'),
                      ),
                    ],
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

// ---------- pieces -------------------------------------------

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  // Figma NOTIF BUTTON: a 39x38 navy pill (radius 19) with the design's
  // own bell glyph (25x25 at 7,6), exported from the frame rather than a
  // Material look-alike. Tinted from the theme so dark mode still reads.
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
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
          if (unread > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints: const BoxConstraints(minWidth: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: context.colors.bg, width: 1.5),
                ),
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardAction {
  const _CardAction({
    required this.label,
    required this.width,
    required this.onTap,
  });
  final String label;

  /// The button's width in the frame. A minimum, not a fixed size, so a
  /// longer Tagalog label grows the pill instead of being clipped.
  final double width;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.body,
    required this.actions,
    this.gap = 17,
    this.bottomPadding = 20,
  });

  final String title;
  final String body;
  final List<_CardAction> actions;

  /// Space between the text and the buttons; differs per card in the frame.
  final double gap;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    // Figma card: 352 wide, radius 25, 20 padding, 1px #F3F3F3 stroke,
    // drop shadow y5 / blur 5 / #121212 at 30%. Figma's blur 5 is sigma
    // 2.5, which Flutter's blurRadius expresses as 3.5.
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding),
      decoration: BoxDecoration(
        color: context.colors.navy,
        border: Border.all(color: context.colors.bg),
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 3.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            // Inverts to the page background, the same navy-card pattern
            // used on the login screen — a literal white would vanish
            // against the near-white card colour dark mode gives
            // context.colors.navy.
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              // The body starts 26 below the title's top.
              height: 26 / 18,
              color: context.colors.bg,
            ),
          ),
          Text(
            body,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              height: 15 / 12,
              color: context.colors.bg,
            ),
          ),
          SizedBox(height: gap),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              for (final a in actions)
                InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(20),
                  // No `alignment` on the Container: that makes it fill the
                  // width the Wrap offers. Center(widthFactor: 1) centres the
                  // label while the pill keeps its own (minimum) width.
                  child: Container(
                    height: 36,
                    constraints: BoxConstraints(minWidth: a.width),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: context.colors.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        a.label,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: context.colors.navy,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
