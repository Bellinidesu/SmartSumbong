// SmartSumbong — Forgot password by SMS code (0085).
//
// Rose's design: Forgot Password → Verify OTP → Reset Password → Success,
// here as one screen in three steps. The code is texted through Semaphore
// by the password-otp Edge Function; this screen never sees it. Residents
// with no load or signal still have the counter reset (0028), named at the
// foot of the first step.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_theme.dart';
import '../d/d_ui.dart';

/// SMS reset is built but needs Semaphore credits. Off: "Forgot password?"
/// shows the counter-reset instructions instead. Turn on once the account
/// is approved and topped up (5 Oct 2026: approval pending, no credits).
const bool kSmsResetEnabled = false;

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.mobile});

  /// Whatever was typed on the sign-in screen, to save typing it again.
  final String? mobile;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { number, code, done }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  late final _mobile = TextEditingController(text: widget.mobile ?? '');
  final _code = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  _Step _step = _Step.number;
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _mobile.dispose();
    _code.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    try {
      final r = await Supabase.instance.client.functions.invoke('password-otp', body: body);
      return Map<String, dynamic>.from(r.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['message'] is String) return {'ok': false, 'message': d['message']};
      return {'ok': false, 'message': context.tr('Something went wrong. Check your connection and try again.', 'May mali. Tingnan ang koneksyon at subukan muli.')};
    } catch (_) {
      return {'ok': false, 'message': context.tr('No connection. Try again when you have signal.', 'Walang koneksyon. Subukan muli kapag may signal.')};
    }
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _call({'action': 'send', 'mobile': _mobile.text.trim()});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r['ok'] == true) {
        _step = _Step.code;
        _info = r['message'] as String?;
      } else {
        _error = r['message'] as String?;
      }
    });
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    if (_pw.text != _pw2.text) {
      setState(() => _error = context.tr('The two passwords do not match.', 'Hindi magkatugma ang dalawang password.'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final r = await _call({'action': 'verify', 'mobile': _mobile.text.trim(), 'code': _code.text.trim(), 'password': _pw.text});
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (r['ok'] == true) {
        _step = _Step.done;
      } else {
        _error = r['message'] as String?;
      }
    });
  }

  InputDecoration _deco(String hint) {
    final d = context.d;
    return InputDecoration(
      hintText: hint,
      hintStyle: DType.body(d.muted, size: 14.5),
      filled: true,
      fillColor: d.card,
      counterText: '',
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.link, width: 1.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final label = DType.body(d.ink2, size: 13, w: FontWeight.w700);
    Widget field(String l, TextEditingController c, {String hint = '', TextInputType? type, bool obscure = false, int? max}) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l, style: label),
            const SizedBox(height: 6),
            TextField(
              controller: c,
              keyboardType: type,
              obscureText: obscure,
              maxLength: max,
              enabled: !_busy,
              style: DType.body(d.ink, size: 15),
              decoration: _deco(hint),
              onChanged: (_) => setState(() => _error = null),
            ),
          ],
        );

    final title = switch (_step) {
      _Step.number => context.tr('Forgot password', 'Nakalimutan ang password'),
      _Step.code => context.tr('Enter the code', 'Ilagay ang code'),
      _Step.done => context.tr('Password changed', 'Napalitan na ang password'),
    };

    return DPage(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
        children: [
          Row(children: [
            const DBack(),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: DType.h2(d.ink).copyWith(fontSize: 22))),
          ]),
          const SizedBox(height: 18),
          if (_step == _Step.number) ...[
            Text(context.tr('We will text a 6-digit code to the mobile number you signed up with.', 'Magte-text kami ng 6-digit na code sa mobile number na ginamit mo sa pag-sign up.'),
                style: DType.body(d.ink2, size: 14.5).copyWith(height: 1.5)),
            const SizedBox(height: 18),
            field(context.tr('Mobile number', 'Mobile number'), _mobile, hint: '09XXXXXXXXX', type: TextInputType.phone, max: 13),
          ] else if (_step == _Step.code) ...[
            if (_info != null) DNote(title: context.tr('Code sent', 'Naipadala ang code'), body: _info!),
            const SizedBox(height: 16),
            field(context.tr('6-digit code', '6-digit na code'), _code, hint: '••••••', type: TextInputType.number, max: 6),
            const SizedBox(height: 14),
            field(context.tr('New password', 'Bagong password'), _pw, obscure: true, hint: context.tr('At least 8 characters', 'Hindi bababa sa 8 character')),
            const SizedBox(height: 14),
            field(context.tr('Type it again', 'I-type muli'), _pw2, obscure: true),
          ] else ...[
            Center(
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, color: DColors.greenVivid, boxShadow: [BoxShadow(color: DColors.greenVivid.withValues(alpha: .4), blurRadius: 24, offset: const Offset(0, 8))]),
                child: const Icon(Icons.check_rounded, size: 48, color: Colors.white),
              ),
            ),
            const SizedBox(height: 18),
            Text(context.tr('Sign in with your new password.', 'Mag-sign in gamit ang bagong password.'),
                textAlign: TextAlign.center, style: DType.body(d.ink2, size: 15)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13.5, w: FontWeight.w700)),
          ],
          const SizedBox(height: 22),
          if (_step == _Step.number)
            DButton(context.tr('Send code', 'Ipadala ang code'), expand: true, busy: _busy, onTap: _busy ? null : _send)
          else if (_step == _Step.code) ...[
            DButton(context.tr('Change password', 'Palitan ang password'), expand: true, busy: _busy, onTap: _busy ? null : _verify),
            const SizedBox(height: 10),
            DButton(context.tr('Send a new code', 'Magpadala ng bagong code'), kind: DButtonKind.ghost, expand: true, onTap: _busy ? null : _send),
          ] else
            DButton(context.tr('Back to sign in', 'Bumalik sa sign in'), expand: true, onTap: () => Navigator.of(context).maybePop()),
          if (_step == _Step.number) ...[
            const SizedBox(height: 22),
            Text(
              context.tr("No load or no signal? Visit the barangay hall with a valid ID and they will give you a temporary password.",
                  'Walang load o signal? Pumunta sa barangay hall na may valid ID at bibigyan ka nila ng pansamantalang password.'),
              textAlign: TextAlign.center,
              style: DType.body(d.muted, size: 13).copyWith(height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
