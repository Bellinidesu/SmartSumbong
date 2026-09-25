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
import '../widgets/figma_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    final s = context.s;

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
          // Figma LOG IN RESIDENT: the 403-wide logo art (its FILL box at
          // y=119, 337 tall), "Resident Profile" 28/800 at 426, and the
          // 357-wide navy card at 481 — radius 50, 1px #F3F3F3 edge, y5 /
          // blur 5 shadow — holding 301x44 white fields at 28 in, the
          // 11px Remember me box, the orange Log In and navy Back to Roles
          // pills, and the Inter sign-up line.
          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: (119 - MediaQuery.paddingOf(context).top)
                      .clamp(8.0, 119.0),
                  bottom: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Logo(),
                    Center(
                      child: Text(
                        s.loginProfileHeading,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          fontSize: 28,
                          height: 43.68 / 28,
                          color: context.colors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 11),

                    // The navy card from the design. Fields sit on white
                    // inside it, so labels invert to the page background.
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 27),
                      padding: const EdgeInsets.fromLTRB(27, 23, 27, 21),
                      decoration: BoxDecoration(
                        color: context.colors.navy,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: context.colors.bg),
                        boxShadow: _shadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _OnNavyField(
                            label: s.loginPhoneLabel,
                            hint: s.loginPhoneHint,
                            controller: _mobile,
                            error: _fieldErrors['mobile'] ??
                                _fieldErrors['mobile_number'],
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+ ]')),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _OnNavyField(
                            label: s.loginPasswordLabel,
                            hint: s.loginPasswordHint,
                            controller: _password,
                            error: _fieldErrors['password'],
                            enabled: !_busy,
                            obscure: _obscure,
                            onToggleObscure: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          Row(
                            children: [
                              _RememberMe(
                                value: _remember,
                                label: s.loginRememberMe,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() => _remember = v),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed:
                                    _busy ? null : () => _forgotPassword(),
                                style: TextButton.styleFrom(
                                  foregroundColor: context.colors.bg,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  s.loginForgotPassword,
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                    decoration: TextDecoration.underline,
                                    decorationColor: context.colors.bg,
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
                          const SizedBox(height: 9),

                          DecoratedBox(
                            decoration: const BoxDecoration(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(50)),
                              boxShadow: _shadow,
                            ),
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFF9800),
                                foregroundColor: Colors.white,
                                minimumSize: const Size.fromHeight(44),
                                elevation: 0,
                                side: BorderSide(color: context.colors.bg),
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
                                  : Text(s.loginButton),
                            ),
                          ),
                          const SizedBox(height: 8),

                          DecoratedBox(
                            decoration: const BoxDecoration(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(50)),
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0x4D121212),
                                  blurRadius: 2.9,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context)
                                      .pushNamedAndRemoveUntil(
                                          '/roles', (_) => false),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.bg,
                                backgroundColor: context.colors.navy,
                                side: BorderSide(color: context.colors.bg),
                                minimumSize: const Size.fromHeight(44),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              child: Text(s.loginBackToRoles),
                            ),
                          ),
                          const SizedBox(height: 8),

                          Center(
                            child: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context)
                                      .pushReplacementNamed('/register'),
                              // 40 tall so the line sits 18 under Back to
                              // Roles, as in the frame.
                              style: TextButton.styleFrom(
                                foregroundColor: context.colors.bg,
                                minimumSize: const Size(0, 40),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text.rich(
                                TextSpan(
                                  text: s.loginNoAccountPrefix,
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w400,
                                    fontSize: 13,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: s.loginSignUp,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        decoration: TextDecoration.underline,
                                        decorationColor: context.colors.bg,
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
    // configured.
    //
    // What exists instead is admin_reset_password (0028): the barangay
    // checks an ID at the counter, the same inspection that approved the
    // account, and issues a temporary password the resident must then
    // change. So this dialog is not an apology for a missing feature —
    // it is the instruction for the route that works.
    //
    // No "request a reset" button here on purpose. It would need an
    // endpoint taking a phone number, which is the enumeration surface
    // 0021 removed, and it would tell the admin nothing they will not
    // learn when the person walks in.
    final s = context.s;
    showFigmaDialog<void>(
      context,
      builder: (context) => FigmaDialog(
        title: s.loginForgotDialogTitle,
        body: s.loginForgotDialogBody,
        primaryLabel: s.loginDialogOk,
        onPrimary: () => Navigator.of(context).pop(),
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
        // The frame's label: 16/600 in a 23 box, 12 in from the field.
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 23 / 16,
              color: context.colors.bg,
            ),
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: context.colors.navy,
          ),
          // 44 tall with the text 21 in, as the frame's fields.
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            // The frame's white. `field` rather than a literal white so it
            // still inverts with the navy card in dark mode, where
            // context.colors.navy is near-white.
            fillColor: context.colors.field,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 21, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(50),
              borderSide: BorderSide.none,
            ),
            suffixIconConstraints:
                const BoxConstraints.tightFor(width: 44, height: 44),
            suffixIcon: onToggleObscure == null
                ? null
                : IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      obscure ? Icons.visibility_off : Icons.visibility,
                      color: context.colors.navy,
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

const _shadow = [
  BoxShadow(
    color: Color(0x4D121212),
    blurRadius: 3.5,
    offset: Offset(0, 5),
  ),
];

/// The frame's logo: the square art drawn 403 wide (scaled to narrower
/// screens), its box starting at y=119 and the title overlapping its
/// transparent lower edge by 30, as in the frame.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final k = (MediaQuery.sizeOf(context).width / 412).clamp(0.0, 1.0);
    final side = 403 * k;
    return SizedBox(
      height: 307 * k,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: -33 * k,
            width: side,
            height: side,
            child: Image.asset(
              'assets/images/onboarding-logo.png',
              semanticLabel: 'SmartSumbong',
              filterQuality: FilterQuality.medium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The frame's 11px light square with its 11/600 label. The whole row is
/// the tap target (at least 32 tall), not just the tiny box.
class _RememberMe extends StatelessWidget {
  const _RememberMe({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      enabled: onChanged != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 11,
                  height: 11,
                  color: context.colors.bg,
                  alignment: Alignment.center,
                  child: value
                      ? Icon(Icons.check, size: 10, color: context.colors.navy)
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: context.colors.bg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
