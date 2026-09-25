// SmartSumbong — Select Language (tanod).
//
// Figma: LANGUAGES.
//
// Was a stub: choice recorded, nothing rendered — "Filipino is not
// available yet" shown in a snackbar when picked. As of 8 Sep 2026 it
// actually switches the app's language, porting the resident app's own
// fix (26 Aug 2026) — see i18n.dart for the lookup table and why it's a
// plain Dart class rather than the generated flutter_localizations
// pipeline. This screen no longer touches SharedPreferences itself;
// that lives in LocaleController now, shared with every other screen in
// the app.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';

class LanguagesScreen extends StatelessWidget {
  const LanguagesScreen({super.key});

  void _choose(BuildContext context, AppLocale locale) {
    final controller = AppLocaleScope.controllerOf(context);
    final already = controller.value == locale;
    controller.set(locale);
    if (already) return;
    final s = Strings(locale);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          backgroundColor: context.colors.navy,
          content: Text(locale == AppLocale.fil
              ? s.languagesChangedToFilipino
              : s.languagesChangedToEnglish),
        ),
      );
  }

  // Figma TANOD - LANGUAGES: the title 28/800 at y=50, the two rows 70
  // apart from x=70 with the orange radios, the 150x45 Back 54 under them.
  @override
  Widget build(BuildContext context) {
    final value = AppLocaleScope.of(context);
    final s = context.s;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(43, figmaTop(context, 50), 43, 24),
          child: Column(
            children: [
              FigmaTitle(s.languagesTitle),
              const SizedBox(height: 28),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 27),
                child: Column(
                  children: [
                    FigmaRadioRow(
                      label: s.languagesFilipino,
                      selected: value == AppLocale.fil,
                      onTap: () => _choose(context, AppLocale.fil),
                    ),
                    const SizedBox(height: 20),
                    FigmaRadioRow(
                      label: s.languagesEnglish,
                      selected: value == AppLocale.en,
                      onTap: () => _choose(context, AppLocale.en),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              FigmaBackPill(label: s.languagesBack),
            ],
          ),
        ),
      ),
    );
  }
}
