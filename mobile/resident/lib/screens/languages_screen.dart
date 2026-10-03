// SmartSumbong — Select Language.
//
// Figma: LANGUAGES.
//
// Was a stub: choice recorded, nothing rendered. As of 26 Aug 2026
// (Rose's notes, Group 5's QA exchange) it actually switches the app's
// language — see i18n.dart for the lookup table and why it's a plain
// Dart class rather than the generated flutter_localizations pipeline.
// This screen no longer touches SharedPreferences itself; that lives in
// LocaleController now, shared with every other screen in the app.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../d/d_ui.dart';
import '../theme.dart';

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

  // Figma LANGUAGES: the title 28/800 50 from the top of the screen, the
  // two rows 70 apart from 138 (label at 70, the 20 radio ending 87 from
  // the right), and Back as the frame's 150x45 pill at 282.
  // Branch D: the languages as two cards with their flags.
  @override
  Widget build(BuildContext context) {
    final value = AppLocaleScope.of(context);
    final s = context.s;
    Widget flag(String e) => Text(e, style: const TextStyle(fontSize: 26));
    return DOptionsPage(
      title: s.languagesTitle,
      options: [
        DOption(title: s.languagesFilipino, sub: 'Filipino', leading: flag('🇵🇭'), selected: value == AppLocale.fil, onTap: () => _choose(context, AppLocale.fil)),
        DOption(title: s.languagesEnglish, sub: 'English', leading: flag('🇺🇸'), selected: value == AppLocale.en, onTap: () => _choose(context, AppLocale.en)),
      ],
    );
  }
}
