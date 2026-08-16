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
    return Scaffold(
      backgroundColor: Tokens.navy,
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
                // The composite from the design: gradient, blur and
                // contours already flattened, exported at 4x so it stays
                // sharp on a 1220px handset.
                Image.asset(
                  'assets/images/loading-bg.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset('assets/images/bagong-pilipinas.png',
                            height: 64, semanticLabel: 'Bagong Pilipinas'),
                        const SizedBox(width: 18),
                        // Largest of the three: this is the barangay
                        // whose system it is, and its seal already
                        // carries "Barangay 183 Zone 20 Villamor, Pasay
                        // City" around the rim, so no caption is needed
                        // underneath.
                        Image.asset('assets/images/brgy-183-seal.png',
                            height: 88,
                            semanticLabel: 'Barangay 183 Zone 20 Villamor, '
                                'Pasay City'),
                        const SizedBox(width: 18),
                        Image.asset('assets/images/bagong-villamor.png',
                            height: 64, semanticLabel: 'Bagong Villamor'),
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
              decoration: const BoxDecoration(
                color: Tokens.bg,
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
                            const Text(
                              'Sumbong na may resibo,\naksyong garantisado!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w800,
                                fontSize: 18,
                                height: 1.15,
                                color: Tokens.navy,
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_error == null) ...[
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.5, color: Tokens.navy),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Mabuhay! Signing you in\u2026',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Tokens.navy,
                          ),
                        ),
                      ] else ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13, height: 1.4, color: Tokens.navy),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () {
                              setState(() => _error = null);
                              _decide();
                            },
                            child: const Text('Try again'),
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
