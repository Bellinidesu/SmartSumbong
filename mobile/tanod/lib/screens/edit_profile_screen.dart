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
import '../widgets/figma_ui.dart';

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
    // _dirty is read in build (SAVE's enabled state, PopScope.canPop), so
    // typing has to rebuild the page — without this SAVE stayed disabled
    // after editing email or address and BACK skipped the unsaved guard.
    // Same fix as the resident app's Edit Profile.
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

  // Figma TANOD - EDIT PROFILE: the title 28/800 50 from the top of the
  // screen (no app bar — Back and the system back do the same guarded
  // pop), the 139 avatar 20 under it with its 25 camera badge, the fields
  // at 35 in on a 20 gap in the frame's order, and Back / Save 150x45
  // pills 44 under the last one.
  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await showDialog<bool>(
          context: context,
          barrierColor: context.colors.bg.withValues(alpha: 0.7),
          builder: (_) => _ProfileDialog(
            title: s.editProfileUnsavedTitle,
            body: s.editProfileUnsavedBody,
            secondaryLabel: s.editProfileCancel,
            onSecondary: () => Navigator.of(context).pop(false),
            primaryLabel: s.editProfileContinue,
            onPrimary: () => Navigator.of(context).pop(true),
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: SafeArea(
          child: _loading
              ? Center(
                  child: CircularProgressIndicator(color: context.colors.navy))
              : ListView(
                  padding:
                      EdgeInsets.fromLTRB(35, figmaTop(context, 50), 35, 32),
                  children: [
                    FigmaTitle(s.editProfileTitle),
                    const SizedBox(height: 20),

                    Center(
                      child: GestureDetector(
                        onTap: _saving ? null : _pickAvatar,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 139,
                              height: 139,
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
                                        fontFamily: 'Urbanist',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 44,
                                        color: context.colors.bg,
                                      ),
                                    ),
                            ),
                            // A small camera badge is the only hint that
                            // the circle above is tappable. The frame's 25
                            // #FBFBFB badge, 14/10 in from the circle's
                            // bottom-right, on the theme's field colour so
                            // the glyph stays visible at night.
                            Positioned(
                              right: 14,
                              bottom: 10,
                              child: Container(
                                width: 25,
                                height: 25,
                                decoration: BoxDecoration(
                                  color: context.colors.field,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Image.asset(
                                    'assets/images/icon-camera.png',
                                    scale: 4,
                                    color: context.colors.navy),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 21),

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
                      label: s.editProfileNameLabel,
                      value: _name ?? '',
                      note: s.editProfileNameNote,
                      onTap: () =>
                          _requestChange('full_name', s.editProfileNameWord),
                    ),
                    const SizedBox(height: 20),

                    _EditableField(
                      label: s.editProfileEmailLabel,
                      controller: _email,
                      hint: s.editProfileEmailHint,
                      note: s.editProfileOptional,
                      error: _emailError,
                      enabled: !_saving,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 20),

                    _LockedField(
                      label: s.editProfilePhoneLabel,
                      value: _mobile ?? '',
                      note: s.editProfilePhoneNote,
                      onTap: () => _requestChange(
                          'mobile_number', s.editProfilePhoneWord),
                    ),
                    const SizedBox(height: 20),

                    _LockedField(
                      label: s.editProfilePasswordLabel,
                      value: '\u2022' * 10,
                      note: s.editProfilePasswordChange,
                      onTap: _changePassword,
                    ),
                    const SizedBox(height: 20),

                    _EditableField(
                      label: s.editProfileAddressLabel,
                      controller: _address,
                      hint: s.editProfileAddressHint,
                      note: s.editProfileOptional,
                      enabled: !_saving,
                      keyboardType: TextInputType.streetAddress,
                    ),
                    const SizedBox(height: 44),

                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 20,
                      runSpacing: 12,
                      children: [
                        FigmaPill(
                          style: FigmaPillStyle.light,
                          width: 150,
                          height: 45,
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).maybePop(),
                          child: Text(s.editProfileBack),
                        ),
                        FigmaPill(
                          width: 150,
                          height: 45,
                          onPressed: (_saving || !_dirty) ? null : _save,
                          child: _saving
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: context.colors.bg),
                                )
                              : Text(s.editProfileSave),
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

/// The frame's field label (16/700) and value (14/500).
TextStyle _fieldLabel(BuildContext context) => TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 16,
      height: 14 / 16,
      color: context.colors.navy,
    );

TextStyle _fieldValue(Color colour) => TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w500,
      fontSize: 14,
      color: colour,
    );

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
          padding: const EdgeInsets.only(bottom: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(label, style: _fieldLabel(context)),
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
          style: _fieldValue(context.colors.navy),
          // 44 tall with the value 15 in, as the frame's fields.
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
          ),
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
/// dialog — a field the tanod cannot edit should still be a way to start
/// changing it, not a dead end.
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
          padding: const EdgeInsets.only(bottom: 11),
          child: Text(label, style: _fieldLabel(context)),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 15),
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
                    style: _fieldValue(context.colors.muted),
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

  // The frames' dialog card, as EDIT PROFILE - BACK.
  @override
  Widget build(BuildContext context) {
    return _ProfileDialog(
      title: widget.title,
      body: widget.prompt,
      content: _CardField(
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

  @override
  Widget build(BuildContext context) {
    return _ProfileDialog(
      title: context.s.editProfileChangePasswordTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardField(
            controller: _new,
            hint: context.s.editProfileNewPasswordHint,
            obscure: true,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          _CardField(
            controller: _confirm,
            hint: context.s.editProfileConfirmPasswordHint,
            obscure: true,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: context.colors.hint, fontSize: 12)),
          ],
        ],
      ),
      secondaryLabel: context.s.editProfileCancel,
      onSecondary: () => Navigator.of(context).pop(),
      primaryLabel: context.s.editProfilePasswordChange,
      onPrimary: _submit,
    );
  }
}

/// A 44-tall pill field for inside the dialog card: #FBFBFB, a 1px ink
/// edge, 14/500 text.
class _CardField extends StatelessWidget {
  const _CardField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool autofocus;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onSubmitted: onSubmitted,
        style: _fieldValue(context.colors.navy),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      );
}

/// The modal from TANOD - EDIT PROFILE - BACK and - SAVE.
///
/// The tanod frames invert the resident's dialog: a light card with an
/// ink edge and ink title, rather than a dark card with an orange one —
/// kept as drawn, since the tanod app is used outdoors in daylight where
/// the lighter card reads better. 300 wide, #FBFBFB, a 2px edge, radius
/// 50; the title 24/700, the body 16/500, and 106x40 pills 13 apart.
class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog({
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
    this.body,
    this.content,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String? body;
  final Widget? content;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 27),
        decoration: BoxDecoration(
          color: c.field,
          border: Border.all(color: c.navy, width: 2),
          borderRadius: BorderRadius.circular(50),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  height: 1.1,
                  color: c.navy,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 16),
                Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    height: 1.2,
                    color: c.navy,
                  ),
                ),
              ],
              if (content != null) ...[
                const SizedBox(height: 16),
                content!,
              ],
              const SizedBox(height: 23),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 13,
                runSpacing: 12,
                children: [
                  if (secondaryLabel != null)
                    _Pill(
                      label: secondaryLabel!,
                      onTap: onSecondary!,
                      filled: false,
                    ),
                  _Pill(label: primaryLabel, onTap: onPrimary, filled: true),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The dialog's 106x40 pill: ink filled, or #FBFBFB with an ink edge; the
/// design shadow; 16/700. Widens for a longer (Filipino) label.
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
    final c = context.colors;
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(50)),
        boxShadow: kFigmaShadow,
      ),
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: filled ? c.navy : c.field,
          foregroundColor: filled ? c.bg : c.navy,
          minimumSize: const Size(106, 40),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          elevation: 0,
          side: filled ? BorderSide.none : BorderSide(color: c.navy),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
