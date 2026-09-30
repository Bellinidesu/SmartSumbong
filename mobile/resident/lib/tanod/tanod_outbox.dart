// SmartSumbong — the tanod's outbox (0073, use case "Upload Report
// Status to Admin": if the connection is unavailable, the update is saved
// on the phone and synced automatically once reconnected).
//
// What the dispatch window sends with no signal waits here: an update
// (text and photos), a step (On the way / Arrived), or the resolution
// (report, photos and video). Each keeps its own copies of the files and
// remembers what already reached Cloudinary, so a retry never uploads
// twice. It sends by itself when the phone reconnects, when the app
// opens, and when it comes back to the foreground — the same triggers as
// the resident's report outbox (outbox.dart), and the same test for
// "the network, not the server, said no".
//
// A refusal from the server (the dispatch was rerouted meanwhile, say)
// is not retried: the item stays with the reason, for the tanod to
// discard.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../outbox.dart' show Outbox;

const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
const _videoPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET_VIDEO');

class TanodOutboxItem {
  TanodOutboxItem({
    required this.id,
    required this.kind,
    required this.dispatchId,
    required this.queuedAt,
    this.body,
    this.step,
    this.photos = const [],
    this.video,
    List<Map<String, dynamic>>? uploaded,
    this.uploadedVideo,
    this.mediaSaved = false,
    this.error,
  }) : uploaded = uploaded ?? [];

  final String id;

  /// 'update', 'step' or 'resolve'.
  final String kind;
  final String dispatchId;
  final String? body;
  final String? step;
  final List<String> photos;
  final String? video;
  final List<Map<String, dynamic>> uploaded;
  Map<String, dynamic>? uploadedVideo;

  /// For a resolution: its proof rows are already in dispatch_media.
  bool mediaSaved;
  final DateTime queuedAt;
  String? error;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'dispatch_id': dispatchId,
        'body': body,
        'step': step,
        'photos': photos,
        'video': video,
        'uploaded': uploaded,
        'uploaded_video': uploadedVideo,
        'media_saved': mediaSaved,
        'queued_at': queuedAt.toIso8601String(),
        'error': error,
      };

  static TanodOutboxItem fromJson(Map<String, dynamic> j) => TanodOutboxItem(
        id: j['id'] as String,
        kind: j['kind'] as String,
        dispatchId: j['dispatch_id'] as String,
        body: j['body'] as String?,
        step: j['step'] as String?,
        photos: [for (final p in (j['photos'] as List? ?? const [])) p as String],
        video: j['video'] as String?,
        uploaded: [
          for (final u in (j['uploaded'] as List? ?? const []))
            Map<String, dynamic>.from(u as Map),
        ],
        uploadedVideo: j['uploaded_video'] == null
            ? null
            : Map<String, dynamic>.from(j['uploaded_video'] as Map),
        mediaSaved: j['media_saved'] == true,
        queuedAt: DateTime.tryParse(j['queued_at'] as String? ?? '') ?? DateTime.now(),
        error: j['error'] as String?,
      );
}

class TanodOutbox extends ChangeNotifier {
  TanodOutbox._();
  static final instance = TanodOutbox._();

  List<TanodOutboxItem> items = [];
  bool _loaded = false;
  bool _flushing = false;
  StreamSubscription<List<ConnectivityResult>>? _net;

  final _uploader = MediaUploader(
    cloudName: _cloudName,
    uploadPreset: _uploadPreset,
    videoUploadPreset: _videoPreset.isEmpty ? null : _videoPreset,
  );

  /// Waiting items for one dispatch, oldest first.
  List<TanodOutboxItem> forDispatch(String dispatchId) =>
      items.where((i) => i.dispatchId == dispatchId).toList();

  /// Called once at startup (main.dart). Safe to call again.
  void start() {
    if (_net != null) return;
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((c) => c != ConnectivityResult.none)) unawaited(flush());
    });
    unawaited(_load().then((_) => flush()));
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/tanod_outbox');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = File('${(await _dir()).path}/outbox.json');
      if (!await f.exists()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      items = [
        for (final j in list) TanodOutboxItem.fromJson(Map<String, dynamic>.from(j as Map)),
      ];
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final f = File('${(await _dir()).path}/outbox.json');
      await f.writeAsString(jsonEncode([for (final i in items) i.toJson()]));
    } catch (_) {}
  }

  /// Keeps something for sending later; files are copied in, so the
  /// originals may go.
  Future<void> enqueue({
    required String kind,
    required String dispatchId,
    String? body,
    String? step,
    List<File> photos = const [],
    File? video,
  }) async {
    await _load();
    final id = const Uuid().v4();
    final dir = Directory('${(await _dir()).path}/$id');
    await dir.create(recursive: true);
    Future<String> keep(File f, String name) async {
      final ext = f.path.contains('.') ? f.path.split('.').last : 'bin';
      return (await f.copy('${dir.path}/$name.$ext')).path;
    }

    final photoPaths = <String>[];
    for (var i = 0; i < photos.length; i++) {
      photoPaths.add(await keep(photos[i], 'photo$i'));
    }
    items = [
      ...items,
      TanodOutboxItem(
        id: id,
        kind: kind,
        dispatchId: dispatchId,
        body: body,
        step: step,
        photos: photoPaths,
        video: video == null ? null : await keep(video, 'video'),
        queuedAt: DateTime.now(),
      ),
    ];
    await _save();
    notifyListeners();
  }

  Future<void> discard(String id) async {
    items = items.where((i) => i.id != id).toList();
    await _save();
    notifyListeners();
    try {
      final d = Directory('${(await _dir()).path}/$id');
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  /// Sends what can be sent, in order. Stops at the first sign the
  /// network is still down.
  Future<void> flush() async {
    await _load();
    if (_flushing || items.isEmpty) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (!await Outbox.isOnline()) return;
    _flushing = true;
    final client = Supabase.instance.client;
    try {
      for (final item in [...items]) {
        if (item.error != null) continue;
        try {
          // Files first, each remembered as soon as it lands.
          // [uploaded] grows in step with [photos]: resume where it stopped.
          for (var i = item.uploaded.length; i < item.photos.length; i++) {
            final up = await _uploader.upload(File(item.photos[i]), kind: MediaKind.fieldProof);
            item.uploaded.add(up.toJson());
            await _save();
          }
          if (item.video != null && item.uploadedVideo == null) {
            final up = await _uploader.uploadVideo(File(item.video!), kind: MediaKind.fieldProof);
            item.uploadedVideo = up.toJson();
            await _save();
          }

          switch (item.kind) {
            case 'update':
              await client.rpc('post_dispatch_update', params: {
                'p_dispatch': item.dispatchId,
                'p_body': item.body ?? '',
                'p_media': item.uploaded,
              });
            case 'step':
              await client.rpc('set_dispatch_step',
                  params: {'p_dispatch': item.dispatchId, 'p_step': item.step});
            case 'resolve':
              if (!item.mediaSaved &&
                  (item.uploaded.isNotEmpty || item.uploadedVideo != null)) {
                await client.from('dispatch_media').insert([
                  for (final u in [
                    ...item.uploaded,
                    if (item.uploadedVideo != null) item.uploadedVideo!,
                  ])
                    {'dispatch_id': item.dispatchId, ...u},
                ]);
                item.mediaSaved = true;
                await _save();
              }
              try {
                await client.rpc('submit_field_report', params: {
                  'p_dispatch': item.dispatchId,
                  'p_text': item.body ?? '',
                });
              } on PostgrestException catch (e) {
                // The first try reached the server but its reply was lost:
                // the dispatch is already resolved, which is what we wanted.
                if (!e.message.contains('not in an accepted state')) rethrow;
              }
          }
          await discard(item.id);
        } catch (e) {
          if (Outbox.isNetworkError(e)) break;
          item.error = e is PostgrestException ? e.message : e.toString();
          await _save();
          notifyListeners();
        }
      }
    } finally {
      _flushing = false;
    }
  }
}
