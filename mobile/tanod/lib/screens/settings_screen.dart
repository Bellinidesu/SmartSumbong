// SmartSumbong — Settings (tanod).
//
// Figma: SETTINGS (2212:186), LOG OUT (2260:2478).
//
// Four rows and a header. The header is the resident's own name and
// number, which doubles as a check that they are signed in as who they
// think they are — worth having on a shared handset.

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../duty.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import '../widgets/tanod_nav_bar.dart';

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
  String? _version;
  bool _busy = false;

  final _biometrics = BiometricAuthService();
  bool _biometricEnabled = false;
  bool _biometricBusy = false;

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
  /// toggle commits -- proving right now, while the tanod is looking at
  /// the screen, that the prompt this will show on every future cold
  /// start (and background resume -- see BiometricLockGate) actually
  /// works on this phone. Turning it off needs no such proof; there is
  /// nothing to break by disabling. Off by default, same as the resident
  /// app -- opt-in, not something that slows anyone down until they ask
  /// for it.
  Future<void> _onBiometricToggle(bool value) async {
    if (!value) {
      await BiometricAuthService.setEnabled(false);
      if (mounted) setState(() => _biometricEnabled = false);
      return;
    }

    final s = context.s;
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
  // through a store that tracks versions for you.
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
          .select('full_name, mobile_number')
          .eq('id', uid)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() {
        _name = row['full_name'] as String?;
        _mobile = row['mobile_number'] as String?;
      });
    } catch (_) {
      // The rows below still work; only the header is missing.
    }
  }

  Future<void> _logOut() async {
    final s = context.s;
    final confirmed = await showFigmaDialog<bool>(
      context,
      builder: (dialogContext) => FigmaDialog(
        title: s.settingsLogOut,
        body: s.settingsLogOutConfirmBody,
        secondaryLabel: s.settingsCancel,
        onSecondary: () => Navigator.of(dialogContext).pop(false),
        primaryLabel: s.settingsLogOut,
        onPrimary: () => Navigator.of(dialogContext).pop(true),
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    DutyController.instance.reset();
    await widget.auth.signOut();
    if (!mounted) return;
    // Clear the stack: a back gesture after signing out should not
    // return to a screen that queries as the person who just left.
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    // Figma SETTINGS - TANOD: the title 28/800 at y=50; the 111 avatar at
    // x=44, the name 20/700 and the ink Edit Profile pill beside it; rows
    // 66 apart with the icon box at 54 and the label at 123.
    return Scaffold(
      bottomNavigationBar:
          const TanodNavBar(current: TanodTab.settings),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(top: figmaTop(context, 50), bottom: 24),
          children: [
            FigmaTitle(s.settingsTitle),
            const SizedBox(height: 24),

            Padding(
              padding: const EdgeInsets.only(left: 44, right: 30),
              child: Row(
                children: [
                  Container(
                    width: 111,
                    height: 111,
                    decoration: BoxDecoration(
                      color: context.colors.navy,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(_name),
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 36,
                        color: context.colors.bg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name ?? '\u2014',
                          style: TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            height: 1.4,
                            letterSpacing: -0.5,
                            color: context.colors.navy,
                          ),
                        ),
                        if (_mobile != null)
                          Text(
                            _mask(_mobile!),
                            style: TextStyle(
                              fontFamily: 'Urbanist',
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                              height: 21.84 / 14,
                              color: context.colors.navy,
                            ),
                          ),
                        const SizedBox(height: 6),
                        _EditProfilePill(
                          label: s.settingsEditProfile,
                          onTap: () => Navigator.of(context)
                              .pushNamed('/edit-profile')
                              .then((_) => _load()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            _SettingsRow(
              asset: 'assets/images/settings-personal.png',
              label: s.settingsPersonalInfo,
              onTap: () => Navigator.of(context)
                  .pushNamed('/edit-profile')
                  .then((_) => _load()),
            ),
            _SettingsRow(
              asset: 'assets/images/settings-languages.png',
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
              asset: 'assets/images/settings-facebook.png',
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
              icon: Icons.privacy_tip_outlined,
              label: s.settingsTermsPrivacy,
              onTap: () => Navigator.of(context).pushNamed('/terms-privacy'),
            ),
            _SettingsRow(
              icon: Icons.admin_panel_settings_outlined,
              label: s.settingsExtraAdminServices,
              onTap: () =>
                  Navigator.of(context).pushNamed('/extra-admin-services'),
            ),
            _SettingsRow(
              asset: 'assets/images/settings-logout.png',
              label: s.settingsLogOut,
              showChevron: false,
              onTap: _busy ? null : _logOut,
            ),
            if (_version != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'SmartSumbong Tanod • v$_version',
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
/// label doesn't silently flip the switch. Not itself a Figma frame --
/// there is nowhere in the design this setting was ever specified. See
/// the resident app's settings_screen.dart, where the same row was
/// added first.
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
    return Container(
      constraints: const BoxConstraints(minHeight: _rowPitch),
      padding: const EdgeInsets.only(left: 54, right: 44),
      child: Row(
        children: [
          _RowIcon(icon: icon, colour: context.colors.navy),
          const SizedBox(width: _labelGap),
          Expanded(
            child: Text(label, style: _rowLabel(context.colors.navy)),
          ),
          if (busy)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: context.colors.navy),
            )
          else
            Semantics(
              label: label,
              child: FigmaSwitch(value: value, onChanged: onChanged),
            ),
        ],
      ),
    );
  }
}

/// The frame's rows sit 40 apart at 26 tall; each row's tap target is the
/// whole 66 pitch.
const double _rowPitch = 66;

/// Label at 123 with the 28-wide icon box at 54.
const double _labelGap = 41;

TextStyle _rowLabel(Color colour) => TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w600,
      fontSize: 16,
      height: 1.15,
      color: colour,
    );

/// A Figma icon where the frame drew one, otherwise the Material icon in
/// the same 28x26 box.
class _RowIcon extends StatelessWidget {
  const _RowIcon({this.icon, this.asset, required this.colour});

  final IconData? icon;
  final String? asset;
  final Color colour;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 28,
        height: 26,
        child: Center(
          child: asset != null
              ? Image.asset(asset!, scale: 4, color: colour)
              : Icon(icon, color: colour, size: 24),
        ),
      );
}

/// The frame's Edit Profile pill: ink, 1px page-colour edge, 14/700 label
/// and the design shadow; at least 100 wide, growing for the Filipino
/// label.
class _EditProfilePill extends StatelessWidget {
  const _EditProfilePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 100),
            height: 25,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: context.colors.navy,
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: context.colors.bg),
              boxShadow: kFigmaShadow,
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1,
                  color: context.colors.bg,
                ),
              ),
            ),
          ),
        ),
      );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    this.icon,
    this.asset,
    required this.label,
    required this.onTap,
    this.showChevron = true,
  });

  final IconData? icon;
  final String? asset;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final tint = context.colors.navy;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: _rowPitch),
        padding: const EdgeInsets.only(left: 54, right: 58),
        child: Row(
          children: [
            _RowIcon(icon: icon, asset: asset, colour: tint),
            const SizedBox(width: _labelGap),
            Expanded(child: Text(label, style: _rowLabel(tint))),
            if (showChevron)
              Image.asset('assets/images/settings-chevron.png',
                  scale: 4, color: tint),
          ],
        ),
      ),
    );
  }
}
