// SmartSumbong — the self-updater (0161).
//
// A super admin publishes a version in the portal's Control Room (App updates): the APK's https link, its SHA-256, notes in English and
// Tagalog, and whether it must be installed. The app asks latest_app_release() (no sign-in needed), and when the published build number is
// higher than its own it offers the update: download, check the SHA-256, hand the file to Android's installer. A file that does not match
// its checksum is deleted and never opened. Android itself still refuses an APK signed with a different key than this app's.
//
// Android only (the APK is the thing). Never in the browser preview or the demo. Quiet when there is nothing to offer, no signal, or the
// server answers nothing: the app is not held up by any of it.

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_ui.dart' show DTr;
import '../i18n.dart';
import '../preview/demo.dart' show kDemo;

class AppRelease {
  const AppRelease({required this.version, required this.build, required this.apkUrl, required this.sha256, this.notesEn, this.notesFil, this.mandatory = false});

  final String version;
  final int build;
  final String apkUrl;
  final String sha256;
  final String? notesEn;
  final String? notesFil;
  final bool mandatory;

  /// null when the answer is not a usable release (so a half-made row is never offered).
  static AppRelease? fromJson(Object? j) {
    if (j is! Map) return null;
    final version = j['version'], build = j['build'], url = j['apk_url'], sha = j['sha256'];
    if (version is! String || build is! int || url is! String || sha is! String) return null;
    if (!url.startsWith('https://') || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) return null;
    return AppRelease(
      version: version,
      build: build,
      apkUrl: url,
      sha256: sha,
      notesEn: j['notes_en'] as String?,
      notesFil: j['notes_fil'] as String?,
      mandatory: j['mandatory'] == true,
    );
  }
}

/// Why an update did not go through.
class UpdateError implements Exception {
  const UpdateError(this.kind);

  /// 'download' (no signal, a bad answer) or 'checksum' (the file is not the one that was published).
  final String kind;
}

class AppUpdater {
  AppUpdater._();

  static bool _asked = false;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && !kDemo;

  /// Whether the offered build is newer than the one running.
  static bool isNewer(int running, int offered) => offered > running;

  /// The published release when it is newer than this app; null when there is none, nothing newer, or no way to tell.
  static Future<AppRelease?> check() async {
    if (!supported) return null;
    try {
      final info = await PackageInfo.fromPlatform();
      final running = int.tryParse(info.buildNumber) ?? 0;
      final r = await Supabase.instance.client.rpc('latest_app_release').timeout(const Duration(seconds: 10));
      final rel = AppRelease.fromJson(r);
      return rel != null && isNewer(running, rel.build) ? rel : null;
    } catch (_) {
      return null;
    }
  }

  /// True when the file's SHA-256 is [expected] (lower-case hex).
  static Future<bool> checksumMatches(File file, String expected) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expected.toLowerCase();
  }

  /// Downloads the APK into the app's temporary folder and checks it. [onProgress] gets 0..1 (null when the size is not known).
  static Future<File> download(AppRelease rel, void Function(double? progress) onProgress) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/smartsumbong-${rel.build}.apk');
    if (await file.exists()) await file.delete();
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(rel.apkUrl))).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw const UpdateError('download');
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(total == null || total == 0 ? null : (got / total).clamp(0.0, 1.0));
        }
      } finally {
        await sink.close();
      }
    } on UpdateError {
      rethrow;
    } catch (_) {
      if (await file.exists()) await file.delete();
      throw const UpdateError('download');
    } finally {
      client.close();
    }
    if (!await checksumMatches(file, rel.sha256)) {
      await file.delete();
      throw const UpdateError('checksum');
    }
    return file;
  }

  /// Hands a checked APK to Android's installer (which asks the person to allow installs from this app the first time).
  static Future<void> install(File file) => OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');

  /// Once per launch, a little after the app is up: offers a newer version. One that can be skipped is offered at most every 12 hours.
  static Future<void> checkOnStart(GlobalKey<NavigatorState> navigator) async {
    if (_asked || !supported) return;
    _asked = true;
    final rel = await check();
    final ctx = navigator.currentContext;
    if (rel == null || ctx == null || !ctx.mounted) return;
    final prefs = await SharedPreferences.getInstance();
    final key = 'update_asked_${rel.build}';
    final last = prefs.getInt(key) ?? 0;
    if (!rel.mandatory && DateTime.now().millisecondsSinceEpoch - last < const Duration(hours: 12).inMilliseconds) return;
    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
    if (!ctx.mounted) return;
    await showUpdateDialog(ctx, rel);
  }

  /// Asked for by a person (Settings): answers either way.
  static Future<void> checkNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final said = context.tr('You have the newest version.', 'Ito na ang pinakabagong bersyon.');
    final rel = await check();
    if (!context.mounted) return;
    if (rel == null) {
      messenger.showSnackBar(SnackBar(content: Text(said)));
      return;
    }
    await showUpdateDialog(context, rel);
  }
}

Future<void> showUpdateDialog(BuildContext context, AppRelease rel) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !rel.mandatory,
    builder: (_) => _UpdateDialog(rel),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog(this.rel);

  final AppRelease rel;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _busy = false;
  double? _progress;
  String? _problem;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _problem = null;
      _progress = null;
    });
    try {
      final file = await AppUpdater.download(widget.rel, (p) {
        if (mounted) setState(() => _progress = p);
      });
      await AppUpdater.install(file);
      if (mounted && !widget.rel.mandatory) Navigator.of(context).pop();
      if (mounted) setState(() => _busy = false);
    } on UpdateError catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _problem = e.kind == 'checksum'
            ? context.tr('The file did not match what was published, so it was not installed.', 'Hindi tugma ang file sa inilathala, kaya hindi ito na-install.')
            : context.tr('Could not download it. Check your connection and try again.', 'Hindi ma-download. Suriin ang koneksyon at subukan muli.');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.rel;
    final fil = AppLocaleScope.of(context) == AppLocale.fil;
    final notes = (fil ? (rel.notesFil ?? rel.notesEn) : (rel.notesEn ?? rel.notesFil))?.trim();
    return PopScope(
      canPop: !rel.mandatory && !_busy,
      child: AlertDialog(
        title: Text(context.tr('A new version is ready', 'May bagong bersyon')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SmartSumbong v${rel.version}', style: const TextStyle(fontWeight: FontWeight.w800)),
            if (notes != null && notes.isNotEmpty) ...[const SizedBox(height: 8), Text(notes)],
            if (rel.mandatory) ...[
              const SizedBox(height: 8),
              Text(context.tr('This update is needed to keep using the app.', 'Kailangan ang update na ito para magamit pa ang app.'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            if (_busy) ...[const SizedBox(height: 14), LinearProgressIndicator(value: _progress)],
            if (_problem != null) ...[const SizedBox(height: 12), Text(_problem!, style: TextStyle(color: Theme.of(context).colorScheme.error))],
          ],
        ),
        actions: [
          if (!rel.mandatory) TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: Text(context.tr('Later', 'Mamaya'))),
          FilledButton(onPressed: _busy ? null : _go, child: Text(_problem != null ? context.tr('Try again', 'Subukan muli') : context.tr('Update', 'I-update'))),
        ],
      ),
    );
  }
}
