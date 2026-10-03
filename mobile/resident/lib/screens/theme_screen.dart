// SmartSumbong — Appearance.
//
// Added 27 Aug 2026 alongside dark mode itself — there is no Figma frame
// for this screen because there is no Figma dark-mode design at all (the
// file's own DOCUMENTATION page has only the one light palette). Built
// to match `languages_screen.dart`'s pattern exactly: same row shape,
// same radio-dot selection, same "pop back to Settings" button, since a
// resident who has used one settings picker in this app already knows
// how to use this one.
//
// No snackbar confirmation the way Languages has one. Language changes
// text you might not immediately register as different; a theme change
// repaints this very screen the instant you tap a row, live, under your
// thumb — that is the confirmation.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  // Branch D: the three modes as cards, each with its own icon.
  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final mode = AppThemeScope.of(context);
    final controller = AppThemeScope.controllerOf(context);
    final s = context.s;
    return DOptionsPage(
      title: s.themeTitle,
      options: [
        DOption(
          title: s.themeSystem,
          leading: DWell(Icons.phone_android_rounded, size: 42),
          selected: mode == ThemeMode.system,
          onTap: () => controller.set(ThemeMode.system),
        ),
        DOption(
          title: s.themeLight,
          leading: DWell(Icons.light_mode_rounded, size: 42, color: DColors.orange),
          selected: mode == ThemeMode.light,
          onTap: () => controller.set(ThemeMode.light),
        ),
        DOption(
          title: s.themeDark,
          leading: DWell(Icons.dark_mode_rounded, size: 42, color: d.dark ? const Color(0xFFFFD27A) : d.link),
          selected: mode == ThemeMode.dark,
          onTap: () => controller.set(ThemeMode.dark),
        ),
      ],
    );
  }
}
