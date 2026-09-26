// SmartSumbong — tanod launch gate.
//
// Same decision as the resident gate, plus one: this app is for tanods,
// and a resident who installs it and signs in must be told so rather
// than dropped onto a duty screen where every action fails against RLS
// with no explanation. The role lives on public.users and is what every
// dispatch policy keys off, so it is the honest thing to check.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import 'login_screen.dart' show rememberMeKey;

/// This screen's own fixed dark gradient (see build() below) never
/// changes with the app's theme setting -- it is a splash/brand moment,
/// not a themed UI surface, the same way the resident app's launch gate
/// hero band stays fixed regardless of dark mode. So the text and
/// controls painted on top of it use these two literals -- the exact
/// values `Tokens.bg`/`Tokens.navy` held before dark mode existed --
/// rather than `context.colors.bg`/`context.colors.navy`, which would
/// go near-black in dark mode and vanish against this gradient.
const _fixedBg = Color(0xFFF3F3F3);
const _fixedNavy = Color(0xFF14181D);

/// True until this app process's first `_decide()` finishes, then false
/// for the rest of the process's life.
///
/// "Remember me" is a promise about surviving an app *restart* — it has
/// nothing to decide the second time this screen is reached in the same
/// run, which happens on every successful sign-in and again after
/// setting a new password (both route back through '/'). Without this
/// guard, unchecking "Remember me" would sign a tanod right back out the
/// instant they landed here — the very screen after they typed their
/// password correctly — because the flag they just set for *next time*
/// was being re-read as though this were next time. Module-level rather
/// than per-widget: a fresh LaunchGate instance is constructed on every
/// one of those re-entries, so instance state cannot carry this across
/// them. See the resident app's launch_gate.dart, where the same bug was
/// found and fixed first.
bool _isColdStart = true;

/// The last account check the phone saw (JsonCache): {'ok': true} when
/// it let the tanod through to Home. Home refreshes it on every load.
const gateCacheKey = 'gate';

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  String? _error;
  bool _wrongApp = false;
  final _biometrics = BiometricAuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _decide());
  }

  Future<void> _decide() async {
    if (widget.auth.session == null) {
      _go('/login');
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
        _go('/login');
        return;
      }

      // Opt-in, set from the Settings toggle -- see smartsumbong_core's
      // biometric_auth.dart. A declined, failed, or cancelled prompt
      // never touches the session sitting on disk; it only sends this
      // one cold start to the password screen instead of restoring
      // silently, exactly as if "remember me" had been off just this
      // once. The account is never signed out over this. See the
      // resident app's launch_gate.dart, where the same gate was added
      // first.
      if (await BiometricAuthService.enabled() &&
          await _biometrics.isAvailable()) {
        final unlocked = await _biometrics
            .authenticate(context.s.launchGateBiometricReason);
        if (!unlocked) {
          _go('/login');
          return;
        }
      }
    }

    // The last check this phone saw let this account in (branch B):
    // straight to Home, no waiting on the network — and Home works
    // offline on its saved copy. Home re-runs every check below with its
    // own first requests and sends the tanod on if anything changed.
    final last = await JsonCache.read(gateCacheKey);
    if (last is Map && last['ok'] == true) {
      _go('/home');
      return;
    }

    try {
      final s = await widget.auth.verificationStatus();

      if (s.isSuspended) {
        _go('/account-suspended');
        return;
      }

      // Checked ahead of the wrong-app/verification branches below for
      // the same reason suspension is: it is the more final state.
      // finalize_retirement() (0052) never un-sets is_retired, so there
      // is no "and it might still change" ordering question the way
      // pending verification has.
      if (s.isRetired) {
        _go('/account-retired');
        return;
      }

      if (s.status != VerificationState.verified) {
        _go(s.status == VerificationState.rejected
            ? '/verification-rejected'
            : '/verification-pending');
        return;
      }

      // A temporary password is still in force. Nothing else happens
      // until it is replaced — the administrator who issued it can sign
      // in as this account until then.
      if (s.mustChangePassword) {
        _go('/change-password');
        return;
      }

      // Verified, but is this a tanod? A resident account reaching here
      // would see an empty ticket list and a duty toggle that silently
      // refuses to save, because duty_status is constrained to tanods
      // in 0001.
      if (await _role() != 'tanod') {
        if (mounted) setState(() => _wrongApp = true);
        return;
      }

      // '/home', not '/duty'. Duty status moved onto the home screen
      // with HOME - TANOD and the standalone duty screen is gone.
      unawaited(JsonCache.write(gateCacheKey, {'ok': true}));
      _go('/home');
    } on AuthRequiredException {
      await widget.auth.signOut();
      _go('/login');
    } on PostgrestException catch (e) {
      // Named, not swallowed. A refused policy and a malformed call both
      // land here, and "check your connection" sends whoever is testing
      // to look at the wifi.
      if (mounted) {
        final s = context.s;
        setState(
            () => _error = s.launchGatePostgrestError(e.message));
      }
    } catch (e) {
      if (mounted) {
        final s = context.s;
        setState(() => _error = s.launchGateOfflineError('$e'));
      }
    }
  }

  /// my_role() is security definer and returns the caller's role without
  /// exposing anyone else's row.
  Future<String?> _role() async {
    final r = await Supabase.instance.client.rpc('my_role');
    return r as String?;
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
  // The resident's loading screen (Figma LOADING SCREEN) in the tanod's
  // colours (branch B): the same contour artwork recoloured to ink
  // (assets/images/loading-bg.png), the three seals on a light plate,
  // the wordmark with "Tanod" in the accent orange, and progress at the
  // bottom.
  Widget build(BuildContext context) {
    final s = context.s;
    return Scaffold(
      backgroundColor: const Color(0xFF14181D),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/loading-bg.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            cacheHeight: (MediaQuery.sizeOf(context).height *
                    MediaQuery.devicePixelRatioOf(context))
                .round(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
              child: Column(
                children: [
                  // The seals first, on a light plate so the navy line
                  // work in their captions reads on the dark ground.
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
                      children: [
                        Image.asset('assets/images/bagong-pilipinas.png',
                            height: 56,
                            filterQuality: FilterQuality.medium,
                            semanticLabel: 'Bagong Pilipinas'),
                        const SizedBox(width: 16),
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
                        const SizedBox(height: 10),
                        const Text(
                          'Sumbong na may resibo,\naksyong garantisado!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.15,
                            color: _fixedBg,
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

              if (_wrongApp) ...[
                Text(
                  s.launchGateWrongApp,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, height: 1.4, color: _fixedBg),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.orange,
                      foregroundColor: _fixedNavy,
                    ),
                    onPressed: () async {
                      await widget.auth.signOut();
                      _go('/login');
                    },
                    child: Text(s.launchGateSignOut),
                  ),
                ),
              ] else if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, height: 1.4, color: _fixedBg),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.orange,
                      foregroundColor: _fixedNavy,
                    ),
                    onPressed: () {
                      setState(() => _error = null);
                      _decide();
                    },
                    child: Text(s.launchGateTryAgain),
                  ),
                ),
              ] else ...[
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 3, color: Tokens.orange),
                ),
                const SizedBox(height: 16),
                Text(
                  s.launchGateSigningIn,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: _fixedBg,
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
