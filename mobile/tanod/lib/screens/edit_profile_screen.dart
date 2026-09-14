// SmartSumbong — Edit Profile (tanod).
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
// ADDRESS AND AVATAR — ported from the resident app's Figma parity pass
// (27 Aug 2026), which tanod never got at the time ("focus first on the
// resident app"). Both are ordinary tanod-editable fields (0038), the
// same shape as email — not identity evidence, so no privileged-field
// guard applies. The avatar upload reuses MediaKind.selfie's Cloudinary
// folder, same as resident, rather than adding a new one.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';

const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _uploader = MediaUploader(
    cloudName: _cloudName,
    uploadPreset: _uploadPreset,
  );

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
    _load();
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

  /// Gallery-only until 9 Sep 2026 — same gap as resident's, fixed the
  /// same day for the same reason (see resident's
  /// report_details_screen.dart _chooseSource for why this is safe).
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
              leading:
                  Icon(Icons.photo_camera_outlined, color: context.colors.navy),
              title: Text(context.s.editProfileTakePhoto),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading:
                  Icon(Icons.photo_library_outlined, color: context.colors.navy),
              title: Text(context.s.editProfileChooseFromGallery),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

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
      final f = await _uploader.pick(source: source);
      if (f == null || !mounted) return;
      setState(() => _newAvatar = f);
    } on MediaUploadException catch (e) {
      if (!mounted) return;
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
        avatarUrl =
            (await _uploader.upload(_newAvatar!, kind: MediaKind.selfie))
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
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProfileDialog(
          title: context.s.editProfileChangesSavedTitle,
          primaryLabel: context.s.editProfileContinue,
          onPrimary: () => Navigator.of(context).pop(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _banner = e.message.toLowerCase().contains('users_email_key')
            ? context.s.editProfileEmailTaken
            : context.s.editProfileSaveFailed;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestChange(String field, String label) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _RequestDialog(
        title: context.s.editProfileChangeFieldTitle(label),
        prompt: field == 'mobile_number'
            ? context.s.editProfileMobilePrompt
            : context.s.editProfileNamePrompt,
        hint: field == 'mobile_number'
            ? '09171234567'
            : context.s.editProfileFullNameHint,
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
    final pair = await showDialog<String>(
      context: context,
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (_) => _ProfileDialog(
            title: context.s.editProfileUnsavedTitle,
            body: context.s.editProfileUnsavedBody,
            secondaryLabel: context.s.editProfileCancel,
            onSecondary: () => Navigator.of(context).pop(false),
            primaryLabel: context.s.editProfileContinue,
            onPrimary: () => Navigator.of(context).pop(true),
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: context.colors.bg,
          surfaceTintColor: context.colors.bg,
          elevation: 0,
          foregroundColor: context.colors.navy,
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: context.colors.navy))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 32),
                  children: [
                    Center(
                      child: Text(context.s.editProfileTitle,
                          style: t.headlineLarge?.copyWith(fontSize: 28)),
                    ),
                    const SizedBox(height: 24),

                    Center(
                      child: GestureDetector(
                        onTap: _saving ? null : _pickAvatar,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                color: context.colors.navy,
                                shape: BoxShape.circle,
                                image: _newAvatar != null
                                    ? DecorationImage(
                                        image: FileImage(_newAvatar!),
                                        fit: BoxFit.cover,
                                      )
                                    : (_avatarUrl != null
                                        ? DecorationImage(
                                            image: NetworkImage(_avatarUrl!),
                                            fit: BoxFit.cover,
                                          )
                                        : null),
                              ),
                              alignment: Alignment.center,
                              child: (_newAvatar != null || _avatarUrl != null)
                                  ? (_uploadingAvatar
                                      ? CircularProgressIndicator(
                                          color: context.colors.bg, strokeWidth: 2)
                                      : null)
                                  : Text(
                                      _SettingsInitials.of(_name),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 32,
                                        color: context.colors.bg,
                                      ),
                                    ),
                            ),
                            // A small camera badge is the only hint that
                            // the circle above is tappable.
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: context.colors.bg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: context.colors.navy, width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: Icon(Icons.camera_alt_outlined,
                                    size: 15, color: context.colors.navy),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    if (_banner != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: context.colors.hint.withValues(alpha: 0.08),
                          border: Border.all(color: context.colors.hint),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_banner!,
                            style: TextStyle(
                                color: context.colors.hint, fontSize: 13)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _LockedField(
                      label: context.s.editProfileNameLabel,
                      value: _name ?? '',
                      note: context.s.editProfileNameNote,
                      onTap: () => _requestChange(
                          'full_name', context.s.editProfileNameWord),
                    ),
                    const SizedBox(height: 18),

                    _EditableField(
                      label: context.s.editProfileEmailLabel,
                      controller: _email,
                      hint: context.s.editProfileEmailHint,
                      note: context.s.editProfileOptional,
                      error: _emailError,
                      enabled: !_saving,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 18),

                    _EditableField(
                      label: context.s.editProfileAddressLabel,
                      controller: _address,
                      hint: context.s.editProfileAddressHint,
                      note: context.s.editProfileOptional,
                      enabled: !_saving,
                      keyboardType: TextInputType.streetAddress,
                    ),
                    const SizedBox(height: 18),

                    _LockedField(
                      label: context.s.editProfilePhoneLabel,
                      value: _mobile ?? '',
                      note: context.s.editProfilePhoneNote,
                      onTap: () => _requestChange(
                          'mobile_number', context.s.editProfilePhoneWord),
                    ),
                    const SizedBox(height: 18),

                    _LockedField(
                      label: context.s.editProfilePasswordLabel,
                      value: '\u2022' * 10,
                      note: context.s.editProfilePasswordChange,
                      onTap: _changePassword,
                    ),
                    const SizedBox(height: 32),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.colors.navy,
                              backgroundColor: context.colors.field,
                              minimumSize: const Size.fromHeight(45),
                              side: BorderSide(color: context.colors.navy),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            child: Text(context.s.editProfileBack),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: (_saving || !_dirty) ? null : _save,
                            child: _saving
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: context.colors.bg),
                                  )
                                : Text(context.s.editProfileSave),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: context.colors.navy,
                  )),
              if (note != null) ...[
                const SizedBox(width: 8),
                Text(note!,
                    style: TextStyle(fontSize: 10, color: context.colors.muted)),
              ],
            ],
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: TextStyle(fontSize: 14, color: context.colors.navy),
          decoration: InputDecoration(hintText: hint),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 4),
            child: Text(error!,
                style: TextStyle(color: context.colors.hint, fontSize: 11)),
          ),
      ],
    );
  }
}

/// Shown but not typed into. Tapping opens the request or the password
/// dialog — a field the resident cannot edit should still be a way to
/// start changing it, not a dead end.
class _LockedField extends StatelessWidget {
  const _LockedField({
    required this.label,
    required this.value,
    required this.note,
    required this.onTap,
  });

  final String label;
  final String value;
  final String note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 6),
          child: Text(label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: context.colors.navy,
              )),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: context.colors.bg,
              border: Border.all(color: context.colors.muted),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(fontSize: 14, color: context.colors.muted),
                  ),
                ),
                Text(note,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.navy,
                      decoration: TextDecoration.underline,
                    )),
              ],
            ),
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.bg,
      title: Text(widget.title, style: const TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.prompt,
              style: const TextStyle(fontSize: 13, height: 1.35)),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            inputFormatters: widget.keyboardType == TextInputType.phone
                ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))]
                : null,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(hintText: widget.hint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.s.editProfileCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.s.editProfileSendRequest),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.bg,
      title: Text(context.s.editProfileChangePasswordTitle,
          style: const TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _new,
            obscureText: true,
            autofocus: true,
            decoration:
                InputDecoration(hintText: context.s.editProfileNewPasswordHint),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: InputDecoration(
                hintText: context.s.editProfileConfirmPasswordHint),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: context.colors.hint, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.s.editProfileCancel),
        ),
        FilledButton(
            onPressed: _submit, child: Text(context.s.editProfilePasswordChange)),
      ],
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
    this.body,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String? body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    // The tanod frames invert the resident's dialog: white card with a
    // navy border and navy title, rather than a navy card with an
    // orange one. Same shape, same copy, opposite ground — worth
    // keeping as drawn rather than unifying, because the tanod app is
    // used outdoors in daylight where the lighter card reads better.
    return Dialog(
      backgroundColor: context.colors.bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(25),
        side: BorderSide(color: context.colors.navy, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: context.colors.navy,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: context.colors.navy,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (secondaryLabel != null) ...[
                  _Pill(
                    label: secondaryLabel!,
                    onTap: onSecondary!,
                    filled: false,
                  ),
                  const SizedBox(width: 12),
                ],
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
    const size = Size(96, 38);

    return filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.navy,
              foregroundColor: context.colors.bg,
              minimumSize: size,
              padding: EdgeInsets.zero,
              shape: shape,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.navy,
              side: BorderSide(color: context.colors.navy),
              minimumSize: size,
              padding: EdgeInsets.zero,
              shape: shape,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            child: Text(label),
          );
  }
}
