// SmartSumbong — verification rejected / account suspended.
//
// Two dead ends the launch gate can route to, and one screen because
// they are the same shape: the account exists, it cannot be used, an
// administrator decided that, and there is nothing the person can do
// in the app about it.
//
// Both were `_Placeholder` stubs in main.dart until now — reachable
// routes rendering a debug widget, which is what someone denied at
// registration would have seen.
//
// The reason is shown when there is one. verify_user_account() and
// set_account_suspension() both write it to users.rejection_reason, and
// the portal's Deny panel labels the field "the applicant sees this".
// Withholding it here would make that label false, and would leave the
// person with no idea what to fix.
//
// Neither state offers a retry. A denied registration has to be filed
// again from scratch; a suspension is lifted by the barangay or not at
// all. Offering a button that cannot work would be worse than the wall.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../theme.dart';

enum AccountBlock { rejected, suspended }

class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({
    super.key,
    required this.auth,
    required this.block,
    this.canRegisterAgain = true,
  });

  final AuthService auth;
  final AccountBlock block;

  /// False in the tanod app, which has no registration screen of its
  /// own — a tanod signs up through the resident app and then uses this
  /// one. Offering a button that routes nowhere would be worse than
  /// saying where to go.
  final bool canRegisterAgain;

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  String? _reason;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await widget.auth.verificationStatus();
      if (!mounted) return;
      setState(() {
        _reason = s.reason;
        _loading = false;
      });
    } catch (_) {
      // The screen still says the important part without it.
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  bool get _isRejected => widget.block == AccountBlock.rejected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),

                Icon(
                  _isRejected
                      ? Icons.cancel_outlined
                      : Icons.pause_circle_outline,
                  size: 56,
                  color: const Color(0xFFFF4949),
                ),
                const SizedBox(height: 16),

                Text(
                  _isRejected
                      ? 'Registration not approved'
                      : 'Account suspended',
                  textAlign: TextAlign.center,
                  style: t.headlineLarge?.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 12),

                Text(
                  _isRejected
                      ? 'The barangay reviewed your registration and did '
                          'not approve it.'
                      : 'The barangay has suspended this account. You '
                          'cannot file or follow up on complaints while '
                          'it is suspended.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, height: 1.5, color: Tokens.navy),
                ),

                if (_loading) ...[
                  const SizedBox(height: 20),
                  const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ] else if (_reason != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Tokens.field,
                      border: Border.all(color: Tokens.navy),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Reason given',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: Tokens.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _reason!,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: Tokens.navy),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Text(
                  _isRejected
                      ? (widget.canRegisterAgain
                          ? 'If you think this is a mistake, visit the '
                              'barangay hall with a valid ID. You can '
                              'register again once the problem is fixed.'
                          : 'If you think this is a mistake, visit the '
                              'barangay hall with your Barangay ID. To '
                              'register again, use the SmartSumbong app '
                              'for residents.')
                      : 'To have this looked at, visit the barangay hall '
                          'with a valid ID.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, height: 1.5, color: Tokens.muted),
                ),

                const Spacer(flex: 2),

                if (_isRejected && widget.canRegisterAgain)
                  FilledButton(
                    onPressed: () async {
                      // Signed out first: registering again creates a new
                      // account, and the denied session must not survive
                      // into it.
                      await widget.auth.signOut();
                      if (context.mounted) {
                        Navigator.of(context)
                            .pushNamedAndRemoveUntil('/register', (_) => false);
                      }
                    },
                    child: const Text('Register again'),
                  ),
                if (_isRejected && widget.canRegisterAgain)
                  const SizedBox(height: 10),

                OutlinedButton(
                  onPressed: _signOut,
                  child: const Text('Sign out'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
