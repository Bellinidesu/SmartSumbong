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
        Text(
          s.extraAdminServicesLockedTitle,
          textAlign: TextAlign.center,
          style: t.headlineLarge?.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 10),
        Text(
          s.extraAdminServicesLockedBody,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: c.muted),
        ),
        const SizedBox(height: 24),

        Text(s.extraAdminServicesPasswordLabel,
            style: TextStyle(fontSize: 13, color: c.navy)),
        const SizedBox(height: 6),
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

        FilledButton(
          onPressed: _checking ? null : _unlock,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
          child: _checking
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : Text(s.extraAdminServicesUnlock),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
          child: Text(s.extraAdminServicesBack),
        ),
        const Spacer(flex: 2),
      ],
    );
  }

  Widget _buildMenu(TextTheme t, AppColors c, Strings s) {
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(s.extraAdminServicesTitle,
            textAlign: TextAlign.center,
            style: t.headlineLarge?.copyWith(fontSize: 22)),
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
                          style: TextStyle(fontSize: 14, color: c.navy)),
                      Text(
                        _pendingRetirement
                            ? s.extraAdminServicesRetirementPending
                            : s.extraAdminServicesRetirementSubtitle,
                        style: TextStyle(fontSize: 11.5, color: c.muted),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: c.navy, size: 20),
              ],
            ),
          ),
        ),

        const Spacer(),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            minimumSize: const Size(120, 42),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
          ),
          child: Text(s.extraAdminServicesBack),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
