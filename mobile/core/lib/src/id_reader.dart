// SmartSumbong — what an ID card says, from the lines an OCR model read off it.
//
// A direct port of engine/reader.py (22 Oct 2026, the version measured in
// tools/ocr_lab): which kind of card it is, the name, and the ID number. It
// decides nothing: the database compares the reading with what the resident
// registered (0126) and a person decides. Pure Dart with no OCR model, so the
// tests (test/id_reader_test.dart, the same cases as engine/test_reader.py)
// run anywhere.

import 'dart:math' as math;

/// Header phrases printed on each kind of card, keyed by the id_document_type
/// wire value. Several per kind: a cropped or glare-washed photo can still give
/// back part of one. REPUBLIKA NG PILIPINAS is on nearly every card, so it is
/// not here.
const Map<String, List<String>> idHeaderHints = {
  'drivers_license': [
    "DRIVER'S LICENSE",
    'DRIVERS LICENSE',
    'LAND TRANSPORTATION OFFICE',
    'NON-PROFESSIONAL',
    'PROFESSIONAL DRIVER',
  ],
  'passport': ['PASSPORT', 'PASAPORTE', 'DEPARTMENT OF FOREIGN AFFAIRS'],
  'philsys': ['PHILIPPINE IDENTIFICATION CARD', 'PAMBANSANG PAGKAKAKILANLAN'],
  'postal_id': ['POSTAL ID', 'PHLPOST', 'PHILIPPINE POSTAL'],
  'barangay_id': ['BARANGAY ID', 'BARANGAY IDENTIFICATION'],
  'barangay_appointment': ['APPOINTMENT', 'DESIGNATION', 'TANOD'],
};

// A label, then the value on the next line (PhilSys and the driver's licence
// print them this way). 'SUMAME' is "SURNAME" with rn read as m.
const Map<String, List<String>> _nameLabels = {
  'last': ['APELYIDO', 'LAST NAME', 'SURNAME', 'SUMAME'],
  'given': ['MGA PANGALAN', 'GIVEN NAME', 'GIVEN NAMES', 'PANGALAN'],
  'middle': ['GITNANG APELYIDO', 'MIDDLE NAME'],
  'full': ['NAME'],
};

// Words on a card that are never part of a person's name: mastheads, offices,
// labels, months.
final Set<String> _notName = {
  ...('REPUBLIKA REPUBLIC PILIPINAS PHILIPPINES PHILIPPINE PAMBANSANG PAGKAKAKILANLAN DEPARTMENT OFFICE '
          'CORPORATION AUTHORITY NATIONAL LUNGSOD CITY BARANGAY ZONE PASAY CARD IDENTIFICATION IDENTITY LICENSE DRIVER DRIVERS '
          'POSTAL PHLPOST TRANSPORTATION FOREIGN AFFAIRS PASSPORT PASAPORTE SIGNATURE ADDRESS NATIONALITY SEX DATE BIRTH '
          'EXPIRATION VALID UNTIL PRN BLOOD TYPE APPOINTMENT DESIGNATION TANOD OF THE NG SA AND JANUARY FEBRUARY MARCH APRIL MAY '
          'JUNE JULY AUGUST SEPTEMBER OCTOBER NOVEMBER DECEMBER')
      .split(' '),
};

final RegExp _ltoNumber = RegExp(r'\b[A-Z]\d{2}-\d{2}-\d{6}\b');
final RegExp _anyNumber = RegExp(r'\b\d[\d\- ]{4,}\d\b');
final RegExp _nameWord = RegExp(r"[A-Z][A-Z'.-]*");

/// What was read: the card's id_document_type wire value, the name and the ID
/// number. Each is null when it could not be found.
class CardReading {
  const CardReading({this.type, this.name, this.number});

  final String? type;
  final String? name;
  final String? number;

  bool get isEmpty => type == null && name == null && number == null;
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      cur.add(math.min(
        math.min(cur[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      ));
    }
    prev = cur;
  }
  return prev.last;
}

/// The phrase is in the text, allowing about one slip in five letters (phrases
/// of six letters or more).
bool fuzzyContains(String hay, String needle, {double rate = 0.22}) {
  if (needle.isEmpty) return false;
  if (hay.contains(needle)) return true;
  if (needle.length < 6) return false;
  final errors = (needle.length * rate).floor();
  if (errors == 0) return false;
  final lo = math.max(1, needle.length - errors);
  final hi = math.min(hay.length, needle.length + errors);
  for (var start = 0; start <= hay.length - lo; start++) {
    for (var n = lo; n <= hi; n++) {
      if (start + n > hay.length) break;
      if (levenshtein(hay.substring(start, start + n), needle) <= errors) return true;
    }
  }
  return false;
}

/// Capitals, mostly letters, of a sensible length: how a name is printed on a card.
bool _nameLike(String value, int lo, int hi) {
  if (value.length < lo || value.length > hi || value != value.toUpperCase()) return false;
  final bare = value.replaceAll(' ', '');
  final letters = bare.replaceAll(RegExp(r'[^A-Za-z]'), '');
  return bare.isNotEmpty && letters.length >= bare.length * 0.7;
}

String _tidy(String s) => s.replaceAll(',', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

String? _nameByLabel(List<String> lines) {
  final parts = <String, String>{};
  final used = <int>{};
  for (var i = 0; i < lines.length - 1; i++) {
    final line = lines[i].toUpperCase();
    for (final entry in _nameLabels.entries) {
      // one value line answers one label: "Last Name, First Name, Middle Name" is one label over one line
      if (parts.containsKey(entry.key) || used.contains(i + 1)) continue;
      if (!entry.value.any((h) => fuzzyContains(line, h))) continue;
      final value = lines[i + 1].trim();
      if (_nameLike(value, 2, 40)) {
        parts[entry.key] = value;
        used.add(i + 1);
      }
    }
  }
  final joined = ['last', 'given', 'middle'].where(parts.containsKey).map((k) => parts[k]!).join(' ').trim();
  final out = _tidy(joined.isNotEmpty ? joined : (parts['full'] ?? ''));
  return out.isEmpty ? null : out;
}

bool _plainName(String line) {
  if (!_nameLike(line, 2, 60)) return false;
  final words = _nameWord.allMatches(line.toUpperCase()).map((m) => m.group(0)!).toList();
  if (words.isEmpty) return false;
  return !words.any((w) => _notName.contains(w.replaceAll(RegExp(r'^\.+|\.+$'), '')));
}

/// The name when no label survived: a "SURNAME, GIVEN" line, or else the
/// longest run of name-like lines in a row (PhilSys prints surname, given names
/// and middle name one under another), up to three.
String? _nameLines(List<String> lines) {
  final cands = [for (final l in lines) l.trim()];
  for (final l in cands) {
    if (l.contains(',') && _plainName(l)) return _tidy(l);
  }
  var best = <String>[];
  var run = <String>[];
  int size(List<String> r) => r.fold(0, (n, s) => n + s.length);
  for (final l in [...cands, '']) {
    if (l.isNotEmpty && _plainName(l) && run.length < 3) {
      run.add(l);
      continue;
    }
    if (size(run) > size(best)) best = run;
    run = (l.isNotEmpty && _plainName(l)) ? [l] : <String>[];
  }
  final out = best.join(' ');
  return out.isEmpty ? null : out;
}

String? idNumber(String text) {
  final lto = _ltoNumber.firstMatch(text.toUpperCase());
  if (lto != null) return lto.group(0);
  final m = _anyNumber.firstMatch(text);
  if (m == null || m.group(0)!.replaceAll(RegExp(r'\D'), '').length < 6) return null;
  return m.group(0)!.trim();
}

/// [lines]: the text lines, top of the card first.
CardReading readCard(List<String> lines) {
  final clean = [for (final l in lines) if (l.trim().isNotEmpty) l.trim()];
  final text = clean.join('\n');
  final up = text.toUpperCase();
  if (RegExp(r'[A-Z0-9]').allMatches(up).length < 12) return const CardReading();
  String? kind;
  for (final e in idHeaderHints.entries) {
    if (e.value.any((h) => fuzzyContains(up, h))) {
      kind = e.key;
      break;
    }
  }
  // by label, or by the run of name lines, whichever found more of the name (a label can be lost to glare)
  final found = [_nameByLabel(clean), _nameLines(clean)].whereType<String>().toList();
  String? name;
  for (final n in found) {
    if (name == null || n.split(' ').length > name.split(' ').length) name = n;
  }
  if (name != null && name.length > 120) name = name.substring(0, 120);
  return CardReading(type: kind, name: name, number: idNumber(text));
}
