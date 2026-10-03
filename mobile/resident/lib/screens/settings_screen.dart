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
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import '../tanod/tanod_strings.dart';
import '../tanod/widgets/tanod_nav_bar.dart';
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
    // Figma LOG OUT (2260:2478): a 300x200 navy card, radius 50, 2px
    // #252525 edge, the title orange at 24/700, the question 16/500, and
    // 106x40 Cancel / Log Out pills 13 apart; the page fades to 30%.
    final confirmed = await showDDialog(
      context,
      title: s.settingsLogOut,
      body: s.settingsLogOutConfirmBody,
      primary: s.settingsLogOut,
      secondary: s.settingsCancel,
      icon: Icons.logout_rounded,
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
    final confirmed = await showFigmaDialog<bool>(
      context,
      builder: (_) => _DeleteAccountDialog(s: s, auth: widget.auth),
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

  // Branch D: the preview's Settings — a role-colour profile card (photo
  // or initials, name, masked number, Edit Profile), then the rows in two
  // white cards with round icon wells. Appearance carries its day/night
  // switch and Languages its EN/PH flags right on the row; the row itself
  // still opens the full page.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    // One Settings for both roles (branch C): a tanod gets the tanod nav
    // bar and Extra Administrative Services; a resident gets notification
    // preferences and Delete Account (a tanod retires instead).
    final tanod = AppRoleController.instance.value == AppRole.tanod;

    return DPage(
      bottomBar: tanod ? const TanodNavBar(current: TanodTab.settings) : const ResidentNavBar(current: ResidentTab.settings),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        children: [
          Text(s.settingsTitle, style: DType.h1(d.accent).copyWith(fontSize: 30)),
          const SizedBox(height: 16),
          DCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white.withValues(alpha: .6), width: 3),
                  image: _avatarUrl != null
                      ? DecorationImage(image: NetworkImage(cloudinarySized(_avatarUrl!, width: 300)), fit: BoxFit.cover)
                      : null,
                ),
                alignment: Alignment.center,
                child: _avatarUrl != null
                    ? null
                    : Text(_initials(_name),
                        style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 26, color: d.card2)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name ?? '—', style: DType.h3(Colors.white).copyWith(fontSize: 18.5)),
                  if (_mobile != null) Text(_mask(_mobile!), style: DType.body(Colors.white.withValues(alpha: .8), size: 13)),
                  const SizedBox(height: 10),
                  DButton(s.settingsEditProfile,
                      small: true,
                      kind: DButtonKind.white,
                      height: 34,
                      onTap: () => Navigator.of(context).pushNamed('/edit-profile').then((_) => _load())),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _Group(children: [
            _Row(
              icon: Icons.person_outline_rounded,
              label: s.settingsPersonalInfo,
              onTap: () => Navigator.of(context).pushNamed('/edit-profile').then((_) => _load()),
            ),
            _Row(
              icon: Icons.translate_rounded,
              label: s.settingsLanguages,
              onTap: () => Navigator.of(context).pushNamed('/languages'),
              trailing: const _LangFlags(),
            ),
            _Row(
              icon: Icons.dark_mode_outlined,
              label: s.settingsAppearance,
              onTap: () => Navigator.of(context).pushNamed('/appearance'),
              trailing: const _DayNight(),
            ),
            _Row(
              icon: Icons.fingerprint_rounded,
              label: s.settingsBiometricUnlock,
              trailing: _biometricBusy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                  : Switch(value: _biometricEnabled, activeThumbColor: Colors.white, activeTrackColor: DColors.greenVivid, onChanged: _onBiometricToggle),
            ),
            if (!tanod)
              _Row(
                icon: Icons.notifications_none_rounded,
                label: s.settingsNotificationPrefs,
                onTap: () => Navigator.of(context).pushNamed('/notification-preferences'),
              ),
          ]),
          const SizedBox(height: 14),
          _Group(children: [
            if (tanod)
              _Row(
                icon: Icons.admin_panel_settings_outlined,
                label: context.ts.settingsExtraAdminServices,
                onTap: () => Navigator.of(context).pushNamed('/t/extra-admin-services'),
              ),
            _Row(
              icon: Icons.privacy_tip_outlined,
              label: s.termsPrivacyTitle,
              onTap: () => Navigator.of(context).pushNamed('/terms-privacy'),
            ),
            _Row(
              icon: Icons.facebook_rounded,
              label: s.settingsFacebook,
              onTap: () async {
                final uri = Uri.parse(_facebookUrl);
                if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.settingsFacebookError)));
                }
              },
            ),
            if (!tanod)
              _Row(
                icon: Icons.delete_outline_rounded,
                label: s.settingsDeleteAccount,
                danger: true,
                busy: _deletingAccount,
                onTap: _deletingAccount ? null : _deleteAccount,
              ),
            _Row(
              icon: Icons.logout_rounded,
              label: s.settingsLogOut,
              danger: true,
              busy: _busy,
              onTap: _busy ? null : _logOut,
            ),
          ]),
          if (_version != null) ...[
            const SizedBox(height: 22),
            Center(child: Text('SmartSumbong • v$_version', style: DType.body(d.muted, size: 11.5))),
          ],
        ],
      ),
    );
  }

  static String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }

  /// Shown on a screen someone might hold up in a barangay hall.
  static String _mask(String mobile) {
    if (mobile.length < 4) return mobile;
    return '${mobile.substring(0, 3)} •••••• '
        '${mobile.substring(mobile.length - 4)}';
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, indent: 64, color: d.line),
          children[i],
        ],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.onTap, this.trailing, this.danger = false, this.busy = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final red = d.dark ? const Color(0xFFFF8A8A) : const Color(0xFFDC2626);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          DWell(icon, size: 40, color: danger ? red : d.link, tint: danger ? red.withValues(alpha: .1) : null),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: DType.body(danger ? red : d.ink, size: 15, w: FontWeight.w700))),
          if (busy)
            const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
          else if (trailing != null)
            trailing!
          else if (!danger)
            Icon(Icons.chevron_right_rounded, color: d.muted),
        ]),
      ),
    );
  }
}

/// The day/night switch on the Appearance row: light or dark straight
/// away; "follow the phone" stays on the Appearance page.
class _DayNight extends StatelessWidget {
  const _DayNight();

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return GestureDetector(
      onTap: () => AppThemeScope.controllerOf(context).set(dark ? ThemeMode.light : ThemeMode.dark),
      child: Container(
        width: 56,
        height: 30,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: dark ? const Color(0xFF22305E) : const Color(0xFFDCE6FA)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200),
          alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dark ? const Color(0xFF0E1322) : Colors.white),
            child: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 15, color: dark ? const Color(0xFFFFD27A) : DColors.orange),
          ),
        ),
      ),
    );
  }
}

class _LangFlags extends StatelessWidget {
  const _LangFlags();

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final lang = AppLocaleScope.of(context);
    Widget f(AppLocale l, String e) {
      final on = lang == l;
      return GestureDetector(
        onTap: () => AppLocaleScope.controllerOf(context).set(l),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: on ? d.card : Colors.transparent,
            boxShadow: on ? [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 5)] : null,
          ),
          child: Opacity(opacity: on ? 1 : .55, child: Text(e, style: const TextStyle(fontSize: 16))),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: d.field, border: Border.all(color: d.line)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [f(AppLocale.en, '🇺🇸'), f(AppLocale.fil, '🇵🇭')]),
    );
  }
}

/// Two gates in one dialog: the explanation (why this differs from just
/// signing out) and a typed "DELETE" the confirm button won't accept
/// without — see _deleteAccount's own comment for why an irreversible
/// action gets more friction here than anywhere else in this app.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({required this.s, required this.auth});

  final Strings s;
  final AuthService auth;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password.addListener(() {
      if (_error != null) setState(() => _error = null);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  /// The second gate is the account's own password (branch B), not a
  /// typed DELETE: an irreversible action should prove the person holding
  /// the phone is the account holder, not just that the app is unlocked.
  /// verifyPassword re-checks it without ending the session; offline is
  /// said as offline, not as a wrong password.
  Future<void> _confirm() async {
    if (_checking || _password.text.isEmpty) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    bool ok;
    try {
      ok = await widget.auth.verifyPassword(_password.text);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = widget.s.deleteAccountCheckFailed;
      });
      return;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _checking = false;
        _error = widget.s.deleteAccountWrongPassword;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  // The design's dialog card (as LOG OUT), with the title in the
  // design's red and a red confirm pill, since this one can't be undone.
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final c = context.colors;
    return FigmaDialog(
      title: s.deleteAccountConfirmTitle,
      titleColor: kFigmaRed,
      body: s.deleteAccountConfirmBody,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 4),
            child: Text(
              s.deleteAccountPasswordPrompt,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: c.bg,
              ),
            ),
          ),
          FigmaDialogField(
            controller: _password,
            hint: s.loginPasswordHint,
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => _confirm(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: kFigmaOrange, fontSize: 12),
            ),
          ],
        ],
      ),
      secondaryLabel: s.settingsCancel,
      onSecondary: () => Navigator.of(context).pop(false),
      primaryLabel: s.deleteAccountConfirmButton,
      onPrimary:
          _checking || _password.text.isEmpty ? null : () => _confirm(),
      destructive: true,
    );
  }
}
