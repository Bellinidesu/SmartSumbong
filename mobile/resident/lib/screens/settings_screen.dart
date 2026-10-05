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
import '../d/d_switches.dart';
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
  BiometricStatus? _bio;

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
    final bio = await _biometrics.status();
    if (!mounted) return;
    setState(() {
      _bio = bio;
      // A setting left on from before (or a sensor since removed) cannot
      // stay on when the phone can no longer do it.
      _biometricEnabled = enabled && bio.state == BiometricState.ready;
    });
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

  /// The line under the row: what was found, or why it cannot be used.
  String? _bioReason(BuildContext context) {
    final b = _bio;
    if (b == null) return null;
    switch (b.state) {
      case BiometricState.ready:
        final what = [if (b.fingerprint) context.tr('fingerprint', 'fingerprint'), if (b.face) context.tr('face', 'mukha')].join(context.tr(' and ', ' at '));
        return context.tr('Uses your phone\'s $what', 'Gamit ang $what ng iyong telepono');
      case BiometricState.notEnrolled:
        return context.tr('Set up a fingerprint or face in your phone\'s Settings first', 'Mag-set up muna ng fingerprint o mukha sa Settings ng telepono');
      case BiometricState.noHardware:
        return context.tr('This phone has no fingerprint or face sensor the app can use', 'Walang fingerprint o face sensor ang teleponong ito na magagamit ng app');
      case BiometricState.unsupported:
        return context.tr('Not available on this phone', 'Hindi available sa teleponong ito');
    }
  }

  void _explainBiometric() {
    final b = _bio;
    if (b == null) return;
    final body = switch (b.state) {
      BiometricState.notEnrolled => context.tr(
          'Your phone has a sensor, but no fingerprint or face is saved yet. Open your phone\'s Settings → Security (or Biometrics), add a fingerprint, then come back and turn this on.',
          'May sensor ang iyong telepono pero wala pang naka-save na fingerprint o mukha. Buksan ang Settings → Security (o Biometrics) ng telepono, magdagdag ng fingerprint, saka bumalik dito.'),
      BiometricState.noHardware => context.tr(
          'This phone has no fingerprint reader the app can use. Some phones\' face unlock only uses the front camera, which Android does not trust for apps, so it cannot be used here either. You can still sign in with your password.',
          'Walang fingerprint reader ang teleponong ito na magagamit ng app. Ang face unlock ng ilang telepono ay gumagamit lang ng front camera, na hindi pinagkakatiwalaan ng Android para sa mga app. Makakapag-sign in ka pa rin gamit ang password.'),
      _ => context.tr(
          'This phone or its Android version cannot use fingerprint or face unlock for apps, or it has no screen lock set. You can still sign in with your password.',
          'Hindi magagamit ng teleponong ito o ng bersyon ng Android nito ang fingerprint o face unlock para sa mga app, o wala itong screen lock. Makakapag-sign in ka pa rin gamit ang password.'),
    };
    showDDialog(context, title: context.tr('Why this is greyed out', 'Bakit ito naka-grey'), body: body, primary: context.tr('OK', 'OK'), icon: Icons.fingerprint_rounded);
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

  // Branch D, 1:1 with the preview's Settings: the h1, the role-colour
  // profile card (64 px white avatar, name, number, Edit Profile), then
  // one bordered list — icon, label, chevron — with the EN/PH flags on
  // the Languages row and the sun/moon switch on Appearance, Log Out in
  // red, and Delete Account as a ghost button under it.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    // One Settings for both roles (branch C): a tanod gets the tanod nav
    // bar and Extra Administrative Services; a resident gets notification
    // preferences and Delete Account (a tanod retires instead).
    final tanod = AppRoleController.instance.value == AppRole.tanod;
    final red = const Color(0xFFC62828);
    return DPage(
      bottomBar: tanod ? const TanodNavBar(current: TanodTab.settings) : const ResidentNavBar(current: ResidentTab.settings),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        children: [
          Text(s.settingsTitle, style: DType.h1(d.ink)),
          const SizedBox(height: 14),
          DCard(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // A green ring and a tick: the account is verified (an
              // unverified one never reaches Settings).
              Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 68,
                  height: 68,
                  padding: const EdgeInsets.all(2.5),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3DDC84)),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      image: _avatarUrl != null ? DecorationImage(image: NetworkImage(cloudinarySized(_avatarUrl!, width: 300)), fit: BoxFit.cover) : null,
                    ),
                    alignment: Alignment.center,
                    child: _avatarUrl != null
                        ? null
                        : Text(_initials(_name),
                            style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 22, color: d.tanod ? const Color(0xFF14181D) : DColors.brandNavy)),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF1F8A45), border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.check_rounded, size: 13, color: Colors.white),
                  ),
                ),
              ]),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_name ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 17, color: Colors.white)),
                  if (_mobile != null)
                    Text('${_mask(_mobile!)} · ${tanod ? context.tr('Verified tanod', 'Beripikadong tanod') : context.tr('Verified resident', 'Beripikadong residente')}', style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w500, fontSize: 12.5, color: Colors.white.withValues(alpha: .8))),
                ]),
              ),
              DButton(s.settingsEditProfile, small: true, kind: DButtonKind.white, onTap: () => Navigator.of(context).pushNamed('/edit-profile').then((_) => _load())),
            ]),
          ),
          const SizedBox(height: 18),
          _Heading(context.tr('Account & preferences', 'Account at mga kagustuhan')),
          _List(children: [
            _Row(icon: Icons.person_outline_rounded, label: s.settingsPersonalInfo, onTap: () => Navigator.of(context).pushNamed('/edit-profile').then((_) => _load()), chevron: true),
            _Row(icon: Icons.language_rounded, label: s.settingsLanguages, onTap: () => Navigator.of(context).pushNamed('/languages'), trailing: const DFlags()),
            _Row(icon: Icons.dark_mode_outlined, label: s.settingsAppearance, onTap: () => Navigator.of(context).pushNamed('/appearance'), trailing: const DDayNight()),
            if (!tanod)
              _Row(icon: Icons.notifications_none_rounded, label: s.settingsNotificationPrefs, onTap: () => Navigator.of(context).pushNamed('/notification-preferences'), chevron: true),
            if (tanod)
              _Row(icon: Icons.work_outline_rounded, label: context.ts.settingsExtraAdminServices, onTap: () => Navigator.of(context).pushNamed('/t/extra-admin-services'), chevron: true),
            _Row(
              icon: Icons.facebook_rounded,
              label: s.settingsFacebook,
              chevron: true,
              onTap: () async {
                final uri = Uri.parse(_facebookUrl);
                if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.settingsFacebookError)));
                }
              },
            ),
          ]),
          const SizedBox(height: 18),
          _Heading(context.tr('Security & privacy', 'Seguridad at privacy')),
          _List(children: [
            _Row(
              icon: Icons.fingerprint_rounded,
              label: s.settingsBiometricUnlock,
              sub: _bioReason(context),
              dim: _bio != null && _bio!.state != BiometricState.ready,
              onTap: _biometricBusy
                  ? null
                  : (_bio != null && _bio!.state != BiometricState.ready)
                      ? _explainBiometric
                      : () => _onBiometricToggle(!_biometricEnabled),
              trailing: _biometricBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2))
                  : _OnPill(on: _biometricEnabled),
            ),
            _Row(icon: Icons.shield_outlined, label: s.termsPrivacyTitle, onTap: () => Navigator.of(context).pushNamed('/terms-privacy'), chevron: true),
            _Row(icon: Icons.logout_rounded, label: s.settingsLogOut, labelColor: red, busy: _busy, onTap: _busy ? null : _logOut),
          ]),
          if (!tanod) ...[
            const SizedBox(height: 14),
            _DeleteButton(label: s.settingsDeleteAccount, busy: _deletingAccount, onTap: _deletingAccount ? null : _deleteAccount),
          ],
          if (_version != null) ...[
            const SizedBox(height: 18),
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

/// `.list`: radius 18, hairline border, rows divided by lines.
class _List extends StatelessWidget {
  const _List({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: d.line),
          children[i],
        ],
      ]),
    );
  }
}

/// A row: a bare 20 px icon, the label 14.5/600, then a chevron, a pill,
/// the flags or the switch.
class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, this.onTap, this.trailing, this.chevron = false, this.labelColor, this.busy = false, this.sub, this.dim = false});

  final IconData icon;
  final String label;
  final String? sub;
  final bool dim;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool chevron;
  final Color? labelColor;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Icon(icon, size: 20, color: d.link),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: DType.body(dim ? d.muted : (labelColor ?? d.ink), size: 14.5, w: FontWeight.w600).copyWith(height: 1.25)),
              if (sub != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(sub!, style: DType.body(d.muted, size: 12).copyWith(height: 1.3))),
            ]),
          ),
          if (busy)
            const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
          else if (trailing != null)
            Opacity(opacity: dim ? .4 : 1, child: trailing!)
          else if (chevron)
            Text('›', style: TextStyle(fontSize: 20, height: 1, color: d.muted)),
        ]),
      ),
    );
  }
}

/// The preview's green On pill (grey when off).
class _OnPill extends StatelessWidget {
  const _OnPill({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final c = on ? const Color(0xFF1F8A45) : d.muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: Color.alphaBlend(c.withValues(alpha: .14), d.card), borderRadius: BorderRadius.circular(99)),
      child: Text(on ? context.tr('On', 'Naka-on') : context.tr('Off', 'Naka-off'), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: on ? (d.dark ? const Color(0xFF5FD68A) : c) : c)),
    );
  }
}

/// `.btn.ghost` in red: Delete Account.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      height: 44,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: d.line, width: 1.5)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Center(
          child: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2))
              : Text(label, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFFC62828))),
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

/// A small label over a group of Settings rows (Martin, 6 Oct 2026).
class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(text.toUpperCase(), style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11.5, letterSpacing: 1.04, color: context.d.muted)),
      );
}
