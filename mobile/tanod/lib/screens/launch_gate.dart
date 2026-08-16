// SmartSumbong — tanod launch gate.
//
// Same decision as the resident gate, plus one: this app is for tanods,
// and a resident who installs it and signs in must be told so rather
// than dropped onto a duty screen where every action fails against RLS
// with no explanation. The role lives on public.users and is what every
// dispatch policy keys off, so it is the honest thing to check.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

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

      // Verified, but is this a tanod? A resident account reaching here
      // would see an empty ticket list and a duty toggle that silently
      // refuses to save, because duty_status is constrained to tanods
      // in 0001.
      if (await _role() != 'tanod') {
        if (mounted) setState(() => _wrongApp = true);
        return;
      }

      _go('/duty');
    } on AuthRequiredException {
      await widget.auth.signOut();
      _go('/login');
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not reach the barangay\u2019s system. Check your '
            'connection and try again.');
      }
    }
  }

  /// my_role() is security definer and returns the caller's role without
  /// exposing anyone else's row.
  Future<String?> _role() async {
    final r = await Supabase.instance.client.rpc('my_role');
    return r as String?;
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tokens.navy,
      body: SafeArea(
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
    );
  }
}
