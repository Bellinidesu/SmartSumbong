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
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

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
          _banner = 'Could not load your profile.';
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    setState(() => _banner = null);
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.photos,
      title: 'Photo access',
      rationale: 'SmartSumbong needs access to your photos to update your '
          'profile picture.',
    );
    if (!granted || !mounted) return;
    try {
      final f = await widget.uploader.pick();
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
      setState(() => _emailError = 'That email address does not look right.');
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
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ProfileDialog(
          title: 'Changes Saved.',
          primaryLabel: 'Continue',
          onPrimary: () => Navigator.of(context).pop(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _banner = e.message.toLowerCase().contains('users_email_key')
            ? 'That email address is already used by another account.'
            : 'Could not save your profile. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _requestChange(String field, String label) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _RequestDialog(
        title: 'Change your $label',
        prompt: field == 'mobile_number'
            ? 'Your mobile number is how you sign in, so the barangay '
                'changes it for you. Enter the new number and they will '
                'be notified.'
            : 'The barangay checked this name against your ID, so they '
                'change it for you. Enter the correct name and they will '
                'be notified.',
        hint: field == 'mobile_number' ? '09171234567' : 'Your full name',
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
      setState(() => _banner = 'Enter a mobile number like 09171234567.');
      return;
    }

    try {
      await Supabase.instance.client.rpc('request_profile_change', params: {
        'p_field': field,
        'p_value': normalised,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your request has been sent to the barangay.'),
          backgroundColor: Tokens.navy,
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
        const SnackBar(
          content: Text('Your password has been changed.'),
          backgroundColor: Tokens.navy,
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
            title: 'Unsaved Changes',
            body: 'If you continue without saving, these changes will '
                'be lost.',
            secondaryLabel: 'Cancel',
            onSecondary: () => Navigator.of(context).pop(false),
            primaryLabel: 'Continue',
            onPrimary: () => Navigator.of(context).pop(true),
          ),
        );
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Tokens.bg,
          surfaceTintColor: Tokens.bg,
          elevation: 0,
          foregroundColor: Tokens.navy,
        ),
        body: SafeArea(
          top: false,
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Tokens.navy))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(30, 0, 30, 32),
                  children: [
                    Center(
                      child: Text('Edit Profile',
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
                                color: Tokens.navy,
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
                                      ? const CircularProgressIndicator(
                                          color: Tokens.bg, strokeWidth: 2)
                                      : null)
                                  : Text(
                                      _SettingsInitials.of(_name),
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w700,
                                        fontSize: 32,
                                        color: Tokens.bg,
                                      ),
                                    ),
                            ),
                            // A small camera badge is the only hint that the
                            // circle above is tappable — nothing else on this
                            // screen suggests avatar upload lives here.
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: Tokens.bg,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Tokens.navy, width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(Icons.camera_alt_outlined,
                                    size: 15, color: Tokens.navy),
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
                          color: Tokens.hint.withValues(alpha: 0.08),
                          border: Border.all(color: Tokens.hint),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(_banner!,
                            style: const TextStyle(
                                color: Tokens.hint, fontSize: 13)),
                      ),
                      const SizedBox(height: 16),
                    ],

                    _LockedField(
                      label: 'Name',
                      value: _name ?? '',
                      note: 'The barangay changes this',
                      onTap: () => _requestChange('full_name', 'name'),
                    ),
                    const SizedBox(height: 18),

                    _EditableField(
                      label: 'Email Address',
                      controller: _email,
                      hint: 'example@gmail.com',
                      note: '(Optional)',
                      error: _emailError,
                      enabled: !_saving,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 18),

                    _EditableField(
                      label: 'Address',
                      controller: _address,
                      hint: 'House/unit no., street, purok',
                      note: '(Optional)',
                      enabled: !_saving,
                      keyboardType: TextInputType.streetAddress,
                    ),
                    const SizedBox(height: 18),

                    _LockedField(
                      label: 'Phone Number',
                      value: _mobile ?? '',
                      note: 'This is how you sign in',
                      onTap: () =>
                          _requestChange('mobile_number', 'mobile number'),
                    ),
                    const SizedBox(height: 18),

                    _LockedField(
                      label: 'Password',
                      value: '\u2022' * 10,
                      note: 'Change',
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
                              foregroundColor: Tokens.navy,
                              backgroundColor: Tokens.field,
                              minimumSize: const Size.fromHeight(45),
                              side: const BorderSide(color: Tokens.navy),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(50),
                              ),
                            ),
                            child: const Text('BACK'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: (_saving || !_dirty) ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Tokens.bg),
                                  )
                                : const Text('SAVE'),
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
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Tokens.navy,
                  )),
              if (note != null) ...[
                const SizedBox(width: 8),
                Text(note!,
                    style: const TextStyle(fontSize: 10, color: Tokens.muted)),
              ],
            ],
          ),
        ),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, color: Tokens.navy),
          decoration: InputDecoration(hintText: hint),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 4),
            child: Text(error!,
                style: const TextStyle(color: Tokens.hint, fontSize: 11)),
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
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Tokens.navy,
              )),
        ),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(50),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: Tokens.bg,
              border: Border.all(color: Tokens.muted),
              borderRadius: BorderRadius.circular(50),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontSize: 14, color: Tokens.muted),
                  ),
                ),
                Text(note,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Tokens.navy,
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
      backgroundColor: Tokens.bg,
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Send request'),
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
    if (_new.text.length < 8) {
      setState(() => _error = 'Your password must be at least 8 characters.');
      return;
    }
    if (_new.text != _confirm.text) {
      setState(() => _error = 'Your passwords should match.');
      return;
    }
    Navigator.of(context).pop(_new.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Tokens.bg,
      title: const Text('Change password', style: TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _new,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'New password'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Confirm password'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(color: Tokens.hint, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Change')),
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

  static const _orange = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Tokens.navy,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: _orange,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Tokens.bg,
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
              backgroundColor: Tokens.bg,
              foregroundColor: Tokens.navy,
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
              foregroundColor: Tokens.bg,
              side: const BorderSide(color: Tokens.bg),
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
