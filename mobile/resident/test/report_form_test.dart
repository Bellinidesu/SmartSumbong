// Filing a report, on the real screens over the preview backend (Rose, 18 Nov 2026): the other concerns are picked
// on the first page and keep to the chosen category (0176), and the draft-restored note can be put away without
// discarding anything.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/main.dart' show navigatorKey;
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';
import 'package:resident/screens/where_screen.dart';
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
       ]},
      {'key': 'peace_order_nuisance', 'en': 'Peace, Order, & Nuisance', 'fil': 'Kapayapaan, Kaayusan at Istorbo', 'colour': '#E0609A', 'icon': 'peace_order_nuisance', 'active': true,
       'options': [
         {'id': 4, 'en': 'Street Drinking Nuisance', 'active': true},
         {'id': 5, 'en': 'Unreasonable Neighborhood Noise', 'active': true},
       ]},
      {'key': 'other', 'en': 'Others', 'fil': 'Iba pa', 'colour': '#0F9D9A', 'icon': 'other', 'active': true, 'options': []},
    ]);

Finder _inSheet(String text) => find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

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

  testWidgets('the other concerns are on the first page, and only the chosen category\'s are offered', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    const more = 'Is there more than one problem? (optional)';
    expect(find.text(more), findsNothing, reason: 'nothing chosen yet');

    await _tapVisible(tester, find.text('Illegal Parking'));
    expect(find.text(more), findsOneWidget);
    await _tapVisible(tester, find.text('Add another concern'));
    expect(_inSheet('Obstructed Sidewalks'), findsOneWidget);
    expect(_inSheet('Vendor Blocking Sidewalks'), findsOneWidget);
    expect(_inSheet('Illegal Parking'), findsNothing, reason: 'already the main concern');
    expect(_inSheet('Street Drinking Nuisance'), findsNothing, reason: 'a second category is not offered');
    expect(_inSheet('Others'), findsNothing);
    await tester.tap(_inSheet('Obstructed Sidewalks'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Remove Obstructed Sidewalks'), findsOneWidget);

    // Another category asks first; keeping the old one changes nothing.
    await _tapVisible(tester, find.text('Street Drinking Nuisance'));
    expect(find.text('Change the category?'), findsOneWidget);
    await tester.tap(find.text('Keep Street Obstruction'));
    await settle(tester);
    expect(find.text('Change the category?'), findsNothing);
    expect(find.byTooltip('Remove Obstructed Sidewalks'), findsOneWidget);

    // Back on the dialog closes the dialog only.
    await _tapVisible(tester, find.text('Street Drinking Nuisance'));
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('Change the category?'), findsNothing);
    expect(find.byTooltip('Remove Obstructed Sidewalks'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget, reason: 'still on the first page');

    // Changing it clears the other concerns.
    await _tapVisible(tester, find.text('Street Drinking Nuisance'));
    await tester.tap(find.text('Change category'));
    await settle(tester);
    expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Remove ')), findsNothing);
    await _tapVisible(tester, find.text('Add another concern'));
    expect(_inSheet('Unreasonable Neighborhood Noise'), findsOneWidget);
    expect(_inSheet('Obstructed Sidewalks'), findsNothing);
    await tester.tap(_inSheet('Unreasonable Neighborhood Noise'));
    await settle(tester);

    // The second step is where it is; the third shows them, and has no picker of its own.
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('Confirm this spot'), findsOneWidget);
    await tester.tap(find.text('Confirm this spot'));
    await settle(tester);
    expect(find.text('+ Unreasonable Neighborhood Noise'), findsOneWidget);
    expect(find.text(more), findsNothing);
    expect(find.text('Add another concern'), findsNothing);
    await finish(tester);
  });

  testWidgets('a picked concern becomes the main one when its pill is tapped, and Others has no picker', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    await _tapVisible(tester, find.text('Illegal Parking'));
    await _tapVisible(tester, find.text('Add another concern'));
    await tester.tap(_inSheet('Vendor Blocking Sidewalks'));
    await settle(tester);
    // its pill (the chip under the pills carries the same name)
    await _tapVisible(tester, find.text('Vendor Blocking Sidewalks').first);
    expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Remove ')), findsNothing, reason: 'it is the main concern now, not another one');
    await _tapVisible(tester, find.text('Others').last);
    expect(find.text('Is there more than one problem? (optional)'), findsNothing);
    await finish(tester);
  });

  testWidgets('the remove cross answers a 48 x 48 touch around it, and the rest of the name does not', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    Finder chips() => find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith('Remove '));
    Future<void> add(String name) async {
      await _tapVisible(tester, find.text('Add another concern'));
      await tester.tap(_inSheet(name));
      await settle(tester);
    }

    // Street Obstruction: the main one and two more.
    await _tapVisible(tester, find.text('Illegal Parking'));
    await add('Obstructed Sidewalks');
    await add('Vendor Blocking Sidewalks');
    expect(chips(), findsNWidgets(2));
    final cross = tester.getCenter(find.byTooltip('Remove Obstructed Sidewalks'));
    final pill = tester.getRect(find.ancestor(of: find.byTooltip('Remove Obstructed Sidewalks'), matching: find.byType(Container)).first);
    expect(pill.height, lessThan(48), reason: 'drawn as before');
    // far along the name: nothing
    await tester.tapAt(cross + const Offset(-60, 0));
    await settle(tester);
    expect(chips(), findsNWidgets(2));
    // over the end of the name and above the pill, 21 px from the cross's middle each way
    await tester.tapAt(cross + const Offset(-28, -21));
    await settle(tester);
    expect(find.byTooltip('Remove Obstructed Sidewalks'), findsNothing);
    expect(chips(), findsOneWidget);
    // past the cross, in the pill's end
    final cross2 = tester.getCenter(find.byTooltip('Remove Vendor Blocking Sidewalks'));
    await tester.tapAt(cross2 + const Offset(15, 0));
    await settle(tester);
    expect(chips(), findsNothing);

    // below the pill, in the card's padding: a category with one option left, so nothing sits under the chip
    await _tapVisible(tester, find.text('Street Drinking Nuisance'));
    await add('Unreasonable Neighborhood Noise');
    expect(chips(), findsOneWidget);
    final cross3 = tester.getCenter(find.byTooltip('Remove Unreasonable Neighborhood Noise'));
    await tester.tapAt(cross3 + const Offset(0, 21));
    await settle(tester);
    expect(chips(), findsNothing);
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
      await _open(tester, '/submit-report/details', DetailsArgs(choice, const WhereResult(pin: brgyCentre)));
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
