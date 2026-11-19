// The barangay's complaint catalogue (0146): what the phone makes of complaint_catalogue()'s answer.

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/d/d_categories.dart';
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';
import 'package:resident/widgets/category_card.dart' show concernFill;

void main() {
  test('before the catalogue is read, the built-in list stands in', () {
    expect(ComplaintCategory.values.length, 8);
    expect(ComplaintCategory.parse('street_obstruction').issues, contains('Illegal Parking'));
    expect(ComplaintCategory.parse(null), ComplaintCategory.other);
  });

  test("the barangay's list replaces it: order, Tagalog, colour, symbol, options switched off", () {
    final ok = ComplaintCatalogue.apply([
      {'key': 'overgrown_trees', 'en': 'Overgrown Trees', 'fil': 'Lumagong Puno', 'colour': '#2E7D32', 'icon': 'environmental_waste_hazard', 'active': true,
       'options': [{'id': 40, 'en': 'Branches Over Power Lines', 'fil': 'Sanga sa kawad ng kuryente', 'active': true}, {'id': 41, 'en': 'Gone', 'fil': 'Wala na', 'active': false}]},
      {'key': 'animal_welfare', 'en': 'Animal Welfare', 'fil': 'Kapakanan ng Hayop', 'colour': '#34C759', 'icon': 'animal_welfare', 'active': true, 'options': []},
      {'key': 'traffic_violation', 'en': 'Traffic Violation', 'fil': 'Paglabag sa Trapiko', 'colour': '#8E9ABB', 'icon': 'traffic_violation', 'active': false, 'options': []},
      {'key': 'other', 'en': 'Others', 'fil': 'Iba pa', 'colour': '#0F9D9A', 'icon': 'other', 'active': true, 'options': []},
    ]);
    expect(ok, isTrue);
    expect([for (final c in ComplaintCategory.values) c.wire], ['overgrown_trees', 'animal_welfare', 'other']);
    final t = ComplaintCategory.parse('overgrown_trees');
    expect(t.labelFil, 'Lumagong Puno');
    expect(t.issues, ['Branches Over Power Lines']);
    expect(t.options.single.fil, 'Sanga sa kawad ng kuryente');
    expect(categoryColour(t).toARGB32(), 0xFF2E7D32);
    expect(categoryGlyph(t), categoryGlyph(ComplaintCategory.environmentalWasteHazard));
    // switched off: no longer offered, but an old report keeps its name
    expect(ComplaintCategory.parse('traffic_violation').label, 'Traffic Violation');
    // a key this phone has never seen reads as a name, in the Others look
    final u = ComplaintCategory.parse('car_clamping');
    expect(u.label, 'Car Clamping');
    expect(categoryColour(u), categoryColour(ComplaintCategory.other));
  });

  test('an empty or broken answer changes nothing', () {
    final before = [for (final c in ComplaintCategory.values) c.wire];
    expect(ComplaintCatalogue.apply([]), isFalse);
    expect(ComplaintCatalogue.apply(['x', {'key': 5}]), isFalse);
    expect([for (final c in ComplaintCategory.values) c.wire], before);
  });
  test('a picked pill reaches AA (4.5:1) with its white text, for every category colour', () {
    double ratio(Color fill) => 1.05 / (fill.computeLuminance() + .05);
    final colours = <Color>[
      for (final c in ComplaintCategory.builtIn) categoryColour(c),
      // the colours the tests and the portal's colour picker use
      const Color(0xFFF93535), const Color(0xFFE0609A), const Color(0xFF0F9D9A), const Color(0xFFF9AB35), const Color(0xFF34C759),
      const Color(0xFF356CF9), const Color(0xFF8E9ABB), const Color(0xFF422F8A), const Color(0xFFFFFF00), const Color(0xFF00FF00), const Color(0xFFFFFFFF),
      // and a sweep of hues, strong and soft
      for (var h = 0; h < 360; h += 10)
        for (final s in [.4, .7, 1.0])
          for (final l in [.35, .5, .65, .8]) HSLColor.fromAHSL(1, h.toDouble(), s, l).toColor(),
    ];
    for (final c in colours) {
      final fill = concernFill(c);
      expect(ratio(fill), greaterThanOrEqualTo(4.5), reason: 'white on ${fill.toARGB32().toRadixString(16)} (from ${c.toARGB32().toRadixString(16)})');
      // the same hue, and only ever darker
      expect(fill.computeLuminance(), lessThanOrEqualTo(c.computeLuminance() + 1e-9));
    }
    // a colour that already reads is left alone
    expect(concernFill(const Color(0xFF422F8A)), const Color(0xFF422F8A));
  });
}
