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

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';

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
  // Branch D: one centred card — the state's icon in a soft circle of its
  // colour, the heading and what it means, the reason or the date, the
  // note, then Register again (when allowed) and Sign out.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final tint = _isRetired ? DColors.orange : (d.dark ? const Color(0xFFFF8A8A) : DColors.red);
    Widget box(String label, String value) => Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(color: d.field, borderRadius: BorderRadius.circular(14), border: Border.all(color: d.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: DType.body(d.ink, size: 13.5, w: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(value, style: DType.body(d.ink2, size: 14)),
          ]),
        );
    return PopScope(
      canPop: false,
      child: DPage(
        fullContour: true,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              decoration: BoxDecoration(
                color: d.card,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: d.line),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: d.dark ? .35 : .08), blurRadius: 24, offset: const Offset(0, 10))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Container(
                    width: 74,
                    height: 74,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: tint.withValues(alpha: .14)),
                    child: Icon(
                      _isRetired ? Icons.workspace_premium_outlined : _isRejected ? Icons.cancel_outlined : Icons.pause_circle_outline,
                      size: 40,
                      color: tint,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _isRetired ? s.accountStatusRetiredTitle : _isRejected ? s.accountStatusRejectedTitle : s.accountStatusSuspendedTitle,
                  textAlign: TextAlign.center,
                  style: DType.h1(d.ink),
                ),
                const SizedBox(height: 8),
                Text(
                  _isRetired ? s.accountStatusRetiredBody : _isRejected ? s.accountStatusRejectedBody : s.accountStatusSuspendedBody,
                  textAlign: TextAlign.center,
                  style: DType.body(d.ink2, size: 15),
                ),
                if (_loading) ...[
                  const SizedBox(height: 18),
                  const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                ] else if (_isRetired && _retiredAt != null) ...[
                  const SizedBox(height: 18),
                  box(s.accountStatusRetiredDateLabel, () {
                    final t = _retiredAt!.toLocal();
                    return '${s.monthFull(t.month)} ${t.day}, ${t.year}';
                  }()),
                ] else if (_reason != null) ...[
                  const SizedBox(height: 18),
                  box(s.accountStatusReasonGiven, _reason!),
                ],
                const SizedBox(height: 14),
                Text(
                  _isRetired
                      ? s.accountStatusRetiredNote
                      : _isRejected
                          ? (widget.canRegisterAgain ? s.accountStatusRejectedCanRegister : s.accountStatusRejectedCannotRegister)
                          : s.accountStatusSuspendedNote,
                  textAlign: TextAlign.center,
                  style: DType.body(d.muted, size: 13),
                ),
                const SizedBox(height: 20),
                if (_isRejected && widget.canRegisterAgain) ...[
                  DButton(s.accountStatusRegisterAgain, expand: true, onTap: () async {
                    // Signed out first: registering again creates a new
                    // account, and the denied session must not survive.
                    await widget.auth.signOut();
                    if (context.mounted) Navigator.of(context).pushNamedAndRemoveUntil('/register', (_) => false);
                  }),
                  const SizedBox(height: 10),
                ],
                DButton(s.accountStatusSignOut,
                    kind: _isRejected && widget.canRegisterAgain ? DButtonKind.ghost : DButtonKind.accent, expand: true, onTap: _signOut),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
