// SmartSumbong — Settings.
//
// Figma: SETTINGS (2212:186), LOG OUT (2260:2478).
//
// Four rows and a header. The header is the resident's own name and
// number, which doubles as a check that they are signed in as who they
// think they are — worth having on a shared handset.
//
// A fifth row, Terms & Privacy Notice, was added during the Figma parity
// pass (27 Aug 2026) once terms_privacy_screen.dart existed to link to —
// see that file's header for why this stopped being a "link once it
// exists" TODO. Not itself a Figma frame; there is nowhere else in the
// app a resident could otherwise find it.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/resident_nav_bar.dart';

/// The barangay's page. Worth confirming with them before deployment —
/// a wrong link here sends residents to somebody else's page.
const _facebookUrl = 'https://www.facebook.com/profile.php?id=100054387766158';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.auth});

  final AuthService auth;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _name;
  String? _mobile;
  String? _avatarUrl;
  String? _version;
  bool _busy = false;

  final _biometrics = BiometricAuthService();
  bool _biometricEnabled = false;
  bool _biometricBusy = false;

  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadVersion();
    _loadBiometricSetting();
  }

  Future<void> _loadBiometricSetting() async {
    final enabled = await BiometricAuthService.enabled();
    if (!mounted) return;
    setState(() => _biometricEnabled = enabled);
  }

  /// Turning it on asks for an actual fingerprint/face scan before the
  /// toggle commits -- proving right now, while the resident is looking
  /// at the screen, that the prompt this will show on every future cold
  /// start actually works on this phone. Turning it off needs no such
  /// proof; there is nothing to break by disabling.
  Future<void> _onBiometricToggle(bool value) async {
    final s = context.s;

    if (!value) {
      await BiometricAuthService.setEnabled(false);
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    setState(() => _biometricBusy = true);
    try {
      if (!await _biometrics.isAvailable()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.settingsBiometricUnavailable)),
        );
        return;
      }

      final confirmed =
          await _biometrics.authenticate(s.settingsBiometricConfirmReason);
      if (!mounted) return;

      if (confirmed) {
        await BiometricAuthService.setEnabled(true);
        if (mounted) setState(() => _biometricEnabled = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.settingsBiometricEnableFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _biometricBusy = false);
    }
  }

  // Useful now that builds are shared and installed manually rather than
  // through a store that tracks versions for you -- worth being able to
  // ask "which build is this?" without pulling the file's own metadata.
  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version} (${info.buildNumber})');
    } catch (_) {
      // Not worth surfacing an error over; the row just stays hidden.
    }
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final row = await client
          .from('users')
          .select('full_name, mobile_number, avatar_url')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _name = row['full_name'] as String?;
        _mobile = row['mobile_number'] as String?;
        _avatarUrl = row['avatar_url'] as String?;
      });
    } catch (_) {
      // The rows below still work; only the header is missing.
    }
  }

  Future<void> _logOut() async {
    final s = context.s;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: context.colors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.settingsLogOut,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  // Figma (LOG OUT, 2260:2478): the dialog title is the
                  // same orange as the Edit Profile badge, not white.
                  color: Color(0xFFFF9800),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.settingsLogOutConfirmBody,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: context.colors.bg),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.colors.bg,
                        side: BorderSide(color: context.colors.bg),
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: Text(s.settingsCancel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: context.colors.field,
                        foregroundColor: context.colors.navy,
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: Text(s.settingsLogOut),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    await widget.auth.signOut();
    if (!mounted) return;
    // Clear the stack: a back gesture after signing out should not
    // return to a screen that queries as the person who just left.
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  // Two gates, not one: the explanation dialog is where a resident learns
  // what actually happens (sign-in disabled forever; kept reports lose
  // their personal details, not their existence) — see 0045's own reasons
  // for that split. Typing DELETE is the second gate, the same weight
  // this app already gives an irreversible action nowhere else quite
  // reaches. request_account_deletion() runs inside the delete-account
  // Edge Function (0045's comment explains why it can't run from Flutter
  // directly: only that function holds the service role key GoTrue's
  // admin ban/delete calls need).
  Future<void> _deleteAccount() async {
    final s = context.s;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(s: s),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deletingAccount = true);
    try {
      await Supabase.instance.client.functions.invoke('delete-account');
      await widget.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.deleteAccountFailed)),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      bottomNavigationBar:
          const ResidentNavBar(current: ResidentTab.settings),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
          children: [
            Center(
              child: Text(s.settingsTitle,
                  style: t.headlineLarge?.copyWith(fontSize: 28)),
            ),
            const SizedBox(height: 28),

            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: context.colors.navy,
                    shape: BoxShape.circle,
                    // Same pattern as Edit Profile's avatar circle: a saved
                    // avatar_url paints as the circle's own background image,
                    // and only an unset avatar falls back to the initials
                    // text below. Previously this row never even read
                    // avatar_url, so a resident who set a photo on Edit
                    // Profile still saw blank initials the moment they came
                    // back here.
                    image: _avatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_avatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _avatarUrl != null
                      ? null
                      : Text(
                          _initials(_name),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 24,
                            color: context.colors.bg,
                          ),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _name ?? '\u2014',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: context.colors.navy,
                        ),
                      ),
                      if (_mobile != null)
                        Text(
                          _mask(_mobile!),
                          style: TextStyle(
                              fontSize: 12, color: context.colors.muted),
                        ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () => Navigator.of(context)
                            .pushNamed('/edit-profile')
                            .then((_) => _load()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.settingsEditProfile,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            _SettingsRow(
              icon: Icons.person_outline,
              label: s.settingsPersonalInfo,
              onTap: () => Navigator.of(context)
                  .pushNamed('/edit-profile')
                  .then((_) => _load()),
            ),
            _SettingsRow(
              icon: Icons.language,
              label: s.settingsLanguages,
              onTap: () => Navigator.of(context).pushNamed('/languages'),
            ),
            _SettingsRow(
              icon: Icons.dark_mode_outlined,
              label: s.settingsAppearance,
              onTap: () => Navigator.of(context).pushNamed('/appearance'),
            ),
            _SettingsToggleRow(
              icon: Icons.fingerprint,
              label: s.settingsBiometricUnlock,
              value: _biometricEnabled,
              busy: _biometricBusy,
              onChanged: _onBiometricToggle,
            ),
            _SettingsRow(
              icon: Icons.notifications_none,
              label: s.settingsNotificationPrefs,
              onTap: () =>
                  Navigator.of(context).pushNamed('/notification-preferences'),
            ),
            _SettingsRow(
              icon: Icons.privacy_tip_outlined,
              label: s.termsPrivacyTitle,
              onTap: () => Navigator.of(context).pushNamed('/terms-privacy'),
            ),
            _SettingsRow(
              icon: Icons.facebook,
              label: s.settingsFacebook,
              onTap: () async {
                final uri = Uri.parse(_facebookUrl);
                if (!await launchUrl(uri,
                    mode: LaunchMode.externalApplication)) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.settingsFacebookError)),
                  );
                }
              },
            ),
            _SettingsRow(
              icon: Icons.delete_outline,
              label: s.settingsDeleteAccount,
              showChevron: false,
              color: const Color(0xFFDC2626),
              busy: _deletingAccount,
              onTap: _deletingAccount ? null : _deleteAccount,
            ),
            _SettingsRow(
              icon: Icons.logout,
              label: s.settingsLogOut,
              showChevron: false,
              onTap: _busy ? null : _logOut,
            ),
            if (_version != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'SmartSumbong Resident • v$_version',
                  style: TextStyle(fontSize: 11, color: context.colors.muted),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// Shown on a screen someone might hold up in a barangay hall.
  static String _mask(String mobile) {
    if (mobile.length < 4) return mobile;
    return '${mobile.substring(0, 3)} \u2022\u2022\u2022\u2022\u2022\u2022 '
        '${mobile.substring(mobile.length - 4)}';
  }
}

/// Same row shape as [_SettingsRow], but for a plain on/off setting
/// rather than a link to another screen -- a Switch in place of the
/// chevron, and no [onTap] on the row itself, so a stray tap on the
/// label doesn't silently flip the switch a Figma frame never drew.
/// Not itself a Figma frame, same as the Terms & Privacy row above it --
/// there is nowhere in the design this setting was ever specified.
class _SettingsToggleRow extends StatelessWidget {
  const _SettingsToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final bool value;
  final bool busy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: context.colors.navy, size: 22),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: context.colors.navy),
            ),
          ),
          if (busy)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.colors.navy),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: context.colors.navy,
            ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showChevron = true,
    this.color,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.colors.navy;
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: tint, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 14, color: tint),
              ),
            ),
            if (busy)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: tint),
              )
            else if (showChevron)
              Icon(Icons.chevron_right, color: tint, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Two gates in one dialog: the explanation (why this differs from just
/// signing out) and a typed "DELETE" the confirm button won't accept
/// without — see _deleteAccount's own comment for why an irreversible
/// action gets more friction here than anywhere else in this app.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.s});

  final Strings s;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();
  bool _match = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final ok = _controller.text.trim() == 'DELETE';
      if (ok != _match) setState(() => _match = ok);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    const red = Color(0xFFDC2626);
    return Dialog(
      backgroundColor: context.colors.navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.deleteAccountConfirmTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 20,
                color: red,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.deleteAccountConfirmBody,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: context.colors.bg),
            ),
            const SizedBox(height: 16),
            Text(
              s.deleteAccountTypeToConfirm,
              style: TextStyle(fontSize: 12, color: context.colors.bg),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _controller,
              autocorrect: false,
              style: TextStyle(color: context.colors.bg),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: context.colors.field,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.bg,
                      side: BorderSide(color: context.colors.bg),
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(s.settingsCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed:
                        _match ? () => Navigator.of(context).pop(true) : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: red,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: red.withValues(alpha: 0.35),
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50),
                      ),
                    ),
                    child: Text(s.deleteAccountConfirmButton),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
