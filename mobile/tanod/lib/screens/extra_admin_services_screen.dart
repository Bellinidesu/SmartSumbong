// SmartSumbong — Extra Administrative Services (tanod).
//
// Not a Figma frame — there is no design for this because the barangay
// asked for it directly, in the same breath as Retirement: "to even
// access the retirement option its also locked in EXTRA ADMINISTRATIVE
// SERVICES which also requires password." So this screen is a lock, not
// a menu that happens to have a lock in front of it. It opens locked
// every time — there is no "stay unlocked" state to remember, on
// purpose, since a fresh instance of this screen is pushed each visit
// and _unlocked always starts false.
//
// The password check itself is AuthService.verifyPassword (smartsumbong
// core) — the same signInWithPassword mechanism sign-in already uses,
// aimed at the account already signed in rather than a login form. It
// is deliberately a second, independent check from whatever unlocked
// the phone itself (a PIN, biometrics via BiometricLockGate) — a device
// left unlocked on a desk should not be enough to reach this.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

class ExtraAdminServicesScreen extends StatefulWidget {
  const ExtraAdminServicesScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<ExtraAdminServicesScreen> createState() =>
      _ExtraAdminServicesScreenState();
}

class _ExtraAdminServicesScreenState extends State<ExtraAdminServicesScreen> {
  final _password = TextEditingController();
  bool _unlocked = false;
  bool _checking = false;
  String? _error;

  bool _pendingRetirement = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final s = context.s;
    if (_password.text.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final ok = await widget.auth.verifyPassword(_password.text);
      if (!mounted) return;
      if (!ok) {
        setState(() {
          _error = s.extraAdminServicesWrongPassword;
          _checking = false;
        });
        return;
      }
      await _loadRetirementStatus();
      if (!mounted) return;
      setState(() {
        _unlocked = true;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = s.extraAdminServicesCheckFailed;
        _checking = false;
      });
    }
  }

  /// Advisory only — a failure here still lets the tanod in and just
  /// leaves the pending-request note off the Retirement row, the same
  /// way Retirement's own screen re-checks on open and would tell them
  /// properly.
  Future<void> _loadRetirementStatus() async {
    try {
      final rows = await Supabase.instance.client
          .rpc('my_retirement_status') as List;
      if (rows.isEmpty) return;
      final row = rows.first as Map<String, dynamic>;
      _pendingRetirement = row['status'] == 'pending';
    } catch (_) {
      // See doc comment above.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final s = context.s;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: _unlocked ? _buildMenu(t, c, s) : _buildLock(t, c, s),
        ),
      ),
    );
  }

  Widget _buildLock(TextTheme t, AppColors c, Strings s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(Icons.lock_outline, size: 48, color: c.navy),
        const SizedBox(height: 16),
        // In the frames' language: 24/800 title, 16/500 body, the 16/700
        // field label, the frames' 44-tall pills.
        FigmaTitle(s.extraAdminServicesLockedTitle, size: 24),
        const SizedBox(height: 8),
        Text(
          s.extraAdminServicesLockedBody,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 1.4,
            color: c.muted,
          ),
        ),
        const SizedBox(height: 24),

        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: Text(s.extraAdminServicesPasswordLabel,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: c.navy,
              )),
        ),
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          onSubmitted: (_) => _unlock(),
          style: TextStyle(fontSize: 14, color: c.navy),
          decoration:
              InputDecoration(hintText: s.extraAdminServicesPasswordHint),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: c.hint, fontSize: 12)),
        ],
        const SizedBox(height: 20),

        FigmaPill(
          onPressed: _checking ? null : _unlock,
          child: _checking
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.bg),
                )
              : Text(s.extraAdminServicesUnlock),
        ),
        const SizedBox(height: 14),
        FigmaPill(
          style: FigmaPillStyle.light,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.extraAdminServicesBack),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _buildMenu(TextTheme t, AppColors c, Strings s) {
    return Column(
      children: [
        SizedBox(height: figmaTop(context, 50)),
        FigmaTitle(s.extraAdminServicesTitle),
        const SizedBox(height: 28),

        InkWell(
          onTap: () => Navigator.of(context)
              .pushNamed('/retirement')
              .then((_) => _loadRetirementStatus().then((_) {
                    if (mounted) setState(() {});
                  })),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    color: c.navy, size: 22),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.extraAdminServicesRetirementLabel,
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: c.navy,
                          )),
                      const SizedBox(height: 2),
                      Text(
                        _pendingRetirement
                            ? s.extraAdminServicesRetirementPending
                            : s.extraAdminServicesRetirementSubtitle,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          color: c.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.navy, size: 20),
              ],
            ),
          ),
        ),

        const SizedBox(height: 40),
        FigmaBackPill(label: s.extraAdminServicesBack),
        const Spacer(),
      ],
    );
  }
}
