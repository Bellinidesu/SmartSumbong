// The self-updater (0161): what the phone makes of a published release, and the checksum that stands between a download and the installer.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resident/dev/app_updater.dart';

void main() {
  final sha = 'a1' * 32;

  test('a published release is read as it is: version, build, link, checksum, notes in both languages, must update', () {
    final r = AppRelease.fromJson({
      'version': '1.1.0', 'build': 5, 'apk_url': 'https://example.org/a.apk', 'sha256': sha, 'notes_en': 'Faster map', 'notes_fil': 'Mas mabilis na mapa', 'mandatory': true,
    });
    expect(r, isNotNull);
    expect(r!.version, '1.1.0');
    expect(r.build, 5);
    expect(r.notesFil, 'Mas mabilis na mapa');
    expect(r.mandatory, isTrue);
    expect(AppRelease.fromJson({'version': '1.0.2', 'build': 6, 'apk_url': 'https://example.org/b.apk', 'sha256': sha})!.mandatory, isFalse);
  });

  test('a half-made, plain-http or badly checksummed release is never offered', () {
    expect(AppRelease.fromJson(null), isNull);
    expect(AppRelease.fromJson({'version': '1.1.0'}), isNull);
    expect(AppRelease.fromJson({'version': '1.1.0', 'build': 5, 'apk_url': 'http://example.org/a.apk', 'sha256': sha}), isNull);
    expect(AppRelease.fromJson({'version': '1.1.0', 'build': 5, 'apk_url': 'https://example.org/a.apk', 'sha256': 'abc'}), isNull);
    expect(AppRelease.fromJson({'version': '1.1.0', 'build': 5, 'apk_url': 'https://example.org/a.apk', 'sha256': sha.toUpperCase()}), isNull);
  });

  test('only a higher build is an update', () {
    expect(AppUpdater.isNewer(4, 5), isTrue);
    expect(AppUpdater.isNewer(5, 5), isFalse);
    expect(AppUpdater.isNewer(6, 5), isFalse);
  });

  test('a file is installed only if its SHA-256 is the published one', () async {
    final dir = await Directory.systemTemp.createTemp('upd');
    final f = File('${dir.path}/x.apk');
    await f.writeAsBytes(List<int>.generate(5000, (i) => i % 251));
    final real = sha256.convert(await f.readAsBytes()).toString();
    expect(await AppUpdater.checksumMatches(f, real), isTrue);
    expect(await AppUpdater.checksumMatches(f, real.toUpperCase()), isTrue);
    expect(await AppUpdater.checksumMatches(f, sha), isFalse);
    await dir.delete(recursive: true);
  });
}
