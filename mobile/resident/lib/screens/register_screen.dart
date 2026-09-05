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
//
// WHERE THIS SCREEN STOPS MATCHING SIGN UP AS TANOD (2613:921), AND WHY.
//
// Figma's tanod variant drops Email Address (done here — see the field
// below) but also drops the selfie photo and the ID-type dropdown,
// replacing both with one plain "Attach Media" upload for the Barangay
// ID. Neither of those two is safe to drop from this side alone:
// handle_new_auth_user() (0032) raises "selfie_url is required at
// signup" unconditionally, with no role exemption, so an application
// missing it fails the same way for a tanod as for a resident. Matching
// Figma there means a migration decision — is selfie-to-ID matching
// still wanted for a tanod, given the roster check at approval is a
// second, independent control — not a widget change, and it has been
// left for that decision rather than made silently here.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';

import '../i18n.dart';
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

  /// On-device OCR triage on the ID photo (id_ocr.dart), kicked off the
  /// moment a photo is picked so it has already run by the time the
  /// applicant finishes the rest of the form -- see _capture and _submit.
  /// Never awaited anywhere that could block or fail the signup itself;
  /// see AuthService.submitIdOcrResult for why a failure here is silent.
  Future<IdOcrResult>? _ocrFuture;

  final _errors = <String, String>{};

  @override
  void initState() {
    super.initState();
    // Figma's tanod signup has no ID-type picker — one upload, implicitly
    // the Barangay ID. Presetting this is what lets the dropdown stay
    // hidden for that role without leaving _idType null (see _validate).
    if (widget.role == AccountRole.tanod) {
      _idType = IdDocumentType.barangayId;
    }
  }

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
    final s = context.s;

    if (_fullName.text.trim().isEmpty) {
      _errors['full_name'] = s.registerFullNameRequired;
    } else if (!_looksLikeLastFirst(_fullName.text)) {
      _errors['full_name'] = s.registerFullNameFormat;
    }

    // Optional. Many residents do not have an email address, and
    // requiring one would exclude exactly the people this system is for.
    // The identity is the mobile number (migration 0021).
    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      _errors['email'] = s.registerEmailInvalid;
    }

    // Philippine mobile numbers are 10 digits after the country code and
    // always begin with 9. Accept 09XXXXXXXXX, +639XXXXXXXXX and
    // 639XXXXXXXXX; store one normalised form.
    if (_normalisedMobile() == null) {
      _errors['mobile_number'] = s.registerMobileInvalid;
    }

    if (_password.text.length < 8) {
      _errors['password'] = s.registerPasswordTooShort;
    }
    if (_confirm.text != _password.text) {
      _errors['confirm'] = s.registerPasswordMismatch;
    }
    // Figma's tanod signup (2613:921) has no ID-type dropdown — one
    // upload, implicitly the Barangay ID (see the header comment on why
    // the Barangay-Appointment option was dropped from the UI rather
    // than kept behind a picker). _idType is set to that once, below,
    // and never cleared for a tanod, so this only ever fires for a
    // resident who has not picked one yet.
    if (_idType == null) {
      _errors['id_type'] = s.registerIdTypeRequired;
    }
    if (_idFile == null && _idUrl == null) {
      _errors['id_image'] = s.registerIdPhotoRequired;
    }
    // Figma's tanod signup has no selfie step at all — 0036 makes
    // selfie_url optional server-side for that role specifically, so
    // this only applies to a resident.
    if (widget.role != AccountRole.tanod &&
        _selfieFile == null &&
        _selfieUrl == null) {
      _errors['selfie'] = s.registerSelfieRequired;
    }
    if (!_agreed) {
      _errors['agree'] = s.registerAgreeRequired;
    }

    setState(() {});
    return _errors.isEmpty;
  }

  /// Mirrors the check `handle_new_auth_user()` makes server-side
  /// (migration 0032) — a comma with something on both sides. Loose on
  /// purpose: "Dela Cruz, Juan", "Dela Cruz, Juan Miguel" and "Dela
  /// Cruz, Juan, Jr." all pass; only a missing comma, or nothing on one
  /// side of it, fails.
  static bool _looksLikeLastFirst(String name) {
    final idx = name.indexOf(',');
    if (idx <= 0) return false;
    final before = name.substring(0, idx).trim();
    final after = name.substring(idx + 1).trim();
    return before.isNotEmpty && after.isNotEmpty;
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

  /// Neither Figma nor the original build offered a gallery option here —
  /// only the camera. Registration photos still go through
  /// [MediaUploader.pick]'s own strip-and-recompress step regardless of
  /// source (see media_upload.dart's EXIF header), so a gallery pick is
  /// exactly as safe as a fresh camera shot; there was no privacy reason
  /// for the restriction, only that nobody had asked for it yet.
  Future<void> _capture({required bool selfie}) async {
    setState(() => _banner = null);
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;

    final s = context.s;
    final granted = await PermissionGate.ensure(
      context,
      permission:
          source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.registerCameraAccessTitle
          : s.registerPhotoAccessTitle,
      rationale: source == ImageSource.camera
          ? (selfie ? s.registerCameraSelfieRationale : s.registerCameraIdRationale)
          : (selfie
              ? s.registerGallerySelfieRationale
              : s.registerGalleryIdRationale),
    );
    if (!granted || !mounted) return;
    try {
      final f = await widget.uploader.pick(source: source);
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
          // Fire-and-forget: runs on-device while the applicant is still
          // filling in the rest of the form. _submit awaits this later,
          // matched against whatever _idType ends up being at that point
          // (see runIdOcr's own doc comment for why not now).
          _ocrFuture = runIdOcr(f, enteredFullName: _fullName.text);
        }
      });
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  /// A plain bottom sheet, not the navy pill dialog used elsewhere — this
  /// is a system-style action list (two equal choices, one of them a
  /// cancel-by-dismissing), not a confirm/deny decision, so it does not
  /// borrow that pattern.
  Future<ImageSource?> _chooseSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera_outlined, color: context.colors.navy),
              title: Text(context.s.registerTakePhoto),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: context.colors.navy),
              title: Text(context.s.registerChooseFromGallery),
              onTap: () =>
                  Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------- submit -----------------------------------------

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    final confirmed = await _confirmReview();
    if (confirmed != true) return;

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
      // Not asked of a tanod (see _validate) — nothing to upload.
      if (_selfieFile != null) {
        _selfieUrl ??= (await widget.uploader
                .upload(_selfieFile!, kind: MediaKind.selfie))
            .mediaUrl;
      }

      await widget.auth.register(
        fullName: _fullName.text,
        contactEmail: _email.text.trim().isEmpty ? null : _email.text,
        mobileNumber: _normalisedMobile()!,
        password: _password.text,
        idType: _idType!,
        idImageUrl: _idUrl!,
        selfieUrl: _selfieUrl,
        role: widget.role,
      );

      // Best-effort OCR triage write, now that the account exists and
      // _idType is guaranteed final. A timeout guards against a
      // pathological on-device hang; any other failure is already
      // swallowed inside AuthService.submitIdOcrResult itself. Either
      // way this must never block or fail the signup the applicant is
      // actually waiting on.
      final ocrFuture = _ocrFuture;
      if (ocrFuture != null) {
        try {
          final result = await ocrFuture.timeout(const Duration(seconds: 8));
          await widget.auth
              .submitIdOcrResult(result.withSelectedType(_idType!));
        } catch (_) {
          // Advisory only -- see id_ocr.dart's header.
        }
      }

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
      setState(() => _banner = context.s.registerSomethingWentWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- review-before-submit ----------------------------

  /// Shown after validation passes, before anything is uploaded or
  /// written. Cheaper to catch a wrong ID photo or a typo'd number here
  /// than after it is sitting in the Admin Verification queue — the
  /// applicant cannot edit a submitted application, only wait for a
  /// decision or register again from scratch.
  ///
  /// Returns true only if the applicant tapped "Confirm & Submit".
  /// Dismissing the dialog any other way (barrier tap, back gesture)
  /// resolves to null/false and _submit() simply stops, leaving every
  /// typed field and picked photo exactly as it was.
  Future<bool?> _confirmReview() {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    final mobile = _normalisedMobile() ?? _mobile.text.trim();
    final email = _email.text.trim();

    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.bg,
        title: Text(s.registerReviewTitle, style: t.titleMedium),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.registerReviewIntro,
                style: TextStyle(fontSize: 12, color: context.colors.muted, height: 1.4),
              ),
              const SizedBox(height: 16),
              _ReviewRow(s.registerReviewFullName, _fullName.text.trim()),
              if (email.isNotEmpty) _ReviewRow(s.registerReviewEmail, email),
              _ReviewRow(s.registerReviewPhone, mobile),
              _ReviewRow(
                s.registerReviewAccountType,
                widget.role == AccountRole.tanod
                    ? s.registerReviewTanod
                    : s.registerReviewResident,
              ),
              _ReviewRow(s.registerReviewIdType, _idType?.label ?? ''),
              const SizedBox(height: 12),
              // A tanod has nothing in the second slot — no selfie is
              // asked of that role (see _validate) — so the row is just
              // the one photo rather than an empty box beside it.
              widget.role == AccountRole.tanod
                  ? _ReviewPhoto(s.registerReviewYourId, _idFile)
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _ReviewPhoto(
                                s.registerReviewYourId, _idFile)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: _ReviewPhoto(
                                s.registerReviewYourSelfie, _selfieFile)),
                      ],
                    ),
            ],
          ),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(s.registerGoBackAndEdit),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(s.registerConfirmAndSubmit),
          ),
        ],
      ),
    );
  }

  // ---------- build ------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

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
                Text(s.registerCreateAccount, style: t.titleMedium),
                const SizedBox(height: 6),
                Text(
                  widget.role == AccountRole.tanod
                      ? s.registerSignUpTanod
                      : s.registerSignUpResident,
                  style: t.headlineLarge,
                ),
                const SizedBox(height: Tokens.gap),

                if (_banner != null) ...[
                  _Banner(_banner!),
                  const SizedBox(height: Tokens.gap),
                ],

                _Field(
                  label: s.registerFullNameLabel,
                  note: s.registerFullNameNote,
                  hint: s.registerFullNameHint,
                  controller: _fullName,
                  error: _errors['full_name'],
                  textCapitalization: TextCapitalization.words,
                  enabled: !_busy,
                ),
                // Figma's Sign Up as Tanod (2613:921) has no Email Address
                // field at all — a tanod's identity is already the roster
                // check at approval, not a lookup key the way it can be
                // for an anonymous resident. contact_email is optional in
                // handle_new_auth_user() regardless of role, so hiding it
                // here is a UI choice, not a workaround for a backend
                // requirement.
                if (widget.role != AccountRole.tanod)
                  _Field(
                    label: s.registerEmailLabel,
                    note: s.registerEmailNote,
                    hint: s.registerEmailHint,
                    controller: _email,
                    error: _errors['email'],
                    keyboardType: TextInputType.emailAddress,
                    enabled: !_busy,
                  ),
                _Field(
                  label: s.registerPhoneLabel,
                  note: s.registerPhoneNote,
                  hint: s.registerPhoneHint,
                  controller: _mobile,
                  error: _errors['mobile_number'],
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                  ],
                  enabled: !_busy,
                ),
                _Field(
                  label: s.registerPasswordLabel,
                  note: s.registerPasswordNote,
                  hint: s.registerPasswordHint,
                  controller: _password,
                  error: _errors['password'],
                  obscure: true,
                  enabled: !_busy,
                ),
                _Field(
                  label: s.registerConfirmPasswordLabel,
                  note: s.registerConfirmPasswordNote,
                  hint: s.registerConfirmPasswordHint,
                  controller: _confirm,
                  error: _errors['confirm'],
                  obscure: true,
                  enabled: !_busy,
                ),

                // Figma's tanod signup (2613:921) has no dropdown — see
                // the header comment and initState for why _idType is
                // preset to barangayId instead of asked here.
                if (widget.role != AccountRole.tanod)
                  _IdTypeDropdown(
                    role: widget.role,
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
                if (widget.role != AccountRole.tanod)
                  const SizedBox(height: Tokens.gap),

                _PhotoRow(
                  label: widget.role == AccountRole.tanod
                      ? s.registerAttachBarangayId
                      : s.registerPhotoOfYourId,
                  caption: widget.role == AccountRole.tanod
                      ? s.registerMakeSureReadable
                      : (_idType == null
                          ? s.registerChooseIdTypeFirst
                          : s.registerMakeSureReadable),
                  file: _idFile,
                  uploaded: _idUrl != null,
                  error: _errors['id_image'],
                  enabled: !_busy && _idType != null,
                  onTap: () => _capture(selfie: false),
                ),
                // Figma's tanod signup has no selfie step — see _validate
                // and 0036 for why that is safe to drop for this role.
                if (widget.role != AccountRole.tanod) ...[
                  const SizedBox(height: 16),
                  _PhotoRow(
                    label: s.registerPhotoOfYourself,
                    caption: s.registerSelfieCaption,
                    file: _selfieFile,
                    uploaded: _selfieUrl != null,
                    error: _errors['selfie'],
                    enabled: !_busy,
                    onTap: () => _capture(selfie: true),
                  ),
                ],
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
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.bg,
                          ),
                        )
                      : Text(s.registerSignUp),
                ),
                const SizedBox(height: 24),

                Center(
                  child: TextButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pushReplacementNamed('/login'),
                    child: Text(s.registerAlreadyHaveAccount),
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
          color: context.colors.hint.withValues(alpha: 0.08),
          border: Border.all(color: context.colors.hint),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message,
          style: TextStyle(color: context.colors.hint, fontSize: 13),
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
                  style: TextStyle(color: context.colors.hint, fontSize: 11)),
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
    this.role = AccountRole.resident,
    this.error,
    this.enabled = true,
  });

  /// Decides which documents are offered. A tanod proves an appointment,
  /// not residence, so the two lists have nothing to do with each other.
  final AccountRole role;

  final IdDocumentType? value;
  final bool open;
  final VoidCallback onToggle;
  final ValueChanged<IdDocumentType> onSelect;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 8,
            children: [
              Text(
                role == AccountRole.tanod
                    ? s.registerAttachBarangayId
                    : s.registerAttachValidId,
                style: t.labelLarge,
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(s.registerInfoReadableNote, style: t.bodySmall),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: context.colors.field,
            border: Border.all(color: error == null ? context.colors.navy : context.colors.hint),
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
                          value?.label ??
                              (role == AccountRole.tanod
                                  ? s.registerSelectYourDocument
                                  : s.registerSelectAValidId),
                          style: t.bodyMedium,
                        ),
                      ),
                      Icon(
                        open ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: context.colors.navy,
                      ),
                    ],
                  ),
                ),
              ),
              if (open) ...[
                Divider(height: 1, color: context.colors.divider),
                for (final o in role == AccountRole.tanod
                    ? IdDocumentType.tanodOptions
                    : IdDocumentType.residentOptions)
                  InkWell(
                    onTap: () => onSelect(o),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: context.colors.divider, width: 0.5),
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
                style: TextStyle(color: context.colors.hint, fontSize: 11)),
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
    final s = context.s;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(Tokens.dropdownRadius),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.colors.field,
              border:
                  Border.all(color: error == null ? context.colors.navy : context.colors.hint),
              borderRadius: BorderRadius.circular(Tokens.dropdownRadius),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: context.colors.bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.colors.divider),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: file == null
                      ? Icon(Icons.photo_camera_outlined,
                          color: enabled ? context.colors.navy : context.colors.muted)
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
                            : (uploaded ? s.registerUploaded : s.registerTapToRetake),
                        style: TextStyle(
                            fontSize: 12, color: context.colors.muted),
                      ),
                    ],
                  ),
                ),
                if (file != null)
                  Icon(Icons.check_circle, color: context.colors.navy, size: 20),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
            child: Text(error!,
                style: TextStyle(color: context.colors.hint, fontSize: 11)),
          ),
      ],
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 11,
                color: context.colors.muted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(fontSize: 14, color: context.colors.navy),
            ),
          ],
        ),
      );
}

class _ReviewPhoto extends StatelessWidget {
  const _ReviewPhoto(this.label, this.file);

  final String label;
  final File? file;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 4),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                color: context.colors.field,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.colors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: file == null
                  ? Icon(Icons.photo_camera_outlined, color: context.colors.muted)
                  : Image.file(file!, fit: BoxFit.cover),
            ),
          ),
        ],
      );
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
              // Linked to terms_privacy_screen.dart during the Figma
              // parity pass (27 Aug 2026) -- this TODO used to say "link
              // these once the barangay's Terms and Privacy Notice
              // exist." That screen is a draft, not the barangay's
              // approved one (see its own header for why that is still
              // honest to link here): collecting a government ID and
              // complaint records makes a privacy notice naming the
              // barangay as personal information controller a Data
              // Privacy Act requirement, not a formality, and a resident
              // agreeing to "Terms and Conditions and Privacy Policy"
              // ought to be able to tap through and read them.
              Expanded(
                child: Builder(
                  builder: (context) => RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: context.colors.navy,
                        height: 1.25,
                      ),
                      children: [
                        TextSpan(text: context.s.registerAgreementPrefix),
                        TextSpan(
                          text: context.s.registerAgreementLink,
                          style: const TextStyle(
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          ),
                          recognizer: TapGestureRecognizer()
                            ..onTap = () => Navigator.of(context)
                                .pushNamed('/terms-privacy'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text(error!,
                  style: TextStyle(color: context.colors.hint, fontSize: 11)),
            ),
        ],
      );
}
