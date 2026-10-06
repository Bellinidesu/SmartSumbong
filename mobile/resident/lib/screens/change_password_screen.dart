// SmartSumbong — set a new password.
//
// Reached only when public.users.must_change_password is true, which an
// administrator sets by issuing a temporary password (0028).
//
// There is no way past this screen except setting a password or signing
// out. That is the point: until the change happens, the administrator
// who read the temporary password across the counter still holds
// working credentials for this account. A screen that could be
// dismissed would leave that true indefinitely and quietly.
//
// No "current password" field. The person arrived here holding a
// password a stranger chose and read aloud; asking them to type it
// again proves nothing, and Supabase's updateUser() acts on the session
// rather than on a re-check.

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../theme.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  String? _error;

  /// Which field the error belongs to, so the frame's red state lands on
  /// the right one: 'new' (too short), 'both' (mismatch), or null for a
  /// server failure shown under the form.
  String? _errorOn;

  /// Set once the new password is saved: the frame's success page, whose
  /// button then carries on through the gate as before.
  bool _done = false;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_password.text.length < 8) {
      setState(() {
        _error = context.s.changePasswordTooShort;
        _errorOn = 'new';
      });
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() {
        _error = context.s.changePasswordMismatch;
        _errorOn = 'both';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _errorOn = null;
    });

    try {
      await widget.auth.changePassword(_password.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = true;
      });
    } on RegistrationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } on AuthRequiredException {
      if (!mounted) return;
      await widget.auth.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.s.changePasswordFailed;
      });
    }
  }

  Future<void> _signOut() async {
    await widget.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    }
  }

  // Back through the gate, which will now see the flag cleared.
  void _continue() =>
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);

  // Figma RESET PASSWORD / PASSWORD DIDN'T MATCH / RESET PASSWORD SUCCESS
  // (the resident's navy version): the 30/800 title at 109, 16/700 labels
  // over 301x44 fields with the 10/400 red note under each (the field and
  // its hint turn red when it is the one in error), and the 301x44 Submit
  // 34 below. The app's own note on why this screen exists, and the way
  // to sign out instead, stay.
  @override
  Widget build(BuildContext context) {
    final s = context.s;

    // No back button and no gesture out. Signing out is the only other
    // way off this screen, and it is offered explicitly below.
    // Branch D, 1:1 with the preview's Change password: the h2, the lead
    // line, one bordered box of two fields (UPPERCASE label, the note
    // under the field, wide letter-spaced dots), and Save password.
    return PopScope(
      canPop: false,
      child: DPage(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: _done
              ? Center(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(22, 24, 22, 24), child: _success(s)))
              : _form(s),
        ),
      ),
    );
  }

  Widget _success(Strings s) {
    return Column(
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(shape: BoxShape.circle, color: DColors.greenVivid.withValues(alpha: .15)),
            child: const Icon(Icons.verified_user_rounded, size: 38, color: DColors.greenVivid),
          ),
          const SizedBox(height: 14),
          Text(
            s.changePasswordDoneTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w800,
              fontSize: 26,
              height: 1.1,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            s.changePasswordDoneBody,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 16,
              height: 20 / 16,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 22),
          DButton(s.changePasswordContinue, expand: true, onTap: _continue),
        ],
    );
  }

  Widget _form(Strings s) {
    final d = context.d;
    final newBad = _errorOn == 'new' || _errorOn == 'both';
    final confirmBad = _errorOn == 'both';
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
      children: [
        Text(s.changePasswordTitle, style: DType.h2(d.ink).copyWith(fontSize: 22)),
        const SizedBox(height: 14),
        Text(s.changePasswordBody, style: DType.body(d.ink2, size: 13.5)),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            _Field(
              first: true,
              label: s.changePasswordNewLabel,
              hint: s.changePasswordNewHint,
              note: newBad ? _error! : s.changePasswordNewNote,
              bad: newBad,
              controller: _password,
              enabled: !_busy,
              obscure: _obscure,
              onToggleObscure: () => setState(() => _obscure = !_obscure),
              onChanged: () => setState(() {
                _error = null;
                _errorOn = null;
              }),
            ),
            _Field(
              label: s.changePasswordConfirmLabel,
              hint: s.changePasswordConfirmHint,
              note: confirmBad ? _error! : s.changePasswordConfirmNote,
              bad: confirmBad,
              controller: _confirm,
              enabled: !_busy,
              obscure: _obscure,
              onSubmitted: _busy ? null : _submit,
              onChanged: () => setState(() {
                _error = null;
                _errorOn = null;
              }),
            ),
          ]),
        ),
        if (_error != null && _errorOn == null) ...[
          const SizedBox(height: 10),
          Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
        ],
        const SizedBox(height: 14),
        DButton(s.changePasswordSave, expand: true, busy: _busy, onTap: _busy ? null : _submit),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _signOut,
            child: Text(s.changePasswordSignOutInstead, style: DType.body(d.link, size: 14, w: FontWeight.w700).copyWith(decoration: TextDecoration.underline)),
          ),
        ),
      ],
    );
  }
}

/// `.box .f`: UPPERCASE label, the field, the note under it (red when
/// this is the one in error).
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.note,
    required this.bad,
    required this.controller,
    required this.enabled,
    required this.obscure,
    required this.onChanged,
    this.onToggleObscure,
    this.onSubmitted,
    this.first = false,
  });

  final String label;
  final String hint;
  final String note;
  final bool bad;
  final TextEditingController controller;
  final bool enabled;
  final bool obscure;
  final VoidCallback onChanged;
  final VoidCallback? onToggleObscure;
  final VoidCallback? onSubmitted;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final red = d.dark ? const Color(0xFFFF8A8A) : DColors.red;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: d.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label.toUpperCase(), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: .66, color: bad ? red : d.muted)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              obscureText: obscure,
              onChanged: (_) => onChanged(),
              onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
              style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: obscure ? 1.5 : 0, color: d.ink),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 15, letterSpacing: 0, color: d.muted, fontStyle: FontStyle.normal),
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 2),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
              ),
            ),
          ),
          if (onToggleObscure != null)
            GestureDetector(
              onTap: onToggleObscure,
              child: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: d.muted),
            ),
        ]),
        const SizedBox(height: 2),
        Text(note, style: TextStyle(fontFamily: 'Urbanist', fontSize: 11.5, color: bad ? red : d.muted)),
      ]),
    );
  }
}
