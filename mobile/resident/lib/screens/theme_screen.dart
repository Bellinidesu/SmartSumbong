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
import '../widgets/figma_ui.dart';

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  // Laid out as the translated LANGUAGES frame: the title 28/800 at 50,
  // the rows 16/600 at 70 with the 20px radio 87 from the right on a 70
  // pitch, and the 150x45 Back pill 39 below.
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = AppThemeScope.of(context);
    final controller = AppThemeScope.controllerOf(context);
    final s = context.s;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(30, figmaTop(context, 50), 30, 24),
          child: Column(
            children: [
              FigmaTitle(s.themeTitle),
              const SizedBox(height: 29),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 57, 0),
                child: Column(
                  children: [
                    FigmaRadioRow(
                      label: s.themeSystem,
                      selected: mode == ThemeMode.system,
                      onTap: () => controller.set(ThemeMode.system),
                    ),
                    const SizedBox(height: 20),
                    FigmaRadioRow(
                      label: s.themeLight,
                      selected: mode == ThemeMode.light,
                      onTap: () => controller.set(ThemeMode.light),
                    ),
                    const SizedBox(height: 20),
                    FigmaRadioRow(
                      label: s.themeDark,
                      selected: mode == ThemeMode.dark,
                      onTap: () => controller.set(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 39),
              FigmaBackPill(label: s.themeBack),
            ],
          ),
        ),
      ),
    );
  }
}
