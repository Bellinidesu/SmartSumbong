// SmartSumbong — the day/night switch and the EN/PH flags (branch D).
//
// Carried over from the portal's sign-in: set the look and the language
// before signing in, without digging into Settings.

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme.dart';
import 'd_theme.dart';

class DPrefsRow extends StatelessWidget {
  const DPrefsRow({super.key, this.colors});

  final DColors? colors;

  @override
  Widget build(BuildContext context) {
    final d = colors ?? context.d;
    final dark = context.isDark;
    final lang = AppLocaleScope.of(context);
    Widget flag(AppLocale l, String emoji, String code) {
      final on = lang == l;
      return InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => AppLocaleScope.controllerOf(context).set(l),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: on ? d.card : Colors.transparent,
            boxShadow: on ? [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 6, offset: const Offset(0, 2))] : null,
          ),
          child: Text('$emoji $code',
              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, color: on ? d.ink : d.muted)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: dark ? 'Switch to light mode' : 'Switch to dark mode',
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => AppThemeScope.controllerOf(context).set(dark ? ThemeMode.light : ThemeMode.dark),
          child: Container(
            width: 58,
            height: 32,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              color: dark ? const Color(0xFF22305E) : const Color(0xFFDCE6FA),
              border: Border.all(color: d.line),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 200),
              alignment: dark ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(shape: BoxShape.circle, color: dark ? const Color(0xFF0E1322) : Colors.white),
                child: Icon(dark ? Icons.dark_mode_rounded : Icons.light_mode_rounded, size: 16, color: dark ? const Color(0xFFFFD27A) : DColors.orange),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: d.field, border: Border.all(color: d.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          flag(AppLocale.en, '🇺🇸', 'EN'),
          flag(AppLocale.fil, '🇵🇭', 'PH'),
        ]),
      ),
    ]);
  }
}
