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

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

enum AccountBlock { rejected, suspended, retired }

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

  /// A retired tanod (0052) — one app for both roles since branch C.
  bool get _isRetired => widget.block == AccountBlock.retired;

  // No frame of its own: set like its sibling VERIFICATION PENDING —
  // over the contour texture, the 30/800 title and 16/500 body centred,
  // the barangay's reason in a radius-25 card, and the design's 301x44
  // pills (navy Register again, light Sign out).
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            const FigmaTexture(),
            SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    46, figmaTop(context, 240, min: 32), 46, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          _isRetired
                              ? Icons.workspace_premium_outlined
                              : _isRejected
                                  ? Icons.cancel_outlined
                                  : Icons.pause_circle_outline,
                          size: 56,
                          color: _isRetired ? Tokens.orange : kFigmaRed,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _isRetired
                              ? s.accountStatusRetiredTitle
                              : _isRejected
                                  ? s.accountStatusRejectedTitle
                                  : s.accountStatusSuspendedTitle,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w800,
                            fontSize: 30,
                            height: 1.1,
                            color: c.navy,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isRetired
                              ? s.accountStatusRetiredBody
                              : _isRejected
                                  ? s.accountStatusRejectedBody
                                  : s.accountStatusSuspendedBody,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                            height: 20 / 16,
                            color: c.navy,
                          ),
                        ),

                        if (_loading) ...[
                          const SizedBox(height: 20),
                          Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: c.navy),
                            ),
                          ),
                        ] else if (_isRetired && _retiredAt != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                            decoration: BoxDecoration(
                              color: c.field,
                              border: Border.all(color: c.navy),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.accountStatusRetiredDateLabel,
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: c.navy,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  () {
                                    final d = _retiredAt!.toLocal();
                                    return '${s.monthFull(d.month)} ${d.day}, ${d.year}';
                                  }(),
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    height: 1.4,
                                    color: c.navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else if (_reason != null) ...[
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                            decoration: BoxDecoration(
                              color: c.field,
                              border: Border.all(color: c.navy),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.accountStatusReasonGiven,
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: c.navy,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _reason!,
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    height: 1.4,
                                    color: c.navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),
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
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            height: 1.4,
                            color: c.muted,
                          ),
                        ),
                        const SizedBox(height: 40),

                        if (_isRejected && widget.canRegisterAgain) ...[
                          FigmaPill(
                            onPressed: () async {
                              // Signed out first: registering again
                              // creates a new account, and the denied
                              // session must not survive into it.
                              await widget.auth.signOut();
                              if (context.mounted) {
                                Navigator.of(context).pushNamedAndRemoveUntil(
                                    '/register', (_) => false);
                              }
                            },
                            child: Text(s.accountStatusRegisterAgain),
                          ),
                          const SizedBox(height: 16),
                        ],

                        FigmaPill(
                          style: _isRejected && widget.canRegisterAgain
                              ? FigmaPillStyle.light
                              : FigmaPillStyle.navy,
                          onPressed: _signOut,
                          child: Text(s.accountStatusSignOut),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
