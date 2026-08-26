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
// resume — same reasoning as Verification Pending: this is not a live
// feed, and holding a websocket open for a badge is not worth the
// connection.

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
          .select('full_name, verification_status, is_suspended')
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
    final t = Theme.of(context).textTheme;
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
              color: Tokens.navy,
              child: ListView(
            padding: const EdgeInsets.fromLTRB(26, 12, 26, 24),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _NotificationBell(
                    unread: _unread,
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
                     // The wordmark carries the brand; a screen reader
                     // should hear the name, not "image".
                    semanticLabel: 'SmartSumbong',
                  ),
                ),
              ),

              const SizedBox(height: 24),

              Text(
                _loading
                    ? s.homeWelcomeGeneric
                    : (_firstName == null
                        ? s.homeWelcomeGeneric
                        : s.homeWelcomeNamed(_firstName!)),
                style: t.headlineLarge?.copyWith(fontSize: 22),
              ),
              Text(
                s.homeSubtitle,
                style: t.titleMedium?.copyWith(fontSize: 13),
              ),
              const SizedBox(height: 18),

              _ActionCard(
                title: s.homeEmergencyTitle,
                body: s.homeEmergencyBody,
                actions: [
                  _CardAction(
                    label: s.homeEmergencyLabel,
                    onTap: () =>
                        Navigator.of(context).pushReplacementNamed('/emergency'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _ActionCard(
                title: s.homeReportTitle,
                body: s.homeReportBody,
                actions: [
                  _CardAction(
                    label: s.homeReportIssue,
                    onTap: () =>
                        Navigator.of(context).pushNamed('/submit-report'),
                  ),
                  _CardAction(
                    label: s.homeViewReports,
                    onTap: () =>
                        Navigator.of(context).pushReplacementNamed('/reports'),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              _ActionCard(
                title: s.homeMapTitle,
                body: s.homeMapBody,
                actions: [
                  _CardAction(
                    label: s.homeViewMap,
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
            decoration: const BoxDecoration(
              color: Tokens.navy,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: Tokens.bg, size: 22),
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
                  border: Border.all(color: Tokens.bg, width: 1.5),
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
  const _CardAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final String body;
  final List<_CardAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 16),
      decoration: BoxDecoration(
        color: Tokens.navy,
        border: Border.all(color: Tokens.bg),
        borderRadius: BorderRadius.circular(25),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 2.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              height: 1.15,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 11,
              height: 1.3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final a in actions)
                InkWell(
                  onTap: a.onTap,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Tokens.bg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      a.label,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Tokens.navy,
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
