// SmartSumbong — tanod launch gate.
//
// Same decision as the resident gate, plus one: this app is for tanods,
// and a resident who installs it and signs in must be told so rather
// than dropped onto a duty screen where every action fails against RLS
// with no explanation. The role lives on public.users and is what every
// dispatch policy keys off, so it is the honest thing to check.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'login_screen.dart' show rememberMeKey;

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

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  String? _error;
  bool _wrongApp = false;

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
    }

    try {
      final s = await widget.auth.verificationStatus();

      if (s.isSuspended) {
        _go('/account-suspended');
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
      _go('/home');
    } on AuthRequiredException {
      await widget.auth.signOut();
      _go('/login');
    } on PostgrestException catch (e) {
      // Named, not swallowed. A refused policy and a malformed call both
      // land here, and "check your connection" sends whoever is testing
      // to look at the wifi.
      if (mounted) {
        setState(() => _error = 'The barangay\u2019s system refused the '
            'request. (${e.message})');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error =
            'Could not reach the barangay\u2019s system. Check your '
            'connection and try again.\n\n$e');
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
  Widget build(BuildContext context) {
    return Scaffold(
      // Ink rather than the resident's blue, and a gradient rather than
      // a flat fill: white text on unbroken #14181D reads as a crash
      // screen. Lifting the centre toward slate keeps the wordmark and
      // the spinner sitting on something, and keeps contrast well above
      // the point where the text stops being legible outdoors.
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF14181D),
              Color(0xFF2C333D),
              Color(0xFF14181D),
            ],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Text(
                'SmartSumbong',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  color: Tokens.bg,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Tanod',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 20,
                  color: Tokens.orange,
                ),
              ),
              const Spacer(),

              if (_wrongApp) ...[
                const Text(
                  'This account is not a barangay tanod. Please use the '
                  'SmartSumbong resident app to file and follow up on '
                  'complaints.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13, height: 1.4, color: Tokens.bg),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.orange,
                      foregroundColor: Tokens.navy,
                    ),
                    onPressed: () async {
                      await widget.auth.signOut();
                      _go('/login');
                    },
                    child: const Text('Sign out'),
                  ),
                ),
              ] else if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, height: 1.4, color: Tokens.bg),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Tokens.orange,
                      foregroundColor: Tokens.navy,
                    ),
                    onPressed: () {
                      setState(() => _error = null);
                      _decide();
                    },
                    child: const Text('Try again'),
                  ),
                ),
              ] else ...[
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Tokens.orange),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Signing you in\u2026',
                  style: TextStyle(fontSize: 14, color: Tokens.bg),
                ),
              ],

              const Spacer(),
            ],
          ),
        ),
        ),
      ),
    );
  }
}
