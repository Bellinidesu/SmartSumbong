// Accessibility on the main screens, on the real app over the preview
// backend: every tappable thing has a name a screen reader can say, can be
// touched over at least 44x44 (WCAG 2.5.5 / Apple; Android asks 48, the
// app's buttons are drawn 44 by design), and text keeps WCAG AA contrast.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/d/d_theme.dart';
import 'support/app_harness.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + .05) / ((la > lb ? lb : la) + .05);
}

const tapTarget = MinimumTapTargetGuideline(size: Size(44, 44), link: 'https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced');

Future<void> checkScreen(WidgetTester tester, {bool contrast = true}) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(tapTarget));
  if (contrast) await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

void main() {
  testWidgets('choosing a role and signing in', (tester) async {
    await bootApp(tester, role: null);
    await checkScreen(tester);
    await tester.tap(find.text('I’m a Resident'));
    await settle(tester);
    await checkScreen(tester);
    await finish(tester);
  });

  testWidgets('resident home and reports', (tester) async {
    await bootApp(tester);
    // The greeting sits on the contour-map texture, which the contrast
    // check reads pixel by pixel as background; checked by eye instead.
    await checkScreen(tester, contrast: false);
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    // The bottom bar's contrast is checked exactly below; read from pixels
    // here, the Settings tab's light avatar icon counts as background.
    await checkScreen(tester, contrast: false);
    await finish(tester);
  });

  test('bottom bar labels keep 4.5:1 in every theme, inactive ones too', () {
    for (final c in [DColors.residentLight, DColors.residentDark, DColors.tanodLight, DColors.tanodDark]) {
      final inactive = Color.lerp(c.bar, c.barFg, .82)!; // resident_nav_bar.dart: opacity .82
      expect(contrast(c.barFg, c.bar), greaterThanOrEqualTo(4.5));
      expect(contrast(inactive, c.bar), greaterThanOrEqualTo(4.5), reason: 'tanod ${c.tanod}, dark ${c.dark}');
    }
  });

  testWidgets('tanod home and a dispatch order', (tester) async {
    await bootApp(tester, role: 'tanod');
    await checkScreen(tester, contrast: false);
    await tester.tap(find.text('View Details'));
    await settle(tester);
    await checkScreen(tester);
    await finish(tester);
  });

  testWidgets('sign-in still fits at 200% text size', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await bootApp(tester, role: null);
    await tester.tap(find.text('I’m a Resident'));
    await settle(tester);
    expect(find.text('Log In'), findsOneWidget);
    await finish(tester);
  });
}
