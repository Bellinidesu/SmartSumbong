// SmartSumbong — tanod app theme.
//
// Tokens read off the mobile Figma file. The design specifies Visby CF,
// which is a commercial typeface and cannot be embedded in a public
// repo or handed to the barangay without a licence that covers app
// distribution. Poppins stands in for it — geometric sans, same
// character, SIL Open Font Licence — and Roboto carries body text.
// Both are already vendored in the admin portal, so the two halves of
// the system look like one system.

import 'package:flutter/material.dart';

abstract final class Tokens {
  /// The tanod accent. Orange carries the primary action, which is how
  /// LOG IN RESPONDER differs from LOG IN RESIDENT.
  static const orange = Color(0xFFFF9800);

  /// The tanod app runs on ink, not the barangay navy.
  ///
  /// Two apps in the same hands doing different jobs should not look
  /// alike. A tanod holding both — filing as a resident off shift,
  /// working the queue on it — needs to know at a glance which one is
  /// open, and a glance is all they get standing in the street.
  ///
  /// Still named `navy` deliberately. Every screen in this app already
  /// reads Tokens.navy, and renaming it would mean touching a dozen
  /// files to change one value. The name records where the colour came
  /// from; the value is what ships.
  static const navy = Color(0xFF14181D);

  /// The barangay navy, kept for anything that has to match the seals
  /// or the wordmark rather than the app chrome.
  static const brandNavy = Color(0xFF00308F);

  /// Page background.
  static const bg = Color(0xFFF3F3F3);

  /// Field fill — very slightly lighter than the page.
  static const field = Color(0xFFFBFBFB);

  /// The small red hints under a label ("must be at least 8 characters").
  static const hint = Color(0xFFE53935);

  /// Divider inside the expanded ID dropdown.
  static const divider = Color(0xFFC8C8C8);

  static const muted = Color(0xFF787878);

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

ThemeData buildTanodTheme() {
  const scheme = ColorScheme.light(
    primary: Tokens.navy,
    onPrimary: Tokens.bg,
    surface: Tokens.bg,
    onSurface: Tokens.navy,
    error: Tokens.hint,
  );

  OutlineInputBorder border([Color color = Tokens.navy, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tokens.pill),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tokens.bg,
    fontFamily: 'Roboto',

    textTheme: const TextTheme(
      // "Sign Up as Resident"
      headlineLarge: TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w700,
        fontSize: 30,
        height: 1.15,
        color: Tokens.navy,
      ),
      // "Create your Account"
      titleMedium: TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: Tokens.navy,
      ),
      // Field labels
      labelLarge: TextStyle(
        fontFamily: 'Poppins',
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: Tokens.navy,
      ),
      // Field text and placeholders
      bodyMedium: TextStyle(fontSize: 14, color: Tokens.navy),
      // The red parenthetical hints
      bodySmall: TextStyle(fontSize: 9, color: Tokens.hint),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Tokens.field,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      hintStyle: const TextStyle(
        fontSize: 13,
        fontStyle: FontStyle.italic,
        color: Tokens.navy,
      ),
      border: border(),
      enabledBorder: border(),
      focusedBorder: border(Tokens.navy, 2),
      errorBorder: border(Tokens.hint),
      focusedErrorBorder: border(Tokens.hint, 2),
      // Errors are rendered under the field by the screen, not by the
      // decorator, so that they sit where the design puts its hints.
      errorStyle: const TextStyle(height: 0, fontSize: 0),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Tokens.navy,
        foregroundColor: Tokens.bg,
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
      side: const BorderSide(color: Tokens.navy),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Tokens.navy : Tokens.field,
      ),
      shape: const RoundedRectangleBorder(),
      visualDensity: VisualDensity.compact,
    ),
  );
}
