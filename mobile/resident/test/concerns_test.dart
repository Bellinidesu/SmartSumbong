// Several categories and sub-categories on one report (0163): what the phone sends, keeps in its outbox, and shows.

import 'package:flutter_test/flutter_test.dart';
import 'package:resident/models/complaint_catalogue.dart';
import 'package:resident/models/complaint_category.dart';
import 'package:resident/outbox.dart';
import 'package:resident/screens/report_details_screen.dart' show ExtraConcern;
import 'package:resident/screens/report_view_screen.dart' show concernFiledAs, concernTitle;

void main() {
  setUp(() {
    ComplaintCatalogue.apply([
      {'key': 'barangay_service', 'en': 'Barangay Help Desk', 'fil': 'Tulong ng Barangay', 'colour': '#5E35B1', 'icon': 'barangay_service', 'active': true,
       'options': [{'id': 11, 'en': 'Slow reply', 'fil': 'Mabagal na tugon', 'active': true}, {'id': 12, 'en': 'Duty negligence', 'fil': 'Pagpapabaya', 'active': true}]},
      {'key': 'animal_welfare', 'en': 'Animal Welfare', 'fil': 'Kapakanan ng Hayop', 'colour': '#34C759', 'icon': 'animal_welfare', 'active': true,
       'options': [{'id': 21, 'en': 'Stray dog', 'fil': 'Asong gala', 'active': true}]},
    ]);
  });

  test('the catalogue keeps each option\'s id, and the choice carries it', () {
    final c = ComplaintCategory.parse('barangay_service');
    expect([for (final o in c.options) o.id], [11, 12]);
    expect(CategoryChoice(category: c, issue: 'Slow reply', optionId: 11).optionId, 11);
  });

  test('a report with one concern sends what it always sent; with more, the option and the others', () {
    expect(concernParams(null, const []), isEmpty);
    final dog = ComplaintCategory.parse('animal_welfare');
    final extra = ExtraConcern(dog, dog.options.single);
    expect(extra.toJson(), {'category': 'animal_welfare', 'option': 21});
    expect(ExtraConcern(dog, null).toJson(), {'category': 'animal_welfare'});
    expect(concernParams(11, [extra.toJson()]), {'p_option': 11, 'p_concerns': [{'category': 'animal_welfare', 'option': 21}]});
  });

  test('a report waiting in the outbox keeps its option and its other concerns', () {
    final item = OutboxItem(
      id: 'r1', category: 'barangay_service', subject: 'Slow reply', description: 'Walang sumagot.', latitude: 14.5, longitude: 121.0,
      anonymous: false, photos: const [], video: null, uploaded: const [], uploadedVideo: null, queuedAt: DateTime(2026, 11, 4),
      optionId: 11, concerns: const [{'category': 'animal_welfare', 'option': 21}],
    );
    final back = OutboxItem.fromJson(item.toJson());
    expect(back.optionId, 11);
    expect(back.concerns, [{'category': 'animal_welfare', 'option': 21}]);
    // an item queued by an older app has neither, and still sends
    final old = OutboxItem.fromJson({...item.toJson()}..remove('optionId')..remove('concerns'));
    expect(old.optionId, isNull);
    expect(old.concerns, isEmpty);
  });

  test('a concern reads by today\'s names, and says what it was filed as when that changed', () {
    final renamed = {'category': 'barangay_service', 'option_id': 11, 'filed_category_en': 'Barangay Service', 'filed_category_fil': 'Serbisyo ng Barangay',
                     'filed_option_en': 'Delayed response', 'filed_option_fil': 'Naantalang tugon'};
    expect(concernTitle(renamed, filipino: false), 'Barangay Help Desk: Slow reply');
    expect(concernFiledAs(renamed, filipino: false), 'Filed as "Barangay Service: Delayed response" (renamed since)');
    expect(concernFiledAs(renamed, filipino: true), 'Isinampa bilang "Serbisyo ng Barangay: Naantalang tugon" (pinalitan ang pangalan mula noon)');
    final same = {'category': 'animal_welfare', 'option_id': 21, 'filed_category_en': 'Animal Welfare', 'filed_option_en': 'Stray dog'};
    expect(concernFiledAs(same, filipino: false), isNull);
    final gone = {'category': 'animal_welfare', 'option_id': 99, 'filed_category_en': 'Animal Welfare', 'filed_option_en': 'Old option'};
    expect(concernTitle(gone, filipino: false), 'Animal Welfare: Old option');
    expect(concernFiledAs(gone, filipino: false), 'Filed as "Animal Welfare: Old option" (no longer offered)');
  });
}
