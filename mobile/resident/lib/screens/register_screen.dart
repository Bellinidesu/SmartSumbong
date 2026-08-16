// SmartSumbong — Sign Up as Resident.
//
// Figma node 2849:192, with the ID dropdown expanded state from 2018:4.
//
// ORDER OF OPERATIONS, and why it is what it is.
//
// Both photos upload before signUp() is ever called. handle_new_auth_user()
// requires id_image_url and selfie_url and runs in the same transaction as
// the auth.users insert, so an application missing either produces no
// account at all. Uploading first means:
//
//   * a failed upload costs one photo, not the form;
//   * a failed signup costs a retry, not the photos;
//   * nothing partial is ever written.
//
// The cost we accept: an upload that succeeds when signup never completes
// leaves an orphan in Cloudinary. There is no delete token on the unsigned
// preset, so it stays. At one barangay's registration volume that is a
// rounding error — noted in turnover.md rather than solved here.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({
    super.key,
    required this.auth,
    required this.uploader,
    this.role = AccountRole.resident,
  });

  final AuthService auth;
  final MediaUploader uploader;
  final AccountRole role;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  IdDocumentType? _idType;
  bool _dropdownOpen = false;
  bool _agreed = false;
  bool _busy = false;
  String? _banner;

  /// Local previews. Kept so a failed signup does not make the applicant
  /// retake anything.
  File? _idFile;
  File? _selfieFile;

  /// Delivery URLs, once uploaded. Held across retries for the same
  /// reason.
  String? _idUrl;
  String? _selfieUrl;

  final _errors = <String, String>{};

  @override
  void dispose() {
    for (final c in [_fullName, _email, _mobile, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------- validation -------------------------------------

  bool _validate() {
    _errors.clear();

    if (_fullName.text.trim().isEmpty) {
      _errors['full_name'] = 'Please enter your full name.';
    }

    // Optional. Many residents do not have an email address, and
    // requiring one would exclude exactly the people this system is for.
    // The identity is the mobile number (migration 0021).
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _errors['email'] = 'That email address does not look right.';
    }

    // Philippine mobile numbers are 10 digits after the country code and
    // always begin with 9. Accept 09XXXXXXXXX, +639XXXXXXXXX and
    // 639XXXXXXXXX; store one normalised form.
    if (_normalisedMobile() == null) {
      _errors['mobile_number'] =
          'Enter a mobile number like 09171234567 or +639171234567.';
    }

    if (_password.text.length < 8) {
      _errors['password'] = 'Your password must be at least 8 characters long.';
    }
    if (_confirm.text != _password.text) {
      _errors['confirm'] = 'Your password should match.';
    }
    if (_idType == null) {
      _errors['id_type'] = 'Please choose which ID you are attaching.';
    }
    if (_idFile == null && _idUrl == null) {
      _errors['id_image'] = 'Please attach a photo of your ID.';
    }
    if (_selfieFile == null && _selfieUrl == null) {
      _errors['selfie'] = 'Please take a photo of yourself.';
    }
    if (!_agreed) {
      _errors['agree'] =
          'Please agree to the Terms and Conditions and Privacy Policy.';
    }

    setState(() {});
    return _errors.isEmpty;
  }

  /// `+639XXXXXXXXX`, or null if it is not a Philippine mobile number.
  String? _normalisedMobile() {
    final digits = _mobile.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 11 && digits.startsWith('09')) {
      return '+63${digits.substring(1)}';
    }
    if (digits.length == 12 && digits.startsWith('639')) {
      return '+$digits';
    }
    return null;
  }

  // ---------- photos -----------------------------------------

  Future<void> _capture({required bool selfie}) async {
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pick(source: ImageSource.camera);
      if (f == null) return;
      setState(() {
        if (selfie) {
          _selfieFile = f;
          _selfieUrl = null; // a new photo invalidates any previous upload
          _errors.remove('selfie');
        } else {
          _idFile = f;
          _idUrl = null;
          _errors.remove('id_image');
        }
      });
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  // ---------- submit -----------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    setState(() {
      _busy = true;
      _banner = null;
    });

    try {
      // Upload only what has not already been uploaded, so a retry after
      // a failed signup does not re-send photos that are already stored.
      _idUrl ??= (await widget.uploader
              .upload(_idFile!, kind: MediaKind.identityCard))
          .mediaUrl;
      _selfieUrl ??=
          (await widget.uploader.upload(_selfieFile!, kind: MediaKind.selfie))
              .mediaUrl;

      await widget.auth.register(
        fullName: _fullName.text,
        contactEmail: _email.text.trim().isEmpty ? null : _email.text,
        mobileNumber: _normalisedMobile()!,
        password: _password.text,
        idType: _idType!,
        idImageUrl: _idUrl!,
        selfieUrl: _selfieUrl!,
        role: widget.role,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/verification-pending');
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    } on RegistrationException catch (e) {
      setState(() {
        _banner = e.message;
        if (e.field != null) _errors[e.field!] = e.message;
      });
    } catch (e) {
      setState(() => _banner = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- build ------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Tokens.pagePad, 56, Tokens.pagePad, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Create your Account', style: t.titleMedium),
                const SizedBox(height: 6),
                Text(
                  widget.role == AccountRole.tanod
                      ? 'Sign Up as Tanod'
                      : 'Sign Up as Resident',
                  style: t.headlineLarge,
                ),
                const SizedBox(height: Tokens.gap),

                if (_banner != null) ...[
                  _Banner(_banner!),
                  const SizedBox(height: Tokens.gap),
                ],

                _Field(
                  label: 'Full Name',
                  hint: 'Enter your full name',
                  controller: _fullName,
                  error: _errors['full_name'],
                  textCapitalization: TextCapitalization.words,
                  enabled: !_busy,
                ),
                _Field(
                  label: 'Email Address',
                  note: '(Optional)',
                  hint: 'example@gmail.com',
                  controller: _email,
                  error: _errors['email'],
                  keyboardType: TextInputType.emailAddress,
                  enabled: !_busy,
                ),
                _Field(
                  label: 'Phone Number',
                  note: '(You will use this to sign in.)',
                  hint: 'e.g. +63 1234567899',
                  controller: _mobile,
                  error: _errors['mobile_number'],
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  ],
                  enabled: !_busy,
                ),
                _Field(
                  label: 'Password',
                  note: '(Your password must be at least 8 characters long.)',
                  hint: 'Enter your password',
                  controller: _password,
                  error: _errors['password'],
                  obscure: true,
                  enabled: !_busy,
                ),
                _Field(
                  label: 'Confirm Password',
                  note: '(Your password should match.)',
                  hint: 'Confirm your password',
                  controller: _confirm,
                  error: _errors['confirm'],
                  obscure: true,
                  enabled: !_busy,
                ),

                _IdTypeDropdown(
                  value: _idType,
                  open: _dropdownOpen,
                  error: _errors['id_type'],
                  enabled: !_busy,
                  onToggle: () =>
                      setState(() => _dropdownOpen = !_dropdownOpen),
                  onSelect: (v) => setState(() {
                    _idType = v;
                    _dropdownOpen = false;
                    _errors.remove('id_type');
                  }),
                ),
                const SizedBox(height: Tokens.gap),

                _PhotoRow(
                  label: 'Photo of your ID',
                  caption: _idType == null
                      ? 'Choose an ID type first'
                      : 'Make sure the details are readable',
                  file: _idFile,
                  uploaded: _idUrl != null,
                  error: _errors['id_image'],
                  enabled: !_busy && _idType != null,
                  onTap: () => _capture(selfie: false),
                ),
                const SizedBox(height: 16),
                _PhotoRow(
                  label: 'Photo of yourself',
                  caption: 'So the barangay can match you to your ID',
                  file: _selfieFile,
                  uploaded: _selfieUrl != null,
                  error: _errors['selfie'],
                  enabled: !_busy,
                  onTap: () => _capture(selfie: true),
                ),
                const SizedBox(height: Tokens.gap),

                _Agreement(
                  value: _agreed,
                  error: _errors['agree'],
                  enabled: !_busy,
                  onChanged: (v) => setState(() {
                    _agreed = v ?? false;
                    _errors.remove('agree');
                  }),
                ),
                const SizedBox(height: Tokens.gap),

                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Tokens.bg,
                          ),
                        )
                      : const Text('Sign Up'),
                ),
                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pushReplacementNamed('/login'),
                    child: const Text('Already have an account? Sign in'),
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

// ---------- pieces -------------------------------------------

class _Banner extends StatelessWidget {
  const _Banner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Tokens.hint.withValues(alpha: 0.08),
          border: Border.all(color: Tokens.hint),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: const TextStyle(color: Tokens.hint, fontSize: 13),
        ),
      );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.note,
    this.error,
    this.obscure = false,
    this.enabled = true,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final String? note;
  final String? error;
  final bool obscure;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 6),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 8,
              children: [
                Text(label, style: t.labelLarge),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(note!, style: t.bodySmall),
                  ),
              ],
            ),
          ),
          TextField(
            controller: controller,
            obscureText: obscure,
            enabled: enabled,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            inputFormatters: inputFormatters,
            style: t.bodyMedium,
            decoration: InputDecoration(
              hintText: hint,
              errorText: error == null ? null : '',
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 4),
              child: Text(error!,
                  style: const TextStyle(color: Tokens.hint, fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _IdTypeDropdown extends StatelessWidget {
  const _IdTypeDropdown({
    required this.value,
    required this.open,
    required this.onToggle,
    required this.onSelect,
    this.error,
    this.enabled = true,
  });

  final IdDocumentType? value;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<IdDocumentType> onSelect;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text('Attach a Valid ID', style: t.labelLarge),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text('(Information should be readable.)',
                    style: t.bodySmall),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Tokens.field,
            border: Border.all(color: error == null ? Tokens.navy : Tokens.hint),
            borderRadius: BorderRadius.circular(Tokens.dropdownRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: enabled ? onToggle : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          value?.label ?? 'Select a Valid ID',
                          style: t.bodyMedium,
                        ),
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: Tokens.navy,
                      ),
                    ],
                  ),
                ),
              ),
              if (open) ...[
                const Divider(height: 1, color: Tokens.divider),
                for (final o in IdDocumentType.residentOptions)
                  InkWell(
                    onTap: () => onSelect(o),
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Tokens.divider, width: 0.5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Text(o.label, style: t.bodyMedium),
                    ),
                  ),
              ],
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(error!,
                style: const TextStyle(color: Tokens.hint, fontSize: 11)),
          ),
      ],
    );
  }
}

class _PhotoRow extends StatelessWidget {
  const _PhotoRow({
    required this.label,
    required this.caption,
    required this.file,
    required this.uploaded,
    required this.onTap,
    this.error,
    this.enabled = true,
  });

  final String label;
  final String caption;
  final File? file;
  final bool uploaded;
  final VoidCallback onTap;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(Tokens.dropdownRadius),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tokens.field,
              border:
                  Border.all(color: error == null ? Tokens.navy : Tokens.hint),
              borderRadius: BorderRadius.circular(Tokens.dropdownRadius),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Tokens.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Tokens.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: file == null
                      ? Icon(Icons.photo_camera_outlined,
                          color: enabled ? Tokens.navy : Tokens.muted)
                      : Image.file(file!, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: t.labelLarge?.copyWith(fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(
                        file == null
                            ? caption
                            : (uploaded ? 'Uploaded' : 'Tap to retake'),
                        style: const TextStyle(
                            fontSize: 12, color: Tokens.muted),
                      ),
                    ],
                  ),
                ),
                if (file != null)
                  const Icon(Icons.check_circle, color: Tokens.navy, size: 20),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(error!,
                style: const TextStyle(color: Tokens.hint, fontSize: 11)),
          ),
      ],
    );
  }
}

class _Agreement extends StatelessWidget {
  const _Agreement({
    required this.value,
    required this.onChanged,
    this.error,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
              const SizedBox(width: 8),
              // TODO: link these once the barangay's Terms and Privacy
              // Notice exist. Collecting government IDs and complaint
              // records makes a privacy notice naming the barangay as
              // personal information controller a Data Privacy Act
              // requirement, not a formality.
              const Expanded(
                child: Text(
                  'By checking, you agree to the Terms and Conditions '
                  'and Privacy Policy',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Tokens.navy,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text(error!,
                  style: const TextStyle(color: Tokens.hint, fontSize: 11)),
            ),
        ],
      );
}
