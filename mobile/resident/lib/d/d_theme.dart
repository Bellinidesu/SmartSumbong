// SmartSumbong — branch D design tokens.
//
// Branch D rebuilds the app from the HTML app preview Ace signed off
// (claude.ai artifact 2TrpqeDRsc6iZK5fJ85N24), the way the portal was
// rebuilt from its refined preview. Every screen of D draws from this one
// palette, read off the preview's CSS:
//
//   resident  light  barangay navy chrome on a light grey page
//   resident  dark   a deep navy-black page, pale blue accents
//   tanod     light  "Ink": the same page with black ink chrome (Ace, 4 Oct)
//   tanod     dark   black, so a tanod can never be mistaken for a resident
//
// The bottom bar follows the C app: filled with the role colour, icons and
// labels in the page colour — so it is pale at night.

import 'package:flutter/material.dart';

import '../theme.dart';

@immutable
class DColors {
  const DColors({
    required this.dark,
    required this.tanod,
    required this.bg,
    required this.card,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.field,
    required this.accent,
    required this.link,
    required this.card1,
    required this.card2,
    required this.bar,
    required this.barFg,
    required this.contour,
    required this.contourAlpha,
  });

  final bool dark;
  final bool tanod;

  /// Page.
  final Color bg;

  /// White cards and sheets on the page.
  final Color card;

  /// Text.
  final Color ink;
  final Color ink2;
  final Color muted;

  /// Hairlines and card edges.
  final Color line;

  /// Field fill, the small round icon wells.
  final Color field;

  /// The role colour: navy for residents, ink for tanods. Buttons, headings.
  final Color accent;

  /// Links and icons that sit on the page (pale at night).
  final Color link;

  /// The big role cards' gradient, top-left to bottom-right.
  final Color card1;
  final Color card2;

  /// Bottom bar fill and its icons/labels.
  final Color bar;
  final Color barFg;

  /// The contour lines' tint and strength.
  final Color contour;
  final double contourAlpha;

  /// The solid role-colour button (the preview's plain `.btn`): brand
  /// navy for residents, ink for tanods — the same in day and night.
  Color get btn => tanod ? (dark ? card1 : const Color(0xFF14181D)) : const Color(0xFF00308F);

  static const orange = Color(0xFFFF9800);
  static const orangeDeep = Color(0xFFE07400);
  static const green = Color(0xFF1F8A45);
  static const greenVivid = Color(0xFF16C25B);
  static const red = Color(0xFFC62828);
  static const brandNavy = Color(0xFF00308F);

  /// The four dispatch steps, vivid (Ace, 4 Oct): Accepted, On the way,
  /// Arrived, Resolved.
  List<Color> get steps => dark
      ? const [Color(0xFF5B9BFF), Color(0xFFFFA033), Color(0xFFC084FC), Color(0xFF34D976)]
      : const [Color(0xFF2F7BFF), Color(0xFFFF8A00), Color(0xFFA855F7), Color(0xFF16C25B)];

  static const residentLight = DColors(
    dark: false,
    tanod: false,
    bg: Color(0xFFF3F3F3),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF141B34),
    ink2: Color(0xFF3A4058),
    muted: Color(0xFF6B6B6B),
    line: Color(0xFFE3E6EE),
    field: Color(0xFFFBFBFB),
    accent: Color(0xFF00308F),
    link: Color(0xFF00308F),
    card1: Color(0xFF00308F),
    card2: Color(0xFF00236A),
    bar: Color(0xFF00308F),
    barFg: Color(0xFFF3F3F3),
    contour: Color(0xFF00308F),
    contourAlpha: .09,
  );

  static const residentDark = DColors(
    dark: true,
    tanod: false,
    bg: Color(0xFF0E1322),
    card: Color(0xFF161C2E),
    ink: Color(0xFFE9ECF5),
    ink2: Color(0xFFC3C8D8),
    muted: Color(0xFF9096AB),
    line: Color(0xFF273050),
    field: Color(0xFF1B2236),
    accent: Color(0xFFEAF0FF),
    link: Color(0xFF8DB2FF),
    card1: Color(0xFF13235A),
    card2: Color(0xFF0A1640),
    bar: Color(0xFFEAF0FF),
    barFg: Color(0xFF0D1B33),
    contour: Color(0xFF8DB2FF),
    contourAlpha: .10,
  );

  static const tanodLight = DColors(
    dark: false,
    tanod: true,
    bg: Color(0xFFF3F3F3),
    card: Color(0xFFFFFFFF),
    ink: Color(0xFF141B34),
    ink2: Color(0xFF3A4058),
    muted: Color(0xFF6B6B6B),
    line: Color(0xFFE3E6EE),
    field: Color(0xFFFBFBFB),
    accent: Color(0xFF14181D),
    link: Color(0xFF14181D),
    card1: Color(0xFF2E343C),
    card2: Color(0xFF14181D),
    bar: Color(0xFF14181D),
    barFg: Color(0xFFF3F3F3),
    contour: Color(0xFF14181D),
    contourAlpha: .09,
  );

  static const tanodDark = DColors(
    dark: true,
    tanod: true,
    bg: Color(0xFF14181D),
    card: Color(0xFF1C2127),
    ink: Color(0xFFF3F3F3),
    ink2: Color(0xFFC9CCD1),
    muted: Color(0xFFA8A8A8),
    line: Color(0xFF34383E),
    field: Color(0xFF1E242B),
    accent: Color(0xFFF3F3F3),
    link: Color(0xFFDADDE2),
    card1: Color(0xFF2A3038),
    card2: Color(0xFF15181D),
    bar: Color(0xFFF3F3F3),
    barFg: Color(0xFF14181D),
    contour: Color(0xFFD0D4DA),
    contourAlpha: .07,
  );

  static DColors resolve(Brightness b, AppRole role) {
    final dk = b == Brightness.dark;
    if (role == AppRole.tanod) return dk ? tanodDark : tanodLight;
    return dk ? residentDark : residentLight;
  }
}

extension DContext on BuildContext {
  /// Branch D's palette for the signed-in role and the current mode.
  DColors get d => DColors.resolve(isDark ? Brightness.dark : Brightness.light,
      AppRoleController.instance.value);

  /// The resident palette regardless of who is signed in (role picker,
  /// sign-in before a role is known).
  DColors get dResident => DColors.resolve(
      isDark ? Brightness.dark : Brightness.light, AppRole.resident);
}

/// Type helpers: Urbanist for words, Inter for numbers and small caps.
abstract final class DType {
  static TextStyle h1(Color c) => TextStyle(
      fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 26, height: 1.15, letterSpacing: -.26, color: c);
  static TextStyle h2(Color c) => TextStyle(
      fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 20, height: 1.2, color: c);
  static TextStyle h3(Color c) => TextStyle(
      fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 17, height: 1.25, color: c);
  static TextStyle body(Color c, {double size = 14, FontWeight w = FontWeight.w500}) =>
      TextStyle(fontFamily: 'Urbanist', fontWeight: w, fontSize: size, height: 1.45, color: c);
  static TextStyle label(Color c) => TextStyle(
      fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 1.1, color: c);
  static TextStyle mono(Color c, {double size = 12}) => TextStyle(
      fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: size, color: c,
      fontFeatures: const [FontFeature.tabularFigures()]);
}
