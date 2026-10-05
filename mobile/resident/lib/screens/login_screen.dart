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

import '../i18n.dart';
import '../theme.dart';
import '../d/d_switches.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../widgets/figma_ui.dart';
import 'forgot_password_screen.dart';

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

  /// The number last signed in with (kept only while Remember me is on),
  /// so it is already there next time. The password is the phone's own
  /// password manager's to remember — see the autofill hints below.
  static const _lastMobileKey = 'last_mobile';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final last = prefs.getString(_lastMobileKey);
      if (mounted && last != null && _mobile.text.isEmpty) setState(() => _mobile.text = last);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final s = context.s;
    _fieldErrors.clear();
    if (AuthService.normaliseMobile(_mobile.text) == null) {
      _fieldErrors['mobile'] = s.loginPhoneError;
    }
    if (_password.text.isEmpty) {
      _fieldErrors['password'] = s.loginPasswordEmptyError;
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
        if (_remember) {
          await prefs.setString(_lastMobileKey, _mobile.text.trim());
        } else {
          await prefs.remove(_lastMobileKey);
        }
      } catch (_) {
        // Storage unavailable: the session persists, which is the
        // existing behaviour and the safer default of the two.
      }

      if (!mounted) return;
      // Tells the phone this sign-in worked, so its password manager offers
      // to save the number and password (only when Remember me is on).
      TextInput.finishAutofillContext(shouldSave: _remember);
      // Back to the gate, which decides where this account belongs:
      // pending, verified, rejected or suspended. Login does not need to
      // know, and duplicating that decision here would be a second place
      // to keep in step.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on LoginLockedException catch (e) {
      if (!mounted) return;
      setState(() =>
          _error = context.s.loginLockedMessage(e.minutesRemaining));
    } on RegistrationException catch (e) {
      // Core words its sign-in failures in English; the known ones are
      // shown in the resident's language instead.
      final message = switch (e.code) {
        'not_activated' => s.loginErrorNotActivated,
        'suspended' => s.loginErrorSuspended,
        'rate_limited' => s.loginErrorRateLimited,
        'bad_credentials' => s.loginErrorBadCredentials,
        _ => e.message,
      };
      setState(() {
        _error = message;
        if (e.field != null) _fieldErrors[e.field!] = message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.loginOfflineError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Branch D: the preview's sign-in. Full contour behind, the page in the
  // light/dark setting, the wordmark, "Resident Profile" or "Tanod
  // Profile", and the form on the role-colour card. Sign Up stays for
  // tanods too — they register themselves and the admin approves them.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final tanod = ModalRoute.of(context)?.settings.arguments == 'tanod';
    final d = tanod ? (context.isDark ? DColors.tanodDark : DColors.tanodLight) : context.dResident;
    final cardText = Colors.white;
    return DPage(
      colors: d,
      fullContour: true,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
          children: [
            Align(alignment: Alignment.centerRight, child: DPrefsRow(colors: d)),
            const SizedBox(height: 18),
            Center(
              child: Image.asset('assets/images/onboarding-logo.png',
                  width: 220, semanticLabel: 'SmartSumbong', filterQuality: FilterQuality.medium),
            ),
            Text(
              tanod ? context.tr('Tanod Profile', 'Profile ng Tanod') : s.loginProfileHeading,
              textAlign: TextAlign.center,
              style: DType.h1(d.accent).copyWith(fontStyle: FontStyle.italic, fontSize: 25),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [d.card1, d.card2]),
                boxShadow: [BoxShadow(color: d.card1.withValues(alpha: .35), blurRadius: 26, offset: const Offset(0, 12))],
              ),
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
              child: AutofillGroup(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _DField(
                  autofill: const [AutofillHints.username],
                  label: s.loginPhoneLabel,
                  hint: s.loginPhoneHint,
                  controller: _mobile,
                  error: _fieldErrors['mobile'] ?? _fieldErrors['mobile_number'],
                  enabled: !_busy,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                ),
                const SizedBox(height: 12),
                _DField(
                  autofill: const [AutofillHints.password],
                  label: s.loginPasswordLabel,
                  hint: s.loginPasswordHint,
                  controller: _password,
                  error: _fieldErrors['password'],
                  enabled: !_busy,
                  obscure: _obscure,
                  onToggleObscure: () => setState(() => _obscure = !_obscure),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  InkWell(
                    onTap: _busy ? null : () => setState(() => _remember = !_remember),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: _remember ? DColors.orange : Colors.transparent,
                            border: Border.all(color: _remember ? DColors.orange : Colors.white70, width: 2),
                          ),
                          child: _remember ? const Icon(Icons.check_rounded, size: 14, color: Color(0xFF141B34)) : null,
                        ),
                        const SizedBox(width: 8),
                        Text(s.loginRememberMe, style: DType.body(cardText, size: 13, w: FontWeight.w600)),
                      ]),
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : _forgotPassword,
                    style: TextButton.styleFrom(foregroundColor: cardText, padding: const EdgeInsets.symmetric(horizontal: 4)),
                    child: Text(s.loginForgotPassword,
                        style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 13, decoration: TextDecoration.underline, decorationColor: Colors.white)),
                  ),
                ]),
                if (_error != null) ...[
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: const Color(0x33FFC107), border: Border.all(color: const Color(0x80FFC107))),
                    child: Text(_error!, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, color: Color(0xFFFFE08A), fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 8),
                DButton(s.loginButton, onTap: _busy ? null : _submit, busy: _busy, expand: true),
                const SizedBox(height: 10),
                DButton(s.loginBackToRoles,
                    kind: DButtonKind.white,
                    expand: true,
                    onTap: _busy ? null : () => Navigator.of(context).pushNamedAndRemoveUntil('/roles', (_) => false)),
                const SizedBox(height: 4),
              ])),
            ),
            const SizedBox(height: 14),
            Center(
              child: TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pushReplacementNamed(tanod ? '/register-tanod' : '/register'),
                style: TextButton.styleFrom(foregroundColor: d.ink),
                child: Text.rich(TextSpan(
                  text: s.loginNoAccountPrefix,
                  style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w500, fontSize: 13.5, color: d.muted),
                  children: [
                    TextSpan(
                      text: s.loginSignUp,
                      style: TextStyle(fontWeight: FontWeight.w800, color: d.link, decoration: TextDecoration.underline, decorationColor: d.link),
                    ),
                  ],
                )),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Rose's design: Forgot Password → Verify OTP → Reset Password →
  // Success, by SMS through Semaphore (0085, forgot_password_screen.dart).
  // The counter reset (0028) is named on that screen for anyone with no
  // load or signal.
  void _forgotPassword() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ForgotPasswordScreen(mobile: _mobile.text.trim()),
    ));
  }

}

/// A labelled field on the role-colour card: the label in white over a
/// white field with dark text, an error line in amber under it.
class _DField extends StatelessWidget {
  const _DField({
    required this.label,
    required this.hint,
    required this.controller,
    this.error,
    this.enabled = true,
    this.obscure = false,
    this.onToggleObscure,
    this.keyboardType,
    this.inputFormatters,
    this.autofill,
  });

  final Iterable<String>? autofill;
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
    final r = BorderRadius.circular(14);
    OutlineInputBorder b(Color c, [double w = 1.5]) => OutlineInputBorder(borderRadius: r, borderSide: BorderSide(color: c, width: w));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(label, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 14, color: Colors.white)),
      ),
      TextField(
        controller: controller,
        enabled: enabled,
        obscureText: obscure,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        autofillHints: autofill,
        style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 15.5, color: Color(0xFF141B34)),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 14.5, color: Color(0xFF8A90A3), fontStyle: FontStyle.normal),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: b(Colors.transparent),
          enabledBorder: b(Colors.transparent),
          disabledBorder: b(Colors.transparent),
          focusedBorder: b(DColors.orange, 2),
          errorBorder: b(const Color(0xFFFFC107)),
          focusedErrorBorder: b(const Color(0xFFFFC107), 2),
          suffixIcon: onToggleObscure == null
              ? null
              : IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: const Color(0xFF6E7489)),
                ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(left: 4, top: 5),
          child: Text(error!, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 12.5, color: Color(0xFFFFE08A))),
        ),
    ]);
  }
}
