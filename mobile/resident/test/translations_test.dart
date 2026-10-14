// Every English string in the app has a Filipino one (item 22).
//
// Reads the source rather than running screens: every _t('en', 'fil') and
// tr('en', 'fil') pair in lib/ is found and checked: the Filipino side is
// there, and differs from the English unless the words are the same in
// both (names, codes, loanwords listed in [sameInBoth]). Text shown with
// no pair at all (a bare Text('Some English')) is caught too.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Words that are the same in English and Filipino: names, and the
/// English loanwords Filipino apps and government forms keep as they are.
const sameInBoth = {
  'SmartSumbong', 'Tanod', 'Email', 'OK', 'Online', 'Offline', 'GPS', 'Video', 'Selfie',
  'Barangay', 'Barangay 183', 'Map', 'Hotline', 'Hotlines', 'PhilSys', 'Pasay City', 'Facebook',
  'Password', 'Email Address', 'Address', 'Mobile number', 'Reference Number', 'Valid ID',
  'Barangay appointment', 'Status', 'Emergency', 'Anonymous', 'fingerprint', 'Filipino / Tagalog',
};

class Pair {
  Pair(this.file, this.line, this.en, this.fil);
  final String file;
  final int line;
  final String en;
  final String fil;
  @override
  String toString() => '$file:$line  "$en" / "$fil"';
}

/// Reads one Dart string literal (or adjacent ones, which Dart joins) at
/// [i]; returns its text and where it ends, or null if not a literal.
(String, int)? readStrings(String src, int i) {
  final buf = StringBuffer();
  var found = false;
  while (true) {
    while (i < src.length && ' \t\r\n'.contains(src[i])) {
      i++;
    }
    var raw = false;
    if (i < src.length && src[i] == 'r' && i + 1 < src.length && (src[i + 1] == "'" || src[i + 1] == '"')) {
      raw = true;
      i++;
    }
    if (i >= src.length || (src[i] != "'" && src[i] != '"')) break;
    final q = src[i];
    i++;
    while (i < src.length && src[i] != q) {
      if (src[i] == '\\' && !raw) {
        buf.write(src[i + 1]);
        i += 2;
        continue;
      }
      buf.write(src[i]);
      i++;
    }
    i++;
    found = true;
  }
  return found ? (buf.toString(), i) : null;
}

List<Pair> pairsIn(File f) {
  final src = f.readAsStringSync();
  final out = <Pair>[];
  for (final m in RegExp(r'(?<![A-Za-z0-9_])(_t|tr)\(').allMatches(src)) {
    final first = readStrings(src, m.end);
    if (first == null) continue;
    var i = first.$2;
    while (i < src.length && ' \t\r\n'.contains(src[i])) {
      i++;
    }
    if (i >= src.length || src[i] != ',') continue;
    final second = readStrings(src, i + 1);
    if (second == null) continue;
    final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
    out.add(Pair(f.path, line, first.$1, second.$1));
  }
  return out;
}

Iterable<File> sources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart') && !f.path.contains('/preview/'));

void main() {
  final pairs = [for (final f in sources()) ...pairsIn(f)];

  test('the string pairs are found', () {
    expect(pairs.length, greaterThan(700));
  });

  test('every string has a Filipino version', () {
    final missing = pairs.where((p) => p.fil.trim().isEmpty).toList();
    expect(missing, isEmpty, reason: missing.join('\n'));
  });

  test('Filipino differs from English, except words that are the same in both', () {
    final same = pairs.where((p) {
      if (p.en != p.fil) return false;
      final t = p.en.trim();
      if (sameInBoth.contains(t)) return false;
      if (!RegExp('[a-z]{3}').hasMatch(t)) return false; // codes, numbers, symbols
      return true;
    }).toList();
    expect(same, isEmpty, reason: same.join('\n'));
  });

  test('no English sentence is shown without a translation', () {
    final bare = <String>[];
    for (final f in sources()) {
      final lines = f.readAsLinesSync();
      for (var n = 0; n < lines.length; n++) {
        for (final m in RegExp(r"""Text\(\s*'([^'$]*[a-z]{2,}[^']*\s[^']*)'""").allMatches(lines[n])) {
          if (!sameInBoth.any((w) => m.group(1)!.startsWith(w))) bare.add('${f.path}:${n + 1}  ${m.group(1)}');
        }
      }
    }
    expect(bare, isEmpty, reason: bare.join('\n'));
  });
}
