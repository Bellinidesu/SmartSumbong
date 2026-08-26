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
          backgroundColor: Tokens.navy,
          content: Text(locale == AppLocale.fil
              ? s.languagesChangedToFilipino
              : s.languagesChangedToEnglish),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final value = AppLocaleScope.of(context);
    final s = context.s;

    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text(s.languagesTitle,
                  style: t.headlineLarge?.copyWith(fontSize: 24)),
              const SizedBox(height: 28),

              _LanguageRow(
                label: s.languagesFilipino,
                selected: value == AppLocale.fil,
                onTap: () => _choose(context, AppLocale.fil),
              ),
              const SizedBox(height: 14),
              _LanguageRow(
                label: s.languagesEnglish,
                selected: value == AppLocale.en,
                onTap: () => _choose(context, AppLocale.en),
              ),

              const SizedBox(height: 30),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, 42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
                child: Text(s.languagesBack),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const _orange = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 14, color: Tokens.navy),
                ),
              ),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _orange, width: 2),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: _orange,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
