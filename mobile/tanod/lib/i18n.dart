// SmartSumbong — tanod-app language switching.
//
// Ported 8 Sep 2026 from the resident app's i18n.dart (26 Aug 2026),
// which tanod never got at the time — its Languages screen recorded a
// choice but only ever rendered English, with a snackbar admitting as
// much when Filipino was picked. Same architecture, same reasoning for
// a hand-written lookup table rather than flutter_localizations + ARB +
// gen-l10n: that pipeline needs the Flutter toolchain to run, which this
// session cannot do, and a change that only works if someone remembers
// to run `flutter gen-l10n` first is exactly the kind of silent trap
// this project avoids elsewhere.
//
// HOW TO ADD A SCREEN TO THIS. Add its strings as getters on [Strings]
// below, grouped under a `// ---------- screen name ----------` comment
// the same way the existing groups are. Read them in the screen via
// `context.s.whateverKey` (the `AppLocaleContext` extension at the
// bottom). No screen should call [Strings] directly — always through
// the extension, so it always reflects the live locale.
//
// Every getter below was written to match the EXACT English copy that
// was already live in each screen, so wiring a screen up to this file
// never changes what an English-reading tanod sees — only what a
// Filipino-reading one does.
//
// A native Filipino speaker on the team should read these before the
// defense — they're a good-faith translation, not a reviewed one.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Matches `languageKey` in the old languages_screen.dart exactly — 'en'
/// / 'fil' — so a value an earlier build already saved to a handset
/// keeps meaning the same thing.
const languageKey = 'language';

enum AppLocale { en, fil }

/// Loads the saved choice once at startup, and is the single place a
/// change is written and broadcast afterward — `languages_screen.dart`
/// no longer touches SharedPreferences itself.
class LocaleController extends ValueNotifier<AppLocale> {
  LocaleController([AppLocale initial = AppLocale.en]) : super(initial);

  static Future<LocaleController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(languageKey);
      return LocaleController(v == 'fil' ? AppLocale.fil : AppLocale.en);
    } catch (_) {
      // Storage unavailable: English, same as every other fallback in
      // this app defaults to the safe, always-correct choice.
      return LocaleController();
    }
  }

  Future<void> set(AppLocale locale) async {
    value = locale; // Notifies every AppLocaleScope listener immediately.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          languageKey, locale == AppLocale.fil ? 'fil' : 'en');
    } catch (_) {
      // The choice still stands for the rest of this session — only the
      // next cold start falls back to English.
    }
  }
}

/// Makes the current locale available to every screen below it and
/// rebuilds that subtree when [LocaleController.set] changes it —
/// `InheritedNotifier` does both in one widget, which is why this file
/// does not also need a `ValueListenableBuilder` wrapped around
/// `MaterialApp` in main.dart.
class AppLocaleScope extends InheritedNotifier<LocaleController> {
  const AppLocaleScope({
    super.key,
    required LocaleController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppLocale of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    return scope?.notifier?.value ?? AppLocale.en;
  }

  static LocaleController controllerOf(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AppLocaleScope>();
    assert(scope != null,
        'AppLocaleScope not found above this widget — wrap MaterialApp with it in main.dart.');
    return scope!.notifier!;
  }
}

/// `context.s.someString` anywhere in the widget tree below
/// [AppLocaleScope]. Reading it via `context` (rather than a global) is
/// what makes `dependOnInheritedWidgetOfExactType` register the
/// dependency, so the calling widget actually rebuilds on a language
/// change.
extension AppLocaleContext on BuildContext {
  Strings get s => Strings(AppLocaleScope.of(this));
}

/// Every user-facing string in the tanod app, as paired getters. English
/// first, Filipino second, in `_t()` — reading the pair together is what
/// a translation review is for, so they are kept side by side rather
/// than in two separate tables that could drift apart silently.
class Strings {
  const Strings(this.locale);
  final AppLocale locale;

  String _t(String en, String fil) => locale == AppLocale.fil ? fil : en;

  static const _monthsAbbrEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthsAbbrFil = [
    'Ene', 'Peb', 'Mar', 'Abr', 'May', 'Hun',
    'Hul', 'Ago', 'Set', 'Okt', 'Nob', 'Dis',
  ];
  String monthAbbr(int month) =>
      _t(_monthsAbbrEn[month - 1], _monthsAbbrFil[month - 1]);

  static const _monthsFullEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthsFullFil = [
    'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
    'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre',
  ];
  String monthFull(int month) =>
      _t(_monthsFullEn[month - 1], _monthsFullFil[month - 1]);

  // ---------- languages ----------
  String get languagesTitle => _t('Select Language', 'Pumili ng Wika');
  String get languagesFilipino => _t('Filipino / Tagalog', 'Filipino / Tagalog');
  String get languagesEnglish => _t('English', 'Ingles');
  String get languagesBack => _t('Back', 'Bumalik');
  String get languagesChangedToFilipino =>
      _t('Language changed to Filipino.', 'Napalitan sa Filipino ang wika.');
  String get languagesChangedToEnglish =>
      _t('Language changed to English.', 'Napalitan sa Ingles ang wika.');

  // ---------- appearance (theme) ----------
  String get themeTitle => _t('Appearance', 'Itsura');
  String get themeSystem => _t('System', 'Sistema');
  String get themeLight => _t('Light', 'Maliwanag');
  String get themeDark => _t('Dark', 'Madilim');
  String get themeBack => _t('Back', 'Bumalik');

  // ---------- background-resume lock screen ----------
  // Shown by BiometricLockGate (smartsumbong_core) when the app is
  // reopened from the background with Face ID / fingerprint unlock on.
  String get launchGateBiometricReason =>
      _t('Unlock SmartSumbong', 'I-unlock ang SmartSumbong');
  String get lockGateTitle => _t('Locked', 'Naka-lock');
  String get lockGateBody => _t(
      'Unlock with Face ID or fingerprint to continue.',
      'I-unlock gamit ang Face ID o fingerprint para magpatuloy.');
  String get lockGateUnlock => _t('Unlock', 'I-unlock');
  String get lockGateFallback =>
      _t('Use password instead', 'Gamitin na lang ang password');

  // ---------- notifications ----------
  String get notificationsTitle => _t('Notifications', 'Mga Notification');
  String get notificationsLoadError => _t(
      'Could not load your notifications.',
      'Hindi ma-load ang iyong mga notification.');
  String get notificationsEmptyTitle =>
      _t('No notifications yet', 'Wala pang notification');
  String get notificationsEmptyBody => _t(
      'When the barangay updates one of your reports, you will see it '
      'here.',
      'Kapag na-update ng barangay ang isa sa iyong mga ulat, makikita mo '
      'ito rito.');
  String get notificationsJustNow => _t('Just now', 'Ngayon lang');
  String notificationsMinutesAgo(int m) =>
      _t('$m minutes ago', '$m minuto ang nakalipas');
  String get notificationsAnHourAgo =>
      _t('An hour ago', 'Isang oras ang nakalipas');
  String notificationsHoursAgo(int h) =>
      _t('$h hours ago', '$h oras ang nakalipas');
  String get notificationsYesterday => _t('Yesterday', 'Kahapon');
  String notificationsDaysAgo(int d) =>
      _t('$d days ago', '$d araw ang nakalipas');

  // ---------- account status (rejected / suspended / retired) ----------
  String get accountStatusRejectedTitle => _t(
      'Registration not approved', 'Hindi Naaprubahan ang Pagpaparehistro');
  String get accountStatusSuspendedTitle =>
      _t('Account suspended', 'Naka-suspend ang Account');
  String get accountStatusRejectedBody => _t(
      'The barangay reviewed your registration and did not approve it.',
      'Sinuri ng barangay ang iyong pagpaparehistro at hindi ito '
      'inaprubahan.');
  String get accountStatusSuspendedBody => _t(
      'The barangay has suspended this account. You cannot file or '
      'follow up on complaints while it is suspended.',
      'Sinuspinde ng barangay ang account na ito. Hindi ka maaaring '
      'mag-file o mag-follow up ng mga reklamo habang naka-suspend.');
  String get accountStatusReasonGiven =>
      _t('Reason given', 'Ibinigay na Dahilan');
  String get accountStatusRejectedCanRegister => _t(
      'If you think this is a mistake, visit the barangay hall with a '
      'valid ID. You can register again once the problem is fixed.',
      'Kung sa tingin mo ay may pagkakamali, pumunta sa barangay hall '
      'na may dalang balidong ID. Maaari kang magrehistro ulit kapag '
      'naayos na ang problema.');
  String get accountStatusRejectedCannotRegister => _t(
      'If you think this is a mistake, visit the barangay hall with your '
      'Barangay ID. To register again, use the SmartSumbong app for '
      'residents.',
      'Kung sa tingin mo ay may pagkakamali, pumunta sa barangay hall '
      'na may dalang Barangay ID mo. Para magrehistro ulit, gamitin ang '
      'SmartSumbong app para sa mga residente.');
  String get accountStatusSuspendedNote => _t(
      'To have this looked at, visit the barangay hall with a valid ID.',
      'Para masuri ito, pumunta sa barangay hall na may dalang balidong ID.');
  String get accountStatusRetiredTitle =>
      _t('You have retired', 'Nagretiro Ka Na');
  String get accountStatusRetiredBody => _t(
      'The barangay approved your retirement request. Thank you for your '
      'service as a tanod of Barangay 183.',
      'Inaprubahan ng barangay ang iyong kahilingan sa pagreretiro. '
      'Salamat sa iyong paglilingkod bilang tanod ng Barangay 183.');
  String get accountStatusRetiredDateLabel =>
      _t('Retired since', 'Nagretiro Noong');
  String get accountStatusRetiredNote => _t(
      'This account can no longer sign in. Your records remain on file '
      'with the barangay. If you believe this was a mistake, visit the '
      'barangay hall.',
      'Hindi na maaaring mag-sign in gamit ang account na ito. Nananatili '
      'ang iyong mga record sa barangay. Kung sa tingin mo ay may '
      'pagkakamali, pumunta sa barangay hall.');
  String get accountStatusRegisterAgain =>
      _t('Register again', 'Magrehistro Ulit');
  String get accountStatusSignOut => _t('Sign out', 'Mag-sign Out');

  // ---------- change password ----------
  String get changePasswordTooShort => _t(
      'Your password must be at least 8 characters long.',
      'Dapat hindi bababa sa 8 na karakter ang iyong password.');
  String get changePasswordMismatch => _t(
      'The two passwords do not match.', 'Hindi magkatugma ang dalawang password.');
  String get changePasswordFailed => _t(
      'Could not set your new password. Please check your connection and '
      'try again.',
      'Hindi maitakda ang iyong bagong password. Suriin ang iyong '
      'koneksyon at subukan ulit.');
  String get changePasswordTitle =>
      _t('Set a new password', 'Magtakda ng Bagong Password');
  String get changePasswordBody => _t(
      'The barangay gave you a temporary password. Choose your own now '
      'so that only you know it.',
      'Binigyan ka ng barangay ng pansamantalang password. Pumili ng '
      'sarili mong password ngayon para ikaw lang ang nakakaalam nito.');
  String get changePasswordNewLabel => _t('New password', 'Bagong Password');
  String get changePasswordNewNote =>
      _t('(At least 8 characters.)', '(Hindi bababa sa 8 na karakter.)');
  String get changePasswordNewHint =>
      _t('Enter your new password', 'Ilagay ang iyong bagong password');
  String get changePasswordConfirmLabel =>
      _t('Confirm password', 'Kumpirmahin ang Password');
  String get changePasswordConfirmNote =>
      _t('(Both must match.)', '(Dapat magkatugma ang dalawa.)');
  String get changePasswordConfirmHint =>
      _t('Type it again', 'I-type ulit');
  String get changePasswordSave => _t('Save password', 'I-save ang Password');
  String get changePasswordSignOutInstead =>
      _t('Sign out instead', 'Mag-sign Out na Lang');

  // ---------- launch gate ----------
  String get launchGateWrongApp => _t(
      'This account is not a barangay tanod. Please use the SmartSumbong '
      'resident app to file and follow up on complaints.',
      'Hindi barangay tanod ang account na ito. Gamitin ang SmartSumbong '
      'resident app para mag-file at mag-follow up ng mga reklamo.');
  String get launchGateSignOut => _t('Sign out', 'Mag-sign Out');
  String get launchGateTryAgain => _t('Try again', 'Subukan Ulit');
  String get launchGateSigningIn =>
      _t('Signing you in…', 'Nagsa-sign in ka na…');
  String launchGatePostgrestError(String detail) => _t(
      'The barangay’s system refused the request. ($detail)',
      'Tinanggihan ng sistema ng barangay ang kahilingan. ($detail)');
  String launchGateOfflineError(String detail) => _t(
      'Could not reach the barangay’s system. Check your connection and '
      'try again.\n\n$detail',
      'Hindi ma-abot ang sistema ng barangay. Suriin ang iyong koneksyon '
      'at subukan ulit.\n\n$detail');

  // ---------- login ----------
  String get loginTanodProfile => _t('Tanod Profile', 'Profile ng Tanod');
  String get loginPhoneLabel => _t('Phone Number', 'Numero ng Telepono');
  String get loginPhoneHint =>
      _t('Enter phone number', 'Ilagay ang numero ng telepono');
  String get loginPasswordLabel => _t('Password', 'Password');
  String get loginPasswordHint =>
      _t('Enter password', 'Ilagay ang password');
  String get loginRememberMe => _t('Remember me', 'Tandaan ako');
  String get loginForgotPassword =>
      _t('Forgot password?', 'Nakalimutan ang password?');
  String get loginButton => _t('Log In', 'Mag-log In');
  String get loginOfflineError => _t(
      'Could not sign you in. Please check your connection and try '
      'again.',
      'Hindi ka ma-sign in. Pakisuri ang iyong koneksyon at subukan '
      'ulit.');
  String loginLockedMessage(int minutes) {
    final unit = _t(minutes == 1 ? 'minute' : 'minutes', 'minuto');
    return _t('Too many failed attempts. Try again in $minutes $unit.',
        'Sobrang dami ng maling pagsubok. Subukan ulit pagkalipas ng '
        '$minutes $unit.');
  }

  String get loginRegisterNote => _t(
      'To register as a tanod, use the SmartSumbong app for residents. '
      'The barangay office approves the account.',
      'Upang magparehistro bilang tanod, gamitin ang SmartSumbong app '
      'para sa mga residente. Ang barangay office ang nag-aaproba ng '
      'account.');
  String get loginForgotDialogTitle =>
      _t('Forgot password', 'Nakalimutan ang password');
  String get loginForgotDialogBody => _t(
      'Ask the barangay office to reset your password. They will give '
      'you a temporary one, and the app will ask you to choose your own '
      'when you sign in.',
      'Hilingin sa barangay office na i-reset ang iyong password. '
      'Bibigyan ka nila ng pansamantalang password, at hihilingin sa iyo '
      'ng app na pumili ng sarili mong password kapag nag-sign in ka.');
  String get loginDialogOk => _t('OK', 'OK');

  // ---------- settings ----------
  String get settingsTitle => _t('Settings', 'Mga Setting');
  String get settingsPersonalInfo =>
      _t('Personal Information', 'Personal na Impormasyon');
  String get settingsEditProfile => _t('Edit Profile', 'I-edit ang Profile');
  String get settingsLanguages => _t('Languages', 'Mga Wika');
  String get settingsAppearance => _t('Appearance', 'Anyo');
  String get settingsBiometricUnlock => _t(
      'Unlock with Face ID / fingerprint',
      'I-unlock gamit ang Face ID / fingerprint');
  String get settingsBiometricUnavailable => _t(
      'No Face ID or fingerprint is set up on this device.',
      'Walang naka-set up na Face ID o fingerprint sa device na ito.');
  String get settingsBiometricConfirmReason => _t(
      'Confirm to turn on Face ID / fingerprint unlock',
      'Kumpirmahin para i-on ang Face ID / fingerprint unlock');
  String get settingsBiometricEnableFailed => _t(
      'Could not confirm. Face ID / fingerprint unlock was not turned on.',
      'Hindi makumpirma. Hindi na-on ang Face ID / fingerprint unlock.');
  String get settingsFacebook => _t('Facebook', 'Facebook');
  String get settingsFacebookError => _t(
      'Could not open the barangay page.',
      'Hindi mabuksan ang page ng barangay.');
  String get settingsTermsPrivacy =>
      _t('Terms & Privacy', 'Mga Tuntunin at Privacy');
  String get settingsExtraAdminServices =>
      _t('Extra Administrative Services', 'Karagdagang Serbisyong Administratibo');
  String get settingsLogOut => _t('Log Out', 'Mag-log Out');
  String get settingsLogOutConfirmBody => _t(
      'Are you sure you want to log out?', 'Sigurado ka bang mag-log out?');
  String get settingsCancel => _t('Cancel', 'Kanselahin');

  // ---------- edit profile ----------
  String get editProfileLoadError =>
      _t('Could not load your profile.', 'Hindi ma-load ang iyong profile.');
  String get editProfilePhotoAccessTitle =>
      _t('Allow photo access', 'Payagan ang Access sa Larawan');
  String get editProfilePhotoAccessRationale => _t(
      'SmartSumbong needs access to your photos to set a profile '
      'picture.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'magtakda ng profile picture.');
  // Added 9 Sep 2026: camera-or-gallery choice for the avatar picker —
  // same reasoning as dispatch_order.dart's, ported to resident's
  // matching addition the same day.
  String get editProfileTakePhoto => _t('Take Photo', 'Kumuha ng Larawan');
  String get editProfileChooseFromGallery =>
      _t('Choose from Gallery', 'Pumili mula sa Gallery');
  String get editProfileCameraAccessTitle =>
      _t('Camera access', 'Access sa Camera');
  String get editProfileCameraAccessRationale => _t(
      'SmartSumbong needs camera access to set a profile picture.',
      'Kailangan ng SmartSumbong ng access sa camera para magtakda ng '
      'profile picture.');
  String get editProfileEmailInvalid => _t(
      'That email address does not look right.',
      'Mukhang mali ang email address na iyon.');
  String get editProfileChangesSavedTitle =>
      _t('Changes Saved.', 'Nai-save ang mga Pagbabago.');
  String get editProfileContinue => _t('Continue', 'Magpatuloy');
  String get editProfileEmailTaken => _t(
      'That email address is already used by another account.',
      'Ginagamit na ng ibang account ang email address na iyon.');
  String get editProfileSaveFailed => _t(
      'Could not save your profile. Please try again.',
      'Hindi ma-save ang iyong profile. Pakisubukan muli.');
  String editProfileChangeFieldTitle(String label) =>
      _t('Change your $label', 'Palitan ang iyong $label');
  String get editProfileMobilePrompt => _t(
      'Your mobile number is how you sign in, so the barangay '
      'changes it for you. Enter the new number and they will '
      'be notified.',
      'Ang iyong mobile number ang ginagamit mo para mag-sign in, kaya '
      'ang barangay ang nagpapalit nito para sa iyo. Ilagay ang bagong '
      'numero at aabisuhan sila.');
  String get editProfileNamePrompt => _t(
      'The barangay checked this name against your ID, so they '
      'change it for you. Enter the correct name and they will '
      'be notified.',
      'Sinuri ng barangay ang pangalang ito laban sa iyong ID, kaya '
      'sila ang nagpapalit nito para sa iyo. Ilagay ang tamang pangalan '
      'at aabisuhan sila.');
  String get editProfileFullNameHint =>
      _t('Your full name', 'Ang iyong buong pangalan');
  String get editProfileMobileInvalid => _t(
      'Enter a mobile number like 09171234567.',
      'Maglagay ng mobile number tulad ng 09171234567.');
  String get editProfileRequestSent => _t(
      'Your request has been sent to the barangay.',
      'Naipadala na ang iyong kahilingan sa barangay.');
  String get editProfilePasswordChanged => _t(
      'Your password has been changed.', 'Napalitan na ang iyong password.');
  String get editProfileUnsavedTitle =>
      _t('Unsaved Changes', 'Hindi Na-save na mga Pagbabago');
  String get editProfileUnsavedBody => _t(
      'If you continue without saving, these changes will be lost.',
      'Kung magpapatuloy ka nang hindi nagse-save, mawawala ang '
      'mga pagbabagong ito.');
  String get editProfileCancel => _t('Cancel', 'Kanselahin');
  String get editProfileTitle => _t('Edit Profile', 'I-edit ang Profile');
  String get editProfileNameLabel => _t('Name', 'Pangalan');
  String get editProfileNameWord => _t('name', 'pangalan');
  String get editProfileNameNote =>
      _t('The barangay changes this', 'Pinapalitan ito ng barangay');
  String get editProfileEmailLabel => _t('Email Address', 'Email Address');
  String get editProfileEmailHint =>
      _t('example@gmail.com', 'halimbawa@gmail.com');
  String get editProfileOptional => _t('(Optional)', '(Opsyonal)');
  String get editProfileAddressLabel => _t('Address', 'Address');
  String get editProfileAddressHint =>
      _t('Your address', 'Ang iyong address');
  String get editProfilePhoneLabel =>
      _t('Phone Number', 'Numero ng Telepono');
  String get editProfilePhoneWord => _t('mobile number', 'numero ng mobile');
  String get editProfilePhoneNote =>
      _t('This is how you sign in', 'Ito ang ginagamit mo para mag-sign in');
  String get editProfilePasswordLabel => _t('Password', 'Password');
  String get editProfilePasswordChange => _t('Change', 'Palitan');
  String get editProfileBack => _t('Back', 'Bumalik');
  String get editProfileSave => _t('Save', 'I-save');
  String get editProfileSendRequest =>
      _t('Send request', 'Ipadala ang kahilingan');
  String get editProfileChangePasswordTitle =>
      _t('Change password', 'Palitan ang password');
  String get editProfileNewPasswordHint =>
      _t('New password', 'Bagong password');
  String get editProfileConfirmPasswordHint =>
      _t('Confirm password', 'Kumpirmahin ang password');
  String get editProfilePasswordTooShort => _t(
      'Your password must be at least 8 characters.',
      'Dapat hindi bababa sa 8 na karakter ang iyong password.');
  String get editProfilePasswordMismatch => _t('Your passwords should match.',
      'Dapat magkatugma ang iyong mga password.');

  // ---------- duty status ----------
  String dutyStateLabel(String wire) {
    switch (wire) {
      case 'on_duty':
        return _t('On Duty', 'Nasa Tungkulin');
      case 'break':
        return _t('Break', 'Pahinga');
      case 'lunch':
        return _t('Lunch', 'Pananghalian');
      case 'offline':
        return _t('Offline', 'Naka-offline');
      default:
        return wire;
    }
  }

  // ---------- home ----------
  String homeLoadError(String detail) =>
      _t('Could not load your dashboard. ($detail)',
          'Hindi ma-load ang iyong dashboard. ($detail)');
  String get homeLoadOffline => _t(
      'Could not load your dashboard. Check your connection.',
      'Hindi ma-load ang iyong dashboard. Suriin ang iyong koneksyon.');
  String get homeNotTanod => _t(
      'This account is not registered as a barangay tanod.',
      'Ang account na ito ay hindi rehistrado bilang barangay tanod.');
  String get homeStatusUpdateFailed => _t(
      'Could not update your status. Please try again.',
      'Hindi ma-update ang iyong status. Pakisubukan muli.');
  String get homeLocationSharing =>
      _t('Sharing your location…', 'Ibinabahagi ang iyong lokasyon…');
  String get homeLocationOff => _t(
      'Location is off. You are on duty but cannot be sent nearby '
      'complaints until you turn it on.',
      'Nakapatay ang location. Nasa tungkulin ka na pero hindi ka '
      'maipapadala sa malapit na reklamo hangga\'t hindi ito naka-on.');
  String get homeLocationShared => _t(
      'Location shared. You can be sent nearby complaints.',
      'Naibahagi ang lokasyon. Maipapadala ka na sa malapit na reklamo.');
  String get homeLocationShareFailed => _t(
      'Could not share your location. Submit On Duty again to retry.',
      'Hindi naibahagi ang lokasyon. I-submit ulit ang On Duty para '
      'subukan muli.');
  String get homeWelcome => _t('Welcome!', 'Welcome!');
  String homeWelcomeName(String name) =>
      _t('Welcome, $name!', 'Welcome, $name!');
  String get homeHowAreYou =>
      _t('How are you doing today?', 'Kumusta ka ngayong araw?');
  String get homeStatusQuestion =>
      _t('What’s your status?', 'Ano ang iyong status?');
  String get homeSelectStatus =>
      _t('Select a Status', 'Pumili ng Status');
  String get homeSubmit => _t('Submit', 'I-submit');
  String get homeIncomingDispatch =>
      _t('Incoming Dispatch', 'Papasok na Dispatch');
  String get homeIncomingEmpty => _t(
      'Nothing assigned to you right now. Set yourself On Duty and '
      'share your location to be sent nearby complaints.',
      'Walang naka-assign sa iyo sa ngayon. Itakda ang iyong sarili sa '
      'On Duty at ibahagi ang iyong lokasyon para maipadala ka sa '
      'malapit na reklamo.');
  String get homeAssignedTo =>
      _t('You have been assigned to ', 'Na-assign ka sa ');
  String get homeViewDetails => _t('View Details', 'Tingnan ang Detalye');
  // Replaced 9 Sep 2026: this used to be a shallow "Alert History" — a
  // tracking ID and a timestamp, nothing a tanod actually did. Rose's
  // team flagged in the CAPSTONE G12 chat that submitting an update left
  // no trace the tanod could see anywhere in the app. This card is now
  // that trace: the same list, but each responded row carries the field
  // report text and any photo/video the tanod attached when they filed
  // it, sourced straight from what submit_field_report() and
  // dispatch_media already store.
  String get homeActivityHistory => _t('Activity History', 'Kasaysayan ng Aktibidad');
  String get homeAlertHistoryTrailing =>
      _t('in the past 7 days', 'nitong nakaraang 7 araw');
  String get homeTabAll => _t('All', 'Lahat');
  String get homeTabResponded => _t('Responded', 'Nasagot');
  String get homeTabMissed => _t('Missed', 'Nalampasan');
  String get homeAlertHistoryEmpty => _t(
      'Nothing in the past seven days.', 'Walang naganap sa nakaraang '
      'pitong araw.');
  String get homeActivityFieldReportLabel =>
      _t('Field report: ', 'Ulat sa Larangan: ');
  String get homeActivityNoText => _t(
      '(No written update was filed.)', '(Walang isinumiteng update.)');
  String get homeActivityMissedNote => _t(
      'The accept window closed with no response.',
      'Nagsara ang oras para tanggapin nang walang tugon.');

  // ---------- reports (assigned dispatch) ----------
  String reportsLoadError(String detail) =>
      _t('Could not load your dispatches. ($detail)',
          'Hindi ma-load ang iyong mga dispatch. ($detail)');
  String get reportsLoadOffline => _t(
      'Could not load your dispatches. Check your connection.',
      'Hindi ma-load ang iyong mga dispatch. Suriin ang iyong koneksyon.');
  String get reportsTitle => _t('Assigned Dispatch', 'Naka-assign na Dispatch');
  String get reportsTryAgain => _t('Try again', 'Subukan Ulit');
  String get reportsEmptyTitle =>
      _t('Nothing assigned to you.', 'Walang naka-assign sa iyo.');
  String get reportsEmptyBody => _t(
      'Tickets appear here once you accept them from Home.',
      'Lalabas dito ang mga ticket kapag tinanggap mo na ang mga ito '
      'mula sa Home.');
  String get reportsUserLabel => _t('User: ', 'User: ');
  String get reportsFilerAnonymous => _t('Anonymous', 'Anonymous');
  String get reportsDescriptionLabel =>
      _t('Description: ', 'Deskripsyon: ');
  String get reportsDeadlineLabel => _t('Deadline: ', 'Deadline: ');
  String get reportsDeadlineNotSet => _t('not set', 'hindi pa naitatakda');
  String get reportsViewMap => _t('View Map', 'Tingnan ang Mapa');
  String get reportsViewMedia =>
      _t('View Attached Media', 'Tingnan ang Kalakip na Media');
  String get reportsViewInstructions =>
      _t('View Instructions', 'Tingnan ang mga Tagubilin');
  String get reportsSubmitUpdate =>
      _t('Submit an update', 'Magsumite ng Update');

  // ---------- dispatch order ----------
  String get dispatchBarrierLabel => _t('Dispatch order', 'Dispatch order');
  String get dispatchAcceptStale => _t(
      'This ticket is no longer yours to accept. It may have timed out '
      'or been reassigned.',
      'Hindi mo na ito matatanggap. Maaaring na-timeout na ito o '
      'naibigay na sa iba.');
  String get dispatchAcceptFailed => _t(
      'Could not accept this ticket. Please try again.',
      'Hindi matanggap ang ticket na ito. Pakisubukan muli.');
  String get dispatchRerouteReasonRequired => _t(
      'A reason is required to reroute.',
      'Kailangan ng dahilan para mag-reroute.');
  String get dispatchRerouteFailed => _t(
      'Could not reroute this ticket. Please try again.',
      'Hindi na-reroute ang ticket na ito. Pakisubukan muli.');
  String get dispatchUpdateDescribeRequired => _t(
      'Please describe what was done.',
      'Pakilarawan kung ano ang nagawa.');
  String dispatchUpdateUploadFailed(String message) => _t(
      '$message Your report has not been sent yet.',
      '$message Hindi pa naipapadala ang iyong report.');
  String get dispatchUpdateSubmitFailed => _t(
      'Could not submit your report. Please try again.',
      'Hindi naipadala ang iyong report. Pakisubukan muli.');
  String get dispatchCameraAccessTitle =>
      _t('Camera access', 'Access sa Camera');
  String get dispatchCameraAccessPhotoRationale => _t(
      'SmartSumbong needs camera access to attach photo proof to this '
      'dispatch.',
      'Kailangan ng SmartSumbong ng access sa camera para maglagay ng '
      'patunay na larawan sa dispatch na ito.');
  String get dispatchCameraAccessVideoRationale => _t(
      'SmartSumbong needs camera access to attach video proof to this '
      'dispatch.',
      'Kailangan ng SmartSumbong ng access sa camera para maglagay ng '
      'patunay na video sa dispatch na ito.');
  String get dispatchCameraOpenFailed =>
      _t('Could not open the camera.', 'Hindi mabuksan ang camera.');
  // Added 9 Sep 2026: the attach-media flow used to force the camera
  // open with no way to pick an existing photo or video — flagged in the
  // CAPSTONE G12 chat. Mirrors register_screen.dart's source-choice
  // sheet on the resident side.
  String get dispatchTakePhoto => _t('Take Photo', 'Kumuha ng Larawan');
  String get dispatchChooseFromGallery =>
      _t('Choose from Gallery', 'Pumili mula sa Gallery');
  String get dispatchPhotoAccessTitle =>
      _t('Gallery access', 'Access sa Gallery');
  String get dispatchGalleryAccessPhotoRationale => _t(
      'SmartSumbong needs access to your photos to attach photo proof to '
      'this dispatch.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'maglagay ng patunay na larawan sa dispatch na ito.');
  String get dispatchGalleryAccessVideoRationale => _t(
      'SmartSumbong needs access to your photos to attach video proof to '
      'this dispatch.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'maglagay ng patunay na video sa dispatch na ito.');
  String get dispatchMediaOpenFailed => _t(
      'Could not open the camera or gallery.',
      'Hindi mabuksan ang camera o gallery.');
  String get dispatchOrderHeaderLabel =>
      _t('DISPATCH ORDER:', 'DISPATCH ORDER:');
  String dispatchSubmittedOn(String date) =>
      _t('Submitted on: $date', 'Isinumite noong: $date');
  String get dispatchBack => _t('Back', 'Bumalik');
  String get dispatchReroute => _t('Reroute', 'I-reroute');
  String get dispatchAccept => _t('Accept', 'Tanggapin');
  String get dispatchConfirm => _t('Confirm', 'Kumpirmahin');
  String get dispatchCancel => _t('Cancel', 'Kanselahin');
  String get dispatchSubmit => _t('Submit', 'I-submit');
  String get dispatchComplainantLabel =>
      _t('Complainant: ', 'Nagreklamo: ');
  String get dispatchNoLocation => _t(
      'No location on this report', 'Walang lokasyon sa report na ito');
  String get dispatchNoMedia => _t(
      'The resident attached no photos.',
      'Walang inilakip na larawan ang residente.');
  String get dispatchAdminDirectivesTitle =>
      _t('Admin Directives:', 'Direktiba ng Admin:');
  String get dispatchNoDirectives => _t(
      'The admin left no directives on this ticket. Use your judgement '
      'and record what you find.',
      'Walang iniwang direktiba ang admin sa ticket na ito. Gamitin ang '
      'iyong sariling pagpapasya at itala ang iyong makikita.');
  String get dispatchResponderNote => _t(
      'Note for Responder: Proceed with caution. Your safety and the '
      'safety of the people at the scene come before the deadline.',
      'Paalala sa Responder: Mag-ingat sa pagpapatuloy. Ang iyong '
      'kaligtasan at ang kaligtasan ng mga tao sa eksena ay mas '
      'mahalaga kaysa sa deadline.');
  String get dispatchRerouteConfirmTitle => _t(
      'Are you sure you want to reroute this assigned complaint to '
      'another Tanod?',
      'Sigurado ka bang gusto mong i-reroute ang naka-assign na reklamong '
      'ito sa ibang Tanod?');
  String get dispatchRerouteConfirmBody => _t(
      'This action cannot be undone and will be logged.',
      'Hindi na maibabalik ang aksyong ito at ito ay itatala.');
  String get dispatchRerouteReasonLabel =>
      _t('Please provide your reason', 'Pakilagay ang iyong dahilan');
  String get dispatchInputHint => _t('Input here...', 'Ilagay dito...');
  String dispatchAcceptedTitle(String trackingId, String subject) => _t(
      '$trackingId - $subject has been accepted.',
      'Tinanggap na ang $trackingId - $subject.');
  String get dispatchAcceptedBody => _t(
      'Kindly ensure that the necessary actions are taken in a timely '
      'manner.',
      'Pakisiguro na naisasagawa ang mga kinakailangang aksyon sa '
      'nararapat na oras.');
  String get dispatchProvideReportLabel =>
      _t('Please provide a report', 'Pakilagay ang report');
  String get dispatchPhotoEvidenceLabel => _t(
      'Submit a photo evidence of the complaint response',
      'Magsumite ng patunay na larawan ng pagtugon sa reklamo');
  String get dispatchAttachMedia => _t('Attach Media', 'Maglakip ng Media');
  String get dispatchMaxPhotoSize => _t('(Max. 10 MB)', '(Max. 10 MB)');
  String get dispatchVideoAttached =>
      _t('Video attached', 'May nakalakip na video');
  String get dispatchAttachVideo => _t('Attach Video', 'Maglakip ng Video');
  String get dispatchMaxVideoSize => _t('(Max. 25 MB)', '(Max. 25 MB)');
  String dispatchSubmittedTitle(String trackingId) => _t(
      '$trackingId\nReport has been submitted.',
      '$trackingId\nNaipadala na ang report.');

  // ---------- extra administrative services ----------
  // A password-gated menu, per the barangay's own instruction: retiring
  // is reachable only from inside here, and getting in here at all takes
  // a password of its own — separate from the second password Retirement
  // asks for again before it actually sends anything. See
  // extra_admin_services_screen.dart.
  String get extraAdminServicesTitle =>
      _t('Extra Administrative Services', 'Karagdagang Serbisyong Administratibo');
  String get extraAdminServicesBack => _t('Back', 'Bumalik');
  String get extraAdminServicesLockedTitle =>
      _t('Enter your password to continue', 'Ilagay ang password para magpatuloy');
  String get extraAdminServicesLockedBody => _t(
      'This section is for service actions you will rarely need — like '
      'ending your service with the barangay. Confirm it is you before '
      'going in.',
      'Ang bahaging ito ay para sa mga aksyong bihira mong kakailanganin '
      '— tulad ng pagtatapos ng iyong paglilingkod sa barangay. '
      'Kumpirmahin muna na ikaw talaga bago magpatuloy.');
  String get extraAdminServicesPasswordLabel => _t('Password', 'Password');
  String get extraAdminServicesPasswordHint =>
      _t('Enter your password', 'Ilagay ang iyong password');
  String get extraAdminServicesUnlock => _t('Unlock', 'I-unlock');
  String get extraAdminServicesWrongPassword => _t(
      'That password is not right.', 'Mali ang password na iyon.');
  String get extraAdminServicesCheckFailed => _t(
      'Could not check your password. Check your connection and try '
      'again.',
      'Hindi nasuri ang iyong password. Suriin ang koneksyon at subukan '
      'muli.');
  String get extraAdminServicesRetirementLabel =>
      _t('Retirement', 'Pagreretiro');
  String get extraAdminServicesRetirementSubtitle => _t(
      'End your service with the barangay',
      'Tapusin ang iyong paglilingkod sa barangay');
  String get extraAdminServicesRetirementPending =>
      _t('Awaiting admin approval', 'Hinihintay ang pag-apruba ng admin');

  // ---------- retirement ----------
  // A tanod cannot delete their own account (unlike a resident — see
  // 0045). This is the only door out, and it opens onto an admin's desk,
  // not straight into effect — see 0052's request_retirement() /
  // finalize_retirement() and retirement_screen.dart.
  String get retirementTitle => _t('Retirement', 'Pagreretiro');
  String get retirementBack => _t('Back', 'Bumalik');
  String get retirementLoadFailed => _t(
      'Could not check your retirement status. Check your connection '
      'and try again.',
      'Hindi nasuri ang status ng iyong pagreretiro. Suriin ang '
      'koneksyon at subukan muli.');
  String get retirementIntroTitle =>
      _t('Requesting retirement', 'Paghiling ng Pagreretiro');
  String get retirementIntroBody => _t(
      'This sends a formal request to the barangay to end your service '
      'as a tanod, whether you have reached your term or simply wish to '
      'stop. It is not immediate: an administrator must review and '
      'approve it before it takes effect. Your name, contact details, '
      'and full service history stay on file either way — retiring does '
      'not delete your account, only your ability to be dispatched or '
      'to sign in once approved.',
      'Ipinapadala nito ang pormal na kahilingan sa barangay na tapusin '
      'ang iyong paglilingkod bilang tanod, sakaling naabot mo na ang '
      'iyong taning o gusto mo lang huminto. Hindi ito agad-agarang '
      'nagkakabisa: kailangan munang suriin at aprubahan ito ng isang '
      'administrator bago ito magkabisa. Mananatili pa rin ang iyong '
      'pangalan, contact details, at buong service history — ang '
      'pagreretiro ay hindi nagbubura ng iyong account, tanging ang '
      'iyong kakayahang ma-dispatch o mag-sign in kapag naaprubahan na.');
  String get retirementRequestButton =>
      _t('Request retirement', 'Humiling ng Pagreretiro');
  String get retirementPendingTitle =>
      _t('Waiting on the barangay', 'Hinihintay ang Barangay');
  String retirementPendingBody(String date) => _t(
      'You asked to retire on $date. An administrator has not decided '
      'yet — you can still sign in and be dispatched until they do.',
      'Humiling ka ng pagreretiro noong $date. Hindi pa ito napagdedesisyunan '
      'ng administrator — maaari ka pa ring mag-sign in at ma-dispatch '
      'hanggang sa desisyunan nila.');
  String get retirementDeniedTitle =>
      _t('Your last request was not approved', 'Hindi Naaprubahan ang Huli Mong Kahilingan');
  String retirementDeniedBody(String reason) => _t(
      'Reason given: $reason\n\nYou may send another request below.',
      'Ibinigay na dahilan: $reason\n\nMaaari kang magpadala ng '
      'panibagong kahilingan sa ibaba.');
  String get retirementConfirmTitle =>
      _t('Confirm with your password', 'Kumpirmahin gamit ang Password');
  String get retirementConfirmBody => _t(
      'Type your password again to send this request. This is the last '
      'step before it reaches the barangay.',
      'I-type ulit ang iyong password para ipadala ang kahilingang ito. '
      'Ito ang huling hakbang bago ito maabot ng barangay.');
  String get retirementPasswordLabel => _t('Password', 'Password');
  String get retirementPasswordHint =>
      _t('Enter your password', 'Ilagay ang iyong password');
  String get retirementConfirmButton =>
      _t('Confirm retirement request', 'Kumpirmahin ang Kahilingan sa Pagreretiro');
  String get retirementCancel => _t('Cancel', 'Kanselahin');
  String get retirementWrongPassword => _t(
      'That password is not right. Nothing was sent.',
      'Mali ang password na iyon. Walang naipadala.');
  String get retirementConfirmCheckFailed => _t(
      'Could not check your password. Check your connection and try '
      'again.',
      'Hindi nasuri ang iyong password. Suriin ang koneksyon at subukan '
      'muli.');
  String get retirementSubmitFailed => _t(
      'Could not send your request. Please try again.',
      'Hindi naipadala ang iyong kahilingan. Pakisubukan muli.');
  String get retirementSuccessTitle =>
      _t('Request sent', 'Naipadala ang Kahilingan');
  String get retirementSuccessBody => _t(
      'The barangay has been notified. You will be told once an '
      'administrator decides — until then, nothing about your account '
      'has changed.',
      'Naabisuhan na ang barangay. Ipapaalam sa iyo kapag nagdesisyon '
      'na ang isang administrator — hanggang dito, walang nagbago sa '
      'iyong account.');
  String get retirementSuccessContinue => _t('Done', 'Tapos Na');

  // ---------- terms & privacy (service personnel) ----------
  // Rose asked for a version specific to service personnel rather than
  // the resident app's consumer-facing text — duty-time location and
  // dispatch-record retention have no equivalent there. Drafted for
  // barangay review; see the 2026-09-08 retirement/terms project note
  // for the reasoning behind each section.
  String get termsPrivacyTitle => _t('Terms & Privacy', 'Mga Tuntunin at Privacy');
  String get termsPrivacyBack => _t('Back', 'Bumalik');
  String get termsPrivacySubtitle => _t(
      'For SmartSumbong Tanod — service personnel of Barangay 183',
      'Para sa SmartSumbong Tanod — service personnel ng Barangay 183');

  List<(String heading, String body)> get termsPrivacySections => [
        (
          _t('1. This app is for appointed service personnel',
              '1. Ang app na ito ay para sa mga hinirang na service personnel'),
          _t(
              'This is not a consumer account. It is issued to you as a '
              'tanod appointed by Barangay 183, and these terms cover '
              'things the resident version of this app does not — your '
              'location while on duty, your dispatch records, and how '
              'your service with the barangay ends.',
              'Hindi ito isang consumer account. Ibinibigay ito sa iyo '
              'bilang tanod na hinirang ng Barangay 183, at sinasaklaw ng '
              'mga tuntuning ito ang mga bagay na wala sa resident '
              'version ng app na ito — ang iyong lokasyon habang naka-duty, '
              'ang iyong mga dispatch record, at kung paano magtatapos '
              'ang iyong paglilingkod sa barangay.'),
        ),
        (
          _t('2. Information the barangay keeps on file',
              '2. Impormasyong itinatago ng barangay'),
          _t(
              'Your full name, mobile number, email address if you gave '
              'one, and your submitted Barangay ID or barangay '
              'appointment document are kept as part of your appointment '
              'record for as long as you serve, and afterward as part of '
              'the barangay’s official record of who served.',
              'Ang iyong buong pangalan, mobile number, email address '
              'kung nagbigay ka, at ang isinumite mong Barangay ID o '
              'dokumento ng appointment ay itinatago bilang bahagi ng '
              'iyong appointment record habang naglilingkod ka, at '
              'pagkatapos nito bilang bahagi ng opisyal na record ng '
              'barangay kung sino ang naglingkod.'),
        ),
        (
          _t('3. Your location while on duty',
              '3. Ang iyong lokasyon habang naka-duty'),
          _t(
              'Your device shares your location with the barangay only '
              'while your duty status is On Duty, and only so nearby '
              'complaints can be routed to you. It is not collected while '
              'you are Off Duty, on Break, or at Lunch. Residents never '
              'see your exact location — only that a tanod has been '
              'assigned.',
              'Ibinabahagi ng iyong device ang iyong lokasyon sa barangay '
              'lamang kapag ang iyong duty status ay On Duty, at para '
              'lamang maipadala sa iyo ang mga malapit na reklamo. Hindi '
              'ito kinokolekta kapag ikaw ay Off Duty, nasa Break, o '
              'Lunch. Hindi kailanman nakikita ng mga residente ang iyong '
              'eksaktong lokasyon — malalaman lang nila na may na-assign '
              'na tanod.'),
        ),
        (
          _t('4. Dispatch and incident records',
              '4. Mga Dispatch at Incident Record'),
          _t(
              'Photos, videos, and reports you submit while responding to '
              'a dispatch become part of the barangay’s official case '
              'record. They are kept for accountability and cannot be '
              'deleted from the app, by you or by the resident who filed '
              'the complaint.',
              'Ang mga larawan, video, at report na isinusumite mo habang '
              'tumutugon sa isang dispatch ay nagiging bahagi ng opisyal '
              'na case record ng barangay. Itinatago ang mga ito para sa '
              'accountability at hindi maaaring burahin sa app, kahit ng '
              'iyong sarili o ng residenteng nagsampa ng reklamo.'),
        ),
        (
          _t('5. Ending your service: retirement, not deletion',
              '5. Pagtatapos ng Iyong Paglilingkod: Pagreretiro, Hindi Pagbura'),
          _t(
              'Unlike a resident, a tanod cannot delete their own account. '
              'The only way to end your service through the app is to '
              'request retirement from Extra Administrative Services, '
              'which a barangay administrator must approve. Approved '
              'retirement stops your account from signing in or being '
              'dispatched, but keeps your name, contact information, and '
              'full service history on file as an employment record — it '
              'is not erased.',
              'Hindi tulad ng isang residente, hindi maaaring burahin ng '
              'tanod ang sarili niyang account. Ang tanging paraan para '
              'tapusin ang iyong paglilingkod sa pamamagitan ng app ay '
              'ang humiling ng pagreretiro mula sa Extra Administrative '
              'Services, na dapat aprubahan ng isang administrator ng '
              'barangay. Ang inaprubahang pagreretiro ay hihinto sa '
              'iyong account na mag-sign in o ma-dispatch, ngunit '
              'mananatili ang iyong pangalan, contact information, at '
              'buong service history bilang employment record — hindi ito '
              'binubura.'),
        ),
        (
          _t('6. Who can see this information',
              '6. Sino ang Maaaring Makakita ng Impormasyong Ito'),
          _t(
              'Only barangay administrators can see your account and '
              'service records. Nothing here is sold or shared with '
              'anyone outside the barangay.',
              'Tanging ang mga administrator ng barangay lamang ang '
              'maaaring makakita ng iyong account at service records. '
              'Walang ibinebenta o ibinabahagi rito sa sinumang labas sa '
              'barangay.'),
        ),
        (
          _t('7. Keeping your account secure',
              '7. Pag-iingat sa Seguridad ng Iyong Account'),
          _t(
              'Do not share your password or leave your phone unlocked '
              'for others. Extra Administrative Services and confirming a '
              'retirement request both ask for your password again on '
              'purpose — those actions need more proof than an already-'
              'unlocked phone.',
              'Huwag ibahagi ang iyong password o iwanang naka-unlock ang '
              'iyong telepono para sa iba. Sinasadyang hinihiling muli ng '
              'Extra Administrative Services at ng pagkumpirma ng '
              'kahilingan sa pagreretiro ang iyong password — kailangan '
              'ng mga aksyong ito ng higit pang patunay kaysa sa isang '
              'naka-unlock na telepono.'),
        ),
        (
          _t('8. Changes to these terms', '8. Mga Pagbabago sa Tuntuning Ito'),
          _t(
              'The barangay may update these terms as the app changes. '
              'Continuing to use the app after an update means you '
              'accept the current version.',
              'Maaaring i-update ng barangay ang mga tuntuning ito habang '
              'nagbabago ang app. Ang patuloy na paggamit ng app pagkatapos '
              'ng update ay nangangahulugan na tinatanggap mo ang '
              'kasalukuyang bersyon.'),
        ),
        (
          _t('9. Questions', '9. Mga Katanungan'),
          _t(
              'Bring questions about this account or these terms to the '
              'Barangay 183 hall.',
              'Dalhin ang mga katanungan tungkol sa account na ito o sa '
              'mga tuntuning ito sa Barangay 183 hall.'),
        ),
      ];
}
