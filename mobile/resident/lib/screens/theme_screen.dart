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

class ThemeScreen extends StatelessWidget {
  const ThemeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final mode = AppThemeScope.of(context);
    final controller = AppThemeScope.controllerOf(context);
    final s = context.s;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const SizedBox(height: 16),
              Text(s.themeTitle, style: t.headlineLarge?.copyWith(fontSize: 24)),
              const SizedBox(height: 28),

              _ThemeRow(
                label: s.themeSystem,
                selected: mode == ThemeMode.system,
                onTap: () => controller.set(ThemeMode.system),
              ),
              const SizedBox(height: 14),
              _ThemeRow(
                label: s.themeLight,
                selected: mode == ThemeMode.light,
                onTap: () => controller.set(ThemeMode.light),
              ),
              const SizedBox(height: 14),
              _ThemeRow(
                label: s.themeDark,
                selected: mode == ThemeMode.dark,
                onTap: () => controller.set(ThemeMode.dark),
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
                child: Text(s.themeBack),
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeRow extends StatelessWidget {
  const _ThemeRow({
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
    final c = context.colors;
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
                  style: TextStyle(fontSize: 14, color: c.navy),
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
