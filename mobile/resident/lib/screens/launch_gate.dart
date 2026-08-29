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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../i18n.dart';
import '../theme.dart';
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
        final unlocked =
            await _biometrics.authenticate(context.s.launchGateBiometricReason);
        if (!unlocked) {
          _go('/login');
          return;
        }
      }
    }

    try {
      final s = await widget.auth.verificationStatus();

      // Suspended accounts keep a valid session but can do nothing. Say
      // so plainly rather than letting them reach a home screen where
      // every action fails against RLS with no explanation.
      if (s.isSuspended) {
        _go('/account-suspended');
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
        VerificationState.verified => '/home',
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

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      // Only ever visible as a small triangle at the product card's two
      // rounded top corners below -- BoxDecoration's rounded corners
      // don't paint all the way into their own bounding box's corner,
      // so whatever sits behind peeks through right there. Deliberately
      // fixed rather than context.colors.navy: the hero band above it
      // (loading-bg.png + _SealWash) is itself fixed regardless of
      // theme, so this sliver has to match that fixed blue artwork, not
      // flip to dark mode's near-white "navy" and stick out against it.
      backgroundColor: AppColors.light.navy,
      body: Column(
        children: [
          // The official half. Three seals on the barangay blue: this is
          // the first thing a resident sees, and for someone deciding
          // whether to hand a government ID to an app on their phone,
          // the seals are the credential. The wordmark below is the
          // product; these are the authority behind it.
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Light: the composite from the design, gradient, blur
                // and contours already flattened, exported at 4x so it
                // stays sharp on a 1220px handset. Dark: there is no
                // dark version of that artwork to export, so this is a
                // plain in-code gradient in the same family as the rest
                // of the dark palette rather than a second image asset
                // -- worth a look on a real device, same caveat as the
                // dark palette itself.
                if (context.isDark)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFF24406E),
                          Color(0xFF152C52),
                          Color(0xFF0D1B33),
                        ],
                        stops: [0.0, 0.55, 1.0],
                      ),
                    ),
                  )
                else
                  Image.asset(
                    'assets/images/loading-bg.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                Positioned.fill(child: _SealWash(dark: context.isDark)),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/bagong-pilipinas.png',
                            height: 64,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Bagong Pilipinas'),
                        const SizedBox(width: 18),
                        // Largest of the three: this is the barangay
                        // whose system it is, and its seal already
                        // carries "Barangay 183 Zone 20 Villamor, Pasay
                        // City" around the rim, so no caption is needed
                        // underneath.
                        Image.asset('assets/images/brgy-183-seal.png',
                            height: 88,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Barangay 183 Zone 20 Villamor, '
                                'Pasay City'),
                        const SizedBox(width: 18),
                        Image.asset('assets/images/bagong-villamor.png',
                            height: 64,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Bagong Villamor'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // The product half, on the page background, with the rounded
          // shoulder from the design.
          Expanded(
            flex: 6,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.colors.bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 28, 32, 32),
                  child: Column(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            FractionallySizedBox(
                              widthFactor: 0.72,
                              child: Image.asset(
                                'assets/images/logo-wordmark.png',
                                semanticLabel: 'SmartSumbong',
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sumbong na may resibo,\naksyong garantisado!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                height: 1.15,
                                color: context.colors.navy,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_error == null) ...[
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: context.colors.navy),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          s.launchGateSigningIn,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: context.colors.navy,
                          ),
                        ),
                      ] else ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, height: 1.4, color: context.colors.navy),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _decide();
                            },
                            child: Text(s.launchGateTryAgain),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Lightens the band the seals sit in, and deepens the band below it.
///
/// All three seals carry some navy line work (most visibly the "Bagong
/// Pilipinas"/"Bagong Villamor" wordmarks under two of them) that reads
/// poorly unmodified against a navy-family background, light or dark.
/// Rather than framing each one, this lifts the top of the background so
/// that line work has something to sit against, then falls away to a
/// deepened tone that gives the card's shoulder below an edge to land
/// on.
///
/// Two colour sets, not one reactive set of colours: composited against
/// its own background (loading-bg.png in light, the in-code gradient
/// above in dark) rather than swapped in isolation, so each needed its
/// own tuning pass rather than being derivable from the other. Checked
/// against the actual seal artwork composited on the dark gradient's
/// tones (the seal graphics themselves read fine on dark navy even
/// unlifted; it's specifically those two wordmark captions that need
/// the lift) but, same as the rest of dark mode, not checked on a real
/// handset yet.
///
/// The stops are the whole design. [_washTop]/[_washTopDark] have to go
/// far enough that navy reads cleanly — a pale blue looks considered
/// and is still hard to read, which is worse than not trying. Tune on
/// the handset, in daylight, not on a monitor.
class _SealWash extends StatelessWidget {
  const _SealWash({required this.dark});

  final bool dark;

  /// Near-white behind the seals, light mode.
  static const _washTop = Color(0xF2FFFFFF);

  /// A translucent pale blue-lavender lift, dark mode -- enough to give
  /// the wordmark captions something to sit against without the stark
  /// white-out a light-mode wash would be against a dark background.
  static const _washTopDark = Color(0xB3B9C8EA);

  /// Where the lift has fully released back to the artwork, both modes.
  static const _washClear = 0.46;

  /// A deepening toward the shoulder of the card below, light mode.
  static const _washBottom = Color(0x33001A4D);

  /// Same idea, dark mode -- the in-code gradient above is already
  /// close to the card's own colour by its bottom edge, so this only
  /// needs to nudge the seam rather than do the heavy lifting light
  /// mode's version does.
  static const _washBottomDark = Color(0x59000814);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            dark ? _washTopDark : _washTop,
            const Color(0x00FFFFFF),
            dark ? _washBottomDark : _washBottom,
          ],
          stops: const [0.0, _washClear, 1.0],
        ),
      ),
    );
  }
}
