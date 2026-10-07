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
import '../d/d_switches.dart';
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
    // The preview (Ace, 7 Oct 2026): English first, each language greeting
    // you in itself under its name, drawn flags.
    return DOptionsPage(
      title: s.languagesTitle,
      options: [
        DOption(title: 'English', sub: 'Welcome! How are you doing today?', leading: const DFlag(us: true), selected: value == AppLocale.en, onTap: () => _choose(context, AppLocale.en)),
        DOption(title: 'Filipino', sub: 'Maligayang pagdating! Kumusta ka ngayon?', leading: const DFlag(us: false), selected: value == AppLocale.fil, onTap: () => _choose(context, AppLocale.fil)),
      ],
    );
  }
}
