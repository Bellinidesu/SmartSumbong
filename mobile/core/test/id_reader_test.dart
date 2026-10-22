// The same cases as engine/test_reader.py: the Dart reader must read a card as the engine's does.
import 'package:flutter_test/flutter_test.dart';
import 'package:smartsumbong_core/src/id_reader.dart';

void main() {
  group('readCard', () {
    test('PhilSys with its labels', () {
      final r = readCard([
        'REPUBLIKA NG PILIPINAS', 'PAMBANSANG PAGKAKAKILANLAN', 'Philippine Identification Card', '5376-3269-4049-1105',
        'Apelyido / Last Name', 'VILLANUEVA', 'Mga Pangalan / Given Names', 'RICHARD', 'Gitnang Apelyido / Middle Name',
        'PEREZ', 'Petsa ng Kapanganakan / Date of Birth', 'JANUARY 15, 1990',
      ]);
      expect(r.type, 'philsys');
      expect(r.name, 'VILLANUEVA RICHARD PEREZ');
      expect(r.number, '5376-3269-4049-1105');
    });

    test('labels lost to blur still give the name', () {
      final r = readCard([
        'REPUBLIKA NG PILIPINAS', 'PAMBANSANG PAGKAKAKILANLAN', '9684-1475-8628-5080', 'RAMOS', 'KRISTINE JOY', 'PEREZ', 'JANUARY 15, 1990',
      ]);
      expect(r.name, 'RAMOS KRISTINE JOY PEREZ');
    });

    test('one label over one line is read once', () {
      final r = readCard([
        'LAND TRANSPORTATION OFFICE', "DRIVER'S LICENSE", 'Last Name, First Name, Middle Name', 'BAUTISTA, MA. TERESA LIM',
        'License No.', 'K11-43-581195',
      ]);
      expect(r.type, 'drivers_license');
      expect(r.name, 'BAUTISTA MA. TERESA LIM');
      expect(r.number, 'K11-43-581195');
    });

    test('a slip in a label', () {
      final r = readCard([
        'PHILIPPINE POSTAL CORPORATION', 'POSTAL IDENTITY CARD', 'PRN 680445687345', 'Given Name(s)', 'RICHARD', 'Sumame',
        'VILLANUEVA', 'Middle Name', 'TAN',
      ]);
      expect(r.type, 'postal_id');
      expect(r.name, contains('VILLANUEVA'));
      expect(r.name, contains('RICHARD'));
    });

    test('headings are never the name', () {
      final r = readCard(['REPUBLIC OF THE PHILIPPINES', 'DEPARTMENT OF TRANSPORTATION', 'LAND TRANSPORTATION OFFICE', 'K80-57-132854']);
      expect(r.name, isNull);
    });

    test('too little text is unreadable', () {
      expect(readCard(['A1', '', 'ok']).isEmpty, isTrue);
    });

    test('a masthead alone is no kind', () {
      expect(readCard(['REPUBLIKA NG PILIPINAS', 'JUAN DELA CRUZ', '1234-5678']).type, isNull);
    });
  });

  group('pieces', () {
    test('fuzzy', () {
      expect(fuzzyContains('PAMBANSANG PAGKAKAKILANLAM', 'PAMBANSANG PAGKAKAKILANLAN'), isTrue);
      expect(fuzzyContains('TANOD', 'TAMOD'), isFalse); // short words must match exactly
    });

    test('numbers', () {
      expect(idNumber('No. N01-23-456789'), 'N01-23-456789');
      expect(idNumber('PRN 405622415499'), '405622415499');
      expect(idNumber('Zone 20, 183'), isNull);
    });
  });
}
