// SmartSumbong — verification rejected / account suspended / retired.
//
// Three dead ends the launch gate can route to, and one screen because
// two of them are exactly the same shape: the account exists, it cannot
// be used, an administrator decided that, and there is nothing the
// person can do in the app about it.
//
// Retirement is the odd one in with them structurally — same "cannot
// sign in, go see a human" wall — but not in tone. Rejection and
// suspension are both something gone wrong; retirement is a tanod's
// service ending on request, approved by an admin (0052's
// finalize_retirement). The copy and the accent colour below say so
// rather than pretending a "thank you" belongs on the same red screen
// as a denial.
//
// Rejected and suspended were `_Placeholder` stubs in main.dart until a
// prior pass — reachable routes rendering a debug widget, which is what
// someone denied at registration would have seen.
//
// The reason is shown when there is one. verify_user_account() and
// set_account_suspension() both write it to users.rejection_reason, and
// the portal's Deny panel labels the field "the applicant sees this".
// Withholding it here would make that label false, and would leave the
// person with no idea what to fix. Retirement carries no such reason —
// finalize_retirement() only writes one on a denial, and a denied
// retirement request does not route here at all (the tanod is not
// blocked; see retirement_screen.dart) — so this screen shows the date
// retirement took effect instead.
//
// No state here offers a retry. A denied registration has to be filed
// again from scratch; a suspension is lifted by the barangay or not at
// all; a retirement is final. Offering a button that cannot work would
// be worse than the wall.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../i18n.dart';
import '../theme.dart';

enum AccountBlock { rejected, suspended, retired }

class AccountStatusScreen extends StatefulWidget {
  const AccountStatusScreen({
    super.key,
    required this.auth,
    required this.block,
    this.canRegisterAgain = false,
  });

  final AuthService auth;
  final AccountBlock block;

  /// False in the tanod app, which has no registration screen of its
  /// own — a tanod signs up through the resident app and then uses this
  /// one. Offering a button that routes nowhere would be worse than
  /// saying where to go. Defaults to false, not true, for exactly that
  /// reason: this file's own routes map has no '/register' entry, so a
  /// caller that forgets to override this explicitly must fail closed
  /// (no button) rather than fail open (a button that throws
  /// "Could not find a generator for route" the moment it's tapped).
  /// Every current call site in main.dart passes false explicitly
  /// anyway — this default is the safety net for the next one.
  final bool canRegisterAgain;

  @override
  State<AccountStatusScreen> createState() => _AccountStatusScreenState();
}

class _AccountStatusScreenState extends State<AccountStatusScreen> {
  String? _reason;
  DateTime? _retiredAt;
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
        _retiredAt = s.retiredAt;
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
  bool get _isRetired => widget.block == AccountBlock.retired;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

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
                  _isRetired
                      ? Icons.workspace_premium_outlined
                      : _isRejected
                          ? Icons.cancel_outlined
                          : Icons.pause_circle_outline,
                  size: 56,
                  // Retirement is not a punishment, so it does not get the
                  // same red as a denial or a suspension — the brand
                  // accent reads as a close as this wall gets to positive.
                  color: _isRetired ? Tokens.orange : const Color(0xFFFF4949),
                ),
                const SizedBox(height: 16),

                Text(
                  _isRetired
                      ? s.accountStatusRetiredTitle
                      : _isRejected
                          ? s.accountStatusRejectedTitle
                          : s.accountStatusSuspendedTitle,
                  textAlign: TextAlign.center,
                  style: t.headlineLarge?.copyWith(fontSize: 24),
                ),
                const SizedBox(height: 12),

                Text(
                  _isRetired
                      ? s.accountStatusRetiredBody
                      : _isRejected
                          ? s.accountStatusRejectedBody
                          : s.accountStatusSuspendedBody,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14, height: 1.5, color: context.colors.navy),
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
                ] else if (_isRetired && _retiredAt != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.field,
                      border: Border.all(color: context.colors.navy),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.accountStatusRetiredDateLabel,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: context.colors.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(context, _retiredAt!.toLocal()),
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: context.colors.navy),
                        ),
                      ],
                    ),
                  ),
                ] else if (_reason != null) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.colors.field,
                      border: Border.all(color: context.colors.navy),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.accountStatusReasonGiven,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: context.colors.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _reason!,
                          style: TextStyle(
                              fontSize: 13,
                              height: 1.45,
                              color: context.colors.navy),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                Text(
                  _isRetired
                      ? s.accountStatusRetiredNote
                      : _isRejected
                          ? (widget.canRegisterAgain
                              ? s.accountStatusRejectedCanRegister
                              : s.accountStatusRejectedCannotRegister)
                          : s.accountStatusSuspendedNote,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.5, color: context.colors.muted),
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
                    child: Text(s.accountStatusRegisterAgain),
                  ),
                if (_isRejected && widget.canRegisterAgain)
                  const SizedBox(height: 10),

                OutlinedButton(
                  onPressed: _signOut,
                  child: Text(s.accountStatusSignOut),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// "September 8, 2026" — same long-form date shape used throughout the
  /// app (reports_screen.dart, tanod_home_screen.dart), via the same
  /// context.s.monthFull lookup rather than a second month-name table.
  static String _formatDate(BuildContext context, DateTime d) =>
      '${context.s.monthFull(d.month)} ${d.day}, ${d.year}';
}
