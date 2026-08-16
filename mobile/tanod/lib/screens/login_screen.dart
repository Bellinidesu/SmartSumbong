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
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../theme.dart';

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
      if (!mounted) return;
      // Back to the gate, which checks verification, suspension and
      // role before deciding where this account belongs.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
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
        _error = 'Could not sign you in. Please check your connection '
            'and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: Tokens.pagePad, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 30),
                Center(
                  child: Text('SmartSumbong', style: t.headlineLarge),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Tanod Profile',
                    style: t.headlineLarge?.copyWith(
                      fontSize: 22,
                      fontStyle: FontStyle.italic,
                      color: Tokens.orange,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // The orange card, mirroring the navy one on the
                // resident side.
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  decoration: BoxDecoration(
                    color: Tokens.orange,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Label('Phone Number'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _mobile,
                        enabled: !_busy,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9+ ]')),
                        ],
                        decoration: const InputDecoration(
                          hintText: 'Enter phone number',
                        ),
                      ),
                      const SizedBox(height: 14),

                      const _Label('Password'),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          hintText: 'Enter password',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: Tokens.navy,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: Tokens.navy,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),

                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.navy,
                          foregroundColor: Tokens.bg,
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Tokens.bg),
                              )
                            : const Text('Log In'),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                // No Sign Up link. A tanod account is created by the
                // barangay, not self-served — and the admin verifies the
                // appointment against their own roster. Registration
                // lives in the resident app for residents only until the
                // barangay says otherwise.
                Center(
                  child: Text(
                    'Accounts are issued by the barangay office.',
                    style: t.bodyMedium?.copyWith(fontSize: 12),
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

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Tokens.navy,
        ),
      );
}
