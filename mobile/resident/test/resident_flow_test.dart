// A resident's own reports, on the real screens over the preview backend.
import 'package:flutter_test/flutter_test.dart';
import 'support/app_harness.dart';

void main() {
  testWidgets('Reports lists the resident\'s complaints and filters them by status', (tester) async {
    await bootApp(tester);
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    for (final title in ['Poor Street Lighting', 'Clogged Drainage', 'Neighborhood Noise', 'Illegal Parking']) {
      expect(find.text(title), findsOneWidget, reason: title);
    }
    await tester.tap(find.text('In Progress · 2'));
    await settle(tester);
    expect(find.text('Neighborhood Noise'), findsOneWidget);
    expect(find.text('Illegal Parking'), findsNothing, reason: 'completed, filtered out');
    await finish(tester);
  });

  testWidgets('a report opens with its status, place, target date and timeline', (tester) async {
    await bootApp(tester);
    await tester.tap(find.text('Reports').last);
    await settle(tester);
    await tester.tap(find.text('Clogged Drainage'));
    await settle(tester);
    final text = screenText();
    for (final expected in ['BRG-2026-0101', '13th Street', 'The barangay expects to resolve this by', 'Filed', 'Validated', 'Tanod dispatched', 'Resolved', 'Ask the barangay']) {
      expect(text.any((t) => t.contains(expected)), isTrue, reason: expected);
    }
    await finish(tester);
  });
}
