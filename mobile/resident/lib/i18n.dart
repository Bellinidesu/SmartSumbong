// SmartSumbong — resident-app language switching.
//
// Was a stub: `languages_screen.dart` recorded the choice but only
// English ever rendered, with a snackbar admitting as much when Filipino
// was picked. Rose and Group 5's QA exchange (26 Aug 2026) both flagged
// it, and the team asked for the real thing rather than another
// deferral note.
//
// WHY A HAND-WRITTEN LOOKUP, NOT flutter_localizations + ARB + gen-l10n.
// The standard path code-generates an `AppLocalizations` class from
// .arb files at build time. That generation step needs the Flutter
// toolchain to run, which this session cannot do — there is no way to
// verify generated bindings compile from here, and shipping a change
// that only works if a teammate remembers to run `flutter gen-l10n`
// first is exactly the kind of silent trap this project has been
// avoiding elsewhere (see HANDOVER.md's note on rebuilding from a stale
// commit). A plain Dart class with getters needs no build step, compiles
// with whatever's already there, and is just as easy to extend.
//
// HOW TO ADD A SCREEN TO THIS. Add its strings as getters on [Strings]
// below, grouped under a `// ---------- screen name ----------` comment
// the same way the existing groups are. Read them in the screen via
// `context.s.whateverKey` (the `AppLocaleContext` extension at the
// bottom). No screen should call [Strings] directly — always through
// the extension, so it always reflects the live locale.
//
// Every getter below was written to match the EXACT English copy that
// was already live in each of the six in-scope screens, so wiring a
// screen up to this file never changes what an English-reading resident
// sees — only what a Filipino-reading one does.

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

/// Every user-facing string this pass translated, as paired getters.
/// English first, Filipino second, in `_t()` — reading the pair together
/// is what a translation review is for, so they are kept side by side
/// rather than in two separate tables that could drift apart silently.
///
/// SCOPE OF THIS PASS (26 Aug 2026): onboarding, role picker, login,
/// languages, home, and settings. `report_category_screen.dart`,
/// `report_details_screen.dart`, `reports_screen.dart` and the rest of
/// the resident app are still English-only — sized and flagged as
/// follow-up work in the QA doc rather than rushed into this pass at the
/// same time as the QA bug fixes.
///
/// A native Filipino speaker on the team should read these before the
/// defense — they're a good-faith translation, not a reviewed one.
class Strings {
  const Strings(this.locale);
  final AppLocale locale;

  String _t(String en, String fil) => locale == AppLocale.fil ? fil : en;

  // ---------- onboarding ----------
  String get onboardTitle1 =>
      _t('Welcome to SmartSumbong!', 'Maligayang pagdating sa SmartSumbong!');
  String get onboardBody1 => _t(
      'SmartSumbong is your trusted platform to voice your concerns and '
      'make a difference in your barangay.',
      'Ang SmartSumbong ang iyong pinagkakatiwalaang plataporma para '
      'iparinig ang iyong mga alalahanin at gumawa ng pagbabago sa iyong '
      'barangay.');
  String get onboardTitle2 => _t('Voice out. Be heard.', 'Magsalita. Marinig.');
  String get onboardBody2 => _t(
      'Your voice matters—stand up, be heard, and shape the future of '
      'your community.',
      'Mahalaga ang iyong tinig—tumindig, magpahayag, at hubugin ang '
      'kinabukasan ng iyong komunidad.');
  String get onboardTitle3 => _t('Stay updated.', 'Manatiling updated.');
  String get onboardBody3 => _t(
      'Track your reports and see real change happening in your '
      'community.',
      'Subaybayan ang iyong mga ulat at makita ang tunay na pagbabago sa '
      'iyong komunidad.');
  String get onboardTitle4 => _t('Get help instantly.', 'Kumuha ng tulong agad.');
  String get onboardBody4 => _t(
      'Just tap to connect with responders and take action when it '
      'matters most.',
      'I-tap lamang para makonekta sa mga responder at kumilos kapag '
      'pinaka-kailangan ito.');
  String get onboardSkip => _t('Skip', 'Laktawan');
  String get onboardNext => _t('Next', 'Susunod');
  String get onboardStart => _t('Start', 'Simulan');

  // ---------- role picker ----------
  String get roleTitle => _t('What’s your role?', 'Ano ang iyong tungkulin?');
  String get roleResident => _t('I’m a Resident', 'Ako ay Residente');
  String get roleTanod => _t('I’m a Tanod', 'Ako ay Tanod');

  // ---------- login ----------
  String get loginProfileHeading => _t('Resident Profile', 'Profile ng Residente');
  String get loginPhoneLabel => _t('Phone Number', 'Numero ng Telepono');
  String get loginPhoneHint => _t('Enter phone number', 'Ilagay ang numero ng telepono');
  String get loginPasswordLabel => _t('Password', 'Password');
  String get loginPasswordHint => _t('Enter password', 'Ilagay ang password');
  String get loginRememberMe => _t('Remember me', 'Tandaan ako');
  String get loginForgotPassword => _t('Forgot password?', 'Nakalimutan ang password?');
  String get loginButton => _t('Log In', 'Mag-log In');
  String get loginBackToRoles => _t('Back to Roles', 'Bumalik sa mga Tungkulin');
  String get loginNoAccountPrefix =>
      _t('Don’t have an account yet? ', 'Wala ka pang account? ');
  String get loginSignUp => _t('Sign Up', 'Mag-sign Up');
  String get loginPhoneError =>
      _t('Enter a number like 09171234567.', 'Maglagay ng numero tulad ng 09171234567.');
  String get loginPasswordEmptyError =>
      _t('Enter your password.', 'Ilagay ang iyong password.');
  String get loginOfflineError => _t(
      'Could not reach the barangay’s system. Check your connection.',
      'Hindi ma-abot ang sistema ng barangay. Suriin ang iyong koneksyon.');
  String get loginForgotDialogTitle => _t('Forgot password', 'Nakalimutan ang password');
  String get loginForgotDialogBody => _t(
      'Bring a valid ID to the barangay hall and ask the staff to reset '
      'your password. They will give you a temporary one, and the app '
      'will ask you to choose your own when you sign in.',
      'Magdala ng balidong ID sa barangay hall at hilingin sa staff na '
      'i-reset ang iyong password. Bibigyan ka nila ng pansamantalang '
      'password, at hihilingin sa iyo ng app na pumili ng sarili mong '
      'password kapag nag-log in ka.');
  String get loginDialogOk => _t('OK', 'OK');
  String loginLockedMessage(int minutes) {
    final unit = _t(
      minutes == 1 ? 'minute' : 'minutes',
      'minuto',
    );
    return _t(
      'Too many failed attempts. Try again in $minutes $unit.',
      'Sobra na ang maling pagtatangka. Subukan ulit pagkalipas ng '
      '$minutes $unit.',
    );
  }

  // ---------- languages ----------
  String get languagesTitle => _t('Select Language', 'Pumili ng Wika');
  String get languagesFilipino => _t('Filipino / Tagalog', 'Filipino / Tagalog');
  String get languagesEnglish => _t('English', 'Ingles');
  String get languagesBack => _t('Back', 'Bumalik');
  String get languagesChangedToFilipino => _t(
      'The app is now in Filipino.', 'Nasa Filipino na ngayon ang app.');
  String get languagesChangedToEnglish => _t(
      'The app is now in English.', 'Nasa Ingles na ngayon ang app.');

  // ---------- home ----------
  String get homeWelcomeGeneric => _t('Welcome!', 'Maligayang pagdating!');
  String homeWelcomeNamed(String name) =>
      _t('Welcome, $name!', 'Maligayang pagdating, $name!');
  String get homeSubtitle =>
      _t('How are you doing today?', 'Kumusta ka ngayong araw?');
  String get homeEmergencyTitle =>
      _t('Need urgent and immediate help?', 'Kailangan ng agarang tulong?');
  String get homeEmergencyBody => _t(
      'You can view and call the emergency services directly from our '
      'app.',
      'Maaari mong tingnan at tawagan ang mga emergency service '
      'direkta mula sa aming app.');
  String get homeEmergencyLabel => _t('Go to Emergency', 'Pumunta sa Emergency');
  String get homeReportTitle =>
      _t('Help us improve our barangay', 'Tulungan kaming pagbutihin ang barangay');
  String get homeReportBody => _t(
      'Want to report a problem in your area? Submit a report so we can '
      'fix the issue.',
      'Gusto mo bang mag-ulat ng problema sa inyong lugar? Magsumite ng '
      'ulat para maayos namin ito.');
  String get homeReportIssue => _t('Report an issue', 'Mag-ulat ng isyu');
  String get homeViewReports => _t('View reports', 'Tingnan ang mga ulat');
  String get homeMapTitle => _t('View map', 'Tingnan ang mapa');
  String get homeMapBody => _t(
      'Get a view of Barangay 183, Pasay City and see your reports '
      'pinned on the map.',
      'Tingnan ang Barangay 183, Pasay City at makita ang iyong mga '
      'ulat na naka-pin sa mapa.');
  String get homeViewMap => _t('View map', 'Tingnan ang mapa');

  // ---------- settings ----------
  String get settingsTitle => _t('Settings', 'Mga Setting');
  String get settingsPersonalInfo =>
      _t('Personal Information', 'Personal na Impormasyon');
  String get settingsEditProfile => _t('Edit Profile', 'I-edit ang Profile');
  String get settingsLanguages => _t('Languages', 'Mga Wika');
  String get settingsFacebook => _t('Facebook', 'Facebook');
  String get settingsFacebookError => _t(
      'Could not open the barangay page.',
      'Hindi mabuksan ang page ng barangay.');
  String get settingsLogOut => _t('Log Out', 'Mag-log Out');
  String get settingsLogOutConfirmBody => _t(
      'Are you sure you want to log out?', 'Sigurado ka bang mag-log out?');
  String get settingsCancel => _t('Cancel', 'Kanselahin');
}
