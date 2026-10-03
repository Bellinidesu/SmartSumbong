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

import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../tanod_strings.dart';

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
    final s = context.ts;
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

  // Branch D: locked, a padlock card asking for the password; unlocked,
  // back, the heading, and the services as white rows (retirement today).
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    return DPage(child: _unlocked ? _buildMenu(d, s) : _buildLock(d, s));
  }

  Widget _buildLock(DColors d, TanodStrings s) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
          decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(26), border: Border.all(color: d.line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(shape: BoxShape.circle, color: d.field, border: Border.all(color: d.line)),
                child: Icon(Icons.lock_outline_rounded, size: 34, color: d.link),
              ),
            ),
            const SizedBox(height: 14),
            Text(s.extraAdminServicesLockedTitle, textAlign: TextAlign.center, style: DType.h2(d.ink)),
            const SizedBox(height: 6),
            Text(s.extraAdminServicesLockedBody, textAlign: TextAlign.center, style: DType.body(d.muted, size: 14)),
            const SizedBox(height: 18),
            Text(s.extraAdminServicesPasswordLabel, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800)),
            const SizedBox(height: 6),
            TextField(
              controller: _password,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) => _unlock(),
              style: DType.body(d.ink, size: 15),
              decoration: InputDecoration(
                hintText: s.extraAdminServicesPasswordHint,
                hintStyle: DType.body(d.muted, size: 14),
                filled: true,
                fillColor: d.field,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: DColors.orange, width: 2)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
            ],
            const SizedBox(height: 16),
            DButton(s.extraAdminServicesUnlock, kind: DButtonKind.accent, expand: true, busy: _checking, onTap: _checking ? null : _unlock),
            const SizedBox(height: 8),
            DButton(s.extraAdminServicesBack, kind: DButtonKind.ghost, expand: true, onTap: () => Navigator.of(context).pop()),
          ]),
        ),
      ),
    );
  }

  Widget _buildMenu(DColors d, TanodStrings s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
      children: [
        const Align(alignment: Alignment.centerLeft, child: DBack()),
        const SizedBox(height: 12),
        DHeading(s.extraAdminServicesTitle),
        const SizedBox(height: 18),
        DSheet(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          onTap: () => Navigator.of(context).pushNamed('/t/retirement').then((_) => _loadRetirementStatus().then((_) {
                if (mounted) setState(() {});
              })),
          child: Row(children: [
            DWell(Icons.workspace_premium_outlined, size: 44, color: DColors.orange, tint: DColors.orange.withValues(alpha: .12)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.extraAdminServicesRetirementLabel, style: DType.body(d.ink, size: 15.5, w: FontWeight.w800)),
                Text(_pendingRetirement ? s.extraAdminServicesRetirementPending : s.extraAdminServicesRetirementSubtitle,
                    style: DType.body(_pendingRetirement ? const Color(0xFFB26A00) : d.muted, size: 12.5)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: d.muted),
          ]),
        ),
      ],
    );
  }
}
