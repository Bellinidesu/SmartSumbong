// SmartSumbong — Cloudinary upload path.
//
// Every photo in the system goes through this file: complaint evidence,
// registration ID cards, and (in the tanod app) resolution proof.
//
// Why unsigned. The registration ID card is uploaded before the account
// exists — there is no JWT to sign with and no session to authorise. A
// signature endpoint would therefore have to issue signatures to
// unauthenticated callers, which is unsigned upload with extra steps and
// an extra thing to keep running. So: unsigned, with the guardrails on
// the preset (below) and the URL pinned in the database by migration
// 0017 so that a forged upload cannot become a rendered image.
//
// PRESET CONFIGURATION — set these in the Cloudinary console on
// `smartsumbong_unsigned`. They are not optional; the code below assumes
// them and the database CHECK constraint will reject uploads made
// without them.
//
//   Signing mode           Unsigned
//   Folder                 smartsumbong
//   Unique filename        Off        (we supply our own public_id)
//   Use filename           Off        (never leak the resident's filename)
//   Incoming transformation  c_limit,w_1920,q_auto
//   Allowed formats        jpg, png, webp
//   Format                 jpg
//   Max file size          10000000
//   Return delete token    On
//
// The incoming transformation MUST live on the preset. An unsigned
// upload request may not carry a `transformation` parameter — Cloudinary
// rejects it outright ("Transformation parameter is not allowed when
// using unsigned upload"). The allowed request parameters are
// upload_preset, public_id, folder, tags, context, metadata, source,
// filename_override and a few others; transformation is not among them.
// Everything else is preset-side.
//
// The incoming transformation also re-encodes the file, which is what
// drops EXIF from the stored asset. That matters more than the file
// size: a phone photo carries GPS coordinates in EXIF, and a resident
// who files anonymously about their own street would otherwise publish
// their home location inside the evidence. Verify this once against a
// real photo from a real handset before trusting it.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

/// Where an upload lands inside the `smartsumbong` folder.
enum MediaKind {
  /// Complaint evidence. Attached to `report_media`.
  reportPhoto('reports'),

  /// Government ID or barangay appointment card, uploaded during
  /// registration before any account exists. Lands in `users.id_image_url`.
  identityCard('ids'),

  /// Optional registration selfie. Lands in `users.selfie_url`.
  selfie('selfies'),

  /// Tanod field proof. Attached to `dispatch_media`.
  fieldProof('dispatch');

  const MediaKind(this.folder);
  final String folder;
}

/// A successfully stored asset, in the shape `file_report()` expects.
class UploadedMedia {
  const UploadedMedia({
    required this.mediaUrl,
    required this.mimeType,
    required this.bytes,
    required this.publicId,
    this.deleteToken,
  });

  final String mediaUrl;
  final String mimeType;
  final int bytes;
  final String publicId;

  /// Valid for ten minutes after upload. Used to clean up an asset whose
  /// complaint never got filed — see [MediaUploader.discard].
  final String? deleteToken;

  Map<String, dynamic> toJson() => {
        'media_url': mediaUrl,
        'mime_type': mimeType,
        'bytes': bytes,
      };
}

class MediaUploadException implements Exception {
  MediaUploadException(this.message, {this.isRetryable = false});
  final String message;
  final bool isRetryable;
  @override
  String toString() => message;
}

class MediaUploader {
  MediaUploader({
    required this.cloudName,
    required this.uploadPreset,
    http.Client? client,
    ImagePicker? picker,
  })  : _client = client ?? http.Client(),
        _picker = picker ?? ImagePicker();

  final String cloudName;
  final String uploadPreset;
  final http.Client _client;
  final ImagePicker _picker;

  static const _uuid = Uuid();
  static const _rootFolder = 'smartsumbong';

  /// Longest edge, in pixels. Matches `c_limit,w_1920` on the preset —
  /// we do it here as well so a resident on mobile data uploads roughly
  /// 400 KB instead of 5 MB. The preset transformation is the backstop
  /// for anything that reaches Cloudinary un-resized.
  static const _maxEdge = 1920.0;

  /// JPEG quality for the on-device re-encode.
  static const _quality = 85;

  /// Refuse before the network is touched. The preset enforces the same
  /// ceiling server-side; this only saves a doomed upload.
  static const _maxBytes = 10 * 1024 * 1024;

  /// Mirrors `public.is_media_url()` in migration 0017. If a URL fails
  /// here it will fail the CHECK constraint, so we fail early and
  /// loudly rather than discovering it when the complaint is submitted.
  static final _pinnedUrl = RegExp(
    r'^https://res\.cloudinary\.com/[a-z0-9]+/image/upload/(v[0-9]+/)?'
    r'smartsumbong/[A-Za-z0-9_/-]+\.(jpg|jpeg|png|webp)$',
  );

  Uri get _endpoint =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  /// Pick one photo and hand back a file already scaled and re-encoded.
  ///
  /// `maxWidth`/`maxHeight` scale to fit inside the box, and passing
  /// `imageQuality` forces a re-encode on both platforms, which is the
  /// first of the two EXIF strips.
  Future<File?> pick({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickImage(
      source: source,
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
      requestFullMetadata: false, // do not ask iOS for location metadata
    );
    return picked == null ? null : File(picked.path);
  }

  Future<List<File>> pickMultiple({int limit = 5}) async {
    final picked = await _picker.pickMultiImage(
      maxWidth: _maxEdge,
      maxHeight: _maxEdge,
      imageQuality: _quality,
      requestFullMetadata: false,
      limit: limit,
    );
    return picked.map((x) => File(x.path)).toList();
  }

  /// Upload one file. Retries transient failures with backoff; does not
  /// retry anything Cloudinary rejected on the merits.
  Future<UploadedMedia> upload(
    File file, {
    required MediaKind kind,
    int attempts = 3,
    void Function(int sent, int total)? onProgress,
  }) async {
    final length = await file.length();
    if (length <= 0) {
      throw MediaUploadException('That file is empty.');
    }
    if (length > _maxBytes) {
      throw MediaUploadException(
        'That photo is larger than 10 MB even after resizing. '
        'Try taking it again at a lower resolution.',
      );
    }

    // Unique per upload because the preset has Unique filename off, and
    // because unsigned uploads force overwrite=false — a collision would
    // fail rather than silently replace. Also: the delivery URL is
    // public to anyone holding it, so an unguessable id is the only
    // thing standing between a complaint photo and a scraper walking
    // sequential names. That is obscurity, not access control. Say so in
    // the defence; the alternative is Cloudinary's authenticated
    // delivery type, which needs the API secret to sign every view.
    final publicId = '${kind.folder}/${_uuid.v4()}';

    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        return await _postOnce(file, publicId, length, onProgress);
      } on MediaUploadException catch (e) {
        lastError = e;
        if (!e.isRetryable || attempt == attempts) rethrow;
      } on SocketException catch (e) {
        lastError = e;
        if (attempt == attempts) {
          throw MediaUploadException(
            'No connection while uploading. Your report has not been sent.',
            isRetryable: true,
          );
        }
      } on HttpException catch (e) {
        lastError = e;
        if (attempt == attempts) {
          throw MediaUploadException(
            'The upload was interrupted. Please try again.',
            isRetryable: true,
          );
        }
      }
      await Future<void>.delayed(Duration(seconds: 1 << (attempt - 1)));
    }
    throw MediaUploadException('Upload failed: $lastError', isRetryable: true);
  }

  Future<UploadedMedia> _postOnce(
    File file,
    String publicId,
    int length,
    void Function(int sent, int total)? onProgress,
  ) async {
    final request = http.MultipartRequest('POST', _endpoint)
      ..fields['upload_preset'] = uploadPreset
      ..fields['public_id'] = publicId
      // `source` is one of the parameters unsigned uploads do allow, and
      // it tags the asset in the Cloudinary console with where it came
      // from. Useful when the barangay asks what is filling the quota.
      ..fields['source'] = 'smartsumbong-resident'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    onProgress?.call(0, length);

    final streamed = await _client.send(request).timeout(
          const Duration(seconds: 60),
          onTimeout: () => throw MediaUploadException(
            'The upload timed out. Please try again on a better connection.',
            isRetryable: true,
          ),
        );

    final body = await streamed.stream.bytesToString();
    onProgress?.call(length, length);

    if (streamed.statusCode >= 500) {
      throw MediaUploadException(
        'Cloudinary is not responding. Please try again shortly.',
        isRetryable: true,
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw MediaUploadException(
        'Unexpected response from the media service.',
        isRetryable: true,
      );
    }

    if (streamed.statusCode != 200) {
      final message =
          (json['error'] as Map<String, dynamic>?)?['message'] as String? ??
              'Upload rejected (HTTP ${streamed.statusCode}).';
      // 400 here is almost always a preset misconfiguration, not a user
      // error. Surface it verbatim in debug builds.
      throw MediaUploadException(_friendly(message));
    }

    final url = json['secure_url'] as String?;
    if (url == null || !_pinnedUrl.hasMatch(url)) {
      throw MediaUploadException(
        'The media service returned an address this app will not accept. '
        'Check the upload preset folder and allowed formats.',
      );
    }

    final format = (json['format'] as String? ?? 'jpg').toLowerCase();
    return UploadedMedia(
      mediaUrl: url,
      mimeType: switch (format) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      },
      // Cloudinary's own count of the stored asset, not the phone's count
      // of what was sent. They differ, because the preset re-encodes.
      bytes: (json['bytes'] as num?)?.toInt() ?? length,
      publicId: json['public_id'] as String? ?? '$_rootFolder/$publicId',
      deleteToken: json['delete_token'] as String?,
    );
  }

  /// Delete an asset whose complaint was never filed — the resident
  /// backed out, or `file_report()` rolled back. Best effort: the token
  /// expires ten minutes after upload, and a failure here costs quota,
  /// not correctness. Never surface an error from this to the resident.
  Future<void> discard(UploadedMedia media) async {
    final token = media.deleteToken;
    if (token == null) return;
    try {
      await _client.post(
        Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/delete_by_token'),
        body: {'token': token},
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Orphan stays. It is inside `smartsumbong/reports/` with a random
      // name and is referenced by nothing.
    }
  }

  String _friendly(String cloudinaryMessage) {
    final m = cloudinaryMessage.toLowerCase();
    if (m.contains('file size') || m.contains('too large')) {
      return 'That photo is too large. Please choose a smaller one.';
    }
    if (m.contains('format')) {
      return 'That file type is not supported. Use a JPG or PNG photo.';
    }
    if (m.contains('preset')) {
      return 'Media uploads are misconfigured. Please report this to the barangay.';
    }
    return 'The photo could not be uploaded. Please try again.';
  }

  void dispose() => _client.close();
}
