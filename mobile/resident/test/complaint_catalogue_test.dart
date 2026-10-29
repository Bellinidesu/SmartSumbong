// The barangay's complaint catalogue (0146): what the phone makes of complaint_catalogue()'s answer.

import 'package:flutter_test/flutter_test.dart';
import 'package:resident/d/d_categories.dart';
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';

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
}
