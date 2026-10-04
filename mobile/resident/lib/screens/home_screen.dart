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
import '../outbox.dart';
import 'launch_gate.dart' show gateCacheKey;
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../d/flood_watch.dart';
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

  FloodReading? _flood;
  Timer? _floodTimer;

  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (state == AppLifecycleState.resumed) {
      _load();
      // Anything filed while offline goes out now.
      Outbox.instance.flush();
    }
  }

  static const _homeCacheKey = 'home';

  /// Last launch's greeting and badge, shown at once.
  Future<void> _showSaved() async {
    final c = await JsonCache.read(_homeCacheKey);
    if (c is! Map || !mounted || !_loading) return;
    setState(() {
      _firstName = c['first_name'] as String?;
      _unread = (c['unread'] as num?)?.toInt() ?? 0;
      _loading = false;
    });
  }

  Future<void> _load() async {
    if (_loading) unawaited(_showSaved());
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      _bounce('/login');
      return;
    }

    try {
      // The profile and the unread count together (branch B): both need
      // only the uid. The count is simply dropped if the profile sends
      // the resident elsewhere.
      final got = await Future.wait<Object?>([
        client
            .from('users')
            .select('full_name, role, verification_status, is_suspended, '
                'must_change_password, '
                'id_image_url, id_type, ocr_rescan_requested_at')
            .eq('id', uid)
            .maybeSingle(),
        client
            .from('notifications')
            .count(CountOption.exact)
            .eq('user_id', uid)
            .eq('is_read', false),
      ], eagerError: true);
      final profile = got[0] as Map<String, dynamic>?;
      final unread = got[1] as int;

      if (profile == null) {
        _bounce('/login');
        return;
      }

      // The loading screen now sends a resident here on the last check
      // it saw (branch B), so this is the check: remembered for the next
      // launch, and acted on if anything changed.
      unawaited(JsonCache.write(gateCacheKey, {
        'verified': profile['verification_status'] == 'verified',
        'suspended': profile['is_suspended'] == true,
        'must_change': profile['must_change_password'] == true,
        'role': profile['role'],
      }));

      // One app for both roles (branch C): a tanod belongs on the tanod
      // home; the loading screen sends them there.
      if (profile['role'] == 'tanod') {
        _bounce('/');
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
      // A temporary password from the barangay: nothing else until it is
      // replaced (was the loading screen's check).
      if (profile['must_change_password'] == true) {
        _bounce('/change-password');
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
      if (kIdOcrEnabled &&
          profile['ocr_rescan_requested_at'] != null &&
          profile['id_image_url'] != null) {
        unawaited(_maybeRescanId(
          imageUrl: profile['id_image_url'] as String,
          fullName: profile['full_name'] as String? ?? '',
          idTypeWire: profile['id_type'] as String?,
        ));
      }

      if (!mounted) return;
      setState(() {
        _firstName = _firstNameOf(profile['full_name'] as String?);
        _unread = unread;
        _loading = false;
      });
      unawaited(JsonCache.write(_homeCacheKey,
          {'first_name': _firstName, 'unread': unread}));
    } on PostgrestException catch (e) {
      // The session outlived the account or its token is unusable (was
      // the loading screen's AuthRequiredException): sign in again.
      if (e.code == 'PGRST301' || e.message.toLowerCase().contains('jwt')) {
        await widget.auth.signOut();
        _bounce('/login');
        return;
      }
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      // Offline. Show the screen anyway — the cards are static and the
      // buttons still work; the greeting and badge are the saved ones.
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

  // Branch D, 1:1 with the preview's Home (in the C app's layout): the
  // bell alone at the top right, the trimmed wordmark centred (250 px, at
  // most 70% of the width) with 44 above and 14 below, the greeting, the
  // flood watch, then the three cards on a 14 gap. The contour runs the
  // page's full height.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final w = MediaQuery.sizeOf(context).width;
    return DPage(
      homeContour: true,
      bottomBar: const ResidentNavBar(current: ResidentTab.home),
      child: RefreshIndicator(
        onRefresh: () async {
          await _load();
          await _readFlood();
        },
        color: d.accent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 44, 0, 14),
                child: Center(
                  child: Image.asset('assets/images/home-wordmark-trim.png',
                      width: (w - 40) * .7 < 250 ? (w - 40) * .7 : 250, semanticLabel: 'SmartSumbong', filterQuality: FilterQuality.medium),
                ),
              ),
              Positioned(top: 0, right: 0, child: DBell(unread: _unread, onTap: () => Navigator.of(context).pushNamed('/notifications'))),
            ]),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_loading || _firstName == null ? s.homeWelcomeGeneric : s.homeWelcomeNamed(_firstName!),
                  style: DType.h1(d.ink).copyWith(letterSpacing: 0, height: 1.2)),
            ),
            Text(s.homeSubtitle, style: DType.body(d.muted, size: 14).copyWith(height: 1.3)),
            const SizedBox(height: 14),
            DFloodCard(reading: _flood, onTap: () => Navigator.of(context).pushReplacementNamed('/map')),
            const SizedBox(height: 14),
            DCard(
              gradient: const [Color(0xFFC62828), Color(0xFF8E1B1B)],
              padding: const EdgeInsets.all(18),
              child: _CardBody(
                title: s.homeEmergencyTitle,
                body: s.homeEmergencyBody,
                actions: [DButton(s.homeEmergencyLabel, small: true, kind: DButtonKind.white, onTap: () => Navigator.of(context).pushReplacementNamed('/emergency'))],
              ),
            ),
            const SizedBox(height: 14),
            DCard(
              padding: const EdgeInsets.all(18),
              child: _CardBody(
                title: s.homeReportTitle,
                body: s.homeReportBody,
                actions: [
                  DButton(s.homeReportIssue, small: true, textColour: Colors.white, onTap: () => Navigator.of(context).pushNamed('/submit-report')),
                  DButton(s.homeViewReports, small: true, kind: DButtonKind.white, onTap: () => Navigator.of(context).pushReplacementNamed('/reports')),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DCard(
              padding: const EdgeInsets.all(18),
              child: _CardBody(
                title: s.homeMapTitle,
                body: s.homeMapBody,
                actions: [DButton(s.homeViewMap, small: true, kind: DButtonKind.white, onTap: () => Navigator.of(context).pushReplacementNamed('/map'))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({required this.title, required this.body, required this.actions});

  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 19, height: 1.25, color: Colors.white)),
      const SizedBox(height: 8),
      Text(body, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 13, height: 1.4, color: Colors.white.withValues(alpha: .85))),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: actions),
    ]);
  }
}
