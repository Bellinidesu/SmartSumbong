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

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    if (_password.text.length < 8) {
      setState(() => _error = context.s.changePasswordTooShort);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = context.s.changePasswordMismatch);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.changePassword(_password.text);
      if (!mounted) return;
      // Back through the gate, which will now see the flag cleared.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    // No back button and no gesture out. Signing out is the only other
    // way off this screen, and it is offered explicitly below.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Text(s.changePasswordTitle,
                      textAlign: TextAlign.center,
                      style: t.headlineLarge?.copyWith(fontSize: 24)),
                  const SizedBox(height: 10),
                  Text(
                    s.changePasswordBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13, height: 1.45, color: context.colors.navy),
                  ),
                  const SizedBox(height: 28),

                  _Label(s.changePasswordNewLabel,
                      note: s.changePasswordNewNote),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _password,
                    enabled: !_busy,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: s.changePasswordNewHint,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                          color: context.colors.navy,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),
                  const SizedBox(height: 16),

                  _Label(s.changePasswordConfirmLabel,
                      note: s.changePasswordConfirmNote),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _confirm,
                    enabled: !_busy,
                    obscureText: _obscure,
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      hintText: s.changePasswordConfirmHint,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                          fontSize: 12, height: 1.35, color: context.colors.hint),
                    ),
                  ],
                  const SizedBox(height: 28),

                  FilledButton(
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

                  TextButton(
                    onPressed: _busy ? null : _signOut,
                    child: Text(s.changePasswordSignOutInstead),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.note});

  final String text;
  final String? note;

  @override
  Widget build(BuildContext context) => RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: context.colors.navy,
          ),
          children: [
            TextSpan(text: text),
            if (note != null)
              TextSpan(
                text: '  $note',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  color: Color(0xFFFF4949),
                ),
              ),
          ],
        ),
      );
}
