// The resident's Map tab (20 Nov 2026), as the Map tab artifact draws it, on the real screens over the preview backend: the
// chips that are the legend and the filter, the Layers sheet, the round Frame 183 button with no zoom buttons, the pin's
// small card and the case card it expands into, and what the tab says when there is nothing to draw. The native map is a
// platform view and does not draw in a widget test; the pins a test "taps" are handed to the map's own callback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:resident/i18n.dart';
import 'package:resident/main.dart' show navigatorKey;
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/preview/demo_data.dart' show demoResidentId;
import 'package:resident/preview/fake_backend.dart';
import 'package:resident/screens/report_view_screen.dart';
import 'package:resident/widgets/brgy_map.dart';
import 'package:resident/widgets/category_card.dart' show concernFill;
import 'package:resident/widgets/map_tab_ui.dart';

import 'support/app_harness.dart';

String _rid(int n) => 'b1000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

void _seed(DemoBackend b, {bool reports = true}) {
  ComplaintCatalogue.apply([
    {'key': 'street_obstruction', 'en': 'Street Obstruction', 'fil': 'Sagabal sa Kalsada', 'colour': '#F93535', 'icon': 'street_obstruction', 'active': true, 'options': []},
    {'key': 'peace_order_nuisance', 'en': 'Peace, Order, & Nuisance', 'fil': 'Katahimikan at Kaayusan', 'colour': '#E0609A', 'icon': 'peace_order_nuisance', 'active': true, 'options': []},
    {'key': 'public_safety_infrastructure', 'en': 'Public Safety and Infrastructure', 'fil': 'Kaligtasan at Imprastraktura', 'colour': '#356CF9', 'icon': 'public_safety_infrastructure', 'active': true, 'options': []},
    {'key': 'environmental_waste_hazard', 'en': 'Environmental and Waste Hazards', 'fil': 'Kapaligiran at Basura', 'colour': '#F9AB35', 'icon': 'environmental_waste_hazard', 'active': true, 'options': []},
    {'key': 'traffic_violation', 'en': 'Traffic Violation', 'fil': 'Paglabag sa Trapiko', 'colour': '#8E9ABB', 'icon': 'traffic_violation', 'active': true, 'options': []},
    {'key': 'other', 'en': 'Others', 'fil': 'Iba pa', 'colour': '#0F9D9A', 'icon': 'other', 'active': true, 'options': []},
  ]);
  final rows = b.table('reports')..clear();
  if (!reports) return;
  Map<String, dynamic> rep(int n, String tracking, String category, String subject, String status, String label, double lat, double lng, {String? office}) => {
        'id': _rid(n), 'resident_id': demoResidentId, 'tracking_id': tracking, 'category': category, 'subject': subject, 'description': subject,
        'status': status, 'latitude': lat, 'longitude': lng, 'location_label': label, 'is_anonymous': false, 'created_at': '2026-11-17T09:53:00Z',
        'resolved_at': null, 'closed_at': null, 'reopened_count': 0, 'due_at': '2099-01-01T00:00:00Z', 'referred_to': office, 'referral_note': null,
        'followed_up_at': null, 'deleted_at': null,
      };
  rows.addAll([
    rep(216, 'BRG-2026-0116', 'peace_order_nuisance', 'Late-Night Gathering', 'pending_review', '7th Street', 14.52674, 121.01415),
    rep(301, 'BRG-2026-0201', 'street_obstruction', 'Illegal Parking', 'in_progress', '8th Street', 14.52487, 121.01672),
    rep(297, 'BRG-2026-0197', 'peace_order_nuisance', 'Unreasonable Neighborhood Noise', 'resolved', '15th Street', 14.52820, 121.01780),
    rep(306, 'BRG-2026-0206', 'public_safety_infrastructure', 'Poor Street Lighting', 'rejected', '9th Street', 14.52300, 121.01522),
  ]);
  b.table('report_concerns')
    ..clear()
    ..addAll([
      {'report_id': _rid(301), 'category': 'street_obstruction', 'status': 'resolved', 'created_at': '2026-11-17T09:53:00Z'},
      {'report_id': _rid(301), 'category': 'street_obstruction', 'status': 'open', 'created_at': '2026-11-17T09:54:00Z'},
      {'report_id': _rid(301), 'category': 'street_obstruction', 'status': 'open', 'created_at': '2026-11-17T09:55:00Z'},
    ]);
  b.table('status_logs')
    ..clear()
    ..add({'id': 'L1', 'report_id': _rid(301), 'old_status': 'assigned', 'new_status': 'in_progress', 'remark': 'Tanod dispatched', 'created_at': DateTime.now().toUtc().subtract(const Duration(hours: 2)).toIso8601String()});
}

Future<DemoBackend> _openMap(WidgetTester tester, {bool reports = true}) async {
  final b = await bootApp(tester);
  _seed(b, reports: reports);
  navigatorKey.currentState!.pushNamed('/map');
  await settle(tester);
  return b;
}

BrgyMap _map(WidgetTester t) => t.widget<BrgyMap>(find.byType(BrgyMap));

Future<void> _pick(WidgetTester t, String id) async {
  _map(t).onPinTap!(id);
  await settle(t, rounds: 4);
}

Future<void> _chip(WidgetTester t, String label) async {
  final f = find.textContaining(label).first;
  await t.ensureVisible(f);
  await t.pump(const Duration(milliseconds: 200));
  await t.tap(f);
  await settle(t, rounds: 3);
}

Future<void> _layers(WidgetTester t) async {
  await t.tap(find.byType(MapFab).first);
  await settle(t, rounds: 4);
}

void main() {
  setUpAll(() => BrgyMap.nativeView = false);

  testWidgets('the tab is the artifact: chips, Layers and Frame 183, no zoom buttons and no eye card', (t) async {
    final sem = t.ensureSemantics();
    await _openMap(t);
    expect(find.text('Barangay 183 Map'), findsOneWidget);
    expect(find.text('Your reports on the barangay map'), findsOneWidget);
    // the chips: My reports (4 of the resident's own), Notices (the barangay's published ones), then a chip per category
    expect(find.bySemanticsLabel('My reports, 4'), findsOneWidget);
    expect(find.bySemanticsLabel('Notices, 3'), findsOneWidget);
    expect(find.textContaining('Street Obstruction'), findsOneWidget);
    expect(find.bySemanticsLabel('Frame 183'), findsOneWidget);
    expect(find.bySemanticsLabel('Layers'), findsOneWidget);
    // Google-style: pinch and double-tap, so no +/- and no eye card
    expect(find.bySemanticsLabel('Zoom in'), findsNothing);
    expect(find.bySemanticsLabel('Zoom out'), findsNothing);
    expect(find.text('Want to see your reports?'), findsNothing);
    expect(find.byType(BrgyMapLayersTile), findsNothing);
    // the map is the Map tab's own use; My reports is on, Dim outside is off
    final map = _map(t);
    expect(map.use, BrgyMapUse.tab);
    expect(map.use.zoomButtons, isFalse);
    expect(map.pins.length, 7);
    expect(map.dimOutside, isFalse);
    expect(map.showPlaces, isTrue);
    sem.dispose();
    await finish(t);
  });

  testWidgets('Frame 183 puts the map back on the residential centre at zoom 16, never a fit to the pins', (t) async {
    await _openMap(t);
    final ctl = _map(t).controller!;
    ctl.move(const LatLng(14.5300, 121.0200), 18);
    await t.tap(find.byType(MapFab).last);
    await settle(t, rounds: 2);
    expect(ctl.lastMove, (brgyCentre, 16.0));
    await finish(t);
  });

  testWidgets('the touch targets are 44 px or more: the chips, the two buttons, the Layers tiles', (t) async {
    final sem = t.ensureSemantics();
    await _openMap(t);
    for (final label in ['My reports, 4', 'Notices, 3', 'Frame 183', 'Layers']) {
      final r = t.getSemantics(find.bySemanticsLabel(label)).rect;
      expect(r.height, greaterThanOrEqualTo(44), reason: label);
      expect(r.width, greaterThanOrEqualTo(44), reason: label);
    }
    await _layers(t);
    for (final label in ['My reports', 'Barangay notices', 'Places', 'Dim outside 183', 'Rain watch', 'Close']) {
      final f = find.descendant(of: find.byType(BottomSheet), matching: find.bySemanticsLabel(label));
      final r = t.getSemantics(f).rect;
      expect(r.height, greaterThanOrEqualTo(44), reason: label);
      expect(r.width, greaterThanOrEqualTo(44), reason: label);
    }
    sem.dispose();
    await finish(t);
  });

  testWidgets('the Layers sheet: five tiles, on or off; Notices off takes its chip and pins away; Dim is the map\'s', (t) async {
    await _openMap(t);
    await _layers(t);
    expect(find.text('Layers'), findsWidgets);
    expect(find.text('MAP DETAILS'), findsOneWidget);
    for (final n in ['My reports', 'Barangay notices', 'Places', 'Dim outside 183', 'Rain watch']) {
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text(n)), findsOneWidget, reason: n);
    }
    expect(find.text('Layers choose what is drawn. The chips on the map narrow it down.'), findsOneWidget);
    // Barangay notices off: its pins and its chip go
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Barangay notices')));
    await settle(t, rounds: 2);
    expect(_map(t).pins.length, 4);
    // Dim outside on, Places off: the map is told
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Dim outside 183')));
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Places')));
    await settle(t, rounds: 2);
    expect(_map(t).dimOutside, isTrue);
    expect(_map(t).showPlaces, isFalse);
    // Close
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byType(InkWell)).first);
    await settle(t, rounds: 3);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Notices'), findsNothing);
    await finish(t);
  });

  testWidgets('a chip narrows the pins and the other chips; choosing it again clears it; no match says so', (t) async {
    await _openMap(t);
    await _chip(t, 'Peace');
    expect(_map(t).pins.map((p) => p.id), unorderedEquals([_rid(216), _rid(297)]));
    await _chip(t, 'Peace');
    expect(_map(t).pins.length, 7);
    // Notices only, then a category the notices do not have
    await _chip(t, 'Notices');
    expect(_map(t).pins.length, 3);
    await _chip(t, 'Peace');
    expect(_map(t).pins, isEmpty);
    expect(find.text('Nothing matches this filter'), findsOneWidget);
    await t.tap(find.text('Show all'));
    await settle(t, rounds: 3);
    expect(_map(t).pins.length, 7);
    expect(find.text('Nothing matches this filter'), findsNothing);
    await finish(t);
  });

  testWidgets('a pin of the resident\'s own opens the small card: status pill, 3 concerns, the track, the age, Open this report', (t) async {
    await _openMap(t);
    await _pick(t, _rid(301));
    expect(find.byType(MapPeekCard), findsOneWidget);
    expect(find.text('Street Obstruction'), findsWidgets);
    expect(find.text('Illegal Parking'), findsOneWidget);
    expect(find.text('In Progress'), findsOneWidget);
    expect(find.textContaining('BRG-2026-0201'), findsOneWidget);
    expect(find.text('3 concerns · 1 resolved'), findsOneWidget);
    expect(find.text('Tanod dispatched · updated 2 hours ago'), findsOneWidget);
    expect(find.text('Open this report'), findsOneWidget);
    // the pin is drawn larger, and the map was panned (never zoomed) to keep it clear above the card
    expect(_map(t).selectedPinId, _rid(301));
    final cam = _map(t).controller!.camera.value;
    expect(cam, isNotNull);
    expect(cam!.$2, 16.0, reason: 'the camera pans; the zoom stays');
    expect(cam.$1.latitude, lessThan(14.52487), reason: 'the centre sits south of the pin, so the pin is above the card');
    // the Layers and Frame buttons stay clear above the card
    final cardTop = t.getTopLeft(find.byType(MapPeekCard)).dy;
    expect(t.getBottomLeft(find.byType(MapFab).first).dy, lessThan(cardTop));
    expect(t.getBottomLeft(find.byType(MapFab).last).dy, lessThan(cardTop));
    // a tap on the map elsewhere closes it
    _map(t).onMapTap!();
    await settle(t, rounds: 3);
    expect(find.byType(MapPeekCard), findsNothing);
    await finish(t);
  });

  testWidgets('a report with one concern has no tag; a rejected one stops its track in red', (t) async {
    await _openMap(t);
    await _pick(t, _rid(306));
    expect(find.byType(MapPeekCard), findsOneWidget);
    expect(find.textContaining('concerns'), findsNothing);
    expect(find.text('Rejected'), findsWidgets);
    final card = t.widget<MapPeekCard>(find.byType(MapPeekCard));
    expect(card.data.track.stop, 1);
    expect(card.data.track.stopRed, isTrue);
    await finish(t);
  });

  testWidgets('the handle expands the card into the portal\'s case card over the bottom bar; the map pans to keep the pin; it folds back', (t) async {
    await _openMap(t);
    await _pick(t, _rid(301));
    final small = _map(t).controller!.camera.value!;
    await t.tapAt(t.getTopLeft(find.byType(MapPeekCard)) + Offset(t.getSize(find.byType(MapPeekCard)).width / 2, 10));
    await settle(t, rounds: 4);
    expect(find.byType(MapBigCard), findsOneWidget);
    expect(find.byType(MapPeekCard), findsNothing);
    expect(find.text('Barangay 183, Zone 20, Villamor, Pasay City'), findsOneWidget);
    for (final step in ['Filed', 'Validated', 'Tanod dispatched', 'Resolved']) {
      expect(find.text(step), findsOneWidget, reason: step);
    }
    // the big card hides the map further, so the map moved the pin higher: the centre is further south
    final big = _map(t).controller!.camera.value!;
    expect(big.$1.latitude, lessThan(small.$1.latitude));
    // the bar under it is covered
    expect(t.getRect(find.byType(MapBigCard)).bottom, closeTo(t.view.physicalSize.height / t.view.devicePixelRatio, .5));
    // the handle folds it back
    await t.tapAt(t.getTopLeft(find.byType(MapBigCard)) + Offset(t.getSize(find.byType(MapBigCard)).width / 2, 10));
    await settle(t, rounds: 4);
    expect(find.byType(MapPeekCard), findsOneWidget);
    expect(find.byType(MapBigCard), findsNothing);
    await finish(t);
  });

  testWidgets('a tap anywhere on the small card, and the button on either card, open the report', (t) async {
    await _openMap(t);
    await _pick(t, _rid(301));
    // the title is no button of its own: the whole card is
    await t.tap(find.text('Illegal Parking'));
    await settle(t, rounds: 6);
    expect(find.byType(ReportViewScreen), findsOneWidget);
    navigatorKey.currentState!.pop();
    await settle(t, rounds: 4);
    // the button
    await t.tap(find.text('Open this report'));
    await settle(t, rounds: 6);
    expect(find.byType(ReportViewScreen), findsOneWidget);
    navigatorKey.currentState!.pop();
    await settle(t, rounds: 4);
    // and on the big card, the button and a tap on its words
    await t.tapAt(t.getTopLeft(find.byType(MapPeekCard)) + Offset(t.getSize(find.byType(MapPeekCard)).width / 2, 10));
    await settle(t, rounds: 4);
    await t.tap(find.text('Illegal Parking'));
    await settle(t, rounds: 6);
    expect(find.byType(ReportViewScreen), findsOneWidget);
    navigatorKey.currentState!.pop();
    await settle(t, rounds: 4);
    await t.tap(find.text('Open this report'));
    await settle(t, rounds: 6);
    expect(find.byType(ReportViewScreen), findsOneWidget);
    await finish(t);
  });

  testWidgets('a published incident (the barangay\'s, not the resident\'s) says so and has no button', (t) async {
    await _openMap(t);
    await _pick(t, 'pub:p1');
    expect(find.byType(MapPeekCard), findsOneWidget);
    expect(find.text('Published by the barangay'), findsOneWidget);
    expect(find.text('Open this report'), findsNothing);
    expect(find.textContaining('Details stay private'), findsOneWidget);
    await finish(t);
  });

  testWidgets('no reports yet: a designed state with the one orange action; Notices off with nothing left hides the rest', (t) async {
    await _openMap(t, reports: false);
    // the barangay's published ones still draw, so turn them off to see the resident's own empty map
    await _layers(t);
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Barangay notices')));
    await t.tapAt(const Offset(195, 60));
    await settle(t, rounds: 4);
    expect(find.text('No reports yet'), findsOneWidget);
    expect(find.text('The reports you file show up here as pins.'), findsOneWidget);
    expect(find.text('Report a concern'), findsOneWidget);
    expect(_map(t).pins, isEmpty);
    // both layers off: a different state, with a way back to Layers
    await _layers(t);
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('My reports')));
    await t.tapAt(const Offset(195, 60));
    await settle(t, rounds: 4);
    expect(find.text('Reports and notices are hidden'), findsOneWidget);
    expect(find.text('Report a concern'), findsNothing);
    await finish(t);
  });

  testWidgets('it speaks Filipino: the chips, the sheet, the small card and its notes', (t) async {
    await _openMap(t);
    final scope = t.element(find.byType(Scaffold).first).getElementForInheritedWidgetOfExactType<AppLocaleScope>()!.widget as AppLocaleScope;
    scope.notifier!.value = AppLocale.fil;
    await settle(t, rounds: 4);
    expect(find.bySemanticsLabel('Aking reports, 4'), findsOneWidget);
    expect(find.text('Aking reports'), findsOneWidget);
    expect(find.text('Mga paunawa'), findsOneWidget);
    await _layers(t);
    for (final n in ['Aking reports', 'Mga paunawa ng barangay', 'Mga lugar', 'Dimmin ang labas ng 183', 'Bantay-ulan', 'DETALYE NG MAPA']) {
      expect(find.text(n), findsWidgets, reason: n);
    }
    await t.tapAt(const Offset(195, 60));
    await settle(t, rounds: 4);
    await _pick(t, _rid(301));
    expect(find.text('3 concern · 1 ang nalutas'), findsOneWidget);
    expect(find.text('Na-dispatch ang tanod · na-update 2 oras ang nakalipas'), findsOneWidget);
    expect(find.text('Buksan ang report'), findsOneWidget);
    await finish(t);
  });

  for (final scale in [1.6, 2.0]) {
    testWidgets('large text ($scale x): the chips, the cards and the sheet do not overflow, and the big card scrolls with its button pinned', (t) async {
      t.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      await _openMap(t);
      expect(t.takeException(), isNull);
      await _layers(t);
      expect(t.takeException(), isNull);
      await t.tapAt(const Offset(195, 60));
      await settle(t, rounds: 4);
      await _pick(t, _rid(301));
      expect(find.text('Open this report'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.tapAt(t.getTopLeft(find.byType(MapPeekCard)) + Offset(t.getSize(find.byType(MapPeekCard)).width / 2, 10));
      await settle(t, rounds: 4);
      expect(find.byType(MapBigCard), findsOneWidget);
      expect(find.text('Open this report'), findsOneWidget);
      expect(t.takeException(), isNull);
      // the button is on screen
      final h = t.view.physicalSize.height / t.view.devicePixelRatio;
      expect(t.getBottomLeft(find.text('Open this report')).dy, lessThanOrEqualTo(h));
      await finish(t);
    });
  }

  test('every category colour gives its card a header disc and hero with the AA contrast white lettering needs', () {
    // concernFill is the barangay's colour stepped down until white reaches 4.5:1; the cards draw with it
    for (final c in [0xFFF93535, 0xFF356CF9, 0xFFF9AB35, 0xFF34C759, 0xFF8E9ABB, 0xFF422F8A, 0xFFE0609A, 0xFF0F9D9A]) {
      final ratio = 1.05 / (concernFill(Color(c)).computeLuminance() + .05);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: c.toRadixString(16));
    }
  });
}
