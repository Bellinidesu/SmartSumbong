// SmartSumbong — resident app theme.
//
// Tokens read off the mobile Figma file. The design specifies Visby CF,
// which is a commercial typeface and cannot be embedded in a public
// repo or handed to the barangay without a licence that covers app
// distribution. Poppins stands in for it — geometric sans, same
// character, SIL Open Font Licence — and Roboto carries body text.
// Both are already vendored in the admin portal, so the two halves of
// the system look like one system.
//
// DARK MODE (27 Aug 2026). The Figma file has no dark-mode frames or
// second palette — checked directly in the file, not assumed — so
// there is no design to match here, only a palette chosen to keep the
// same brand feel (a navy-family surface, not a neutral black) with
// reasonable contrast. Two things were deliberately kept identical
// across both modes rather than given dark variants: the brand orange
// accent (`Color(0xFFFF9800)`, used as a bare literal throughout the
// app rather than through this file) reads fine on both a near-white
// and a near-black background, and [AppColors.hint]'s red does too —
// so neither needed a second value, only [AppColors.navy],
// [AppColors.bg], [AppColors.field], [AppColors.muted] and
// [AppColors.divider] actually differ between the two swatches below.
//
// ARCHITECTURE: mirrors i18n.dart's LocaleController/AppLocaleScope
// pattern exactly, for the same reason — a ValueNotifier wrapped in an
// InheritedNotifier is what makes `context.colors` (below) rebuild the
// exact widgets that read it when the mode changes, without every
// screen needing to know how that happens. `Tokens` used to hold the
// six colour constants directly as `static const` fields; they have
// moved to `context.colors.xxx` (through [AppColors]) since a colour
// that must vary at runtime cannot also be a compile-time constant —
// `Tokens` now only holds the dimension constants that never change
// with brightness.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class Tokens {
  /// Fields and the primary button are 44 high and fully rounded.
  /// The tanod accent (branch C, one app): orange carries the primary
  /// action on the tanod screens. Identical in both modes.
  static const orange = Color(0xFFFF9800);

  /// The barangay navy for anything that has to match the seals or the
  /// wordmark rather than the app chrome — on the tanod screens, whose
  /// chrome is ink. Identical in both modes.
  static const brandNavy = Color(0xFF00308F);

  static const fieldHeight = 44.0;
  static const pill = 50.0;

  /// The ID dropdown is squarer than the text fields.
  static const dropdownRadius = 20.0;

  /// Horizontal page inset. The design lays out at 412 wide with content
  /// from x=45 and 323 wide, which is 44/45 either side.
  static const pagePad = 45.0;

  /// Vertical rhythm between field groups.
  static const gap = 24.0;
}

/// The six colours that change between light and dark. Both
/// [buildResidentTheme] and `context.colors` resolve through
/// [AppColors.resolve] so the two swatches are defined in exactly one
/// place — a screen and the app-level ThemeData can never disagree
/// about what "dark mode" looks like.
class AppColors {
  const AppColors._({
    required this.navy,
    required this.bg,
    required this.field,
    required this.hint,
    required this.divider,
    required this.muted,
  });

  /// Barangay navy in light mode. The field has always meant "primary
  /// label/border/button ink", not literally the colour navy — dark
  /// mode is the first time those two meanings diverge, so this
  /// resolves to a pale blue-white at night instead, the same role a
  /// deep navy plays on a light page.
  final Color navy;

  /// Page background.
  final Color bg;

  /// Field fill — one step lighter than the page in light mode, one
  /// step lighter than the page in dark mode too, so the relationship
  /// between the two carries across.
  final Color field;

  /// The small red hints under a label ("must be at least 8
  /// characters"). Unchanged between modes — see the file header.
  final Color hint;

  /// Divider inside the expanded ID dropdown.
  final Color divider;

  final Color muted;

  static const light = AppColors._(
    navy: Color(0xFF00308F),
    bg: Color(0xFFF3F3F3),
    field: Color(0xFFFBFBFB),
    hint: Color(0xFFE53935),
    divider: Color(0xFFC8C8C8),
    muted: Color(0xFF787878),
  );

  /// A dark desaturated navy surface rather than neutral black, so the
  /// app still reads as the same barangay-blue product at night.
  static const dark = AppColors._(
    navy: Color(0xFFEAF0FF),
    bg: Color(0xFF0D1B33),
    field: Color(0xFF16264A),
    hint: Color(0xFFE53935),
    divider: Color(0xFF30416B),
    muted: Color(0xFFA8B3C7),
  );

  /// The tanod screens' ink (branch C, one app — Ace kept the tanod app's
  /// black ink rather than the Figma navy, 25 Sep 2026). `navy` still
  /// names the role, not the hue: ink by day, pale at night.
  static const inkLight = AppColors._(
    navy: Color(0xFF14181D),
    bg: Color(0xFFF3F3F3),
    field: Color(0xFFFBFBFB),
    hint: Color(0xFFE53935),
    divider: Color(0xFFC8C8C8),
    muted: Color(0xFF787878),
  );

  static const inkDark = AppColors._(
    navy: Color(0xFFF3F3F3),
    bg: Color(0xFF14181D),
    field: Color(0xFF1E242B),
    hint: Color(0xFFE53935),
    divider: Color(0xFF34383E),
    muted: Color(0xFFA8A8A8),
  );

  /// The palette for [brightness] and the signed-in role.
  static AppColors resolve(Brightness brightness, [AppRole? role]) {
    final tanod = (role ?? AppRoleController.instance.value) == AppRole.tanod;
    final dark_ = brightness == Brightness.dark;
    if (tanod) return dark_ ? inkDark : inkLight;
    return dark_ ? dark : light;
  }
}

/// Who is signed in (branch C: one app for residents and tanods). The
/// resident screens draw in barangay navy, the tanod screens in ink —
/// each role still looks like its own app. Saved, so a tanod's cold
/// start opens in ink before the network has said anything; the launch
/// gate corrects it from the account's actual role.
enum AppRole { resident, tanod }

const appRoleKey = 'appRole';

class AppRoleController extends ValueNotifier<AppRole> {
  AppRoleController._() : super(AppRole.resident);

  static final instance = AppRoleController._();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString(appRoleKey) == 'tanod' ? AppRole.tanod : AppRole.resident;
    } catch (_) {}
  }

  Future<void> set(AppRole role) async {
    value = role;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(appRoleKey, role.name);
    } catch (_) {}
  }
}

/// Matches `languageKey` in i18n.dart's shape exactly — loaded once at
/// startup, and the single place a change is written and broadcast
/// afterward.
const themeModeKey = 'themeMode';

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([super.initial = ThemeMode.system]);

  static Future<ThemeController> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(themeModeKey);
      return ThemeController(switch (v) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      });
    } catch (_) {
      // Storage unavailable: follow the OS setting, same as a resident
      // who has never opened the picker at all.
      return ThemeController();
    }
  }

  Future<void> set(ThemeMode mode) async {
    value = mode; // Notifies every AppThemeScope listener immediately.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(themeModeKey, mode.name);
    } catch (_) {
      // The choice still stands for the rest of this session — only the
      // next cold start falls back to System.
    }
  }
}

/// Makes the current theme mode available to every screen below it and
/// rebuilds that subtree when [ThemeController.set] changes it.
class AppThemeScope extends InheritedNotifier<ThemeController> {
  const AppThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeMode of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    return scope?.notifier?.value ?? ThemeMode.system;
  }

  static ThemeController controllerOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppThemeScope>();
    assert(scope != null,
        'AppThemeScope not found above this widget — wrap MaterialApp with it in main.dart.');
    return scope!.notifier!;
  }
}

/// `context.colors.navy` anywhere in the widget tree below
/// [AppThemeScope] — the dark-mode equivalent of i18n.dart's
/// `context.s`. Reading it via `context` is what registers the
/// dependency, so the calling widget rebuilds when the mode changes,
/// and (in [ThemeMode.system]) when the OS brightness does.
extension AppThemeContext on BuildContext {
  Brightness get _resolvedBrightness {
    final mode = AppThemeScope.of(this);
    return switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => MediaQuery.platformBrightnessOf(this),
    };
  }

  AppColors get colors => AppColors.resolve(_resolvedBrightness);

  /// For the handful of spots that need a yes/no rather than a colour --
  /// a second image asset to pick between, or a decision a Color alone
  /// can't express. Resolves exactly the way [colors] does, so the two
  /// can never disagree about which mode is showing.
  bool get isDark => _resolvedBrightness == Brightness.dark;
}

/// Figma sets letter spacing to 0 on all but 8 of its ~1,630 text layers.
/// Material 3's defaults, which fill in every style the theme above does
/// not override, add 0.1–0.5 of tracking, and every Text inherits it
/// through DefaultTextStyle, so type came out visibly looser than the
/// design. This zeroes it once for every style instead of per widget.
TextTheme _figmaTracking(TextTheme t) {
  TextStyle? z(TextStyle? s) => s?.copyWith(letterSpacing: 0);
  return t.copyWith(
    displayLarge: z(t.displayLarge),
    displayMedium: z(t.displayMedium),
    displaySmall: z(t.displaySmall),
    headlineLarge: z(t.headlineLarge),
    headlineMedium: z(t.headlineMedium),
    headlineSmall: z(t.headlineSmall),
    titleLarge: z(t.titleLarge),
    titleMedium: z(t.titleMedium),
    titleSmall: z(t.titleSmall),
    bodyLarge: z(t.bodyLarge),
    bodyMedium: z(t.bodyMedium),
    bodySmall: z(t.bodySmall),
    labelLarge: z(t.labelLarge),
    labelMedium: z(t.labelMedium),
    labelSmall: z(t.labelSmall),
  );
}

ThemeData buildResidentTheme(Brightness brightness) {
  final c = AppColors.resolve(brightness, AppRole.resident);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.navy,
    onPrimary: c.bg,
    secondary: c.navy,
    onSecondary: c.bg,
    surface: c.bg,
    onSurface: c.navy,
    error: c.hint,
    onError: c.bg,
  );

  OutlineInputBorder border([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.pill),
        borderSide: BorderSide(color: color ?? c.navy, width: width),
      );

  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Urbanist',

    textTheme: TextTheme(
      // "Sign Up as Resident"
      headlineLarge: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w700,
        fontSize: 30,
        height: 1.15,
        color: c.navy,
      ),
      // "Create your Account"
      titleMedium: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: c.navy,
      ),
      // Field labels
      labelLarge: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: c.navy,
      ),
      // Field text and placeholders
      bodyMedium: TextStyle(fontSize: 14, color: c.navy),
      // The red parenthetical hints
      bodySmall: TextStyle(fontSize: 9, color: c.hint),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      hintStyle: TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        color: c.navy,
      ),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(c.navy, 2),
      errorBorder: border(c.hint),
      focusedErrorBorder: border(c.hint, 2),
      // Errors are rendered under the field by the screen, not by the
      // decorator, so that they sit where the design puts its hints.
      errorStyle: const TextStyle(height: 0, fontSize: 0),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.navy,
        foregroundColor: c.bg,
        minimumSize: const Size.fromHeight(Tokens.fieldHeight),
        elevation: 3,
        shadowColor: const Color(0x4D121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.pill),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Urbanist',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),

    // Every snackbar (the draft-restored note, save/copy confirmations,
    // errors) in the design's language rather than Material's grey: a
    // floating navy pill, radius 25, light Urbanist text, orange action.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.navy,
      contentTextStyle: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: c.bg,
      ),
      actionTextColor: const Color(0xFFFF9800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      insetPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      elevation: 3,
    ),

    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: c.navy),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.navy : c.field,
      ),
      shape: const RoundedRectangleBorder(),
      visualDensity: VisualDensity.compact,
    ),
  );
  return theme.copyWith(
    textTheme: _figmaTracking(theme.textTheme),
    primaryTextTheme: _figmaTracking(theme.primaryTextTheme),
  );
}

/// The tanod screens' theme (branch C): the tanod app's own, moved here
/// when the two apps became one — ink chrome, orange for the primary
/// action. main.dart picks it while a tanod is signed in.
ThemeData buildTanodTheme(Brightness brightness) {
  final c = AppColors.resolve(brightness, AppRole.tanod);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.navy,
    onPrimary: c.bg,
    secondary: c.navy,
    onSecondary: c.bg,
    surface: c.bg,
    onSurface: c.navy,
    error: c.hint,
    onError: c.bg,
  );

  OutlineInputBorder border([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.pill),
        borderSide: BorderSide(color: color ?? c.navy, width: width),
      );

  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Urbanist',

    textTheme: TextTheme(
      // "Sign Up as Resident"
      headlineLarge: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w700,
        fontSize: 30,
        height: 1.15,
        color: c.navy,
      ),
      // "Create your Account"
      titleMedium: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: c.navy,
      ),
      // Field labels
      labelLarge: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: c.navy,
      ),
      // Field text and placeholders
      bodyMedium: TextStyle(fontSize: 14, color: c.navy),
      // The red parenthetical hints
      bodySmall: TextStyle(fontSize: 9, color: c.hint),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.field,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      hintStyle: TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        color: c.navy,
      ),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(c.navy, 2),
      errorBorder: border(c.hint),
      focusedErrorBorder: border(c.hint, 2),
      // Errors are rendered under the field by the screen, not by the
      // decorator, so that they sit where the design puts its hints.
      errorStyle: const TextStyle(height: 0, fontSize: 0),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.navy,
        foregroundColor: c.bg,
        minimumSize: const Size.fromHeight(Tokens.fieldHeight),
        elevation: 3,
        shadowColor: const Color(0x4D121212),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.pill),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Urbanist',
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: c.navy),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.navy : c.field,
      ),
      shape: const RoundedRectangleBorder(),
      visualDensity: VisualDensity.compact,
    ),
  );
  return theme.copyWith(
    textTheme: _figmaTracking(theme.textTheme),
    primaryTextTheme: _figmaTracking(theme.primaryTextTheme),
  );
}
