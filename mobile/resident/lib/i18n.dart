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
  String get settingsLogOut => _t('Log Out', 'Mag-log Out');
  String get settingsLogOutConfirmBody => _t(
      'Are you sure you want to log out?', 'Sigurado ka bang mag-log out?');
  String get settingsCancel => _t('Cancel', 'Kanselahin');

  // ---------- shared: month names for date formatting ----------
  // Used by every screen below that formats a DateTime for display
  // (reports, report view, notifications, verification pending) so a
  // date reads in the same language as the rest of the screen around it.
  static const _monthsFullEn = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  static const _monthsFullFil = [
    'Enero', 'Pebrero', 'Marso', 'Abril', 'Mayo', 'Hunyo',
    'Hulyo', 'Agosto', 'Setyembre', 'Oktubre', 'Nobyembre', 'Disyembre',
  ];
  static const _monthsAbbrEn = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const _monthsAbbrFil = [
    'Ene', 'Peb', 'Mar', 'Abr', 'May', 'Hun',
    'Hul', 'Ago', 'Set', 'Okt', 'Nob', 'Dis',
  ];
  String monthFull(int month) =>
      _t(_monthsFullEn[month - 1], _monthsFullFil[month - 1]);
  String monthAbbr(int month) =>
      _t(_monthsAbbrEn[month - 1], _monthsAbbrFil[month - 1]);

  // ---------- report category (submit report, step 1) ----------
  String get reportCategoryHeading => _t(
      'Which category most accurately reflects the issue?',
      'Aling kategorya ang pinakaangkop sa isyu?');
  String get reportCategorySubtitle =>
      _t('Select from the list below.', 'Pumili mula sa listahan sa ibaba.');
  String get reportCategoryNote => _t(
      '*Note: We do not interfere with the official procedures, hearings, '
      'mediation, and settlement processes. If the case is severe, it will '
      'be escalated to proper authorities.',
      '*Paalala: Hindi kami nakikialam sa mga opisyal na proseso, pagdinig, '
      'mediation, at settlement. Kung malubha ang kaso, ito ay iaakyat sa '
      'tamang awtoridad.');
  String get reportCategoryBack => _t('Back', 'Bumalik');
  String get reportCategoryOthersHeading => _t(
      'If the issue was not mentioned above:',
      'Kung hindi nabanggit sa itaas ang isyu:');
  String get reportCategoryOthers => _t('Others', 'Iba pa');

  // ---------- report details (submit report, step 2) ----------
  String reportDetailsPhotoLimit(int max) => _t(
      'You can attach up to $max photos.',
      'Maaari kang maglagay ng hanggang $max na larawan.');
  String get reportDetailsPhotoAccessTitle =>
      _t('Photo access', 'Access sa Larawan');
  String get reportDetailsPhotoAccessBody => _t(
      'SmartSumbong needs access to your photos to attach evidence to '
      'this report.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'maidagdag ang ebidensya sa ulat na ito.');
  String get reportDetailsVideoAccessTitle =>
      _t('Photo and video access', 'Access sa Larawan at Video');
  String get reportDetailsVideoAccessBody => _t(
      'SmartSumbong needs access to your videos to attach evidence to '
      'this report.',
      'Kailangan ng SmartSumbong ng access sa iyong mga video para '
      'maidagdag ang ebidensya sa ulat na ito.');
  String get reportDetailsDescriptionValidation => _t(
      'Please describe the issue in a little more detail.',
      'Pakidetalye pa nang kaunti ang paglalarawan ng isyu.');
  String get reportDetailsAckValidation => _t(
      'Please confirm the information is accurate.',
      'Pakikumpirma na tama ang impormasyon.');
  String get reportDetailsAddressNotFound => _t(
      'Could not find that address. Try adding a landmark or street name.',
      'Hindi mahanap ang address na iyon. Subukang magdagdag ng landmark '
      'o pangalan ng kalye.');
  String get reportDetailsAddressLookupFailed => _t(
      'Could not look up that address right now. You can still drag the '
      'map.',
      'Hindi kayang hanapin ang address na iyon sa ngayon. Maaari mo '
      'pa ring i-drag ang mapa.');
  String get reportDetailsTooLarge => _t(
      'Your photos and video are too large altogether. Remove one and '
      'try again.',
      'Sobrang laki ng kabuuang laki ng iyong mga larawan at video. '
      'Mag-alis ng isa at subukan ulit.');
  String get reportDetailsPhotosCorrupt => _t(
      'Your photos could not be attached. Please retake them.',
      'Hindi ma-attach ang iyong mga larawan. Paki-kuha ulit ang mga ito.');
  String get reportDetailsAccountNotAllowed => _t(
      'Your account is not able to file reports yet. Please check with '
      'the barangay.',
      'Hindi pa maaaring mag-file ng ulat ang iyong account. Pakitanong '
      'sa barangay.');
  String get reportDetailsSubmitFailed => _t(
      'Could not submit your report. Please try again.',
      'Hindi maisumite ang iyong ulat. Subukan ulit.');
  String reportDetailsSubmitFailedWithError(String e) => _t(
      'Could not submit your report. ($e)',
      'Hindi maisumite ang iyong ulat. ($e)');
  String get reportDetailsCompleteBelow =>
      _t('Complete the details below.', 'Kumpletuhin ang mga detalye sa ibaba.');
  String get reportDetailsStep1 =>
      _t('Choose location', 'Piliin ang lokasyon');
  String get reportDetailsStep2 =>
      _t('Describe what happened', 'Ilarawan ang nangyari');
  String get reportDetailsStep3 =>
      _t('Attach your photo', 'I-attach ang iyong larawan');
  String get reportDetailsAnonymousQuestion => _t(
      'Would you like to remain anonymous when reporting this incident?',
      'Gusto mo bang manatiling anonymous sa pag-uulat ng insidenteng ito?');
  String get reportDetailsHiddenNote => _t(
      'Your name will be hidden from public records. The barangay can '
      'still see it.',
      'Itatago ang iyong pangalan mula sa pampublikong rekord. Makikita '
      'pa rin ito ng barangay.');
  String get reportDetailsShownNote => _t(
      'Your name will be shown with this report.',
      'Makikita ang iyong pangalan kasama ang ulat na ito.');
  String get reportDetailsBack => _t('Back', 'Bumalik');
  String get reportDetailsSubmit => _t('Submit', 'Isumite');
  String reportDetailsStepLabel(int number, String text) => '$number.  $text';
  String get reportDetailsFindingLocation =>
      _t('Finding your location…', 'Hinahanap ang iyong lokasyon…');
  String get reportDetailsLocationOffNote => _t(
      'Location is off, so the map is showing the barangay centre. Drag '
      'the map to put the pin where the issue is.',
      'Naka-off ang lokasyon, kaya ang sentro ng barangay ang '
      'ipinapakita sa mapa. I-drag ang mapa para ilagay ang pin kung '
      'saan ang isyu.');
  String get reportDetailsEnableLocation =>
      _t('Enable Location', 'I-enable ang Lokasyon');
  String reportDetailsAccuracyNote(int metres) => _t(
      'Accurate to about $metres m. Drag the map if the pin is not in '
      'the right place.',
      'Tumpak sa humigit-kumulang $metres m. I-drag ang mapa kung hindi '
      'tama ang lagay ng pin.');
  String get reportDetailsPinPlacedNote => _t(
      'Pin placed by hand. Drag the map to adjust.',
      'Manwal na inilagay ang pin. I-drag ang mapa para ayusin.');
  String get reportDetailsManualAddressLabel => _t(
      'Or manually input your address', 'O manu-manong ilagay ang iyong address');
  String get reportDetailsManualAddressHint => _t(
      'e.g. 123 Sampaguita St., Purok 3', 'hal. 123 Sampaguita St., Purok 3');
  String get reportDetailsDescribeHint => _t(
      'Describe the issue in detail.', 'Ilarawan nang detalyado ang isyu.');
  String reportDetailsCounter(int length, int max) => '$length/$max';
  String get reportDetailsAttachMedia =>
      _t('Attach Media', 'Mag-attach ng Media');
  String get reportDetailsMaxPhotoSize => _t('(Max: 10 MB)', '(Max: 10 MB)');
  String get reportDetailsVideoAttachedNote => _t(
      'A video is attached to this report.',
      'May naka-attach na video sa ulat na ito.');
  String get reportDetailsAttachVideoOptional => _t(
      'Attach a short video (optional)', 'Mag-attach ng maikling video (opsyonal)');
  String get reportDetailsMaxVideoSize =>
      _t('(Max: 25 MB, about 30 seconds)', '(Max: 25 MB, humigit 30 segundo)');
  String get reportDetailsAcknowledgement => _t(
      'I acknowledge that the information I am submitting is, to the '
      'best of my knowledge, accurate and complete. I understand that '
      'this information will be processed for the purpose of '
      'investigating and addressing my report.',
      'Kinikilala ko na ang impormasyong isinusumite ko ay, sa abot ng '
      'aking kaalaman, tama at kumpleto. Nauunawaan ko na ang '
      'impormasyong ito ay iproproseso para sa layunin ng pagsisiyasat '
      'at pagtugon sa aking ulat.');
  // Draft save/restore, added 29 Aug 2026 — a half-filled report used to
  // vanish if the app was killed or the connection dropped mid-fill.
  String get reportDetailsDraftRestored => _t(
      'Restored your unfinished report.',
      'Naibalik ang hindi mo pa natatapos na ulat.');
  String get reportDetailsDraftDiscard => _t('Discard', 'Itapon');

  // ---------- reports (view your reports, cancel, reopen) ----------
  /// Shared by ReportStatus.wire everywhere its label is shown to the
  /// resident — several internal states collapse into one label, same
  /// as the English original.
  String reportStatusLabel(String wire) {
    switch (wire) {
      case 'pending_review':
      case 'validated':
        return _t('Under Review', 'Nirerepaso');
      case 'assigned':
      case 'in_progress':
      case 'offline_investigation':
        return _t('In Progress', 'Isinasagawa');
      case 'resolved':
      case 'closed':
      case 'archived':
        return _t('Completed', 'Nakumpleto');
      case 'rejected':
        return _t('Rejected', 'Tinanggihan');
      case 'cancelled':
        return _t('Cancelled', 'Kinansela');
      default:
        return _t('Under Review', 'Nirerepaso');
    }
  }

  /// Keyed by ReportFilter's own enum `.name` (all/underReview/inProgress/
  /// rejected/cancelled/completed), so this file doesn't need to import
  /// that enum to translate its dropdown.
  String reportFilterLabel(String name) {
    switch (name) {
      case 'all':
        return _t('All', 'Lahat');
      case 'underReview':
        return _t('Under Review', 'Nirerepaso');
      case 'inProgress':
        return _t('In Progress', 'Isinasagawa');
      case 'rejected':
        return _t('Rejected', 'Tinanggihan');
      case 'cancelled':
        return _t('Cancelled', 'Kinansela');
      case 'completed':
        return _t('Completed', 'Nakumpleto');
      default:
        return name;
    }
  }

  String get reportsLoadError => _t(
      'Could not load your reports. Pull to retry.',
      'Hindi ma-load ang iyong mga ulat. I-pull para subukan ulit.');
  String get reportsCancelConfirmTitle =>
      _t('Confirm to cancel?', 'Kumpirmahin ang pagkansela?');
  String get reportsCancelConfirmBody => _t(
      'Once you cancel, the case can’t be opened again.',
      'Kapag kinansela mo, hindi na mabubuksan ulit ang kaso.');
  String get reportsDialogBack => _t('Back', 'Bumalik');
  String get reportsConfirm => _t('Confirm', 'Kumpirmahin');
  String get reportsCancelledTitle =>
      _t('Report has been cancelled.', 'Nakansela na ang ulat.');
  String get reportsRequestSent => _t(
      'Your request has been sent to the barangay.',
      'Naipadala na ang iyong kahilingan sa barangay.');
  String get reportsErrorAlreadyStarted => _t(
      'The barangay has already started on this report, so it can no '
      'longer be cancelled.',
      'Nasimulan na ng barangay ang ulat na ito, kaya hindi na ito '
      'maaaring kanselahin.');
  String get reportsErrorOnlyCompletedReopen => _t(
      'Only a completed report can be reopened.',
      'Isang nakumpletong ulat lamang ang maaaring buksan muli.');
  String get reportsErrorOwnReportsOnly => _t(
      'You can only do this to your own reports.',
      'Magagawa mo lamang ito sa sarili mong mga ulat.');
  String get reportsErrorGiveReason =>
      _t('Please give a reason.', 'Pakibigay ng dahilan.');
  String get reportsErrorGeneric => _t(
      'That did not work. Please try again.',
      'Hindi iyon gumana. Subukan ulit.');
  String get reportsViewTitle =>
      _t('View your Reports', 'Tingnan ang Iyong mga Ulat');
  /// Small orange eyebrow label above whichever open report the list
  /// auto-expands to show its timeline for — see reports_screen.dart's
  /// hero-card header comment for why exactly one report gets this.
  String get reportsTrackingLabel => _t('TRACKING PROGRESS', 'SINUSUBAYBAYAN');
  String get reportsEmptyAll => _t(
      'You have not filed any reports yet.',
      'Wala ka pang isinumiteng ulat.');
  String reportsEmptyFiltered(String filterLower) => _t(
      'No $filterLower reports.', 'Walang $filterLower na ulat.');
  String reportsSubmittedOn(String date) =>
      _t('Submitted on $date', 'Isinumite noong $date');
  String reportsCardDescription(String description) =>
      '“$description”';
  String get reportsMenuView => _t('View', 'Tingnan');
  String get reportsMenuCancel => _t('Cancel', 'Kanselahin');
  String get reportsMenuReopen => _t('Reopen', 'Buksan Muli');
  String get reportsReasonDialogHint => _t('Your reason', 'Ang iyong dahilan');
  String get reportsReasonDialogSend =>
      _t('Send request', 'Ipadala ang kahilingan');
  String get reportsReopenReasonCameBack =>
      _t('The problem came back', 'Bumalik ang problema');
  String get reportsReopenReasonNotFixed =>
      _t('The problem was not fixed', 'Hindi naayos ang problema');
  String get reportsReopenReasonProofMismatch => _t(
      'The proof does not match my report',
      'Hindi tugma ang patunay sa aking ulat');
  String get reportsReopenReasonOther => _t('Other', 'Iba pa');
  /// The reopen reason dropdown stores its canonical English value (sent
  /// to request_reopen() as free text the barangay reads) and only
  /// translates what's shown for it — same wire/label split as
  /// ReportStatus elsewhere in this app.
  String reportsReopenReasonLabel(String english) {
    switch (english) {
      case 'The problem came back':
        return reportsReopenReasonCameBack;
      case 'The problem was not fixed':
        return reportsReopenReasonNotFixed;
      case 'The proof does not match my report':
        return reportsReopenReasonProofMismatch;
      case 'Other':
        return reportsReopenReasonOther;
      default:
        return english;
    }
  }
  String get reportsPhotoAccessTitle =>
      _t('Photo access', 'Access sa Larawan');
  String get reportsPhotoAccessBody => _t(
      'SmartSumbong needs access to your photos to attach evidence to '
      'this reopen request.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'maidagdag ang ebidensya sa kahilingang ito na buksan muli.');
  String get reportsReasonRequired =>
      _t('Please choose a reason.', 'Pumili ng dahilan.');
  String get reportsConcernRequired => _t(
      'Please describe your concern.', 'Ilarawan ang iyong alalahanin.');
  String get reportsAckRequired => _t(
      'Please confirm the information above is accurate.',
      'Pakikumpirma na tama ang impormasyon sa itaas.');
  String reportsReopenHeader(
          String trackingId, String statusLabel, String subject) =>
      _t('Reopen:\n($trackingId - $statusLabel) $subject',
          'Buksan Muli:\n($trackingId - $statusLabel) $subject');
  String get reportsOriginalClosingRemarks => _t(
      'Original Closing Remarks', 'Orihinal na Puna sa Pagsasara');
  String reportsDateClosed(String date) =>
      _t('Date Closed: $date', 'Petsa ng Pagsasara: $date');
  String get reportsReopenNote => _t(
      'Note: Reopening asks the barangay to look at this case again. If '
      'this is a new problem rather than the same one, please file a '
      'new report instead.',
      'Paalala: Ang pagbukas muli ay humihiling sa barangay na tingnan '
      'ulit ang kasong ito. Kung ito ay bagong problema at hindi pareho '
      'ng dati, mangyaring mag-file na lamang ng bagong ulat.');
  String get reportsReasonOfReopen =>
      _t('Reason of Reopen', 'Dahilan ng Pagbukas Muli');
  String get reportsSelectAReason =>
      _t('Select a Reason', 'Pumili ng Dahilan');
  String get reportsConcernHint =>
      _t('Enter your concern here.', 'Ilagay dito ang iyong alalahanin.');
  String get reportsOptional => _t('(Optional)', '(Opsyonal)');
  String get reportsAckReopen => _t(
      'I acknowledge that the information I am submitting is, to the '
      'best of my knowledge, accurate and complete.',
      'Kinikilala ko na ang impormasyong isinusumite ko ay, sa abot ng '
      'aking kaalaman, tama at kumpleto.');
  String get reportsSubmit => _t('Submit', 'Isumite');
  String get reportsAttachMedia => _t('Attach Media', 'Mag-attach ng Media');
  String get reportsMaxPhotoSize => _t('(Max: 10 MB)', '(Max: 10 MB)');
  String get reportsPhotoAttachedNote => _t(
      'A photo is attached to this request.',
      'May naka-attach na larawan sa kahilingang ito.');

  // ---------- report view (view a report) ----------
  String get reportViewNotFound => _t(
      'That report could not be found.', 'Hindi mahanap ang ulat na iyon.');
  String get reportViewLoadError => _t(
      'Could not load this report. Pull to retry.',
      'Hindi ma-load ang ulat na ito. I-pull para subukan ulit.');
  String get reportViewTitle =>
      _t('View your Reports', 'Tingnan ang Iyong mga Ulat');
  // Share sheet, added 29 Aug 2026 — hands the tracking id off through
  // SMS/Messenger/copy instead of a resident retyping it by hand.
  String get reportViewShare => _t('Share', 'Ibahagi');
  String reportViewShareText(
    String trackingId,
    String subject,
    String statusLabel,
  ) =>
      _t(
        'SmartSumbong complaint $trackingId ($statusLabel): $subject\n'
        'Filed with Barangay 183, Pasay City.',
        'Reklamo sa SmartSumbong $trackingId ($statusLabel): $subject\n'
        'Isinampa sa Barangay 183, Pasay City.',
      );
  String get reportViewShareFailed => _t(
      'Could not open the share menu.', 'Hindi mabuksan ang share menu.');
  String get reportViewHistory => _t('History', 'Kasaysayan');
  /// The synthetic first row report_view_screen.dart's timeline always
  /// shows, built from the report's own created_at rather than a
  /// status_logs row -- submission itself is never a logged transition,
  /// so without this the timeline's first entry would be whatever the
  /// first real transition happened to be, same gap the reference
  /// mockup's own first row ("Report submitted") doesn't have.
  String get reportViewSubmittedStep =>
      _t('Report submitted', 'Naisumite ang ulat');
  /// Subtext under the synthetic last row shown while a report is still
  /// moving -- the next stage in pending_review/validated -> assigned/
  /// in_progress/offline_investigation -> resolved, computed from the
  /// same three buckets reportStatusLabel already collapses statuses
  /// into, not a guess at what a tanod or admin will specifically do.
  String get reportViewUpcomingStep =>
      _t('Not yet reached', 'Hindi pa naaabot');
  String get reportViewAnonymous => _t('Anonymous', 'Anonymous');
  String get reportViewCouldNotLoadPhoto => _t(
      'Could not load this photo.', 'Hindi ma-load ang larawang ito.');
  String get reportViewReviewing => _t(
      'The barangay is reviewing your report.',
      'Rinerepaso ng barangay ang iyong ulat.');
  String get reportViewAssigned => _t(
      'A barangay tanod has been assigned and is working on this.',
      'May tanod ng barangay na nakatalaga at kasalukuyang ginagawa ito.');
  String get reportViewResolvedWithProof => _t(
      'Your report has been resolved. ', 'Naayos na ang iyong ulat. ');
  String get reportViewResolvedNoProof => _t(
      'Your report has been resolved.', 'Naayos na ang iyong ulat.');
  String get reportViewRejected => _t(
      'This report was not accepted. Please visit the barangay hall if '
      'you would like to know why.',
      'Hindi tinanggap ang ulat na ito. Mangyaring pumunta sa barangay '
      'hall kung gusto mong malaman kung bakit.');
  String get reportViewCancelled =>
      _t('You cancelled this report.', 'Kinansela mo ang ulat na ito.');
  String get reportViewForTheProof =>
      _t(' for the proof.', ' para sa patunay.');
  String get reportViewViewPhoto => _t('View Photo', 'Tingnan ang Larawan');
  String get reportViewReopenedOnce => _t(
      'This report has been reopened once.',
      'Nabuksan muli ang ulat na ito nang isang beses.');
  String reportViewReopenedTimes(int n) => _t(
      'This report has been reopened $n times.',
      'Nabuksan muli ang ulat na ito nang $n beses.');
  String get reportViewHowDidWeDo =>
      _t('How did we do?', 'Kumusta ang aming serbisyo?');
  String get reportViewYourFeedback =>
      _t('Your feedback', 'Ang iyong puna');
  String get reportViewFeedbackPrompt => _t(
      'Tell the barangay how this complaint was handled. Your rating '
      'helps them see what is working.',
      'Sabihin sa barangay kung paano naasikaso ang ulat na ito. '
      'Nakakatulong ang iyong rating para makita nila kung ano ang '
      'gumagana.');
  String get reportViewGiveFeedback =>
      _t('Give feedback', 'Magbigay ng Puna');
  String get reportViewRatingRequired => _t(
      'Please choose a rating first.', 'Pumili muna ng rating.');
  String get reportViewFeedbackDuplicate => _t(
      'You have already given feedback on this report.',
      'Nagbigay ka na ng puna sa ulat na ito.');
  String get reportViewFeedbackNotFinished => _t(
      'Feedback can only be given once a report is finished.',
      'Ang puna ay maaari lamang ibigay kapag tapos na ang ulat.');
  String get reportViewFeedbackFailed => _t(
      'Could not send your feedback. Please try again.',
      'Hindi maipadala ang iyong puna. Subukan ulit.');
  String get reportViewCommentHint => _t(
      'Anything you want to add? (optional)',
      'May gusto ka bang idagdag? (opsyonal)');
  String get reportViewSendFeedback =>
      _t('Send feedback', 'Ipadala ang Puna');

  // ---------- notifications ----------
  String get notificationsLoadError => _t(
      'Could not load your notifications.',
      'Hindi ma-load ang iyong mga notification.');
  String get notificationsTitle => _t('Notifications', 'Mga Notification');
  String get notificationsBack => _t('Back', 'Bumalik');
  String get notificationsEmptyTitle =>
      _t('No Notifications', 'Walang Notification');
  String get notificationsEmptyBody => _t(
      "We'll let you know when there will be something to update you.",
      'Ipapaalam namin sa iyo kapag may bagong update.');
  String get notificationsJustNow => _t('Just now', 'Ngayon lang');
  // Kept as compact one-letter units to match Figma's design, the same
  // way "m"/"h"/"d" reads as a unit shorthand rather than an English
  // word in most apps regardless of interface language.
  String notificationsMinutesAgo(int m) => '${m}m';
  String notificationsHoursAgo(int h) => '${h}h';
  String notificationsDaysAgo(int d) => '${d}d';

  // ---------- register (sign up) ----------
  String get registerFullNameRequired =>
      _t('Please enter your full name.', 'Ilagay ang iyong buong pangalan.');
  String get registerFullNameFormat => _t(
      'Enter your name as Last Name, First Name (e.g. Dela Cruz, Juan).',
      'Ilagay ang iyong pangalan bilang Apelyido, Unang Pangalan '
      '(hal. Dela Cruz, Juan).');
  String get registerEmailInvalid => _t(
      'That email address does not look right.',
      'Mukhang mali ang email address na iyon.');
  String get registerMobileInvalid => _t(
      'Enter a mobile number like 09171234567 or +639171234567.',
      'Maglagay ng numero tulad ng 09171234567 o +639171234567.');
  String get registerPasswordTooShort => _t(
      'Your password must be at least 8 characters long.',
      'Dapat hindi bababa sa 8 na karakter ang iyong password.');
  String get registerPasswordMismatch => _t(
      'Your password should match.', 'Dapat magkatugma ang iyong password.');
  String get registerIdTypeRequired => _t(
      'Please choose which ID you are attaching.',
      'Piliin kung aling ID ang iyong ini-attach.');
  String get registerIdPhotoRequired => _t(
      'Please attach a photo of your ID.',
      'Mag-attach ng larawan ng iyong ID.');
  String get registerSelfieRequired => _t(
      'Please take a photo of yourself.',
      'Kumuha ng larawan ng iyong sarili.');
  String get registerAgreeRequired => _t(
      'Please agree to the Terms and Conditions and Privacy Policy.',
      'Pumayag sa Mga Tuntunin at Kondisyon at Patakaran sa Privacy.');
  String get registerCameraAccessTitle =>
      _t('Camera access', 'Access sa Camera');
  String get registerPhotoAccessTitle =>
      _t('Photo access', 'Access sa Larawan');
  String get registerCameraSelfieRationale => _t(
      'SmartSumbong needs your camera to take a selfie, so the barangay '
      'can match you to your ID.',
      'Kailangan ng SmartSumbong ng camera mo para kumuha ng selfie, '
      'para maitugma ka ng barangay sa iyong ID.');
  String get registerCameraIdRationale => _t(
      'SmartSumbong needs your camera to take a photo of your ID.',
      'Kailangan ng SmartSumbong ng camera mo para kumuha ng larawan ng '
      'iyong ID.');
  String get registerGallerySelfieRationale => _t(
      'SmartSumbong needs access to your photos to choose a selfie, so '
      'the barangay can match you to your ID.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'pumili ng selfie, para maitugma ka ng barangay sa iyong ID.');
  String get registerGalleryIdRationale => _t(
      'SmartSumbong needs access to your photos to choose a photo of '
      'your ID.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'pumili ng larawan ng iyong ID.');
  String get registerTakePhoto => _t('Take Photo', 'Kumuha ng Larawan');
  String get registerChooseFromGallery =>
      _t('Choose from Gallery', 'Pumili mula sa Gallery');
  String get registerSomethingWentWrong => _t(
      'Something went wrong. Please try again.',
      'May nangyaring mali. Subukan ulit.');
  String get registerReviewTitle =>
      _t('Review before you submit', 'Repasuhin bago isumite');
  String get registerReviewIntro => _t(
      'The barangay verifies your account against this. Make sure it '
      'matches your ID before you send it.',
      'Ito ang gagamitin ng barangay para i-verify ang iyong account. '
      'Tiyaking tugma ito sa iyong ID bago mo ipadala.');
  String get registerReviewFullName => _t('Full Name', 'Buong Pangalan');
  String get registerReviewEmail => _t('Email Address', 'Email Address');
  String get registerReviewPhone => _t('Phone Number', 'Numero ng Telepono');
  String get registerReviewAccountType =>
      _t('Account type', 'Uri ng Account');
  String get registerReviewTanod => _t('Tanod', 'Tanod');
  String get registerReviewResident => _t('Resident', 'Residente');
  String get registerReviewIdType => _t('ID type', 'Uri ng ID');
  String get registerReviewYourId => _t('Your ID', 'Ang Iyong ID');
  String get registerReviewYourSelfie => _t('Your selfie', 'Ang Iyong Selfie');
  String get registerGoBackAndEdit =>
      _t('Go back and edit', 'Bumalik at i-edit');
  String get registerConfirmAndSubmit =>
      _t('Confirm & Submit', 'Kumpirmahin at Isumite');
  String get registerCreateAccount =>
      _t('Create your Account', 'Gumawa ng Iyong Account');
  String get registerSignUpTanod =>
      _t('Sign Up as Tanod', 'Mag-sign Up bilang Tanod');
  String get registerSignUpResident =>
      _t('Sign Up as Resident', 'Mag-sign Up bilang Residente');
  String get registerFullNameLabel => _t('Full Name', 'Buong Pangalan');
  String get registerFullNameNote => _t(
      '(Format: Last Name, First Name)',
      '(Format: Apelyido, Unang Pangalan)');
  String get registerFullNameHint =>
      _t('e.g. Dela Cruz, Juan', 'hal. Dela Cruz, Juan');
  String get registerEmailLabel => _t('Email Address', 'Email Address');
  String get registerEmailNote => _t('(Optional)', '(Opsyonal)');
  String get registerEmailHint => _t('example@gmail.com', 'halimbawa@gmail.com');
  String get registerPhoneLabel => _t('Phone Number', 'Numero ng Telepono');
  String get registerPhoneNote => _t(
      '(You will use this to sign in.)',
      '(Gagamitin mo ito para mag-log in.)');
  String get registerPhoneHint =>
      _t('e.g. +63 1234567899', 'hal. +63 1234567899');
  String get registerPasswordLabel => _t('Password', 'Password');
  String get registerPasswordNote => _t(
      '(Your password must be at least 8 characters long.)',
      '(Dapat hindi bababa sa 8 na karakter ang iyong password.)');
  String get registerPasswordHint =>
      _t('Enter your password', 'Ilagay ang iyong password');
  String get registerConfirmPasswordLabel =>
      _t('Confirm Password', 'Kumpirmahin ang Password');
  String get registerConfirmPasswordNote => _t(
      '(Your password should match.)', '(Dapat magkatugma ang iyong password.)');
  String get registerConfirmPasswordHint =>
      _t('Confirm your password', 'Kumpirmahin ang iyong password');
  String get registerAttachBarangayId =>
      _t('Attach your Barangay ID', 'I-attach ang iyong Barangay ID');
  String get registerAttachValidId =>
      _t('Attach a Valid ID', 'Mag-attach ng Balidong ID');
  String get registerInfoReadableNote => _t(
      '(Information should be readable.)', '(Dapat nababasa ang impormasyon.)');
  String get registerSelectYourDocument =>
      _t('Select your document', 'Piliin ang iyong dokumento');
  String get registerSelectAValidId =>
      _t('Select a Valid ID', 'Pumili ng Balidong ID');
  String get registerPhotoOfYourId =>
      _t('Photo of your ID', 'Larawan ng Iyong ID');
  String get registerMakeSureReadable => _t(
      'Make sure the details are readable',
      'Tiyaking nababasa ang mga detalye');
  String get registerChooseIdTypeFirst => _t(
      'Choose an ID type first', 'Pumili muna ng uri ng ID');
  String get registerPhotoOfYourself =>
      _t('Photo of yourself', 'Larawan ng Iyong Sarili');
  String get registerSelfieCaption => _t(
      'So the barangay can match you to your ID',
      'Para maitugma ka ng barangay sa iyong ID');
  String get registerUploaded => _t('Uploaded', 'Na-upload na');
  String get registerTapToRetake => _t('Tap to retake', 'I-tap para kunin ulit');
  String get registerSignUp => _t('Sign Up', 'Mag-sign Up');
  String get registerAlreadyHaveAccount => _t(
      'Already have an account? Sign in',
      'May account ka na ba? Mag-sign in');
  String get registerAgreementPrefix =>
      _t('By checking, you agree to the ', 'Sa pag-check, sumasang-ayon ka sa ');
  String get registerAgreementLink => _t(
      'Terms and Conditions and Privacy Policy',
      'Mga Tuntunin at Kondisyon at Patakaran sa Privacy');

  // ---------- verification pending ----------
  String get verificationCheckError => _t(
      'Could not check right now. Please try again in a moment.',
      'Hindi ma-check ngayon. Subukan ulit sa ilang sandali.');
  String get verificationWindowDefault => _t(
      'The barangay usually reviews within two hours.',
      'Karaniwang sinusuri ito ng barangay sa loob ng dalawang oras.');
  String get verificationOverdue => _t(
      'This is taking longer than usual. The barangay has been notified '
      'and will review your account as soon as they can.',
      'Mas matagal ito kaysa karaniwan. Naabisuhan na ang barangay at '
      'susuriin nila ang iyong account sa lalong madaling panahon.');
  String get verificationAnyMoment => _t(
      'The barangay should review your account any moment now.',
      'Dapat suriin na ng barangay ang iyong account sa lalong madaling '
      'panahon.');
  // Kept as compact "h"/"m" units, same reasoning as the notifications
  // relative-time shorthand above.
  String verificationLeftHM(int h, int m) => '${h}h ${m}m';
  String verificationLeftM(int m) => '${m}m';
  String verificationAboutLeft(String pretty) => _t(
      'About $pretty left in the barangay’s two-hour review window.',
      'Humigit-kumulang $pretty na natitira sa dalawang-oras na review '
      'window ng barangay.');
  String get verificationChecking => _t('Checking…', 'Sinusuri…');
  String get verificationCheckedJustNow =>
      _t('Checked just now', 'Nasuri lang ngayon');
  String get verificationCheckedLessThanMinute => _t(
      'Checked less than a minute ago', 'Nasuri wala pang isang minuto ang nakalipas');
  String get verificationChecked1Minute =>
      _t('Checked 1 minute ago', 'Nasuri 1 minuto ang nakalipas');
  String verificationCheckedNMinutes(int n) => _t(
      'Checked $n minutes ago', 'Nasuri $n minuto ang nakalipas');
  String get verificationCheckedOverHour => _t(
      'Checked over an hour ago', 'Nasuri mahigit isang oras ang nakalipas');
  String get verificationAlmostThere => _t('Almost there', 'Halos tapos na');
  String get verificationTitle =>
      _t('Verification Pending', 'Nakabinbing Beripikasyon');
  String get verificationBody => _t(
      'The barangay is checking your ID and photo against their records. '
      'This screen updates on its own once your account is approved — '
      'you can close the app and come back.',
      'Sinusuri ng barangay ang iyong ID at larawan laban sa kanilang mga '
      'rekord. Awtomatikong mag-a-update ang screen na ito kapag na-'
      'aprubahan na ang iyong account — maaari mong isara ang app at '
      'bumalik mamaya.');
  String verificationSubmitted(String date) => _t(
      'Submitted $date', 'Isinumite noong $date');
  String get verificationCheckStatus =>
      _t('Check my status', 'Tingnan ang Aking Status');
  String get verificationSignOut => _t('Sign out', 'Mag-sign Out');

  // ---------- account status (rejected / suspended) ----------
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
  String get launchGateSigningIn =>
      _t('Mabuhay! Signing you in…', 'Mabuhay! Nagsa-sign in ka na…');
  String get launchGateOfflineError => _t(
      'Could not reach the barangay’s system. Check your connection and '
      'try again.',
      'Hindi ma-abot ang sistema ng barangay. Suriin ang iyong koneksyon '
      'at subukan ulit.');
  String get launchGateTryAgain => _t('Try again', 'Subukan Ulit');
  String get launchGateBiometricReason =>
      _t('Unlock SmartSumbong', 'I-unlock ang SmartSumbong');

  // ---------- background-resume lock screen ----------
  // Shown by BiometricLockGate (smartsumbong_core) when the app is
  // reopened from the background with Face ID / fingerprint unlock on --
  // see settingsBiometricUnlock above for the toggle itself.
  String get lockGateTitle => _t('Locked', 'Naka-lock');
  String get lockGateBody => _t(
      'Unlock with Face ID or fingerprint to continue.',
      'I-unlock gamit ang Face ID o fingerprint para magpatuloy.');
  String get lockGateUnlock => _t('Unlock', 'I-unlock');
  String get lockGateFallback =>
      _t('Use password instead', 'Gamitin na lang ang password');

  // ---------- report submitted ----------
  String get reportSubmittedTitle =>
      _t('Report submitted', 'Naisumite ang Ulat');
  String get reportSubmittedBody => _t(
      'Thank you for letting us know about the issue. We will actively '
      'work on this case to continue bringing you good service.',
      'Salamat sa pagpapaalam sa amin tungkol sa isyu. Aktibo naming '
      'gagawan ng aksyon ang kasong ito para patuloy kang mabigyan ng '
      'mahusay na serbisyo.');
  String get reportSubmittedBackHome =>
      _t('Back to Home', 'Bumalik sa Home');
  String get reportSubmittedCopied => _t('Copied', 'Nakopya');
  String get reportSubmittedReferenceNumber =>
      _t('Reference Number', 'Reference Number');
  String get reportSubmittedCopyTooltip =>
      _t('Copy reference number', 'Kopyahin ang reference number');

  // ---------- terms & privacy notice ----------
  // A DRAFT document, in either language — see the screen's own header
  // comment. The Filipino text below is a good-faith translation of the
  // same draft, not an independently reviewed legal document; whoever
  // reviews the English draft before adoption should review this
  // translation too.
  String get termsPrivacyTitle =>
      _t('Terms & Privacy Notice', 'Mga Tuntunin at Paalala sa Privacy');
  String get termsPrivacyDraftBanner => _t(
      'This is a draft prepared from how the app actually handles your '
      'data, for Barangay 183 to review, correct, and formally adopt. '
      'It is not yet an approved barangay document.',
      'Ito ay isang draft na inihanda batay sa aktwal na paghawak ng app '
      'sa iyong datos, para suriin, itama, at pormal na aprubahan ng '
      'Barangay 183. Hindi pa ito isang inaprubahang dokumento ng '
      'barangay.');
  String get termsPrivacySection1Title =>
      _t('Who is collecting your information',
          'Sino ang Kumokolekta ng Iyong Impormasyon');
  String get termsPrivacySection1Body => _t(
      'SmartSumbong is operated for Barangay 183, Pasay City, as its '
      'local complaint-mapping system. For the purpose of the Data '
      'Privacy Act of 2012 (RA 10173), the barangay is the Personal '
      'Information Controller: it decides what this app collects and '
      'why, and it is who to contact about your data. The exact office '
      'and contact details a resident should use go here once the '
      'barangay confirms them -- this app currently only lists the '
      'barangay\'s Facebook page in Settings.',
      'Pinapatakbo ang SmartSumbong para sa Barangay 183, Lungsod ng '
      'Pasay, bilang kanilang lokal na sistema ng pagmapa ng reklamo. '
      'Para sa layunin ng Data Privacy Act of 2012 (RA 10173), ang '
      'barangay ang Personal Information Controller: sila ang '
      'nagpapasya kung ano ang kinokolekta ng app na ito at kung bakit, '
      'at sila ang dapat kontakin tungkol sa iyong datos. Ang eksaktong '
      'opisina at mga detalye ng kontak na dapat gamitin ng residente '
      'ay ilalagay dito kapag nakumpirma na ito ng barangay -- sa '
      'ngayon ay listahan lamang ng Facebook page ng barangay ang '
      'nakalagay sa Settings ng app na ito.');
  String get termsPrivacySection2Title =>
      _t('What we collect, and why', 'Ano ang Kinokolekta Namin, at Bakit');
  String get termsPrivacySection2Body => _t(
      '• Full name and mobile number, at sign-up -- your mobile number '
      'is how you sign in, so it doubles as your account identity.\n'
      '• A photo of a government or barangay ID and a selfie, at '
      'sign-up -- checked by a barangay officer before your account is '
      'approved, so that reports in the system can be traced to a real '
      'resident.\n'
      '• Email address and home address -- both optional, and editable '
      'any time in Edit Profile.\n'
      '• A profile photo, if you choose to add one.\n'
      '• Whatever you submit in a complaint report: category, '
      'description, photos or a short video, and the map location you '
      'place the pin at.\n'
      '• A device token, used only to deliver push notifications about '
      'your own reports and account.\n'
      '• System records of your reports\' status changes, kept as an '
      'accountability trail (who changed a report\'s status and when) '
      'rather than as anything collected about you directly.',
      '• Buong pangalan at numero ng mobile, kapag nagpapa-sign-up -- '
      'ang iyong numero ng mobile ang gagamitin mong mag-log in, kaya '
      'ito rin ang kinatatawan ng iyong pagkakakilanlan sa account.\n'
      '• Larawan ng gobyerno o barangay ID at selfie, kapag '
      'nagpapa-sign-up -- sinusuri ng isang opisyal ng barangay bago '
      'aprubahan ang iyong account, para masubaybayan ang mga ulat sa '
      'sistema pabalik sa isang tunay na residente.\n'
      '• Email address at tirahan -- pareho itong opsyonal, at maaaring '
      'baguhin anumang oras sa Edit Profile.\n'
      '• Larawan sa profile, kung pipiliin mong magdagdag ng isa.\n'
      '• Anumang isumite mo sa isang ulat ng reklamo: kategorya, '
      'paglalarawan, mga larawan o maikling video, at ang lokasyon sa '
      'mapa kung saan mo inilagay ang pin.\n'
      '• Isang device token, ginagamit lamang para maghatid ng push '
      'notification tungkol sa iyong sariling mga ulat at account.\n'
      '• Mga rekord ng sistema ng mga pagbabago sa status ng iyong mga '
      'ulat, itinatago bilang isang accountability trail (sino ang '
      'nagbago ng status ng ulat at kailan) kaysa bilang anumang '
      'direktang kinokolekta tungkol sa iyo.');
  String get termsPrivacySection3Title =>
      _t('How your photos are handled', 'Paano Hinahawakan ang Iyong mga Larawan');
  String get termsPrivacySection3Body => _t(
      'Every photo and video this app uploads -- ID, selfie, profile '
      'photo, or report evidence -- has its metadata (including GPS '
      'location embedded by your phone\'s camera) stripped before it '
      'leaves your device, regardless of whether you took it with the '
      'camera or picked it from your gallery. The complaint\'s location '
      'comes only from the map pin you place, never from a photo\'s '
      'hidden metadata.',
      'Bawat larawan at video na ini-upload ng app na ito -- ID, '
      'selfie, larawan sa profile, o ebidensya ng ulat -- ay '
      'tinatanggalan ng metadata nito (kasama ang GPS location na '
      'naka-embed ng camera ng iyong telepono) bago ito umalis sa iyong '
      'device, kahit kinuha mo ito gamit ang camera o pinili mula sa '
      'iyong gallery. Ang lokasyon ng reklamo ay galing lamang sa pin '
      'na inilagay mo sa mapa, hindi kailanman mula sa nakatagong '
      'metadata ng isang larawan.');
  String get termsPrivacySection4Title =>
      _t('Who can see it', 'Sino ang Makakakita Nito');
  String get termsPrivacySection4Body => _t(
      'Your identity documents are visible only to barangay staff '
      'verifying your account. Report details are visible to barangay '
      'staff and the tanod assigned to your report. Other residents '
      'cannot see your name, contact details, or ID -- and can file '
      'reports anonymously, in which case even barangay staff see the '
      'report without your identity attached. Nothing collected here is '
      'sold, or shared with any organization outside the barangay\'s '
      'own operation of this system.',
      'Ang iyong mga dokumento ng pagkakakilanlan ay makikita lamang ng '
      'staff ng barangay na nag-ve-verify ng iyong account. Ang mga '
      'detalye ng ulat ay makikita ng staff ng barangay at ng tanod na '
      'nakatalaga sa iyong ulat. Hindi makikita ng ibang residente ang '
      'iyong pangalan, mga detalye ng kontak, o ID -- at maaari kang '
      'mag-file ng mga ulat nang anonymous, kung saan kahit ang staff '
      'ng barangay ay makikita ang ulat nang walang naka-attach na '
      'pagkakakilanlan mo. Wala sa mga kinokolekta dito ang '
      'ibinebenta, o ibinabahagi sa anumang organisasyong labas sa '
      'pagpapatakbo ng barangay mismo ng sistemang ito.');
  String get termsPrivacySection5Title =>
      _t('How it is stored', 'Paano Ito Iniimbak');
  String get termsPrivacySection5Body => _t(
      'Data is stored in a Supabase-hosted database with row-level '
      'security rules that limit each account to its own records and '
      'role. Photos and videos are stored with Cloudinary. Passwords '
      'are never visible to barangay staff or stored by this app in '
      'plain form.',
      'Iniimbak ang datos sa isang database na naka-host sa Supabase na '
      'may mga row-level security rule na naglilimita sa bawat account '
      'sa sarili nitong mga rekord at tungkulin. Ang mga larawan at '
      'video ay iniimbak gamit ang Cloudinary. Ang mga password ay '
      'hindi kailanman makikita ng staff ng barangay o iniimbak ng app '
      'na ito sa plain form.');
  String get termsPrivacySection6Title =>
      _t('How long we keep it', 'Gaano Katagal Namin Itong Itinatago');
  String get termsPrivacySection6Body => _t(
      'Account and report records are kept for as long as they serve '
      'the barangay\'s record-keeping and accountability purposes. A '
      'specific retention period, and the process for a resident to '
      'request deletion of their account and data, is something the '
      'barangay needs to set -- this app does not yet have a '
      'self-service "delete my account" action, and one should be '
      'added before or shortly after this notice is finalised.',
      'Ang mga rekord ng account at ulat ay itinatago hangga\'t '
      'kapaki-pakinabang ang mga ito sa layunin ng pagtatala at '
      'accountability ng barangay. Ang tiyak na retention period, at '
      'ang proseso para sa isang residente na humiling ng pagtanggal ng '
      'kanilang account at datos, ay kailangang itakda ng barangay -- '
      'wala pang self-service na "burahin ang aking account" na aksyon '
      'ang app na ito, at dapat itong idagdag bago o hindi nagtatagal '
      'pagkatapos ma-finalize ang paalalang ito.');
  String get termsPrivacySection7Title =>
      _t('Your rights', 'Ang Iyong mga Karapatan');
  String get termsPrivacySection7Body => _t(
      'Under the Data Privacy Act, you may ask to access, correct, or '
      'request deletion of your personal information, object to its '
      'processing, and file a complaint with the National Privacy '
      'Commission if you believe it has been mishandled. Until a '
      'dedicated request channel exists in this app, Personal Info and '
      'Phone Number changes can already be requested from Edit Profile, '
      'which notifies the barangay directly.',
      'Sa ilalim ng Data Privacy Act, maaari kang humiling na '
      'ma-access, maitama, o hilingin ang pagtanggal ng iyong personal '
      'na impormasyon, tumutol sa pagproseso nito, at maghain ng '
      'reklamo sa National Privacy Commission kung sa tingin mo ay '
      'hindi ito maayos na hinawakan. Hanggang wala pang dedikadong '
      'channel para sa kahilingan sa app na ito, ang mga pagbabago sa '
      'Personal Info at Numero ng Telepono ay maaari nang hilingin '
      'mula sa Edit Profile, na direktang nag-aabiso sa barangay.');
  String get termsPrivacySection8Title =>
      _t('Terms of use', 'Mga Tuntunin ng Paggamit');
  String get termsPrivacySection8Body => _t(
      'This app is for reporting genuine barangay concerns. Reports '
      'should be truthful and made in good faith; the barangay may '
      'suspend an account it finds is being used to file false, '
      'abusive, or repeatedly duplicate reports. Your account\'s '
      'verification status, and any suspension, is decided by barangay '
      'staff, not automatically by this app.',
      'Ang app na ito ay para sa pag-uulat ng tunay na alalahanin ng '
      'barangay. Dapat totoo at may mabuting hangarin ang mga ulat; '
      'maaaring suspindihin ng barangay ang isang account na '
      'natuklasang ginagamit para mag-file ng mga huwad, mapang-abuso, '
      'o paulit-ulit na doble na ulat. Ang status ng verification ng '
      'iyong account, at anumang suspensyon, ay pinagpapasyahan ng '
      'staff ng barangay, hindi awtomatiko ng app na ito.');

  // ---------- emergency ----------
  String get emergencyLoadError => _t(
      'Could not load the emergency numbers. Check your connection and '
      'pull down to try again.',
      'Hindi ma-load ang mga emergency number. Suriin ang iyong '
      'koneksyon at i-pull para subukan ulit.');
  String get emergencyNeedHelp => _t('Need help?', 'Kailangan ng Tulong?');
  String get emergencyInstructions => _t(
      'Below are emergency services. View and select the number you '
      'want to copy or dial.',
      'Nasa ibaba ang mga emergency service. Tingnan at piliin ang '
      'numerong gusto mong kopyahin o tawagan.');
  String get emergencyStaleNote => _t(
      'Showing the last numbers saved on this phone.',
      'Ipinapakita ang huling mga numerong na-save sa telepong ito.');
  String get emergencyBack => _t('Back', 'Bumalik');
  String emergencyNumberCopied(String number) =>
      _t('$number copied', 'Nakopya ang $number');
  String emergencyCallPrompt(String number) =>
      _t('Call $number', 'Tawagan ang $number');
  String get emergencyCancel => _t('Cancel', 'Kanselahin');
  String get emergencyCopyNumberTooltip =>
      _t('Copy number', 'Kopyahin ang numero');
  String emergencyDiallerFailed(String number) => _t(
      'Could not open the dialler. The number is $number.',
      'Hindi mabuksan ang dialer. Ang numero ay $number.');

  // ---------- map ----------
  String get mapTitle => _t('Barangay 183 Map', 'Mapa ng Barangay 183');
  String get mapViewReport => _t('View report', 'Tingnan ang ulat');
  String get mapReportsSpotted =>
      _t('Reports spotted!', 'Nakita ang mga ulat!');
  String get mapWantToSeeReports => _t(
      'Want to see your reports?', 'Gusto mo bang makita ang iyong mga ulat?');
  // Sense-for-sense from the MAP and MAP - SEE REPORTS frames. The
  // English original's "you will back to" phrasing is the designer's
  // own wording, signed off as-is; the Filipino translates the meaning
  // naturally rather than reproducing that grammar quirk.
  String get mapCardBodyShowing => _t(
      'Just click the ‘eye’ again and you will back to the '
      'normal map. You can also move the map around.',
      'I-click lang ulit ang ‘mata’ at babalik ka sa '
      'normal na mapa. Maaari mo ring igalaw ang mapa.');
  String get mapCardBodyHidden => _t(
      'Just click the ‘eye’ and you will see the locations '
      'of your reports. You can also move the map around.',
      'I-click lang ang ‘mata’ at makikita mo ang mga '
      'lokasyon ng iyong mga ulat. Maaari mo ring igalaw ang mapa.');

  // ---------- edit profile ----------
  String get editProfileLoadError =>
      _t('Could not load your profile.', 'Hindi ma-load ang iyong profile.');
  String get editProfilePhotoAccessTitle =>
      _t('Photo access', 'Access sa Larawan');
  String get editProfilePhotoAccessRationale => _t(
      'SmartSumbong needs access to your photos to update your '
      'profile picture.',
      'Kailangan ng SmartSumbong ng access sa iyong mga larawan para '
      'i-update ang iyong profile picture.');
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
      'Your password has been changed.',
      'Napalitan na ang iyong password.');
  String get editProfileUnsavedTitle =>
      _t('Unsaved Changes', 'Hindi Na-save na mga Pagbabago');
  String get editProfileUnsavedBody => _t(
      'If you continue without saving, these changes will '
      'be lost.',
      'Kung magpapatuloy ka nang hindi nagse-save, mawawala ang '
      'mga pagbabagong ito.');
  String get editProfileCancel => _t('Cancel', 'Kanselahin');
  String get editProfileTitle => _t('Edit Profile', 'I-edit ang Profile');
  String get editProfileNameLabel => _t('Name', 'Pangalan');
  String get editProfileNameWord => _t('name', 'pangalan');
  String get editProfileNameNote =>
      _t('The barangay changes this', 'Pinapalitan ito ng barangay');
  String get editProfileEmailLabel =>
      _t('Email Address', 'Email Address');
  String get editProfileEmailHint =>
      _t('example@gmail.com', 'halimbawa@gmail.com');
  String get editProfileOptional => _t('(Optional)', '(Opsyonal)');
  String get editProfileAddressLabel => _t('Address', 'Address');
  String get editProfileAddressHint => _t(
      'House/unit no., street, purok', 'Numero ng bahay/unit, kalye, purok');
  String get editProfilePhoneLabel => _t('Phone Number', 'Numero ng Telepono');
  String get editProfilePhoneWord => _t('mobile number', 'numero ng mobile');
  String get editProfilePhoneNote =>
      _t('This is how you sign in', 'Ito ang ginagamit mo para mag-sign in');
  String get editProfilePasswordLabel => _t('Password', 'Password');
  String get editProfilePasswordChange => _t('Change', 'Palitan');
  String get editProfileBack => _t('BACK', 'BUMALIK');
  String get editProfileSave => _t('SAVE', 'I-SAVE');
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
  String get editProfilePasswordMismatch => _t(
      'Your passwords should match.', 'Dapat magkatugma ang iyong mga password.');

  // ---------- appearance / theme ----------
  String get themeTitle => _t('Appearance', 'Anyo');
  String get themeSystem => _t('Match device', 'Ayon sa Device');
  String get themeLight => _t('Light', 'Maliwanag');
  String get themeDark => _t('Dark', 'Madilim');
  String get themeBack => _t('Back', 'Bumalik');

  // ---------- settings: notification prefs + delete account (29 Aug 2026) ----------
  String get settingsNotificationPrefs =>
      _t('Notification Preferences', 'Mga Kagustuhan sa Abiso');
  String get settingsDeleteAccount =>
      _t('Delete Account', 'Burahin ang Account');

  // ---------- notification preferences screen ----------
  String get notifPrefsTitle => _t('Notifications', 'Mga Abiso');
  String get notifPrefsSubtitle => _t(
      'Choose which updates send a push to your phone. You will still '
      'see every update in the app either way.',
      'Piliin kung aling mga update ang magpapadala ng push sa iyong '
      'telepono. Makikita mo pa rin ang lahat ng update sa app kahit '
      'paano.');
  String get notifPrefsBack => _t('Back', 'Bumalik');
  String get notifPrefsLoadError => _t(
      'Could not load your notification settings.',
      'Hindi ma-load ang iyong mga setting ng abiso.');
  String get notifPrefsUpdateFailed => _t(
      'Could not save that. Please try again.',
      'Hindi na-save iyon. Subukan ulit.');
  String get notifPrefsAssignment => _t(
      'A tanod is assigned to my report',
      'May tanod na nakatalaga sa aking ulat');
  String get notifPrefsReroute =>
      _t('My report is reassigned', 'Muling itinalaga ang aking ulat');
  String get notifPrefsStatusChange => _t(
      'My report’s status changes', 'Nagbago ang status ng aking ulat');
  String get notifPrefsEscalation =>
      _t('Escalation alerts', 'Mga alerto sa escalation');
  String get notifPrefsSlaWarning => _t(
      'Response time warnings', 'Mga babala sa oras ng pagtugon');

  // ---------- delete account ----------
  String get deleteAccountConfirmTitle =>
      _t('Delete your account?', 'Burahin ang iyong account?');
  String get deleteAccountConfirmBody => _t(
      'You will no longer be able to sign in, and your name, ID photo, '
      'and other personal details will be removed. If you have filed '
      'any reports, the reports themselves stay on record with the '
      'barangay — just without your personal details attached. This '
      'cannot be undone.',
      'Hindi ka na makakapag-sign in, at aalisin ang iyong pangalan, '
      'larawan ng ID, at iba pang personal na detalye. Kung may '
      'naisumite kang mga ulat, mananatili ang mga ulat mismo sa '
      'talaan ng barangay — wala lang mga personal na detalye. Hindi '
      'na ito maaaring bawiin.');
  String get deleteAccountTypeToConfirm => _t(
      'Type DELETE below to confirm.', 'I-type ang DELETE sa ibaba para kumpirmahin.');
  String get deleteAccountTypeMismatch => _t(
      'Please type DELETE exactly to confirm.',
      'Pakitype nang eksakto ang DELETE para kumpirmahin.');
  String get deleteAccountConfirmButton =>
      _t('Delete my account', 'Burahin ang aking account');
  String get deleteAccountFailed => _t(
      'Could not delete your account. Please try again, or visit the '
      'barangay hall for help.',
      'Hindi mabura ang iyong account. Subukan ulit, o pumunta sa '
      'barangay hall para sa tulong.');
}
