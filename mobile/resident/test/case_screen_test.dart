// The case screen (19 Nov 2026), on the real screens over the preview backend: every state the canvas draws, the More menu, the
// reopen and appeal sheets (one request, no status change), the Resolved card, the full timeline, the evidence viewer and the
// list card. Pictures cannot load in tests, so the thumbnails show their placeholders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/main.dart' show navigatorKey;
import 'package:resident/screens/case/case_screens.dart';
import 'package:resident/screens/case/case_ui.dart';

import 'support/app_harness.dart';
import 'support/case_seed.dart';

Future<void> _open(WidgetTester t, int n) async {
  navigatorKey.currentState!.pushNamed('/report', arguments: caseId(n));
  await settle(t);
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await t.ensureVisible(f.first);
  await t.tap(f.first, warnIfMissed: false);
  await settle(t, rounds: 6);
}

void main() {
  testWidgets('Under Review with details requested: Add details is the one action, the rest is behind More', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    await _open(t, 216);
    final text = screenText();
    for (final s in ['Late-Night Gathering', 'BRG-2026-0116', 'Under Review', 'The barangay is reviewing your report.', 'The barangay needs more details', 'Add details', 'Evidence', 'Full timeline']) {
      expect(text.any((x) => x.contains(s)), isTrue, reason: s);
    }
    expect(find.byType(CaseTrack), findsOneWidget, reason: 'the track shows while the report moves');
    expect(find.text('Ask the barangay'), findsNothing, reason: 'Ask is behind More here');
    await _tap(t, find.byIcon(Icons.more_horiz_rounded));
    expect(find.text('Ask the barangay'), findsOneWidget);
    expect(find.text('Cancel this report'), findsOneWidget);
    await finish(t);
  });

  testWidgets('In Progress with three concerns: each has its own status, the track and one note', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    await _open(t, 301);
    final text = screenText();
    // several concerns: the title is the category
    expect(find.text('Street Obstruction'), findsWidgets);
    for (final s in ['Your concerns', '1 of 3 resolved', 'Illegal Parking', 'Obstructed Sidewalks', 'Vendor Blocking Sidewalks', 'Resolved', 'Being handled', 'A tanod is on it. 1 of 3 concerns is resolved.', 'Latest update']) {
      expect(text.any((x) => x.contains(s)), isTrue, reason: s);
    }
    expect(find.text('Ask the barangay'), findsOneWidget, reason: 'the one main action');
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing, reason: 'nothing else to do while a tanod is on it');
    await finish(t);
  });

  testWidgets('Rejected has Appeal as its action; Cancelled only a quiet Ask and no More', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    await _open(t, 75);
    expect(find.text('Appeal this decision'), findsOneWidget);
    expect(find.text('The barangay’s reason'), findsOneWidget);
    expect(find.byType(CaseTrack), findsNothing, reason: 'no track once it has stopped');
    navigatorKey.currentState!.popUntil((x) => x.isFirst);
    await settle(t);
    await _open(t, 55);
    expect(find.text('Cancelled'), findsWidgets);
    expect(find.text('Ask the barangay'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    expect(find.text('A cancelled case can’t be opened again.'), findsOneWidget);
    await finish(t);
  });

  testWidgets('Completed: the Resolved card, how it was handled, the evidence viewer, the full timeline', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    await _open(t, 297);
    var text = screenText();
    for (final s in ['Your report is resolved.', 'Resolved', 'Tanod’s field report', 'Talked to the household, they lowered the volume. Photo attached.', 'How it was handled', 'Your feedback', 'Evidence']) {
      expect(text.any((x) => x.contains(s)), isTrue, reason: s);
    }
    expect(find.text('Proof'), findsWidgets);
    await _tap(t, find.text('How it was handled'));
    expect(find.text('Hide how it was handled'), findsOneWidget);
    expect(find.text('Tanod dispatched'), findsWidgets);
    // the proof opens in the viewer, with its caption
    await _tap(t, find.bySemanticsLabel('Open the proof photo'));
    expect(find.byType(CaseViewer), findsOneWidget);
    expect(screenText().any((x) => x.contains('Proof of resolution')), isTrue);
    navigatorKey.currentState!.pop();
    await settle(t);
    // your own photo carries the report's words
    await _tap(t, find.byType(CaseThumb).last);
    expect(screenText().any((x) => x.contains('What you sent')), isTrue);
    expect(screenText().any((x) => x.contains('loud karaoke on 15th Street')), isTrue);
    navigatorKey.currentState!.pop();
    await settle(t);
    await _tap(t, find.text('Full timeline'));
    expect(find.byType(CaseTimelineScreen), findsOneWidget);
    for (final s in ['Resolved', 'Tanod dispatched', 'Validated', 'Filed']) {
      expect(find.text(s), findsWidgets, reason: s);
    }
    await finish(t);
  });

  testWidgets('Reopen: pick a reason, one request is sent and the report keeps its status', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    await _open(t, 297);
    await _tap(t, find.byIcon(Icons.more_horiz_rounded));
    await _tap(t, find.text('Reopen this report'));
    expect(find.text('Why are you reopening it?'), findsOneWidget);
    expect(find.text('The problem came back'), findsOneWidget);
    expect(find.text('The proof photo doesn’t match'), findsOneWidget);
    expect(find.text('Other'), findsOneWidget);
    // Other needs words
    await _tap(t, find.text('Other'));
    expect(t.widget<CaseButton>(find.widgetWithText(CaseButton, 'Reopen this report')).onTap, isNull);
    await _tap(t, find.text('The proof photo doesn’t match'));
    await t.enterText(find.byType(TextField), 'The photo is of another street');
    await t.pump();
    await _tap(t, find.widgetWithText(CaseButton, 'Reopen this report'));
    expect(b.calls.where((c) => c == 'rpc request_reopen').length, 1);
    await finish(t);
  });

  testWidgets('Reopen requested: the pill, your reason, the chat opens with the request as its first card', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    await _open(t, 298);
    final text = screenText();
    for (final s in ['Reopen requested', 'You asked the barangay to reopen this report.', 'Your reason', '“The problem came back.”', 'Open the chat']) {
      expect(text.any((x) => x.contains(s)), isTrue, reason: s);
    }
    expect(find.text('Resolved'), findsNothing, reason: 'the Resolved card gives way while a reopen waits');
    expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
    await _tap(t, find.text('Open the chat'));
    expect(find.text('You asked to reopen this report'), findsOneWidget);
    expect(find.text('Reason: The problem came back'), findsOneWidget);
    expect(find.text('Thanks for telling us.'), findsOneWidget);
    expect(find.text('Reopen requested'), findsOneWidget, reason: 'the status band');
    await finish(t);
  });

  testWidgets('the list card says how many concerns are resolved', (t) async {
    final b = await bootApp(t);
    seedCaseData(b);
    navigatorKey.currentState!.pushNamed('/reports');
    await settle(t);
    expect(find.text('3 concerns · 1 resolved'), findsOneWidget);
    await finish(t);
  });
}
