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
  @override
  Widget build(BuildContext context) {
    final value = AppLocaleScope.of(context);
    final s = context.s;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              SizedBox(
                  height: (50 - MediaQuery.paddingOf(context).top)
                      .clamp(8.0, 50.0)),
              Text(
                s.languagesTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 43.68 / 28,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 29),

              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 57, 0),
                child: Column(
                  children: [
                    _LanguageRow(
                      label: s.languagesFilipino,
                      selected: value == AppLocale.fil,
                      onTap: () => _choose(context, AppLocale.fil),
                    ),
                    const SizedBox(height: 20),
                    _LanguageRow(
                      label: s.languagesEnglish,
                      selected: value == AppLocale.en,
                      onTap: () => _choose(context, AppLocale.en),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 39),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x4D121212),
                      blurRadius: 3.5,
                      offset: Offset(0, 5),
                    ),
                  ],
                ),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    fixedSize: const Size(150, 45),
                    minimumSize: const Size(150, 45),
                    padding: EdgeInsets.zero,
                    elevation: 0,
                    side: BorderSide(color: context.colors.bg),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(50),
                    ),
                  ),
                  child: Text(s.languagesBack),
                ),
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
        // 15 above and below the 20 radio, so each row's tap target is 50
        // and the rows land on the frame's 70 pitch.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: context.colors.navy,
                  ),
                ),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _orange, width: 1.5),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 11,
                          height: 11,
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
