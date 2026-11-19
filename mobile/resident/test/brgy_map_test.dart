// The barangay map in the portal's style (widgets/brgy_map.dart): what
// each use turns on, the portal's symbols, the pins' source, the scale, and
// the controls and case card drawn over the map. The map itself is a
// platform view and does not draw in a widget test; these are the parts
// around it.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:resident/widgets/brgy_map.dart';
import 'package:resident/widgets/brgy_map_card.dart';
import 'package:resident/widgets/map_glyphs.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) => MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
          child: Scaffold(body: SizedBox(width: 390, height: 700, child: child)),
        ),
      ),
    );

const _pin = BrgyMapPin(id: 'a', point: LatLng(14.5269, 121.0155), colour: Color(0xFFF93535), glyph: 'street_obstruction');

void main() {
  group('BrgyMapUse', () {
    test('browse is pinned to the barangay with every control', () {
      const u = BrgyMapUse.browse;
      expect(u.bounded, isTrue);
      expect(u.interactive, isTrue);
      expect([u.zoomButtons, u.fitButton, u.layers, u.legend, u.scale], everyElement(isTrue));
      // the portal's zoom range, MapLibre's scale
      expect(u.minZoom, 15);
      expect(u.maxZoom, 18);
    });

    test('a report page is a still picture with no controls', () {
      const u = BrgyMapUse.report;
      expect(u.interactive, isFalse);
      expect(u.hasControls, isFalse);
      expect(u.bounded, isFalse);
    });

    test('the pin picker moves but draws nothing over the pin', () {
      const u = BrgyMapUse.pick;
      expect(u.interactive, isTrue);
      expect(u.hasControls, isFalse);
    });

    test('a job has zoom, frame and scale, no layers or legend; it is not pinned', () {
      const u = BrgyMapUse.job;
      expect([u.zoomButtons, u.fitButton, u.scale], everyElement(isTrue));
      expect([u.layers, u.legend], everyElement(isFalse));
      expect(u.bounded, isFalse);
      expect(u.minZoom, lessThan(15));
    });

    test('navigation leaves the glass to the directions: only the scale', () {
      const u = BrgyMapUse.navigate;
      expect(u.scale, isTrue);
      expect([u.zoomButtons, u.fitButton, u.layers, u.legend], everyElement(isFalse));
    });

    test('each mode is its own use', () {
      expect({for (final u in [BrgyMapUse.browse, BrgyMapUse.report, BrgyMapUse.pick, BrgyMapUse.job, BrgyMapUse.navigate]) u.mode}.length, 5);
    });
  });

  group('portal glyphs', () {
    test('every category symbol reads into a path inside its 24 px box', () {
      for (final e in categoryMapGlyphs.entries) {
        final b = e.value.path.getBounds();
        expect(b.isEmpty, isFalse, reason: e.key);
        expect(b.left, greaterThanOrEqualTo(-.5), reason: e.key);
        expect(b.top, greaterThanOrEqualTo(-.5), reason: e.key);
        expect(b.right, lessThanOrEqualTo(24.5), reason: e.key);
        expect(b.bottom, lessThanOrEqualTo(24.5), reason: e.key);
      }
    });

    test('an unknown or custom icon key wears the Others symbol', () {
      expect(categoryMapGlyph('nope'), same(categoryMapGlyphs['other']));
      expect(categoryMapGlyph(null), same(categoryMapGlyphs['other']));
    });

    test('compact SVG numbers and relative arcs parse', () {
      // ".5.5" is two numbers; "1-1.6.8" is three
      final b = svgPath('M11 6a1 1 0 0 1-1.6.8A.5.5 0 0 1 20.5 7h-17z').getBounds();
      expect(b.left, closeTo(3.5, .01));
      expect(b.right, greaterThan(20));
    });
  });

  group('pins', () {
    test('two reports on the same spot are set a few metres apart', () {
      final fc = pinFeatures([_pin, const BrgyMapPin(id: 'b', point: LatLng(14.5269, 121.0155), colour: Color(0xFF356CF9), glyph: 'other')]);
      final f = fc['features'] as List;
      final a = (f[0]['geometry'] as Map)['coordinates'] as List, b = (f[1]['geometry'] as Map)['coordinates'] as List;
      expect(a, [121.0155, 14.5269]);
      expect(b, isNot(equals(a)));
      final metres = const Distance().as(LengthUnit.Meter, LatLng(a[1] as double, a[0] as double), LatLng(b[1] as double, b[0] as double));
      expect(metres, inInclusiveRange(2, 8));
    });

    test('the open card\'s pin is marked so the map draws it larger', () {
      final f = pinFeatures([_pin], selected: 'a')['features'] as List;
      expect((f.single['properties'] as Map)['sel'], isTrue);
      expect(((pinFeatures([_pin])['features'] as List).single['properties'] as Map)['sel'], isFalse);
    });

    test('pins with the same look share one map image', () {
      const twin = BrgyMapPin(id: 'z', point: LatLng(14.52, 121.01), colour: Color(0xFFF93535), glyph: 'street_obstruction');
      expect(twin.imageKey, _pin.imageKey);
      expect(const BrgyMapPin(id: 'a', point: LatLng(0, 0), colour: Color(0xFFF93535), glyph: 'street_obstruction', muted: true).imageKey,
          isNot(_pin.imageKey));
    });

    testWidgets('a pin paints in light and dark', (t) async {
      for (final b in Brightness.values) {
        await t.pumpWidget(_host(const Center(child: BrgyMapPinPreview(_pin)), brightness: b));
        expect(find.byType(BrgyMapPinPreview), findsOneWidget);
      }
    });
  });

  group('scale bar', () {
    test('a round distance that fits', () {
      expect(BrgyMapScaleBar.niceMetres(1, 96), 50);
      expect(BrgyMapScaleBar.niceMetres(2.5, 96), 200);
      expect(BrgyMapScaleBar.niceMetres(12, 96), 1000);
      expect(BrgyMapScaleBar.label(1000), '1 km');
      expect(BrgyMapScaleBar.label(300), '300 m');
    });
  });

  group('controls', () {
    final legend = [
      const BrgyMapLegendEntry(label: 'Street Obstruction', colour: Color(0xFFF93535), glyph: 'street_obstruction', count: 2),
      const BrgyMapLegendEntry(label: 'Others', colour: Color(0xFF0F9D9A), glyph: 'other', count: 0),
    ];

    testWidgets('browse draws the dock, the zoom pair and the Layers tile', (t) async {
      await t.pumpWidget(_host(BrgyMapOverlay(use: BrgyMapUse.browse, legend: legend)));
      expect(find.bySemanticsLabel('Frame the map'), findsOneWidget);
      expect(find.bySemanticsLabel('Legend'), findsOneWidget);
      expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
      expect(find.bySemanticsLabel('Zoom out'), findsOneWidget);
      expect(find.bySemanticsLabel('Map layers'), findsOneWidget);
    });

    testWidgets('the Layers tile opens its row, the legend button its card', (t) async {
      final opened = <BrgyMapPanel>[];
      await t.pumpWidget(_host(BrgyMapOverlay(use: BrgyMapUse.browse, legend: legend, onPanel: opened.add)));
      await t.tap(find.bySemanticsLabel('Map layers'));
      await t.tap(find.bySemanticsLabel('Legend'));
      expect(opened, [BrgyMapPanel.layers, BrgyMapPanel.legend]);

      await t.pumpWidget(_host(BrgyMapOverlay(use: BrgyMapUse.browse, legend: legend, panel: BrgyMapPanel.layers)));
      expect(find.text('Dim outside'), findsOneWidget);
      expect(find.text('Places'), findsOneWidget);

      await t.pumpWidget(_host(BrgyMapOverlay(use: BrgyMapUse.browse, legend: legend, panel: BrgyMapPanel.legend)));
      expect(find.text('COMPLAINT TYPE'), findsOneWidget);
      expect(find.text('Street Obstruction'), findsOneWidget);
      expect(find.text('2 reports on the map'), findsOneWidget);
    });

    testWidgets('the layer switches report their new state', (t) async {
      bool? dim, places;
      await t.pumpWidget(_host(BrgyMapOverlay(
        use: BrgyMapUse.browse,
        panel: BrgyMapPanel.layers,
        onDim: (v) => dim = v,
        onPlaces: (v) => places = v,
      )));
      await t.tap(find.text('Dim outside'));
      await t.tap(find.text('Places'));
      expect(dim, isFalse);
      expect(places, isFalse);
    });

    testWidgets('a job has zoom and frame, no layers or legend', (t) async {
      await t.pumpWidget(_host(BrgyMapOverlay(use: BrgyMapUse.job, legend: legend)));
      expect(find.bySemanticsLabel('Zoom in'), findsOneWidget);
      expect(find.bySemanticsLabel('Frame the map'), findsOneWidget);
      expect(find.bySemanticsLabel('Map layers'), findsNothing);
      expect(find.bySemanticsLabel('Legend'), findsNothing);
    });

    testWidgets('navigation has no buttons', (t) async {
      await t.pumpWidget(_host(const BrgyMapOverlay(use: BrgyMapUse.navigate)));
      expect(find.byType(BrgyMapButton), findsNothing);
      expect(find.byType(BrgyMapLayersTile), findsNothing);
    });
  });

  group('case card', () {
    testWidgets('the portal\'s parts: hero, title, ticket and status, rows, progress, the button', (t) async {
      var opened = false, closed = false;
      await t.pumpWidget(_host(BrgyMapCaseCard(
        colour: const Color(0xFFF93535),
        glyph: 'street_obstruction',
        category: 'Street Obstruction',
        title: 'Vendors on the sidewalk',
        ticket: 'SS-2610-1012',
        statusLabel: 'Assigned',
        statusColour: const Color(0xFF2457E6),
        rows: const [BrgyMapCardRow(glyph: MapIcons.pin, title: 'Near Andrews Ave.', sub: 'Barangay 183')],
        steps: const ['Filed', 'Validated', 'Tanod dispatched', 'Resolved'],
        stepsOn: 3,
        action: 'Open this report',
        onAction: () => opened = true,
        onClose: () => closed = true,
      )));
      expect(find.text('Street Obstruction'), findsOneWidget);
      expect(find.text('Vendors on the sidewalk'), findsOneWidget);
      expect(find.textContaining('SS-2610-1012', findRichText: true), findsOneWidget);
      expect(find.text('Near Andrews Ave.'), findsOneWidget);
      expect(find.text('PROGRESS'), findsOneWidget);
      expect(find.text('Tanod dispatched'), findsOneWidget);
      await t.tap(find.text('Open this report'));
      await t.tap(find.bySemanticsLabel('Close'));
      expect(opened, isTrue);
      expect(closed, isTrue);
    });

    testWidgets('a published incident has no ticket and no button, only the note', (t) async {
      await t.pumpWidget(_host(const BrgyMapCaseCard(
        colour: Color(0xFF34C759),
        glyph: 'animal_welfare',
        category: 'Animal Welfare',
        title: 'Animal Welfare',
        statusLabel: 'In Progress',
        statusColour: Color(0xFF2457E6),
        note: 'Published by the barangay.',
      ), brightness: Brightness.dark));
      expect(find.text('Published by the barangay.'), findsOneWidget);
      expect(find.text('Open this report'), findsNothing);
      expect(find.text('PROGRESS'), findsNothing);
    });
  });
}
