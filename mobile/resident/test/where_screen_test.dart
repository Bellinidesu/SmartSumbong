// "Where is it?", the second step of filing a report (19 Nov 2026), on the real screens over the preview backend:
// the complaints strip, the address in words, the live outside-Barangay-183 check, typing an address, and the
// details screen's one row with Change. The map itself is a platform view and does not draw in a widget test;
// these are the parts around it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:resident/widgets/d_form.dart';
import 'package:resident/i18n.dart';
import 'package:resident/main.dart' show navigatorKey;
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';
import 'package:resident/place_search.dart';
import 'package:resident/screens/where_screen.dart';
import 'package:resident/widgets/brgy_map.dart';

import 'support/app_harness.dart';

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
       ]},
      {'key': 'other', 'en': 'Others', 'fil': 'Iba pa', 'colour': '#0F9D9A', 'icon': 'other', 'active': true, 'options': []},
    ]);

/// Illegal Parking, with Obstructed Sidewalks and Vendor Blocking Sidewalks as the other concerns.
CategoryChoice _choice() {
  final cat = ComplaintCategory.parse('street_obstruction');
  return CategoryChoice(
    category: cat,
    issue: 'Illegal Parking',
    optionId: 2,
    extras: [for (final o in cat.options.where((o) => o.id == 1 || o.id == 3)) ExtraConcern(cat, o)],
  );
}

/// The Barangay 183 Hall, from assets/map/landmarks.geojson, and a spot well outside the barangay (Makati).
const _hall = LatLng(14.525104, 121.012596);
const _faraway = LatLng(14.5547, 121.0244);

Future<void> _open(WidgetTester tester, String route, [Object? arguments]) async {
  navigatorKey.currentState!.pushNamed(route, arguments: arguments);
  await settle(tester);
}

DFormButton _button(WidgetTester tester, String label) => tester.widget<DFormButton>(find.widgetWithText(DFormButton, label));

void main() {
  setUpAll(() async {
    BrgyMap.nativeView = false;
    // Read in the real zone, once: a future made inside one test's fake-async zone would never deliver to the next test.
    await brgyBoundary();
    await PlaceWords.landmarks();
  });

  tearDown(() {
    PlaceSearch.override = null;
    PlaceWords.reverseOverride = null;
  });

  testWidgets('the sheet says step 2 of 3, shows the strip with +N, the address in words, and Confirm is on inside', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: _hall, accuracyMetres: 12)));

    expect(find.text('STEP 2 OF 3 · WHERE IS IT?'), findsOneWidget);
    // two pills and "+1" for the third
    expect(find.text('Illegal Parking'), findsOneWidget);
    expect(find.text('Obstructed Sidewalks'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('Vendor Blocking Sidewalks'), findsNothing);
    // the nearest landmark on the phone, with no network
    expect(find.text('Near Barangay 183 Hall'), findsOneWidget);
    expect(find.text('Zone 20, Barangay 183 · Villamor, Pasay City'), findsOneWidget);
    expect(find.text('Accurate to about 12 m. Drag the map to move the pin, or type the address above.'), findsOneWidget);
    expect(find.text('That spot is outside Barangay 183'), findsNothing);
    expect(_button(tester, 'Confirm this spot').onTap, isNotNull);
    expect(find.byTooltip('Back'), findsNothing); // the controls speak through Semantics, not tooltips
    expect(find.bySemanticsLabel('Use my location'), findsOneWidget);
    expect(find.bySemanticsLabel('Type an address or landmark'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tapping the strip lists every complaint, read-only', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: _hall)));
    await tester.tap(find.text('+1'));
    await settle(tester);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('Your complaints')), findsOneWidget);
    for (final n in ['Illegal Parking', 'Obstructed Sidewalks', 'Vendor Blocking Sidewalks']) {
      expect(find.descendant(of: sheet, matching: find.text(n)), findsOneWidget, reason: n);
    }
    await tester.tap(find.descendant(of: sheet, matching: find.text('Done')));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    await finish(tester);
  });

  testWidgets('outside Barangay 183 the notice shows, Confirm is off, and Take me back puts the pin inside', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: _faraway)));

    expect(find.text('That spot is outside Barangay 183'), findsOneWidget);
    expect(find.text('A tanod can only be sent inside the barangay. Move the pin into the clear area of the map.'), findsOneWidget);
    expect(_button(tester, 'Confirm this spot').onTap, isNull);
    expect(find.text('Zone 20, Barangay 183 · Villamor, Pasay City'), findsNothing, reason: 'the address card gives way to the notice');

    await tester.tap(find.text('Take me back to Barangay 183'));
    await settle(tester);
    expect(find.text('That spot is outside Barangay 183'), findsNothing);
    expect(_button(tester, 'Confirm this spot').onTap, isNotNull);
    expect(find.text('Zone 20, Barangay 183 · Villamor, Pasay City'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('typing an address offers places; picking one moves the pin, fills the field and updates the words', (tester) async {
    await bootApp(tester);
    _catalogue();
    const eighth = LatLng(14.5262, 121.0141);
    final asked = <String>[];
    PlaceSearch.override = (q) async {
      asked.add(q);
      return const [
        PlaceHit('8th Street', 'Street · Barangay 183', eighth),
        PlaceHit('8th Street Extension', 'Street · Barangay 183', LatLng(14.5265, 121.0150)),
      ];
    };
    final result = navigatorKey.currentState!.pushNamed<WhereResult>(
      '/submit-report/where',
      arguments: WhereArgs(_choice(), current: const WhereResult(pin: _hall, accuracyMetres: 12), returnResult: true),
    );
    await settle(tester);
    expect(find.text('Near Barangay 183 Hall'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '8th Str');
    await tester.pump(const Duration(milliseconds: 600));
    await settle(tester);
    expect(asked, ['8th Str']);
    expect(find.text('8th Street Extension'), findsOneWidget);
    expect(find.text('Pick a suggestion and the pin moves there. The address updates.'), findsOneWidget);

    await tester.tap(find.text('8th Street Extension'));
    await settle(tester);
    expect(find.text('Near 8th Street Extension'), findsOneWidget);
    expect(find.text('Near Barangay 183 Hall'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, '8th Street Extension');
    expect(find.text('Pick a suggestion and the pin moves there. The address updates.'), findsNothing);

    await tester.tap(find.text('Confirm this spot'));
    await settle(tester);
    final r = (await tester.runAsync(() => result))!;
    expect(r.pin, const LatLng(14.5265, 121.0150));
    expect(r.near, '8th Street Extension');
    expect(r.accuracyMetres, isNull, reason: 'a picked place is not a GPS fix');
    await finish(tester);
  });

  testWidgets('with no landmark near, the words come from the reverse lookup, and a lookup that fails says Near your pin', (tester) async {
    await bootApp(tester);
    _catalogue();
    final answer = Completer<String?>();
    PlaceWords.reverseOverride = (lat, lng) => answer.future;
    // a spot in the barangay with no landmark within 60 m
    const quiet = LatLng(14.5281, 121.0149);
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: quiet, accuracyMetres: 9)));
    expect(find.text('Near your pin'), findsOneWidget, reason: 'until the lookup answers; Confirm is not held up');
    expect(_button(tester, 'Confirm this spot').onTap, isNotNull);
    answer.complete('13th Street');
    await settle(tester);
    expect(find.text('Near 13th Street'), findsOneWidget);
    await finish(tester);

    await bootApp(tester);
    _catalogue();
    PlaceWords.reverseOverride = (lat, lng) async => null;
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: quiet)));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('Near your pin'), findsOneWidget);
    expect(_button(tester, 'Confirm this spot').onTap, isNotNull);
    await finish(tester);
  });

  testWidgets('page one goes to Where is it?, Confirm goes to the details with the spot as one row, Change reopens Where', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    await tester.tap(find.text('Illegal Parking'));
    await settle(tester);
    await tester.tap(find.text('Obstructed Sidewalks'));
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    expect(find.text('STEP 2 OF 3 · WHERE IS IT?'), findsOneWidget);
    expect(find.text('Describe what happened'), findsNothing);
    await tester.tap(find.text('Confirm this spot'));
    await settle(tester);

    // step 3: the location is one row, not a map; the sections are renumbered
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Street Obstruction'), findsOneWidget, reason: 'the category is the title');
    expect(find.text('Near your pin'), findsOneWidget);
    expect(find.text('Zone 20, Barangay 183'), findsOneWidget);
    expect(find.text('Choose location'), findsNothing);
    expect(find.byType(TextField), findsNothing, reason: 'the description is a preview now; the address search lives on the Where screen');
    final one = find.ancestor(of: find.text('Describe what happened'), matching: find.byType(Row)).first;
    expect(find.descendant(of: one, matching: find.text('1')), findsOneWidget);
    final two = find.ancestor(of: find.text('Attach your photo'), matching: find.byType(Row)).first;
    expect(find.descendant(of: two, matching: find.text('2')), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);

    await tester.tap(find.text('Change'));
    await settle(tester);
    expect(find.text('STEP 2 OF 3 · WHERE IS IT?'), findsOneWidget);
    await tester.tap(find.text('Confirm this spot'));
    await settle(tester);
    expect(find.text('Step 3 of 3'), findsOneWidget, reason: 'back on the details, not a second details screen under it');
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.text('STEP 2 OF 3 · WHERE IS IT?'), findsOneWidget, reason: 'Back from the details is the step before it');
    await finish(tester);
  });

  testWidgets('the details page: the strip is one row with +N and no stacked chips, then the location row, the preview, the photo tiles and the video row', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/details', DetailsArgs(_choice(), const WhereResult(pin: _hall, near: 'Barangay 183 Hall')));
    final a = tester.getTopLeft(find.text('Illegal Parking').first);
    final b = tester.getTopLeft(find.text('Obstructed Sidewalks'));
    expect(b.dy, a.dy, reason: 'one row');
    expect(b.dx, greaterThan(a.dx));
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('Vendor Blocking Sidewalks'), findsNothing);
    expect(find.textContaining('+ Obstructed'), findsNothing);
    // the order down the page: header, strip, location, 1 Describe, 2 Attach
    double y(String t) => tester.getTopLeft(find.text(t).first).dy;
    expect(y('Street Obstruction'), lessThan(y('Illegal Parking')));
    expect(y('Illegal Parking'), lessThan(y('Near Barangay 183 Hall')));
    expect(y('Near Barangay 183 Hall'), lessThan(y('Describe what happened')));
    expect(y('Describe what happened'), lessThan(y('Attach your photo')));
    expect(find.text('Tap to write more'), findsOneWidget);
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('0 of 5 photos'), findsOneWidget);
    expect(find.text('Attach a short video (optional)'), findsOneWidget);
    expect(find.text('(Max: 25 MB, about 30 seconds)'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Submit'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the Describe pop-up opens from the preview, takes the text, and Done and the cross both write it back', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/details', DetailsArgs(_choice(), const WhereResult(pin: _hall)));
    await tester.tap(find.text('Tap to write more'));
    await settle(tester);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('Describe what happened')), findsOneWidget);
    // every picked concern, as context
    for (final n in ['Illegal Parking', 'Obstructed Sidewalks', 'Vendor Blocking Sidewalks']) {
      expect(find.descendant(of: sheet, matching: find.text(n)), findsOneWidget, reason: n);
    }
    expect(find.text('Helpful to add: when it started, who or what is involved, a landmark nearby.'), findsOneWidget);
    expect(find.text('18 characters'), findsOneWidget, reason: 'the prefill "Illegal Parking — "');
    await tester.enterText(find.descendant(of: sheet, matching: find.byType(TextField)), 'Illegal Parking — a van has blocked the corner all week.');
    await settle(tester);
    expect(find.text('56 characters'), findsOneWidget);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Done')));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Illegal Parking — a van has blocked the corner all week.'), findsOneWidget, reason: 'the preview shows what was written');

    // the cross keeps the text too
    await tester.tap(find.text('Tap to write more'));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'Illegal Parking — and again on Friday.');
    await tester.tap(find.bySemanticsLabel('Close'));
    await settle(tester);
    expect(find.text('Illegal Parking — and again on Friday.'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the complaints pop-up: a pill is put down and picked up again, up to three, one category; the strip follows', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: _hall)));
    await tester.tap(find.text('+1'));
    await settle(tester);
    final sheet = find.byType(BottomSheet);
    expect(find.descendant(of: sheet, matching: find.text('Tap a pill to add or remove it, up to 3. A report keeps to one category.')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('3 of 3 picked · tap one to swap')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Street Obstruction')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Street Drinking Nuisance')), findsNothing, reason: 'one category only');
    expect(find.descendant(of: sheet, matching: find.text('See all categories')), findsOneWidget);

    // out of picks: a fourth does nothing; put one down and the counter says so
    await tester.tap(find.descendant(of: sheet, matching: find.text('Blocked Driveway')));
    await settle(tester);
    expect(find.descendant(of: sheet, matching: find.text('3 of 3 picked · tap one to swap')), findsOneWidget);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Vendor Blocking Sidewalks')));
    await settle(tester);
    expect(find.descendant(of: sheet, matching: find.text('2 of 3 picked')), findsOneWidget);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Blocked Driveway')));
    await settle(tester);
    expect(find.descendant(of: sheet, matching: find.text('3 of 3 picked · tap one to swap')), findsOneWidget);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Done')));
    await settle(tester);
    expect(find.byType(BottomSheet), findsNothing);
    // the strip: Illegal Parking stays the main concern, then Obstructed Sidewalks; Blocked Driveway is the third (+1)
    expect(find.text('Illegal Parking'), findsOneWidget);
    expect(find.text('Obstructed Sidewalks'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    await tester.tap(find.text('+1'));
    await settle(tester);
    expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('Vendor Blocking Sidewalks')), findsOneWidget, reason: 'put down, so a pill again');
    await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Done')));
    await settle(tester);
    await finish(tester);
  });

  testWidgets('See all categories in the pop-up goes back to page one, which keeps the picks', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report');
    await tester.tap(find.text('Illegal Parking'));
    await settle(tester);
    await tester.tap(find.text('Continue'));
    await settle(tester);
    await tester.tap(find.text('Illegal Parking')); // the strip
    await settle(tester);
    final sheet = find.byType(BottomSheet);
    await tester.tap(find.descendant(of: sheet, matching: find.text('Vendor Blocking Sidewalks')));
    await settle(tester);
    await tester.tap(find.descendant(of: sheet, matching: find.text('See all categories')));
    await settle(tester);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('2 of 3 picked'), findsOneWidget, reason: 'what was changed in the pop-up');
    await finish(tester);
  });

  testWidgets('Take me back to Barangay 183 targets the residential centre, and the Frame button on the Map tab does too', (tester) async {
    await bootApp(tester);
    _catalogue();
    final result = navigatorKey.currentState!.pushNamed<WhereResult>(
      '/submit-report/where',
      arguments: WhereArgs(_choice(), current: const WhereResult(pin: _faraway), returnResult: true),
    );
    await settle(tester);
    await tester.tap(find.text('Take me back to Barangay 183'));
    await settle(tester);
    await tester.tap(find.text('Confirm this spot'));
    await settle(tester);
    final r = (await tester.runAsync(() => result))!;
    expect(r.pin, brgyCentre, reason: "the portal's RESIDENTIAL_CENTRE, not the OSM relation's centroid");
    await finish(tester);

    // the Frame button of the bounded Map tab: back to the residential centre at zoom 16, whatever the pins
    final ctl = BrgyMapController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 390,
          height: 700,
          child: BrgyMap(
            use: BrgyMapUse.browse,
            controller: ctl,
            initialCenter: const LatLng(14.52, 121.02),
            pins: const [BrgyMapPin(id: 'a', point: LatLng(14.5205, 121.0205), colour: Color(0xFFF93535), glyph: 'street_obstruction')],
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.bySemanticsLabel('Frame the map').first);
    await tester.pump();
    expect(ctl.lastMove, (brgyCentre, 16.0));
  });

  testWidgets('the details screen still refuses a spot outside the barangay when the report is sent', (tester) async {
    await bootApp(tester);
    _catalogue();
    await _open(tester, '/submit-report/details', DetailsArgs(_choice(), const WhereResult(pin: _faraway, near: 'Somewhere')));
    expect(find.text('Near Somewhere'), findsOneWidget);
    await tester.tap(find.text('Submit'));
    await settle(tester);
    expect(find.textContaining('outside Barangay 183'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Tagalog: the step, the notice and the row speak Filipino', (tester) async {
    await bootApp(tester);
    _catalogue();
    final scope = tester.element(find.byType(Scaffold).first).getElementForInheritedWidgetOfExactType<AppLocaleScope>()!.widget as AppLocaleScope;
    scope.notifier!.value = AppLocale.fil;
    await settle(tester);
    await _open(tester, '/submit-report/where', WhereArgs(_choice(), current: const WhereResult(pin: _faraway)));
    expect(find.text('HAKBANG 2 NG 3 · SAAN ITO?'), findsOneWidget);
    expect(find.text('Nasa labas ng Barangay 183 ang lugar na iyon'), findsOneWidget);
    expect(find.text('Ibalik ako sa Barangay 183'), findsOneWidget);
    expect(find.text('Kumpirmahin ang lugar na ito'), findsOneWidget);
    await finish(tester);
  });
}
