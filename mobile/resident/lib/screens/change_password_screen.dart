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

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

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
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: _done ? _success(s) : _form(s),
          ),
        ),
      ),
    );
  }

  Widget _success(Strings s) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(46, figmaTop(context, 338, min: 24), 46, 24),
      child: Column(
        children: [
          Text(
            s.changePasswordDoneTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w800,
              fontSize: 30,
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
          const SizedBox(height: 40),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 301),
            child: FigmaPill(
              onPressed: _continue,
              child: Text(s.changePasswordContinue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _form(Strings s) {
    final newBad = _errorOn == 'new' || _errorOn == 'both';
    final confirmBad = _errorOn == 'both';
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(52, figmaTop(context, 109, min: 24), 52, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 301),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.changePasswordTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  height: 46.8 / 30,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.changePasswordBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  height: 1.35,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 21),

              _Field(
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
              const SizedBox(height: 29),
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

              if (_error != null && _errorOn == null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, height: 1.35, color: context.colors.hint),
                ),
              ],
              const SizedBox(height: 34),

              FigmaPill(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.bg),
                      )
                    : Text(s.changePasswordSave),
              ),
              const SizedBox(height: 12),

              Center(
                child: TextButton(
                  onPressed: _busy ? null : _signOut,
                  style: TextButton.styleFrom(
                    foregroundColor: context.colors.navy,
                    textStyle: const TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  child: Text(s.changePasswordSignOutInstead),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A labelled field as the frame draws it: the 16/700 label 6 in, the
/// 44-tall field (1px edge, radius 50), and the 10/400 red note 21 in
/// under it. [bad] turns the edge and hint red too.
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final edge = bad ? c.hint : c.navy;
    OutlineInputBorder border(double w) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide(color: edge, width: w),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 23 / 16,
              color: c.navy,
            ),
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          onChanged: (_) => onChanged(),
          onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: c.navy,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: bad ? c.hint : c.navy,
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 21, vertical: 12),
            enabledBorder: border(1),
            focusedBorder: border(2),
            disabledBorder: border(1),
            suffixIconConstraints:
                const BoxConstraints.tightFor(width: 44, height: 44),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: c.navy,
                    ),
                    onPressed: onToggleObscure,
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 21),
          child: Text(
            note,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w400,
              fontSize: 10,
              height: 15.6 / 10,
              color: c.hint,
            ),
          ),
        ),
      ],
    );
  }
}
