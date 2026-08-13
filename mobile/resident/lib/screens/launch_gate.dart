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
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../theme.dart';

class LaunchGate extends StatefulWidget {
  const LaunchGate({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LaunchGate> createState() => _LaunchGateState();
}

class _LaunchGateState extends State<LaunchGate> {
  String? _error;

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
      _go('/login');
      return;
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
        setState(() => _error =
            'Could not reach the barangay\u2019s system. Check your '
            'connection and try again.');
      }
    }
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.pagePad),
            child: _error == null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('SmartSumbong', style: t.headlineLarge),
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(color: Tokens.navy),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('SmartSumbong',
                          style: t.headlineLarge, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 14, color: Tokens.navy, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () {
                          setState(() => _error = null);
                          _decide();
                        },
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
