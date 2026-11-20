// Filing a report, on the real screens over the preview backend (Rose, 18-19 Nov 2026): the concerns are the category's
// own pills, picked in any number on the first page and kept to the chosen category (0176), and the draft-restored
// note can be put away without discarding anything.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/d/d_ui.dart' show DButton;
import 'package:resident/main.dart' show navigatorKey;
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';
import 'package:resident/widgets/brgy_map.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';

/// Two categories with option ids (what the barangay's list gives), and Others.
void _catalogue() => ComplaintCatalogue.apply([
      {'key': 'street_obstruction', 'en': 'Street Obstruction', 'fil': 'Sagabal sa Kalsada', 'colour': '#F93535', 'icon': 'street_obstruction', 'active': true,
       'options': [
         {'id': 1, 'en': 'Obstructed Sidewalks', 'active': true},
         {'id': 2, 'en': 'Illegal Parking', 'active': true},
         {'id': 3, 'en': 'Vendor Blocking Sidewalks', 'active': true},
         {'id': 6, 'en': 'Blocked Driveway', 'active': true},
       ]},
      {'key': 'peace_order_nuisance', 'en': 'Peace, Order, & Nuisance', 'fil': 'Kapayapaan, Kaayusan at Istorbo', 'colour': '#E0609A', 'icon': 'peace_order_nuisance', 'active': true,
       'options': [
         {'id': 4, 'en': 'Street Drinking Nuisance', 'active': true},
         {'id': 5, 'en': 'Unreasonable Neighborhood Noise', 'active': true},
       ]},
      {'key': 'other', 'en': 'Others', 'fil': 'Iba pa', 'colour': '#0F9D9A', 'icon': 'other', 'active': true, 'options': []},
    ]);

Future<void> _open(WidgetTester tester, String route, [Object? arguments]) async {
  navigatorKey.currentState!.pushNamed(route, arguments: arguments);
  await settle(tester);
}

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}

void main() {
  setUpAll(() => BrgyMap.nativeView = false);

  testWidgets('the concerns are the category\'s own pills: pick any number up to three, no "add another" step', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    expect(find.text('Add another concern'), findsNothing);
    expect(find.text('Is there more than one problem? (optional)'), findsNothing);
    expect(find.text('1 of 3 picked'), findsNothing, reason: 'nothing chosen yet');
    expect(tester.widget<DButton>(find.widgetWithText(DButton, 'Continue')).onTap, isNull, reason: 'nothing to continue with');

    await _tapVisible(tester, find.text('Illegal Parking'));
    expect(find.text('1 of 3 picked'), findsOneWidget);
    await _tapVisible(tester, find.text('Obstructed Sidewalks'));
    await _tapVisible(tester, find.text('Vendor Blocking Sidewalks'));
    expect(find.text('3 of 3 picked'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3), reason: 'each picked pill shows a tick');

    // Out of picks: the fourth does nothing.
    await _tapVisible(tester, find.text('Blocked Driveway'));
    expect(find.text('3 of 3 picked'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsNWidgets(3));

    // Tapping a picked one puts it down; the first one tapped was the main concern, so the next in line takes over.
    await _tapVisible(tester, find.text('Illegal Parking'));
    expect(find.text('2 of 3 picked'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('+ Vendor Blocking Sidewalks'), findsOneWidget, reason: 'the second page lists the others');
    expect(find.text('+ Obstructed Sidewalks'), findsNothing, reason: 'Obstructed Sidewalks is the main concern now');
    expect(find.text('Add another concern'), findsNothing);
    await finish(tester);
  });

  testWidgets('a report keeps to one category: another one asks first when concerns would go, and Others stands alone', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');

    // One pick moves freely between categories: nothing is lost.
    await _tapVisible(tester, find.text('Illegal Parking'));
    await _tapVisible(tester, find.text('Street Drinking Nuisance'));
    expect(find.text('Change the category?'), findsNothing);
    expect(find.text('1 of 3 picked'), findsOneWidget);
    await _tapVisible(tester, find.text('Unreasonable Neighborhood Noise'));
    expect(find.text('2 of 3 picked'), findsOneWidget);

    // Two picks: another category asks first; keeping the old one changes nothing.
    await _tapVisible(tester, find.text('Obstructed Sidewalks'));
    expect(find.text('Change the category?'), findsOneWidget);
    await tester.tap(find.text('Keep Peace, Order, & Nuisance'));
    await settle(tester);
    expect(find.text('Change the category?'), findsNothing);
    expect(find.text('2 of 3 picked'), findsOneWidget);

    // Back on the dialog closes the dialog only.
    await _tapVisible(tester, find.text('Obstructed Sidewalks'));
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Change the category?'), findsNothing);
    expect(find.text('2 of 3 picked'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget, reason: 'still on the first page');

    // Changing it clears the others and starts again with the one tapped.
    await _tapVisible(tester, find.text('Obstructed Sidewalks'));
    await tester.tap(find.text('Change category'));
    await settle(tester);
    expect(find.text('1 of 3 picked'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    // Others has no pills to add to: it replaces them (asking first, as two were picked).
    await _tapVisible(tester, find.text('Vendor Blocking Sidewalks'));
    expect(find.text('2 of 3 picked'), findsOneWidget);
    await _tapVisible(tester, find.text('Others').last);
    expect(find.text('Change the category?'), findsOneWidget);
    await tester.tap(find.text('Change category'));
    await settle(tester);
    expect(find.textContaining('picked'), findsNothing);
    expect(tester.widget<DButton>(find.widgetWithText(DButton, 'Continue')).onTap, isNotNull, reason: 'Others can continue');
    await finish(tester);
  });

  testWidgets('a pill answers a 48 px touch though it is drawn 30 tall, and no further', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    final pill = find.text('Obstructed Sidewalks');
    await tester.ensureVisible(pill);
    await tester.pump();
    final c = tester.getCenter(pill);

    // 20 px above the middle: 5 px past the drawn top, inside the 9 px the touch reaches.
    await tester.tapAt(c + const Offset(0, -20));
    await settle(tester);
    expect(find.text('1 of 3 picked'), findsOneWidget);
    // and the middle, to put it down again
    await tester.tapAt(c);
    await settle(tester);
    expect(find.textContaining('picked'), findsNothing);

    // 31 px above the middle is outside it
    await tester.tapAt(c + const Offset(0, -31));
    await settle(tester);
    expect(find.textContaining('picked'), findsNothing);
    await finish(tester);
  });

  group('the draft-restored note', () {
    const typed = 'Illegal Parking — a van has blocked the corner all week';
    final choice = CategoryChoice(category: ComplaintCategory.parse('street_obstruction'), issue: 'Illegal Parking', optionId: 2);

    Future<void> openWithDraft(WidgetTester tester) async {
      await bootApp(tester);
      _catalogue();
      await tester.runAsync(() async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('report_draft_v1',
            jsonEncode({'category': 'street_obstruction', 'description': typed, 'photoPaths': <String>[], 'videoPath': null, 'anonymous': false}));
      });
      await _open(tester, '/submit-report/details', choice);
      expect(find.text('Restored your unfinished report.'), findsOneWidget);
      expect(find.text(typed), findsOneWidget);
    }

    Future<String?> savedDraft(WidgetTester tester) async =>
        tester.runAsync<String?>(() async => (await SharedPreferences.getInstance()).getString('report_draft_v1'));

    testWidgets('can be closed, and goes by itself, without discarding', (tester) async {
      await openWithDraft(tester);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.persist, isFalse);
      expect(bar.showCloseIcon, isTrue);
      await tester.tap(find.descendant(of: find.byType(SnackBar), matching: find.byType(IconButton)));
      await settle(tester);
      expect(find.text('Restored your unfinished report.'), findsNothing);
      expect(find.text(typed), findsOneWidget);
      expect(await savedDraft(tester), isNotNull);
      await finish(tester);
    });

    testWidgets('Discard asks first; Keep editing leaves the form as it was', (tester) async {
      await openWithDraft(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      expect(find.text('Discard your unfinished report?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await settle(tester);
      expect(find.text('Discard your unfinished report?'), findsNothing);
      expect(find.text(typed), findsOneWidget);
      expect(await savedDraft(tester), isNotNull);
      await finish(tester);
    });

    testWidgets('Back on the dialog closes the dialog only', (tester) async {
      await openWithDraft(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.text('Discard your unfinished report?'), findsNothing);
      expect(find.text(typed), findsOneWidget, reason: 'still on the form, untouched');
      expect(find.text('Submit'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('Discard, confirmed, empties the form and forgets the draft', (tester) async {
      await openWithDraft(tester);
      await tester.tap(find.text('Discard'));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(Dialog), matching: find.text('Discard')));
      await settle(tester);
      expect(find.text(typed), findsNothing);
      expect(find.text(choice.descriptionPrefill), findsOneWidget, reason: 'back to how a fresh form opens');
      expect(await savedDraft(tester), isNull);
      expect(find.text('Submit'), findsOneWidget, reason: 'still on the form');
      await finish(tester);
    });
  });

  test('the one-category refusal is recognised, and nothing else is', () {
    expect(isOneCategoryRefusal('A report keeps to one category: this concern is under another category'), isTrue);
    expect(isOneCategoryRefusal('Every concern must be under the same category as the report'), isTrue);
    expect(isOneCategoryRefusal('That option is not under this category'), isFalse);
    expect(isOneCategoryRefusal('A report can have at most four concerns'), isFalse);
  });
}
