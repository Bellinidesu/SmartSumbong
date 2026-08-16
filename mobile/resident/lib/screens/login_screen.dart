// SmartSumbong — Log In as Resident.
//
// Figma node 2009:44.
//
// The form asks for a phone number, not an email, and that is not a
// deviation from the diagrams — the Register Account use case treats a
// duplicate mobile number as the collision that stops registration, and
// the interview was clear that the number is what residents actually
// have. Migration 0021 makes the number the identity; the auth address
// is derived from it locally, so signing in involves no lookup.
//
// WHAT IS NOT BUILT YET, and both are on the open list:
//
//   * "Forgot password?" needs OTP by SMS through Semaphore, which is not
//     configured. Rose's design has the whole branch drawn (Forgot
//     Password -> Verify OTP -> Reset Password -> Success). Until then it
//     tells the resident to visit the barangay, which is true and is what
//     an admin would have to do anyway.
//   * "Back to Roles" needs the role picker (2315:55). Residents and
//     tanods use different apps in this build, so it is not reachable
//     from here yet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../theme.dart';

/// Whether this handset should keep the session across app launches.
/// Read by the launch gate, written here. Absent means remember, which
/// is what an existing install already does.
const rememberMeKey = 'remember_me';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _mobile = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _obscure = true;
  bool _remember = true;
  String? _error;
  final _fieldErrors = <String, String>{};

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    _fieldErrors.clear();
    if (AuthService.normaliseMobile(_mobile.text) == null) {
      _fieldErrors['mobile'] = 'Enter a number like 09171234567.';
    }
    if (_password.text.isEmpty) {
      _fieldErrors['password'] = 'Enter your password.';
    }
    if (_fieldErrors.isNotEmpty) {
      setState(() => _error = null);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.signIn(
        mobileNumber: _mobile.text,
        password: _password.text,
      );
      // Recorded only after the credentials are accepted, so a failed
      // attempt never changes how the next launch behaves.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(rememberMeKey, _remember);
      } catch (_) {
        // Storage unavailable: the session persists, which is the
        // existing behaviour and the safer default of the two.
      }

      if (!mounted) return;
      // Back to the gate, which decides where this account belongs:
      // pending, verified, rejected or suspended. Login does not need to
      // know, and duplicating that decision here would be a second place
      // to keep in step.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on RegistrationException catch (e) {
      setState(() {
        _error = e.message;
        if (e.field != null) _fieldErrors[e.field!] = e.message;
      });
    } catch (_) {
      setState(() => _error =
          'Could not reach the barangay\u2019s system. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        children: [
          // The contour texture, same asset and opacity as Home and the
          // launch gate, so the three screens a resident sees first read
          // as one surface.
          Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: Image.asset(
                'assets/images/texture.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 20),
                Center(
                  child: FractionallySizedBox(
                    widthFactor: 0.68,
                    child: Image.asset(
                      'assets/images/logo-wordmark.png',
                      semanticLabel: 'SmartSumbong',
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Center(
                  child: Text(
                    'Resident Profile',
                    style: t.headlineLarge?.copyWith(
                      fontSize: 28,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // The navy card from the design. Fields sit on white
                // inside it, so labels invert to the page background.
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                  decoration: BoxDecoration(
                    color: Tokens.navy,
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x4D121212),
                        blurRadius: 5,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OnNavyField(
                        label: 'Phone Number',
                        hint: 'Enter phone number',
                        controller: _mobile,
                        error: _fieldErrors['mobile'] ??
                            _fieldErrors['mobile_number'],
                        enabled: !_busy,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _OnNavyField(
                        label: 'Password',
                        hint: 'Enter password',
                        controller: _password,
                        error: _fieldErrors['password'],
                        enabled: !_busy,
                        obscure: _obscure,
                        onToggleObscure: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _remember,
                              onChanged: _busy
                                  ? null
                                  : (v) =>
                                      setState(() => _remember = v ?? true),
                              side: const BorderSide(color: Tokens.bg),
                              checkColor: Tokens.navy,
                              fillColor: WidgetStateProperty.resolveWith(
                                (st) => st.contains(WidgetState.selected)
                                    ? Tokens.bg
                                    : Colors.transparent,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Remember me',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: Tokens.bg,
                            ),
                          ),
                          const Spacer(),
                        TextButton(
                          onPressed: _busy ? null : () => _forgotPassword(),
                          style: TextButton.styleFrom(
                            foregroundColor: Tokens.bg,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              fontSize: 12,
                              decoration: TextDecoration.underline,
                              decorationColor: Tokens.bg,
                            ),
                          ),
                        ),
                        ],
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          _error!,
                          style: const TextStyle(
                              color: Color(0xFFFFC107), fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 12),

                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('Log In'),
                      ),
                      const SizedBox(height: 12),

                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context)
                                .pushNamedAndRemoveUntil(
                                    '/roles', (_) => false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Tokens.bg,
                          side: const BorderSide(color: Tokens.bg),
                          minimumSize: const Size.fromHeight(44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        child: const Text('Back to Roles'),
                      ),
                      const SizedBox(height: 20),

                      Center(
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => Navigator.of(context)
                                  .pushReplacementNamed('/register'),
                          style: TextButton.styleFrom(
                            foregroundColor: Tokens.bg,
                          ),
                          child: const Text.rich(
                            TextSpan(
                              text: 'Don\u2019t have an account yet? ',
                              style: TextStyle(fontSize: 13),
                              children: [
                                TextSpan(
                                  text: 'Sign Up',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
          ),
        ],
      ),
    );
  }

  void _forgotPassword() {
    // Rose's design resets by OTP to the phone (2077:16 -> 2143:282 ->
    // 2077:17 -> 2143:205). That needs Semaphore, which is not
    // configured. Until it is, the truthful answer is the one an admin
    // would give anyway.
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Tokens.bg,
        title: const Text('Forgot password'),
        content: const Text(
          'Password reset by text message is not available yet. Please '
          'visit the barangay hall with a valid ID and ask the staff to '
          'reset your account.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// A labelled field sitting on the navy card: white input, navy text,
/// label in the page background colour.
class _OnNavyField extends StatelessWidget {
  const _OnNavyField({
    required this.label,
    required this.hint,
    required this.controller,
    this.error,
    this.enabled = true,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? error;
  final bool enabled;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Tokens.bg,
            ),
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 14, color: Tokens.navy),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
              borderSide: BorderSide.none,
            ),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: Tokens.navy,
                      size: 20,
                    ),
                    onPressed: enabled ? onToggleObscure : null,
                  ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, top: 4),
            child: Text(
              error!,
              style: const TextStyle(color: Color(0xFFFFC107), fontSize: 11),
            ),
          ),
      ],
    );
  }
}
