// SmartSumbong — Edit Profile.
//
// Figma: EDIT PROFILE (2254:1627), and its BACK / SAVE states.
//
// WHAT A RESIDENT MAY CHANGE, AND WHY THE REST IS NOT A REFUSAL.
//
// Email is theirs. Since 0021 it is contact-only and carries no
// authority, so a typo costs them a notification, not their account.
//
// Name and mobile number are not, and 0026 enforces that in the
// database rather than only in this screen. The number is the login
// identity: changing it in public.users without the matching change in
// auth.users locks the account silently, and repairing that needs the
// service role. The name is what an admin compared against a government
// ID during verification, so a resident who can rewrite it afterwards
// makes that check worthless.
//
// But "you cannot change this" is a dead end, and residents do change
// their numbers. So the fields are tappable and open a request that
// notifies the barangay — request_profile_change() in 0026. The resident
// gets an answer from a person who can see their ID, which is the only
// way either change can be verified anyway.
//
// Password is Supabase's own updateUser, which needs the current
// session and nothing else.
//
// ADDRESS AND AVATAR — added during the Figma parity pass (27 Aug
// 2026). Both are ordinary resident-editable fields (0038), the same
// shape as email: neither is identity evidence an admin checked
// against a government ID, so guard_privileged_user_fields() (0026)
// never restricted them — they just didn't have columns yet. The
// avatar upload reuses MediaKind.selfie's Cloudinary folder rather than
// adding a new one, so is_media_url()'s folder allow-list (0018) does
// not need widening for a photo that is, functionally, the same kind
// of thing.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.auth, required this.uploader});

  final AuthService auth;
  final MediaUploader uploader;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _email = TextEditingController();
  final _address = TextEditingController();

  String? _name;
  String? _mobile;
  String _originalEmail = '';
  String _originalAddress = '';
  String? _avatarUrl;
  File? _newAvatar;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingAvatar = false;
  String? _banner;
  String? _emailError;

  bool get _dirty =>
      _email.text.trim() != _originalEmail ||
      _address.text.trim() != _originalAddress ||
      _newAvatar != null;

  @override
  void initState() {
    super.initState();
    // _dirty is read in build (SAVE's enabled state, PopScope.canPop), so
    // typing has to rebuild the page — without this SAVE stayed disabled
    // after editing email or address and BACK skipped the unsaved guard.
    _email.addListener(_onEdited);
    _address.addListener(_onEdited);
    _load();
  }

  void _onEdited() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await client
          .from('users')
          .select('full_name, mobile_number, email, address, avatar_url')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _name = row['full_name'] as String?;
        _mobile = row['mobile_number'] as String?;
        _originalEmail = (row['email'] as String?) ?? '';
        _email.text = _originalEmail;
        _originalAddress = (row['address'] as String?) ?? '';
        _address.text = _originalAddress;
        _avatarUrl = row['avatar_url'] as String?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _banner = context.s.editProfileLoadError;
        });
      }
    }
  }

  /// Gallery-only until 9 Sep 2026 — same gap as the report-evidence
  /// picker (see report_details_screen.dart's _chooseSource), added
  /// while going through the app for other places the same fix applied.
  Future<ImageSource?> _chooseSource(BuildContext context) =>
      showFigmaSourceSheet(
        context,
        takeLabel: context.s.editProfileTakePhoto,
        galleryLabel: context.s.editProfileChooseFromGallery,
      );


  Future<void> _pickAvatar() async {
    setState(() => _banner = null);
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;
    final s = context.s;
    final granted = await PermissionGate.ensure(
      context,
      permission:
          source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.editProfileCameraAccessTitle
          : s.editProfilePhotoAccessTitle,
      rationale: source == ImageSource.camera
          ? s.editProfileCameraAccessRationale
          : s.editProfilePhotoAccessRationale,
    );
    if (!granted || !mounted) return;
    try {
      final f = await widget.uploader.pick(source: source);
      if (f == null) return;
      setState(() => _newAvatar = f);
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    final email = _email.text.trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _emailError = context.s.editProfileEmailInvalid);
      return;
    }

    setState(() {
      _saving = true;
      _banner = null;
      _emailError = null;
    });

    try {
      String? avatarUrl = _avatarUrl;
      if (_newAvatar != null) {
        setState(() => _uploadingAvatar = true);
        // Same folder as a registration selfie — see this file's header
        // for why, rather than a dedicated MediaKind.avatar.
        avatarUrl = (await widget.uploader
                .upload(_newAvatar!, kind: MediaKind.selfie))
            .mediaUrl;
        if (mounted) setState(() => _uploadingAvatar = false);
      }

      final uid = Supabase.instance.client.auth.currentUser!.id;
      await Supabase.instance.client.from('users').update({
        'email': email.isEmpty ? null : email,
        'address': _address.text.trim().isEmpty ? null : _address.text.trim(),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
      }).eq('id', uid);

      if (!mounted) return;
      setState(() {
        _originalEmail = email;
        _originalAddress = _address.text.trim();
        if (avatarUrl != null) {
          _avatarUrl = avatarUrl;
          _newAvatar = null;
        }
      });
      final s = context.s;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: context.colors.bg.withValues(alpha: 0.7),
        builder: (_) => _ProfileDialog(
          title: s.editProfileChangesSavedTitle,
          primaryLabel: s.editProfileContinue,
          onPrimary: () => Navigator.of(context).pop(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final s = context.s;
      setState(() {
        _banner = e.message.toLowerCase().contains('users_email_key')
            ? s.editProfileEmailTaken
            : s.editProfileSaveFailed;
      });
    } on MediaUploadException catch (e) {
      // Only PostgrestException used to be caught: a failed avatar
      // upload escaped as an unhandled error, with no message and the
      // spinner left turning on the avatar.
      if (!mounted) return;
      setState(() => _banner = e.message);
    } catch (_) {
      // No connection on the update itself — same silent failure.
      if (!mounted) return;
      setState(() => _banner = context.s.editProfileSaveFailed);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _uploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _requestChange(String field, String label) async {
    final s = context.s;
    final value = await showFigmaDialog<String>(
      context,
      builder: (_) => _RequestDialog(
        title: s.editProfileChangeFieldTitle(label),
        prompt: field == 'mobile_number'
            ? s.editProfileMobilePrompt
            : s.editProfileNamePrompt,
        hint: field == 'mobile_number' ? '09171234567' : s.editProfileFullNameHint,
        keyboardType:
            field == 'mobile_number' ? TextInputType.phone : TextInputType.name,
      ),
    );
    if (value == null || value.trim().isEmpty) return;

    // Normalised the same way as signup, so an admin is not asked to
    // approve a number in a shape the identity derivation would reject.
    final normalised = field == 'mobile_number'
        ? AuthService.normaliseMobile(value)
        : value.trim();
    if (normalised == null) {
      if (!mounted) return;
      setState(() => _banner = context.s.editProfileMobileInvalid);
      return;
    }

    try {
      await Supabase.instance.client.rpc('request_profile_change', params: {
        'p_field': field,
        'p_value': normalised,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.s.editProfileRequestSent),
          backgroundColor: context.colors.navy,
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _banner = e.message);
    }
  }

  Future<void> _changePassword() async {
    final pair = await showFigmaDialog<String>(
      context,
      builder: (_) => const _PasswordDialog(),
    );
    if (pair == null) return;

    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: pair));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.s.editProfilePasswordChanged),
          backgroundColor: context.colors.navy,
        ),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() => _banner = e.message);
    }
  }

  // Figma EDIT PROFILE: the title 28/800 50 from the top of the screen
  // (no app bar — BACK and the system back do the same guarded pop), the
  // 139 avatar 20 under it with its 25 camera badge, the fields at 35 in
  // on a 20 gap in the frame's order, and BACK / SAVE 150x45 pills 44
  // under the last one.
  // Branch D, 1:1 with the preview's Personal Information: the back
  // button and h2, the 96 px gradient avatar with its orange camera, one
  // bordered box of rows (UPPERCASE label with its note on the right, the
  // value, a link under the locked ones), then Back and Save side by side.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDDialog(
          context,
          title: s.editProfileUnsavedTitle,
          body: s.editProfileUnsavedBody,
          primary: s.editProfileContinue,
          secondary: s.editProfileCancel,
          icon: Icons.edit_note_rounded,
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: DPage(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: d.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
                children: [
                  Row(children: [
                    const DBack(),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.editProfileTitle, style: DType.h2(d.ink).copyWith(fontSize: 22))),
                  ]),
                  const SizedBox(height: 14),
                  Center(
                    child: GestureDetector(
                      onTap: _saving ? null : _pickAvatar,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(begin: Alignment(-.5, -1), end: Alignment(.5, 1), colors: [Color(0xFF0A3BA0), Color(0xFF00236A)]),
                            image: _newAvatar != null
                                ? DecorationImage(image: FileImage(_newAvatar!), fit: BoxFit.cover)
                                : (_avatarUrl != null ? DecorationImage(image: NetworkImage(cloudinarySized(_avatarUrl!, width: 420)), fit: BoxFit.cover) : null),
                          ),
                          alignment: Alignment.center,
                          child: (_newAvatar != null || _avatarUrl != null)
                              ? (_uploadingAvatar ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : null)
                              : Text(_SettingsInitials.of(_name), style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 32, color: Colors.white)),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(color: DColors.orange, shape: BoxShape.circle, border: Border.all(color: d.bg, width: 3)),
                            child: const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.white),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_banner != null) ...[
                    DSheet(
                      borderColor: DColors.red.withValues(alpha: .5),
                      child: Text(_banner!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Container(
                    decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
                    clipBehavior: Clip.antiAlias,
                    child: Column(children: [
                      _LockedField(first: true, label: s.editProfileNameLabel, value: _name ?? '', note: s.editProfileNameNote, onTap: () => _requestChange('full_name', s.editProfileNameWord)),
                      _EditableField(
                        label: s.editProfileEmailLabel,
                        controller: _email,
                        hint: s.editProfileEmailHint,
                        note: s.editProfileOptional,
                        error: _emailError,
                        enabled: !_saving,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      _LockedField(label: s.editProfilePhoneLabel, value: _mobile ?? '', note: s.editProfilePhoneNote, onTap: () => _requestChange('mobile_number', s.editProfilePhoneWord)),
                      _EditableField(
                        label: s.editProfileAddressLabel,
                        controller: _address,
                        hint: s.editProfileAddressHint,
                        note: s.editProfileOptional,
                        enabled: !_saving,
                        keyboardType: TextInputType.streetAddress,
                      ),
                      _LockedField(label: s.editProfilePasswordLabel, value: '•' * 10, note: s.editProfilePasswordChange, onTap: _changePassword),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: DButton(s.editProfileBack, kind: DButtonKind.ghost, expand: true, onTap: _saving ? null : () => Navigator.of(context).maybePop())),
                    const SizedBox(width: 10),
                    Expanded(child: DButton(s.editProfileSave, expand: true, busy: _saving, onTap: (_saving || !_dirty) ? null : _save)),
                  ]),
                ],
              ),
      ),
    );
  }
}

abstract class _SettingsInitials {
  static String of(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}



/// The y5 / blur 5 shadow at 30% the frame puts under BACK and SAVE.
class _PageShadow extends StatelessWidget {
  const _PageShadow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          boxShadow: const [
            BoxShadow(
              color: Color(0x4D121212),
              blurRadius: 3.5,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );
}

/// `.box .f`: a row inside the bordered box — the UPPERCASE label (11,
/// muted) with its note on the right, then the value 15/600.
class _FRow extends StatelessWidget {
  const _FRow({required this.label, this.em, required this.child, this.below, this.first = false});

  final String label;
  final String? em;
  final Widget child;
  final Widget? below;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(border: first ? null : Border(top: BorderSide(color: d.line))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: .66, color: d.muted))),
          if (em != null && em!.isNotEmpty) Text(em!, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 11, color: d.muted)),
        ]),
        const SizedBox(height: 4),
        child,
        if (below != null) below!,
      ]),
    );
  }
}

class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.controller,
    required this.hint,
    this.note,
    this.error,
    this.enabled = true,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String? note;
  final String? error;
  final bool enabled;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return _FRow(
      label: label,
      em: note,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: keyboardType,
        style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 15, color: d.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 15, color: d.muted, fontStyle: FontStyle.normal),
          isDense: true,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
        ),
      ),
      below: error == null ? null : Padding(padding: const EdgeInsets.only(top: 4), child: Text(error!, style: TextStyle(fontFamily: 'Urbanist', fontSize: 11.5, fontWeight: FontWeight.w700, color: d.dark ? const Color(0xFFFF8A8A) : DColors.red))),
    );
  }
}

class _LockedField extends StatelessWidget {
  const _LockedField({required this.label, required this.value, required this.note, required this.onTap, this.first = false});

  final bool first;

  final String label;
  final String value;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return _FRow(
      first: first,
      label: label,
      child: Text(value, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: 15, height: 1.3, color: d.ink2)),
      below: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 2),
            child: Text(note, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 13, color: d.link)),
          ),
        ),
      ),
    );
  }
}

class _RequestDialog extends StatefulWidget {
  const _RequestDialog({
    required this.title,
    required this.prompt,
    required this.hint,
    required this.keyboardType,
  });

  final String title;
  final String prompt;
  final String hint;
  final TextInputType keyboardType;

  @override
  State<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends State<_RequestDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // The design's dialog card, as EDIT PROFILE - BACK.
  @override
  Widget build(BuildContext context) {
    return FigmaDialog(
      title: widget.title,
      body: widget.prompt,
      content: FigmaDialogField(
        controller: _controller,
        hint: widget.hint,
        autofocus: true,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.keyboardType == TextInputType.phone
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))]
            : null,
      ),
      secondaryLabel: context.s.editProfileCancel,
      onSecondary: () => Navigator.of(context).pop(),
      primaryLabel: context.s.editProfileSendRequest,
      onPrimary: () => Navigator.of(context).pop(_controller.text),
    );
  }
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    final s = context.s;
    if (_new.text.length < 8) {
      setState(() => _error = s.editProfilePasswordTooShort);
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = s.editProfilePasswordMismatch);
      return;
    }
    Navigator.of(context).pop(_new.text);
  }

  // The design's dialog card, as EDIT PROFILE - BACK.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return FigmaDialog(
      title: s.editProfileChangePasswordTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FigmaDialogField(
            controller: _new,
            hint: s.editProfileNewPasswordHint,
            obscure: true,
            autofocus: true,
          ),
          const SizedBox(height: 10),
          FigmaDialogField(
            controller: _confirm,
            hint: s.editProfileConfirmPasswordHint,
            obscure: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Color(0xFFFFC107), fontSize: 12, height: 1.3)),
          ],
        ],
      ),
      secondaryLabel: s.editProfileCancel,
      onSecondary: () => Navigator.of(context).pop(),
      primaryLabel: s.editProfilePasswordChange,
      onPrimary: _submit,
    );
  }
}


/// The navy modal from EDIT PROFILE - BACK and EDIT PROFILE - SAVE.
///
/// One shape serving both: an orange title, optional body, and one or
/// two pills. Cancel is drawn as the quieter of the pair even though it
/// is the safer choice — that is how the frame has it, and the dialog
/// only appears when the resident has already asked to leave.
class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog({
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final String title;
  final String primaryLabel;
  final VoidCallback onPrimary;

  static const _orange = Color(0xFFFF9800);

  // Figma EDIT PROFILE - BACK / - SAVE: a 300-wide navy card, radius 50,
  // 2px #252525 edge; the title orange at 24/700, the body 16/500, and
  // 106x40 pills 13 apart with the frame's shadow. Without a body the
  // gaps open to 32, as in "Changes Saved.".
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 40, 20, 25),
        decoration: BoxDecoration(
          color: context.colors.navy,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: const Color(0xFF252525), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                height: 21 / 24,
                color: _orange,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Pill(label: primaryLabel, onTap: onPrimary, filled: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(50),
    );
    const size = Size(106, 40);
    const text = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 16,
    );

    return _PageShadow(
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.bg,
                foregroundColor: context.colors.navy,
                fixedSize: size,
                minimumSize: size,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.bg,
                backgroundColor: context.colors.navy,
                side: BorderSide(color: context.colors.bg),
                fixedSize: size,
                minimumSize: size,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
              ),
              child: Text(label),
            ),
    );
  }
}
