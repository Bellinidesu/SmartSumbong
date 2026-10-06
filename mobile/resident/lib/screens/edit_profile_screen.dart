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
import 'forgot_password_screen.dart' show kSmsResetEnabled;

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
    // Rose (7 Oct 2026): every change to an account is confirmed first.
    if (!await _confirm(
      context.tr('Save your changes?', 'I-save ang mga pagbabago?'),
      context.tr('Your profile will be updated right away.', 'Maa-update agad ang iyong profile.'),
      context.tr('Save', 'I-save'),
      preview: _newAvatar == null ? null : Image.file(_newAvatar!, fit: BoxFit.cover, width: 160, height: 160),
    )) {
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
        'avatar_url': ?avatarUrl,
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

  /// Martin (6 Oct 2026, 0086): a fresh photo of a valid ID, for the
  /// barangay to approve on the portal before it replaces the one on file.
  Future<void> _sendNewId() async {
    final tanod = AppRoleController.instance.value == AppRole.tanod;
    final types = <(String, String)>[
      if (tanod) ('barangay_appointment', context.tr('Barangay appointment', 'Barangay appointment')),
      ('philsys', 'PhilSys (National ID)'),
      ('barangay_id', 'Barangay ID'),
      ('drivers_license', context.tr("Driver's license", 'Lisensya sa pagmamaneho')),
      ('passport', context.tr('Passport', 'Pasaporte')),
      ('postal_id', 'Postal ID'),
    ];
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: context.d.card,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(context.tr('Which ID is it?', 'Anong ID ito?'), style: DType.body(context.d.ink, size: 16, w: FontWeight.w800)),
          ),
          for (final t in types)
            ListTile(title: Text(t.$2, style: DType.body(context.d.ink, size: 14.5)), onTap: () => Navigator.of(ctx).pop(t.$1)),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (type == null || !mounted) return;
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;
    final granted = await PermissionGate.ensure(
      context,
      permission: source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: context.s.editProfileCameraAccessTitle,
      rationale: context.s.editProfileCameraAccessRationale,
    );
    if (!granted || !mounted) return;
    setState(() {
      _banner = null;
      _saving = true;
    });
    try {
      final f = await widget.uploader.pick(source: source);
      if (f == null) return;
      if (!mounted) return;
      // Rose (7 Oct 2026): a picked photo was sent on the spot. Ask first.
      final send = await _confirm(
        context.tr('Send this ID to the barangay?', 'Ipadala ang ID na ito sa barangay?'),
        context.tr('The barangay checks it first. Your current ID stays on file until they approve the new one.', 'Titingnan muna ito ng barangay. Mananatili ang kasalukuyang ID hanggang aprubahan nila ang bago.'),
        context.tr('Send', 'Ipadala'),
        preview: Image.file(f, fit: BoxFit.cover, width: double.infinity),
      );
      if (!send) return;
      final up = await widget.uploader.upload(f, kind: MediaKind.identityCard);
      await Supabase.instance.client.rpc('request_id_reupload', params: {
        'p_id_type': type,
        'p_id_image_url': up.mediaUrl,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.tr('Sent. The barangay will check it and let you know.', 'Naipadala. Titingnan ito ng barangay at sasabihan ka.')),
        backgroundColor: context.colors.navy,
      ));
    } on MediaUploadException catch (e) {
      if (mounted) setState(() => _banner = e.message);
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _banner = e.message);
    } catch (_) {
      if (mounted) setState(() => _banner = context.tr('The ID could not be sent. Try again.', 'Hindi naipadala ang ID. Subukan muli.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestChange(String field, String label) async {
    final s = context.s;
    final value = field == 'full_name'
        // Rose (6 Oct 2026): first name and last name, not "Last, First".
        // Stored as "Last, First" (0032), the form the ID check uses.
        ? await showFigmaDialog<String>(context, builder: (_) => const _NameRequestDialog())
        : await showFigmaDialog<String>(
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
    if (!mounted) return;
    final shown = field == 'mobile_number' ? _localPhone(normalised) : normalised;
    if (!await _confirm(
      context.tr('Send this change?', 'Ipadala ang pagbabagong ito?'),
      context.tr('$label: $shown. The barangay checks it before it changes.', '$label: $shown. Titingnan muna ito ng barangay bago palitan.'),
      context.tr('Send request', 'Ipadala'),
    )) {
      return;
    }
    // Rose (7 Oct 2026): your own number needs no barangay approval, just
    // a code to the new number. Off until Semaphore has credits.
    if (field == 'mobile_number' && kSmsResetEnabled) {
      await _changeMobileBySms(normalised);
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

  Future<Map<String, dynamic>> _otp(Map<String, dynamic> body) async {
    final failed = context.tr('Something went wrong. Try again.', 'May nangyaring mali. Subukan muli.');
    final offline = context.tr('No connection. Try again.', 'Walang koneksyon. Subukan muli.');
    try {
      final r = await Supabase.instance.client.functions.invoke('password-otp', body: body);
      return Map<String, dynamic>.from(r.data as Map);
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['message'] is String) return {'ok': false, 'message': d['message']};
      return {'ok': false, 'message': failed};
    } catch (_) {
      return {'ok': false, 'message': offline};
    }
  }

  /// 0104: a code to the new number, then the number moves (sign-in too).
  Future<void> _changeMobileBySms(String mobile) async {
    setState(() {
      _banner = null;
      _saving = true;
    });
    final sent = await _otp({'action': 'mobile_send', 'mobile': mobile});
    if (!mounted) return;
    setState(() => _saving = false);
    if (sent['ok'] != true) {
      setState(() => _banner = sent['message'] as String?);
      return;
    }
    final s = context.s;
    final code = await showFigmaDialog<String>(
      context,
      builder: (_) => _RequestDialog(
        title: context.tr('Enter the code', 'Ilagay ang code'),
        prompt: sent['message'] as String? ?? '',
        hint: '123456',
        keyboardType: TextInputType.number,
      ),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() => _saving = true);
    final done = await _otp({'action': 'mobile_verify', 'code': code.trim()});
    if (!mounted) return;
    setState(() => _saving = false);
    if (done['ok'] != true) {
      setState(() => _banner = done['message'] as String?);
      return;
    }
    final old = _mobile;
    setState(() => _mobile = mobile);
    // The remembered sign-in for this role follows the number.
    final role = AppRoleController.instance.value == AppRole.tanod ? 'tanod' : 'resident';
    final saved = await SavedLogins.read(role);
    if (saved != null && old != null && AuthService.normaliseMobile(saved.mobile) == AuthService.normaliseMobile(old)) {
      await SavedLogins.write(role, _localPhone(mobile).replaceAll(' ', ''), saved.password);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(done['message'] as String? ?? s.editProfileRequestSent),
      backgroundColor: context.colors.navy,
    ));
  }

  /// One confirm step for every account change (Rose, 7 Oct 2026).
  Future<bool> _confirm(String title, String body, String primary, {Widget? preview}) async {
    final ok = await showDDialog(
      context,
      title: title,
      body: body,
      primary: primary,
      secondary: context.tr('Cancel', 'Kanselahin'),
      icon: preview == null ? Icons.help_outline_rounded : null,
      preview: preview,
    );
    return ok == true;
  }

  Future<void> _changePassword() async {
    final pair = await showFigmaDialog<String>(
      context,
      builder: (_) => const _PasswordDialog(),
    );
    if (pair == null || !mounted) return;
    if (!await _confirm(
      context.tr('Change your password?', 'Palitan ang password?'),
      context.tr('Use the new password the next time you sign in.', 'Gamitin ang bagong password sa susunod na pag-sign in.'),
      context.tr('Change', 'Palitan'),
    )) {
      return;
    }

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
                      _LockedField(label: s.editProfilePhoneLabel, value: _localPhone(_mobile), note: s.editProfilePhoneNote, onTap: () => _requestChange('mobile_number', s.editProfilePhoneWord)),
                      _EditableField(
                        label: s.editProfileAddressLabel,
                        controller: _address,
                        hint: s.editProfileAddressHint,
                        note: s.editProfileOptional,
                        enabled: !_saving,
                        keyboardType: TextInputType.streetAddress,
                      ),
                      _LockedField(label: s.editProfilePasswordLabel, value: '•' * 8, dots: true, note: s.editProfilePasswordChange, onTap: _changePassword),
                      _LockedField(label: context.tr('Valid ID', 'Valid ID'), value: context.tr('On file with the barangay', 'Nasa barangay na'), note: context.tr('Send a new photo', 'Magpadala ng bagong litrato'), onTap: _sendNewId),
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
  const _FRow({required this.label, this.em, required this.field, this.below, this.first = false});

  final String label;
  final String? em;
  final Widget field;
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
        field,
        ?below,
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
      field: TextField(
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
  const _LockedField({required this.label, required this.value, required this.note, required this.onTap, this.first = false, this.dots = false});

  final bool first;
  /// A masked value (the password): bigger, spaced dots.
  final bool dots;

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
      field: Text(value, style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w600, fontSize: dots ? 18 : 15, letterSpacing: dots ? 3 : 0, height: 1.3, color: d.ink2)),
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

/// A name change as First name + Last name; returns "Last, First".
class _NameRequestDialog extends StatefulWidget {
  const _NameRequestDialog();

  @override
  State<_NameRequestDialog> createState() => _NameRequestDialogState();
}

class _NameRequestDialogState extends State<_NameRequestDialog> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FigmaDialog(
      title: context.tr('Change your name', 'Palitan ang pangalan'),
      body: context.tr('Write it as it appears on your ID. The barangay checks it before it changes.', 'Isulat ayon sa nakalagay sa iyong ID. Titingnan ito ng barangay bago palitan.'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        FigmaDialogField(controller: _first, hint: context.tr('First name', 'Pangalan'), autofocus: true, keyboardType: TextInputType.name),
        const SizedBox(height: 10),
        FigmaDialogField(controller: _last, hint: context.tr('Last name', 'Apelyido'), keyboardType: TextInputType.name),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A8A), fontSize: 12.5, fontWeight: FontWeight.w700))),
      ]),
      secondaryLabel: context.s.editProfileCancel,
      onSecondary: () => Navigator.of(context).pop(),
      primaryLabel: context.s.editProfileSendRequest,
      onPrimary: () {
        final f = _first.text.trim(), l = _last.text.trim();
        if (f.isEmpty || l.isEmpty) {
          setState(() => _error = context.tr('Enter both your first name and last name.', 'Ilagay ang pangalan at apelyido.'));
          return;
        }
        Navigator.of(context).pop('$l, $f');
      },
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

/// +639171234567 -> 0917 123 4567, the way people write their number
/// (and how the portal shows it). Anything else is shown as stored.
String _localPhone(String? stored) {
  final m = RegExp(r'^\+63(\d{3})(\d{3})(\d{4})$').firstMatch(stored ?? '');
  return m == null ? (stored ?? '') : '0${m[1]} ${m[2]} ${m[3]}';
}
