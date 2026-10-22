import 'package:flutter_test/flutter_test.dart';
import 'package:resident/smart_text.dart';

void main() {
  test('reasons read in English and Filipino', () {
    expect(smartReasonText('330 m away', fil: false), '330 m away');
    expect(smartReasonText('330 m away', fil: true), '330 m ang layo');
    expect(smartReasonText('1 job(s) in hand', fil: true), '1 gawain ang hawak');
    expect(smartReasonText('2 case(s) closed within 300 m, last 90 days', fil: true), contains('2 kaso'));
    expect(smartReasonText('no location yet', fil: true), 'wala pang lokasyon');
    expect(smartReasonText('something new', fil: true), 'something new'); // an unknown reason is shown as it came
  });

  test('a pick shows distance, workload and the area, not the location reading', () {
    final lines = smartPickLines([
      {'factor': 'distance', 'detail': '330 m away', 'points': -16},
      {'factor': 'workload', 'detail': '1 job(s) in hand', 'points': -15},
      {'factor': 'knows the area', 'detail': '2 case(s) closed within 300 m, last 90 days', 'points': 10},
      {'factor': 'location', 'detail': 'last reading just now', 'points': 0},
    ], fil: false);
    expect(lines, ['330 m away', '1 job(s) in hand', '2 case(s) closed within 300 m, last 90 days']);
    expect(smartPickLines(null, fil: false), isEmpty);
  });

  test('the title is kind to the one who was not first', () {
    expect(smartPickTitle(1, 4, fil: false), "You were SMART's first choice.");
    expect(smartPickTitle(2, 4, fil: false), 'SMART ranked you #2 of 4.');
    expect(smartPickTitle(2, 4, fil: true), contains('#2 sa 4'));
  });
}
