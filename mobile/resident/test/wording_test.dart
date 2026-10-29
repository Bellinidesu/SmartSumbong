// The barangay's own wording (0149): what the phone shows for a label.

import 'package:flutter_test/flutter_test.dart';
import 'package:resident/models/wording.dart';

void main() {
  test("the code's own wording until the barangay changes a label", () {
    expect(Wording.pick('My Reports', 'Aking mga Ulat', filipino: false), 'My Reports');
    Wording.apply([
      {'source': 'My Reports', 'en': 'My Complaints', 'fil': null},
      {'source': 'Emergency', 'en': null, 'fil': 'Saklolo'},
    ]);
    expect(Wording.pick('My Reports', 'Aking mga Ulat', filipino: false), 'My Complaints');
    expect(Wording.pick('My Reports', 'Aking mga Ulat', filipino: true), 'Aking mga Ulat');
    expect(Wording.pick('Emergency', 'Emerhensiya', filipino: true), 'Saklolo');
    expect(Wording.pick('Emergency', 'Emerhensiya', filipino: false), 'Emergency');
    Wording.apply([]);
    expect(Wording.pick('My Reports', 'Aking mga Ulat', filipino: false), 'My Reports');
  });
}
