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
    final mode = AppThemeScope.of(context);
    final controller = AppThemeScope.controllerOf(context);
    final s = context.s;
    return DOptionsPage(
      title: s.themeTitle,
      options: [
        DOption(
          title: s.themeSystem,
          sub: context.tr('Follows your phone’s setting', 'Sumusunod sa setting ng telepono'),
          leading: const _Mini(_MiniKind.system),
          selected: mode == ThemeMode.system,
          onTap: () => controller.set(ThemeMode.system),
        ),
        DOption(
          title: s.themeLight,
          sub: context.tr('Day: bright and clear', 'Araw: maliwanag'),
          leading: const _Mini(_MiniKind.light),
          selected: mode == ThemeMode.light,
          onTap: () => controller.set(ThemeMode.light),
        ),
        DOption(
          title: s.themeDark,
          sub: context.tr('Night: easy on the eyes', 'Gabi: hindi masakit sa mata'),
          leading: const _Mini(_MiniKind.dark),
          selected: mode == ThemeMode.dark,
          onTap: () => controller.set(ThemeMode.dark),
        ),
      ],
    );
  }
}

enum _MiniKind { system, light, dark }

/// The preview's little phone for each mode (Ace, 7 Oct 2026): the page
/// colour, a navy card near the top and the navy bar along the bottom.
class _Mini extends StatelessWidget {
  const _Mini(this.kind);

  final _MiniKind kind;

  @override
  Widget build(BuildContext context) {
    final line = context.d.line;
    Widget half(bool dark) => Container(
          color: dark ? const Color(0xFF0E1322) : const Color(0xFFF3F3F3),
          child: Column(children: [
            Container(margin: const EdgeInsets.fromLTRB(6, 8, 6, 0), height: 18, decoration: BoxDecoration(color: dark ? const Color(0xFF13235A) : const Color(0xFF00308F), borderRadius: BorderRadius.circular(5))),
            const Spacer(),
            Container(height: 14, color: dark ? const Color(0xFF0A1640) : const Color(0xFF00308F)),
          ]),
        );
    return Container(
      width: 56,
      height: 84,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: line)),
      clipBehavior: Clip.antiAlias,
      child: switch (kind) {
        _MiniKind.light => half(false),
        _MiniKind.dark => half(true),
        _MiniKind.system => Row(children: [Expanded(child: half(false)), Expanded(child: half(true))]),
      },
    );
  }
}
