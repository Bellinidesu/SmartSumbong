// SmartSumbong — the report outbox (branch B).
//
// A report filed with no signal used to fail with "check your connection"
// and leave the resident to try again later. Now it is kept on the phone
// — the text, place and category, plus its own copies of the photos and
// video — and sent by itself when the connection comes back: at launch,
// when the phone reconnects, when the app returns to the foreground, or
// when the resident taps Send now on the Reports screen.
//
// Safe to resend. Every queued report carries a client-generated id that
// file_report() (0066) recognises: a resend of a report the server
// already filed (its reply lost to the dropped connection) returns that
// report instead of filing a second one. Photos already uploaded are
// remembered, so a retry never uploads them twice.
//
// A report the server refuses outright — the account suspended, the
// photo cap, a policy — is not retried forever: it stays in the list
// with the reason, for the resident to discard.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'location_lookup.dart';

class OutboxItem {
  OutboxItem({
    required this.id,
    required this.category,
    required this.subject,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.anonymous,
    required this.photos,
    required this.video,
    required this.uploaded,
    required this.uploadedVideo,
    required this.queuedAt,
    this.error,
  });

  /// Also the report's client_ref (0066).
  final String id;
  final String category;
  final String subject;
  final String description;
  final double latitude;
  final double longitude;
  final bool anonymous;

  /// Paths of the outbox's own copies.
  final List<String> photos;
  final String? video;

  /// file_report()'s media rows for what has already reached Cloudinary.
  final List<Map<String, dynamic>> uploaded;
  Map<String, dynamic>? uploadedVideo;
  final DateTime queuedAt;

  /// Set when the server refused it; such an item is not retried.
  String? error;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'subject': subject,
        'description': description,
        'latitude': latitude,
        'longitude': longitude,
        'anonymous': anonymous,
        'photos': photos,
        'video': video,
        'uploaded': uploaded,
        'uploadedVideo': uploadedVideo,
        'queuedAt': queuedAt.toIso8601String(),
        'error': error,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'] as String,
        category: j['category'] as String,
        subject: j['subject'] as String,
        description: j['description'] as String,
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        anonymous: j['anonymous'] as bool? ?? false,
        photos: [for (final p in (j['photos'] as List? ?? const [])) p as String],
        video: j['video'] as String?,
        uploaded: [
          for (final m in (j['uploaded'] as List? ?? const []))
            Map<String, dynamic>.from(m as Map),
        ],
        uploadedVideo: j['uploadedVideo'] == null
            ? null
            : Map<String, dynamic>.from(j['uploadedVideo'] as Map),
        queuedAt: DateTime.tryParse(j['queuedAt'] as String? ?? '') ??
            DateTime.now(),
        error: j['error'] as String?,
      );
}

class Outbox extends ChangeNotifier {
  Outbox._();

  static final instance = Outbox._();

  /// For telling the resident a queued report went through, whatever
  /// screen they are on. Set on MaterialApp in main.dart.
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Filled in by main.dart: what to say once a queued report is filed.
  static String Function(String? trackingId)? sentMessage;

  MediaUploader? _uploader;
  List<OutboxItem> items = const [];
  bool _loaded = false;
  bool _flushing = false;
  StreamSubscription<List<ConnectivityResult>>? _net;

  static String newRef() => const Uuid().v4();

  /// Called by main.dart once it has the uploader. Safe to call again.
  void attach(MediaUploader uploader) {
    _uploader = uploader;
    if (_net != null) return;
    _net = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((c) => c != ConnectivityResult.none)) unawaited(flush());
    });
    unawaited(_load().then((_) => flush()));
  }

  /// Whether the phone has any network at all right now. A "yes" is not a
  /// promise the server is reachable — sending still catches that.
  static Future<bool> isOnline() async {
    try {
      final r = await Connectivity().checkConnectivity();
      return r.any((c) => c != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// True for the failures a retry can fix: no network, a dropped
  /// connection, a timeout — not a refusal from the server.
  static bool isNetworkError(Object e) {
    if (e is MediaUploadException) return e.isRetryable;
    if (e is SocketException || e is TimeoutException) return true;
    if (e is AuthRetryableFetchException) return true;
    final t = e.toString();
    return t.contains('SocketException') ||
        t.contains('ClientException') ||
        t.contains('Failed host lookup') ||
        t.contains('Connection closed') ||
        t.contains('Connection reset');
  }

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory('${base.path}/outbox');
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
        for (final j in list)
          OutboxItem.fromJson(Map<String, dynamic>.from(j as Map)),
      ];
      notifyListeners();
    } catch (_) {
      // An unreadable outbox is an empty one; nothing else depends on it.
    }
  }

  Future<void> _save() async {
    try {
      final f = File('${(await _dir()).path}/outbox.json');
      await f.writeAsString(jsonEncode([for (final i in items) i.toJson()]));
    } catch (_) {}
  }

  /// Keeps a report for sending later. [photos] and [video] are copied in,
  /// so the originals may go; [uploaded]/[uploadedVideo] are what already
  /// reached Cloudinary before the connection dropped.
  Future<void> enqueue({
    required String id,
    required String category,
    required String subject,
    required String description,
    required double latitude,
    required double longitude,
    required bool anonymous,
    required List<File> photos,
    File? video,
    List<Map<String, dynamic>> uploaded = const [],
    Map<String, dynamic>? uploadedVideo,
  }) async {
    await _load();
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
    final videoPath = video == null ? null : await keep(video, 'video');

    items = [
      ...items.where((i) => i.id != id),
      OutboxItem(
        id: id,
        category: category,
        subject: subject,
        description: description,
        latitude: latitude,
        longitude: longitude,
        anonymous: anonymous,
        photos: photoPaths,
        video: videoPath,
        uploaded: [...uploaded],
        uploadedVideo: uploadedVideo,
        queuedAt: DateTime.now(),
      ),
    ];
    await _save();
    notifyListeners();
  }

  /// Sends what can be sent. Stops at the first sign the network is still
  /// down; skips items the server has already refused.
  Future<void> flush() async {
    await _load();
    final uploader = _uploader;
    if (_flushing || uploader == null || items.isEmpty) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    if (!await isOnline()) return;
    _flushing = true;
    try {
      for (final item in [...items]) {
        if (item.error != null) continue;
        try {
          // Photos in order; each one remembered as soon as it lands.
          for (var i = item.uploaded.length; i < item.photos.length; i++) {
            final up = await uploader.upload(File(item.photos[i]),
                kind: MediaKind.reportPhoto);
            item.uploaded.add(up.toJson());
            await _save();
          }
          if (item.video != null && item.uploadedVideo == null) {
            final up = await uploader.uploadVideo(File(item.video!),
                kind: MediaKind.reportPhoto);
            item.uploadedVideo = up.toJson();
            await _save();
          }
          final row = await Supabase.instance.client.rpc(
            'file_report',
            params: {
              'p_category': item.category,
              'p_subject': item.subject,
              'p_description': item.description,
              'p_latitude': item.latitude,
              'p_longitude': item.longitude,
              'p_is_anonymous': item.anonymous,
              'p_media': [
                ...item.uploaded,
                if (item.uploadedVideo != null) item.uploadedVideo!,
              ],
              'p_client_ref': item.id,
            },
          );
          await _remove(item.id);
          // The street it was filed on, saved for the portal and tanods (0068).
          unawaited(ReverseGeocode.labelReport(Supabase.instance.client, row));
          final msg = sentMessage?.call(row is Map ? row['tracking_id'] as String? : null);
          if (msg != null) {
            messengerKey.currentState
                ?.showSnackBar(SnackBar(content: Text(msg)));
          }
        } catch (e) {
          if (isNetworkError(e)) return; // still offline; try again later
          item.error = e is PostgrestException
              ? e.message
              : e is MediaUploadException
                  ? e.message
                  : e.toString();
          await _save();
          notifyListeners();
        }
      }
    } finally {
      _flushing = false;
    }
  }

  /// Tries a refused item again (the resident fixed what was wrong).
  Future<void> retry(String id) async {
    for (final i in items) {
      if (i.id == id) i.error = null;
    }
    await _save();
    notifyListeners();
    await flush();
  }

  Future<void> discard(String id) => _remove(id);

  Future<void> _remove(String id) async {
    items = [...items.where((i) => i.id != id)];
    await _save();
    notifyListeners();
    try {
      final dir = Directory('${(await _dir()).path}/$id');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}
