// SmartSumbong — Log In as Tanod.
//
// Figma: LOG IN RESPONDER. The frame asks for a "Barangay ID". This
// signs in by mobile number instead, the same as the resident app.
//
// The reason is 0021. The auth address is computed from the number the
// person already knows — 639XXXXXXXXX@auth.smartsumbong.local — with no
// lookup anywhere, so there is no endpoint that will answer "does this
// account exist". A Barangay ID login needs that lookup, which hands
// back the enumeration surface the migration was written to remove. If
// the barangay decides staff must sign in by ID, that is a schema
// change and a rethink of 0021, not a change to this screen.
//
// "Back to Roles" is absent because the tanod app has no role picker —
// it is one client for one role. The resident app's picker exists
// because it is the app a resident installs first.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../i18n.dart';
import '../widgets/figma_ui.dart';

/// Whether this handset keeps the session across launches. Read by the
/// launch gate, written here.
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

  @override
  void dispose() {
    _mobile.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.signIn(
        mobileNumber: _mobile.text,
        password: _password.text,
      );
      // Recorded only once the credentials are accepted, so a failed
      // attempt never changes how the next launch behaves.
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(rememberMeKey, _remember);
      } catch (_) {
        // Storage unavailable: the session persists, which is the
        // existing behaviour and the safer of the two.
      }

      if (!mounted) return;
      // Back to the gate, which checks verification, suspension and
      // role before deciding where this account belongs.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } on LoginLockedException catch (e) {
      // Backend (0031) locks a number out after 5 failed logins for
      // either role, but this screen never showed that specific
      // message — a locked-out tanod just saw the generic "check your
      // connection" text below, with no idea why a correct-looking
      // password kept failing. Mirrors the resident login screen's
      // handling of the same shared exception.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.s.loginLockedMessage(e.minutesRemaining);
      });
    } on RegistrationException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.s.loginOfflineError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      body: Stack(
        children: [
          const FigmaTexture(),
          // Figma LOG IN RESPONDER: the 403-wide logo art (its box at
          // y=119), "Tanod Profile" 28/800 orange at 426, and the 357-wide
          // orange card at 481 — radius 50, 1px #F3F3F3 edge, the design
          // shadow — holding 301x44 white fields 28 in, the 11px Remember
          // me box, and the Log In pill. The card keeps its colours in
          // dark mode: dark ink on orange reads the same at night.
          SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  top: figmaTop(context, 119),
                  bottom: 32,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const FigmaLogo(),
                    Center(
                      child: Text(
                        s.loginTanodProfile,
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                          fontSize: 28,
                          height: 43.68 / 28,
                          color: kFigmaOrange,
                        ),
                      ),
                    ),
                    const SizedBox(height: 11),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 27),
                      padding: const EdgeInsets.fromLTRB(27, 23, 27, 21),
                      decoration: BoxDecoration(
                        color: kFigmaOrange,
                        borderRadius: BorderRadius.circular(50),
                        border: Border.all(color: const Color(0xFFF3F3F3)),
                        boxShadow: kFigmaShadow,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _OnOrangeField(
                            label: s.loginPhoneLabel,
                            hint: s.loginPhoneHint,
                            controller: _mobile,
                            enabled: !_busy,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9+ ]')),
                            ],
                          ),
                          const SizedBox(height: 6),
                          _OnOrangeField(
                            label: s.loginPasswordLabel,
                            hint: s.loginPasswordHint,
                            controller: _password,
                            enabled: !_busy,
                            obscure: _obscure,
                            onSubmitted: (_) => _busy ? null : _submit(),
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
                                onPressed: _busy ? null : _forgotPassword,
                                style: TextButton.styleFrom(
                                  foregroundColor: _cardInk,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 6),
                                  minimumSize: const Size(0, 32),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  s.loginForgotPassword,
                                  style: const TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 11,
                                    decoration: TextDecoration.underline,
                                    decorationColor: _cardInk,
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
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                height: 1.3,
                                color: _cardInk,
                              ),
                            ),
                          ],
                          const SizedBox(height: 9),
                          // The frame's 301x44 Log In: filled, 1px #252525
                          // edge, the design shadow.
                          DecoratedBox(
                            decoration: const BoxDecoration(
                              borderRadius:
                                  BorderRadius.all(Radius.circular(50)),
                              boxShadow: kFigmaShadow,
                            ),
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: _pillInk,
                                foregroundColor: const Color(0xFFFBFBFB),
                                disabledBackgroundColor:
                                    _pillInk.withValues(alpha: 0.6),
                                minimumSize: const Size.fromHeight(44),
                                elevation: 0,
                                side: const BorderSide(color: _cardInk),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(50),
                                ),
                                textStyle: const TextStyle(
                                  fontFamily: 'Urbanist',
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFFBFBFB)),
                                    )
                                  : Text(s.loginButton),
                            ),
                          ),
                          const SizedBox(height: 18),
                          // The frame's "Back to Roles" and "Sign Up" have
                          // nowhere to go here: this app has no role
                          // picker, and tanod registration lives in the
                          // resident app. One line in their place, in the
                          // sign-up line's spot and style, says where to go.
                          Text(
                            s.loginRegisterNote,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontFamily: 'Urbanist',
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                              height: 1.3,
                              color: Color(0xFF404040),
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
}

/// The frame's #252525 ink on the orange card, both modes.
const _cardInk = Color(0xFF252525);

const _noEdge = OutlineInputBorder(
  borderRadius: BorderRadius.all(Radius.circular(50)),
  borderSide: BorderSide.none,
);

/// The Log In pill: the app's light-mode ink, both modes (the card
/// around it doesn't change either).
const _pillInk = Color(0xFF14181D);

extension _Recovery on _LoginScreenState {
  /// Rose's design resets by OTP to the phone. That needs Semaphore,
  /// which is not configured. What exists instead is
  /// admin_reset_password (0028): the barangay checks an ID at the
  /// counter and issues a temporary password the tanod must then change.
  /// So this is not an apology for a missing feature — it is the
  /// instruction for the route that works.
  void _forgotPassword() {
    final s = context.s;
    showFigmaDialog<void>(
      context,
      builder: (dialogContext) => FigmaDialog(
        title: s.loginForgotDialogTitle,
        body: s.loginForgotDialogBody,
        primaryLabel: s.loginDialogOk,
        onPrimary: () => Navigator.of(dialogContext).pop(),
      ),
    );
  }
}

/// A labelled field on the orange card: the frame's 16/600 #252525 label
/// 12 in, over a 301x44 #FBFBFB pill with 13/500 text 21 in.
class _OnOrangeField extends StatelessWidget {
  const _OnOrangeField({
    required this.label,
    required this.hint,
    required this.controller,
    this.enabled = true,
    this.obscure = false,
    this.onToggleObscure,
    this.onSubmitted,
    this.keyboardType,
    this.inputFormatters,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final ValueChanged<String>? onSubmitted;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w600,
              fontSize: 16,
              height: 23 / 16,
              color: _cardInk,
            ),
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onSubmitted: onSubmitted,
          cursorColor: _cardInk,
          style: const TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            color: _cardInk,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              fontSize: 13,
              color: _cardInk,
            ),
            filled: true,
            fillColor: const Color(0xFFFBFBFB),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 21, vertical: 12),
            // No outline, as drawn (the theme's would otherwise apply).
            border: _noEdge,
            enabledBorder: _noEdge,
            disabledBorder: _noEdge,
            focusedBorder: _noEdge,
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
                      color: _cardInk,
                      size: 20,
                    ),
                    onPressed: enabled ? onToggleObscure : null,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The frame's 11px #F3F3F3 square with its 11/600 label. The whole row
/// is the tap target (at least 32 tall), not just the tiny box.
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
                  color: const Color(0xFFF3F3F3),
                  alignment: Alignment.center,
                  child: value
                      ? const Icon(Icons.check, size: 10, color: _cardInk)
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    fontSize: 11,
                    color: _cardInk,
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
