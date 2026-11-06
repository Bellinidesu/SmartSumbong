// Live preview (0160): what the phone makes of the Control Room's draft. Nothing here touches the network.

import 'package:flutter_test/flutter_test.dart';
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';
import 'package:resident/screens/emergency_screen.dart';

void main() {
  test("a draft's categories show as the forms say them: a renamed one, one switched off, one not made yet, options as typed", () {
    final ok = ComplaintCatalogue.applyDraft([
      {
        'key': 'street_obstruction', 'label_en': 'Roads and Drainage', 'label_fil': 'Kalsada at Kanal', 'colour': '#3366FF', 'icon': 'street_obstruction', 'active': true,
        'options': [
          {'id': 1, 'label_en': 'Potholes', 'label_fil': 'Lubak', 'active': true},
          {'id': null, 'label_en': 'Blocked gutters', 'label_fil': '', 'active': true},
          {'id': 2, 'label_en': 'Off', 'label_fil': 'Patay', 'active': false},
        ],
      },
      {'key': 'animal_welfare', 'label_en': 'Animal Welfare', 'label_fil': 'Hayop', 'colour': '#34C759', 'icon': 'animal_welfare', 'active': false, 'options': []},
      {'key': null, 'label_en': 'Overgrown Trees', 'label_fil': 'Lumagong Puno', 'colour': '#2E7D32', 'icon': 'environmental_waste_hazard', 'active': true, 'options': []},
    ]);
    expect(ok, isTrue);
    expect([for (final c in ComplaintCategory.values) c.label], ['Roads and Drainage', 'Overgrown Trees']);
    final r = ComplaintCategory.parse('street_obstruction');
    expect(r.labelFil, 'Kalsada at Kanal');
    expect(r.issues, ['Potholes', 'Blocked gutters']);
    expect(ComplaintCategory.values.last.wire, 'draft_2');   // a category not made yet is given a stand-in key
    // a draft with nothing to show changes nothing
    expect(ComplaintCatalogue.applyDraft([]), isFalse);
    expect(ComplaintCatalogue.applyDraft(['x']), isFalse);
    expect([for (final c in ComplaintCategory.values) c.label], ['Roads and Drainage', 'Overgrown Trees']);
  });

  test("a draft's emergency numbers: nested groups, switched off groups and numbers left out, empty labels read as none", () {
    final g = hotlineGroupsFromDraft([
      {
        'id': 'g1', 'name': 'Barangay 183 Hotline', 'display': 'inline', 'active': true,
        'numbers': [
          {'id': 'n1', 'label': 'Duty officer', 'number': '0917 000 0000', 'carrier': 'Globe', 'active': true},
          {'id': 'n2', 'label': 'Old', 'number': '0000', 'carrier': '', 'active': false},
          {'id': null, 'label': '', 'number': '8 123 4567', 'carrier': '', 'active': true},
          {'id': null, 'label': 'Blank', 'number': '  ', 'carrier': '', 'active': true},
        ],
        'groups': [
          {'id': 'g1a', 'name': 'Night desk', 'display': 'link', 'active': true, 'numbers': [{'id': 'n3', 'label': 'Desk', 'number': '555', 'carrier': '', 'active': true}], 'groups': []},
          {'id': 'g1b', 'name': 'Hidden', 'display': 'inline', 'active': false, 'numbers': [], 'groups': []},
        ],
      },
      {'id': 'g2', 'name': 'Off group', 'display': 'inline', 'active': false, 'numbers': [], 'groups': []},
    ]);
    expect(g.length, 1);
    expect(g.single.name, 'Barangay 183 Hotline');
    expect([for (final n in g.single.numbers) n.number], ['0917 000 0000', '8 123 4567']);
    expect(g.single.numbers.first.carrier, 'Globe');
    expect(g.single.numbers.last.label, isNull);
    expect(g.single.numbers.last.carrier, isNull);
    expect(g.single.children.single.name, 'Night desk');
    expect(g.single.children.single.isLink, isTrue);
    expect(hotlineGroupsFromDraft(null), isEmpty);
  });
}
