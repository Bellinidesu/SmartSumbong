// The barangay's name and place (0148): what the phone makes of barangay_profile's row.

import 'package:flutter_test/flutter_test.dart';
import 'package:resident/models/barangay_profile.dart';

void main() {
  test('before the profile is read, Barangay 183 stands in', () {
    expect(BarangayProfile.name, 'Barangay 183');
    expect(BarangayProfile.city, 'Pasay City');
    expect(BarangayProfile.cityFil, 'Lungsod ng Pasay');
  });

  test("the barangay's own row replaces it; a broken one changes nothing", () {
    expect(BarangayProfile.apply({'name': 'Barangay 184', 'place': 'Zone 20, Villamor, Pasay City'}), isTrue);
    expect(BarangayProfile.name, 'Barangay 184');
    expect(BarangayProfile.apply({'name': 'X', 'place': null}), isFalse);
    expect(BarangayProfile.name, 'Barangay 184');
    expect(BarangayProfile.apply({'name': 'Barangay 1', 'place': 'Poblacion, Bayan ng Rosario'}), isTrue);
    expect(BarangayProfile.cityFil, 'Bayan ng Rosario');
  });
}
