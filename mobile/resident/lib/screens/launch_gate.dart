// SmartSumbong — where the app decides what to show on launch.
//
// Without this, initialRoute is a fixed guess. It was '/register', which
// meant a resident who had already signed up got the registration form
// every time they opened the app — no way back to their own pending
// screen short of registering again.
//
// Three questions, in order, each cheap:
//
//   1. Is there a session? supabase_flutter restores it from disk, so
//      this survives the app being killed. No network call.
//   2. What is this account's standing? One row through users_self_read.
//   3. Is the account suspended? A suspended resident holds a valid
//      session and would otherwise reach the home screen and fail at
//      every RLS-guarded action with no explanation.
//
// This screen is also the only place that handles a session whose user
// row no longer exists — deleted account, or a token that outlived it.
// AuthRequiredException means sign out and start again rather than show
// an error nobody can act on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_theme.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import 'login_screen.dart' show rememberMeKey;
import 'onboarding_screen.dart' show onboardingSeenKey;

/// True until this app process's first `_decide()` finishes, then false
/// for the rest of the process's life.
///
/// "Remember me" is a promise about surviving an app *restart* — it has
/// nothing to decide the second, third or fourth time this screen is
/// reached in the same run, which happens on every successful sign-in
/// and again after setting a new password (both route back through '/').
/// Without this guard, unchecking "Remember me" would sign a resident
/// right back out the instant they landed here — the very screen after
/// they typed their password correctly — because the flag they just set
/// for *next time* was being re-read as though this were next time.
/// Module-level rather than per-widget: a fresh LaunchGate instance is
/// constructed on every one of those re-entries, so instance state
/// cannot carry this across them.
bool _isColdStart = true;

/// The last account check the phone saw (JsonCache), shared with Home,
/// which refreshes it on every load.
const gateCacheKey = 'gate';

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  String? _error;
  final _biometrics = BiometricAuthService();

  @override
  void initState() {
    super.initState();
    // After the first frame, so Navigator is available.
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    // No session: send to login, not registration. Most launches are
    // returning residents, and the login screen carries a Sign Up link
    // for the ones who are not.
    if (widget.auth.session == null) {
      // The cold start is over once this screen has run with no session:
      // the sign-in that follows comes back here, and must not be taken
      // for a fresh launch — that signed out, straight after signing in,
      // anyone who had left Remember me unticked.
      _isColdStart = false;
      // First launch on this handset: introduce the app before asking
      // anyone to sign in. Only checked when there is no session — an
      // account already signed in has necessarily been past this.
      if (!await _onboardingSeen()) {
        _go('/onboarding');
        return;
      }
      _go('/roles');
      return;
    }

    // "Remember me" was left unticked at the last sign-in. The session
    // is on disk because supabase_flutter always persists it, so honour
    // the choice here — but only once per process, the actual cold
    // start. See _isColdStart above for why re-checking on every visit
    // to this screen is the wrong thing, not merely a redundant one.
    if (_isColdStart) {
      _isColdStart = false;
      if (!await _remembered()) {
        await widget.auth.signOut();
        _go('/roles');
        return;
      }

      // Opt-in, set from the Settings toggle -- see biometric_auth.dart.
      // A declined, failed, or cancelled prompt never touches the session
      // sitting on disk; it only sends this one cold start to the
      // password screen instead of restoring silently, exactly as if
      // "remember me" had been off just this once. The account is never
      // signed out over this, so a resident who fails or skips the
      // prompt loses nothing but has to type their password like before
      // this feature existed.
      if (await BiometricAuthService.enabled() &&
          await _biometrics.isAvailable()) {
        if (!mounted) return;
        final unlocked =
            await _biometrics.authenticate(context.s.launchGateBiometricReason);
        if (!unlocked) {
          _go('/login');
          return;
        }
      }
    }

    // The last check this phone saw said "verified, not suspended, no
    // temporary password" (branch B): straight to Home, no waiting on
    // the network. Home re-checks all three with its own first request
    // and sends the resident on if anything changed, so nothing the
    // round trip below enforced is skipped — it just stops holding the
    // loading screen on every launch.
    // One app for both roles (branch C): the saved check carries the
    // role too, so a tanod lands on the tanod home in ink.
    final last = await JsonCache.read(gateCacheKey);
    if (last is Map &&
        last['verified'] == true &&
        last['suspended'] != true &&
        last['retired'] != true &&
        last['must_change'] != true &&
        last['role'] is String) {
      final tanod = last['role'] == 'tanod';
      await AppRoleController.instance.set(tanod ? AppRole.tanod : AppRole.resident);
      await AppRoleController.instance.rememberSignedIn(tanod ? AppRole.tanod : AppRole.resident);
      _go(tanod ? '/t/home' : '/home');
      return;
    }

    try {
      // The role alongside the account check, not after it: one round
      // trip's wait, not two.
      final got = await Future.wait<Object?>([
        widget.auth.verificationStatus(),
        Supabase.instance.client.rpc('my_role'),
      ]);
      final s = got[0] as VerificationSnapshot;
      final role = got[1] as String?;
      final tanod = role == 'tanod';
      await AppRoleController.instance.set(tanod ? AppRole.tanod : AppRole.resident);
      await AppRoleController.instance.rememberSignedIn(tanod ? AppRole.tanod : AppRole.resident);
      unawaited(JsonCache.write(gateCacheKey, {
        'verified': s.status == VerificationState.verified,
        'suspended': s.isSuspended,
        'retired': s.isRetired,
        'must_change': s.mustChangePassword,
        'role': role,
      }));

      // Suspended accounts keep a valid session but can do nothing. Say
      // so plainly rather than letting them reach a home screen where
      // every action fails against RLS with no explanation.
      if (s.isSuspended) {
        _go('/account-suspended');
        return;
      }

      // A retired tanod (0052): final, like a suspension.
      if (s.isRetired) {
        _go('/account-retired');
        return;
      }

      // A temporary password is still in force. Nothing else happens
      // until it is replaced — the administrator who issued it can sign
      // in as this account until then.
      if (s.mustChangePassword) {
        _go('/change-password');
        return;
      }

      _go(switch (s.status) {
        VerificationState.verified => tanod ? '/t/home' : '/home',
        VerificationState.rejected => '/verification-rejected',
        VerificationState.pending => '/verification-pending',
      });
    } on AuthRequiredException {
      // The session outlived the account, or the token is unusable.
      // Clear it so the next launch does not repeat this round trip.
      await widget.auth.signOut();
      _go('/login');
    } catch (_) {
      // Offline, or Supabase unreachable. Do not guess and do not strand
      // the user on a spinner — offer a retry.
      if (mounted) {
        setState(() => _error = context.s.launchGateOfflineError);
      }
    }
  }

  /// Storage failures are treated as "already seen". Showing the
  /// introduction on every launch would be worse than never showing it.
  Future<bool> _onboardingSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(onboardingSeenKey) ?? false;
    } catch (_) {
      return true;
    }
  }

  /// Absent means remember. Only an explicit false signs the account
  /// out, so a storage failure can never lock anyone out of their own
  /// session.
  Future<bool> _remembered() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(rememberMeKey) ?? true;
    } catch (_) {
      return true;
    }
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  // Figma LOADING SCREEN (2074:265): the barangay blue, its angular
  // gradient and contours (loading-bg.png, exported flattened) edge to
  // edge — the frame's other layers are hidden, so the seals, wordmark
  // and progress sit on that one surface rather than on a split band and
  // card. At night the same artwork, dimmed toward the dark palette.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    const onBlue = Color(0xFFF3F3F3);
    // A tanod's phone opens on the tanod loading screen (branch C, one
    // app): the same layout in ink, as the tanod app had it.
    final tanod = AppRoleController.instance.value == AppRole.tanod;
    // Branch D: the role colour edge to edge (navy, or the tanod's ink —
    // black at night), the contour lines over it, a soft light from the top.
    final d = tanod
        ? (context.isDark ? DColors.tanodDark : DColors.tanodLight)
        : (context.isDark ? DColors.residentDark : DColors.residentLight);
    return Scaffold(
      backgroundColor: d.card2,
      body: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: tanod
                    ? (context.isDark ? const [Color(0xFF2A3038), Color(0xFF0E1115)] : const [Color(0xFF3A414A), Color(0xFF14181D)])
                    : (context.isDark ? const [Color(0xFF13235A), Color(0xFF070D24)] : const [Color(0xFF1C4FC0), Color(0xFF00236A)]),
              ),
            ),
          ),
          Image.asset('assets/images/texture.png',
              fit: BoxFit.cover, color: Colors.white.withValues(alpha: .10), colorBlendMode: BlendMode.srcIn),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -.55), radius: .9, colors: [Color(0x33FFFFFF), Color(0x00FFFFFF)]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
              child: Column(
                children: [
                  // The official credential first: the three seals, on a
                  // light plate so the navy line work in their captions
                  // ("Bagong Pilipinas", "Bagong Villamor") stays legible
                  // on the blue.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xF2FBFBFB),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: kFigmaShadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/bagong-pilipinas.png',
                            height: 56,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Bagong Pilipinas'),
                        const SizedBox(width: 16),
                        // Largest of the three: this is the barangay whose
                        // system it is; its rim already names it.
                        Image.asset('assets/images/brgy-183-seal.png',
                            height: 76,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Barangay 183 Zone 20 Villamor, '
                                'Pasay City'),
                        const SizedBox(width: 16),
                        Image.asset('assets/images/bagong-villamor.png',
                            height: 56,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Bagong Villamor'),
                      ],
                    ),
                  ),

                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FractionallySizedBox(
                          widthFactor: 0.78,
                          child: Image.asset(
                            'assets/images/logo-wordmark.png',
                            semanticLabel: 'SmartSumbong',
                          ),
                        ),
                        if (tanod) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Tanod',
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontWeight: FontWeight.w800,
                              fontStyle: FontStyle.italic,
                              fontSize: 28,
                              color: Tokens.orange,
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const Text(
                          'Sumbong na may resibo,\naksyong garantisado!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.15,
                            color: onBlue,
                            shadows: [
                              Shadow(
                                color: Color(0x66000000),
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (_error == null) ...[
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: onBlue),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      s.launchGateSigningIn,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: onBlue,
                      ),
                    ),
                  ] else ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          height: 1.4,
                          color: onBlue),
                    ),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 301),
                      child: FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _decide();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: onBlue,
                          foregroundColor: AppColors.light.navy,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        child: Text(s.launchGateTryAgain),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
