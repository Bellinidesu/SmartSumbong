// SmartSumbong — Appearance (tanod).
//
// Ported 8 Sep 2026 from the resident app's Appearance screen
// (27 Aug 2026), which tanod never got at the time. There is no Figma
// frame for this screen because there is no Figma dark-mode design at
// all (the file's own DOCUMENTATION page has only the one light
// palette). Built to match `languages_screen.dart`'s pattern exactly:
// same row shape, same radio-dot selection, same "pop back to Settings"
// button, since a tanod who has used one settings picker in this app
// already knows how to use this one.
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

  @override
  // No frame of its own; laid out as TANOD - LANGUAGES: the title 28/800
  // at y=50, orange radio rows 70 apart, the 150x45 Back.
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = AppThemeScope.of(context);
    final controller = AppThemeScope.controllerOf(context);
    final s = context.s;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(43, figmaTop(context, 50), 43, 24),
          child: Column(
            children: [
              FigmaTitle(s.themeTitle),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 27),
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
              const SizedBox(height: 40),
              FigmaBackPill(label: s.themeBack),
            ],
          ),
        ),
      ),
    );
  }
}
