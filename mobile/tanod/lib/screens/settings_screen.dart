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

import '../theme.dart';
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

    setState(() => _biometricBusy = true);
    try {
      if (!await _biometrics.isAvailable()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('No Face ID or fingerprint is set up on this device.')),
        );
        return;
      }

      final confirmed = await _biometrics
          .authenticate('Confirm to turn on Face ID / fingerprint unlock');
      if (!mounted) return;

      if (confirmed) {
        await BiometricAuthService.setEnabled(true);
        if (mounted) setState(() => _biometricEnabled = true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Could not confirm. Face ID / fingerprint unlock was not '
                  'turned on.')),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Tokens.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Log Out',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: Tokens.bg,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Are you sure you want to log out?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Tokens.bg),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Tokens.bg,
                        side: const BorderSide(color: Tokens.bg),
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: FilledButton.styleFrom(
                        backgroundColor: Tokens.field,
                        foregroundColor: Tokens.navy,
                        minimumSize: const Size.fromHeight(42),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50),
                        ),
                      ),
                      child: const Text('Log Out'),
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      bottomNavigationBar:
          const TanodNavBar(current: TanodTab.settings),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
          children: [
            Center(
              child: Text('Settings',
                  style: t.headlineLarge?.copyWith(fontSize: 28)),
            ),
            const SizedBox(height: 28),

            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Tokens.navy,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(_name),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      color: Tokens.bg,
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
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: Tokens.navy,
                        ),
                      ),
                      if (_mobile != null)
                        Text(
                          _mask(_mobile!),
                          style: const TextStyle(
                              fontSize: 12, color: Tokens.muted),
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
                          child: const Text(
                            'Edit Profile',
                            style: TextStyle(
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
              label: 'Personal Information',
              onTap: () => Navigator.of(context)
                  .pushNamed('/edit-profile')
                  .then((_) => _load()),
            ),
            _SettingsRow(
              icon: Icons.language,
              label: 'Languages',
              onTap: () => Navigator.of(context).pushNamed('/languages'),
            ),
            _SettingsToggleRow(
              icon: Icons.fingerprint,
              label: 'Unlock with Face ID / fingerprint',
              value: _biometricEnabled,
              busy: _biometricBusy,
              onChanged: _onBiometricToggle,
            ),
            _SettingsRow(
              icon: Icons.facebook,
              label: 'Facebook',
              onTap: () async {
                final uri = Uri.parse(_facebookUrl);
                if (!await launchUrl(uri,
                    mode: LaunchMode.externalApplication)) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Could not open the barangay page.')),
                  );
                }
              },
            ),
            _SettingsRow(
              icon: Icons.logout,
              label: 'Log Out',
              showChevron: false,
              onTap: _busy ? null : _logOut,
            ),
            if (_version != null) ...[
              const SizedBox(height: 24),
              Center(
                child: Text(
                  'SmartSumbong Tanod • v$_version',
                  style: const TextStyle(fontSize: 11, color: Tokens.muted),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Icon(icon, color: Tokens.navy, size: 22),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Tokens.navy),
            ),
          ),
          if (busy)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Tokens.navy),
            )
          else
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: Tokens.navy,
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
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: Tokens.navy, size: 22),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Tokens.navy),
              ),
            ),
            if (showChevron)
              const Icon(Icons.chevron_right, color: Tokens.navy, size: 20),
          ],
        ),
      ),
    );
  }
}
