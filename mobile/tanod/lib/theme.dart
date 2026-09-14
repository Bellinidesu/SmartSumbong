// SmartSumbong — tanod app theme.
//
// Tokens read off the mobile Figma file. The design specifies Visby CF,
// which is a commercial typeface and cannot be embedded in a public
// repo or handed to the barangay without a licence that covers app
// distribution. Poppins stands in for it — geometric sans, same
// character, SIL Open Font Licence — and Roboto carries body text.
// Both are already vendored in the admin portal, so the two halves of
// the system look like one system.
//
// DARK MODE (8 Sep 2026), ported from the resident app's own dark-mode
// pass (27 Aug 2026) — tanod never got it at the time. Same caveat
// applies: there is no dark-mode design anywhere in the Figma file, so
// the palette below was designed directly in code rather than matched
// to a spec.
//
// THE PALETTE IS A LITERAL INVERSION, not two newly-picked colours. This
// app's whole light-mode identity is already just two tones — a
// near-black "ink" (`navy`, despite the name — see below) on a light
// grey page. Dark mode simply swaps which of those two tones is the
// page and which is the ink: the exact hex that was the page background
// in light mode becomes the ink colour in dark mode, and vice versa.
// `field`, `muted`, and `divider` each get a dark-mode value one step
// removed from the new `bg` the same way they sit one step removed from
// the old one. `hint` (the red validation colour) and `orange` (the
// accent, kept as an unthemed `Tokens` literal exactly as before) are
// identical in both modes — both already read fine on near-white and
// near-black alike, so neither needed a second value. `brandNavy`
// (actual barangay navy, for seals/wordmarks) also stays an unthemed
// literal — it has to match a printed seal regardless of what mode the
// phone is in.
//
// ARCHITECTURE: mirrors the resident app's theme.dart exactly (which
// itself mirrors i18n.dart's LocaleController/AppLocaleScope pattern) —
// a ValueNotifier wrapped in an InheritedNotifier is what makes
// `context.colors` (below) rebuild the exact widgets that read it when
// the mode changes, without every screen needing to know how that
// happens.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract final class Tokens {
  /// The tanod accent. Orange carries the primary action, which is how
  /// LOG IN RESPONDER differs from LOG IN RESIDENT. Identical in both
  /// modes — see the file header.
  static const orange = Color(0xFFFF9800);

  /// The barangay navy, kept for anything that has to match the seals
  /// or the wordmark rather than the app chrome. Identical in both
  /// modes for the same reason a printed seal doesn't change colour.
  static const brandNavy = Color(0xFF00308F);

  /// Fields and the primary button are 44 high and fully rounded.
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

/// The five colours that change between light and dark. Both
/// [buildTanodTheme] and `context.colors` resolve through
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

  /// Primary ink/border/button colour. Still named `navy` deliberately —
  /// every screen in this app already reads `context.colors.navy`, and
  /// renaming it would mean touching a dozen files to change one value.
  /// The name records where the colour's role came from ("the tanod app
  /// runs on ink, not the barangay navy"); the value is whatever mode
  /// is active.
  final Color navy;

  /// Page background.
  final Color bg;

  /// Field fill — one step lighter than the page, in both modes.
  final Color field;

  /// The small red hints under a label ("must be at least 8
  /// characters"). Unchanged between modes — see the file header.
  final Color hint;

  /// Divider inside the expanded ID dropdown.
  final Color divider;

  final Color muted;

  static const light = AppColors._(
    navy: Color(0xFF14181D),
    bg: Color(0xFFF3F3F3),
    field: Color(0xFFFBFBFB),
    hint: Color(0xFFE53935),
    divider: Color(0xFFC8C8C8),
    muted: Color(0xFF787878),
  );

  /// The literal inversion described in the file header: light mode's
  /// `bg` (0xFFF3F3F3) becomes dark mode's `navy`, and light mode's
  /// `navy` (0xFF14181D) becomes dark mode's `bg`. `field`, `divider`
  /// and `muted` are each a fresh value one step removed from the new
  /// `bg`, the same relationship they have to the old one.
  static const dark = AppColors._(
    navy: Color(0xFFF3F3F3),
    bg: Color(0xFF14181D),
    field: Color(0xFF1E242B),
    hint: Color(0xFFE53935),
    divider: Color(0xFF34383E),
    muted: Color(0xFFA8A8A8),
  );

  static AppColors resolve(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Matches `languageKey` in i18n.dart's shape exactly — loaded once at
/// startup, and the single place a change is written and broadcast
/// afterward.
const themeModeKey = 'themeMode';

class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController([ThemeMode initial = ThemeMode.system]) : super(initial);

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
      // Storage unavailable: follow the OS setting, same as a tanod who
      // has never opened the picker at all.
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

ThemeData buildTanodTheme(Brightness brightness) {
  final c = AppColors.resolve(brightness);

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

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Roboto',

    textTheme: TextTheme(
      // "Sign Up as Resident"
      headlineLarge: TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w700,
        fontSize: 30,
        height: 1.15,
        color: c.navy,
      ),
      // "Create your Account"
      titleMedium: TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: c.navy,
      ),
      // Field labels
      labelLarge: TextStyle(
        fontFamily: 'Poppins',
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
          fontFamily: 'Poppins',
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
}
