// SCRATCH — delete once the upload path is proven.
//
// Run with:
//   flutter run --dart-define-from-file=dart_defines.json

import 'dart:io';

import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:smartsumbong_core/smartsumbong_core.dart';

const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

void main() => runApp(const HarnessApp());

class HarnessApp extends StatelessWidget {
  const HarnessApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Upload harness',
        theme: ThemeData(useMaterial3: true),
        home: const HarnessPage(),
      );
}

class HarnessPage extends StatefulWidget {
  const HarnessPage({super.key});

  @override
  State<HarnessPage> createState() => _HarnessPageState();
}

class _HarnessPageState extends State<HarnessPage> {
  late final MediaUploader _uploader = MediaUploader(
    cloudName: _cloudName,
    uploadPreset: _uploadPreset,
  );

  File? _file;
  final _log = StringBuffer();
  bool _busy = false;

  void _say(String line) {
    debugPrint(line);
    setState(() => _log.writeln(line));
  }

  @override
  void dispose() {
    _uploader.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() {
      _log.clear();
      _file = null;
    });

    if (_cloudName.isEmpty || _uploadPreset.isEmpty) {
      _say('MISSING --dart-define. Cloud name and preset are both empty.');
      return;
    }

    final f = await _uploader.pick();
    if (f == null) {
      _say('Cancelled.');
      return;
    }

    final bytes = await f.length();
    _say('Local file: ${f.path.split(Platform.pathSeparator).last}');
    _say('Local size: $bytes bytes (${(bytes / 1024).round()} KB)');

    final tags = await readExifFromBytes(await f.readAsBytes());
    final gps = tags.keys.where((k) => k.startsWith('GPS')).toList();

    if (tags.isEmpty) {
      _say('Local EXIF: none at all (already re-encoded).');
    } else {
      _say('Local EXIF: ${tags.length} tags.');
      _say(gps.isEmpty
          ? 'Local GPS:  ABSENT — picker stripped it, EXIF test inconclusive.'
          : 'Local GPS:  PRESENT (${gps.length} tags) — test is valid.');
      for (final k in gps) {
        _say('  $k = ${tags[k]}');
      }
    }

    setState(() => _file = f);
  }

  /// Fetch back what Cloudinary actually serves and read its EXIF. This is
  /// the observation, not the inference: whatever survives here is what a
  /// resident publishes when they attach a photo to a complaint.
  Future<void> _checkDelivered(String url) async {
    _say('');
    _say('Fetching delivered asset…');
    final res = await http.get(Uri.parse(url));
    _say('HTTP ${res.statusCode}, ${res.bodyBytes.length} bytes');

    final tags = await readExifFromBytes(res.bodyBytes);
    final gps = tags.keys.where((k) => k.startsWith('GPS')).toList();
    _say('Delivered EXIF: ${tags.length} tags');
    _say('Delivered GPS:  ${gps.isEmpty ? "ABSENT" : "PRESENT (${gps.length})"}');
    for (final k in tags.keys) {
      _say('  $k');
    }
  }

  Future<void> _upload() async {
    final f = _file;
    if (f == null) return;

    setState(() => _busy = true);
    try {
      final m = await _uploader.upload(f, kind: MediaKind.reportPhoto);
      _say('');
      _say('UPLOAD OK');
      _say('url:       ${m.mediaUrl}');
      _say('public_id: ${m.publicId}');
      _say('mime:      ${m.mimeType}');
      _say('bytes:     ${m.bytes}  (was ${await f.length()} locally)');
      await _checkDelivered(m.mediaUrl);
    } on MediaUploadException catch (e) {
      _say('');
      _say('UPLOAD FAILED: ${e.message}');
      _say('retryable: ${e.isRetryable}');
    } catch (e) {
      _say('');
      _say('UNEXPECTED: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Upload harness')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _pick,
                      child: const Text('Pick photo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (_file == null || _busy) ? null : _upload,
                      child: Text(_busy ? 'Working…' : 'Upload'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _log.isEmpty ? 'No output yet.' : _log.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
