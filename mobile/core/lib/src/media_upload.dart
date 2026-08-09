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
// 0018 so that a forged upload cannot become a rendered image.
//
// PRESET CONFIGURATION — set on `smartsumbong_unsigned`:
//
//   Signing mode             Unsigned
//   Asset folder             smartsumbong
//   Unique filename          Off        (we supply our own public_id)
//   Use filename             Off        (never leak the resident's filename)
//   Incoming transformation  c_limit,w_1920,q_auto
//   Allowed formats          jpg, png, webp
//   Format                   jpg
//   Max file size            10000000
//
// The incoming transformation MUST live on the preset. An unsigned
// upload request may not carry a `transformation` parameter — Cloudinary
// rejects it outright. Only upload_preset, public_id, folder, tags,
// context, metadata, source and a few others are accepted on the
// request; everything else is preset-side.
//
// EXIF — READ THIS BEFORE CHANGING ANYTHING BELOW.
//
// An earlier version of this file claimed the incoming transformation
// strips EXIF. That was wrong, and it was tested: a photo uploaded from
// a POCO X7 came back re-encoded (477657 bytes in, 392666 out) with all
// 44 EXIF tags intact, including Make, Model, DateTimeOriginal and
// MakerNote. Cloudinary re-encodes the pixels and carries the metadata
// through. It does not strip.
//
// GPS was absent in that test only because Android's photo picker
// removes location unless the app holds ACCESS_MEDIA_LOCATION. That
// protection is not ours, it varies by Android version and OEM, and it
// does not apply to ImageSource.camera at all.
//
// This matters because of the anonymous option. A resident reporting a
// problem outside their own house, filing anonymously, with a photo
// taken through the camera, would otherwise publish their home
// coordinates inside the evidence — on a public URL. DateTimeOriginal
// and MakerNote leak too: an exact capture second plus a device
// fingerprint is enough to correlate several anonymous complaints to one
// phone.
//
// So we strip it ourselves, here, before the bytes leave the device.
// flutter_image_compress drops EXIF by default (keepExif is false) and
// bakes rotation into the pixels, so orientation survives without the
// tag. Do not set keepExif: true. Do not rely on Cloudinary or on the
// picker for this.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Where an upload lands inside the `smartsumbong` asset folder.
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
  });

  final String mediaUrl;
  final String mimeType;
  final int bytes;
  final String publicId;

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

  /// Target for the on-device re-encode. flutter_image_compress scales so
  /// that both dimensions are at least this, preserving aspect — a 4:3
  /// photo lands at 2560x1920, not 1920x1440. Cloudinary's c_limit,w_1920
  /// caps the width on top of that. The point of this pass is the EXIF
  /// strip; the size reduction is a bonus for residents on mobile data.
  static const _minEdge = 1920;

  /// JPEG quality for the on-device re-encode.
  static const _quality = 85;

  /// Refuse before the network is touched. The preset enforces the same
  /// ceiling server-side; this only saves a doomed upload.
  static const _maxBytes = 10 * 1024 * 1024;

  /// Mirrors `public.is_media_url()` in migration 0018.
  ///
  /// No folder segment. The preset uses dynamic folders with "use asset
  /// folder as public id prefix" off, so `smartsumbong` is organisational
  /// metadata and never reaches the URL — verified against a real
  /// upload. Pinning it would be theatre in any case: the preset applies
  /// it to every caller, so it constrains nobody. What does constrain a
  /// forged URL is the cloud prefix plus a UUID-shaped name — media_url
  /// cannot point at a host the attacker controls, nor at an asset they
  /// named themselves.
  static final _pinnedUrl = RegExp(
    r'^https://res\.cloudinary\.com/nwb2kryl/image/upload/v[0-9]+/'
    r'(reports|ids|selfies|dispatch)/'
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    r'\.(jpg|jpeg|png|webp)$',
  );

  Uri get _endpoint =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  /// Pick one photo and hand back a file that is scaled, re-encoded, and
  /// stripped of metadata. The returned file is a temporary copy — the
  /// resident's original in their gallery is untouched.
  Future<File?> pick({ImageSource source = ImageSource.gallery}) async {
    final picked = await _picker.pickImage(
      source: source,
      requestFullMetadata: false, // do not ask iOS for location metadata
    );
    return picked == null ? null : _sanitise(File(picked.path));
  }

  Future<List<File>> pickMultiple({int limit = 5}) async {
    final picked = await _picker.pickMultiImage(
      requestFullMetadata: false,
      limit: limit,
    );
    return [for (final x in picked) await _sanitise(File(x.path))];
  }

  /// The EXIF strip. Everything the app uploads passes through here.
  ///
  /// keepExif defaults to false and must stay that way; autoCorrectionAngle
  /// rotates the pixels so the image still displays the right way up once
  /// the Orientation tag is gone.
  Future<File> _sanitise(File input) async {
    final dir = await getTemporaryDirectory();
    final target = '${dir.path}/${_uuid.v4()}.jpg';

    final out = await FlutterImageCompress.compressAndGetFile(
      input.absolute.path,
      target,
      minWidth: _minEdge,
      minHeight: _minEdge,
      quality: _quality,
      format: CompressFormat.jpeg,
      keepExif: false,
      autoCorrectionAngle: true,
    );

    if (out == null) {
      throw MediaUploadException(
        'That photo could not be processed. Please try another one.',
      );
    }
    return File(out.path);
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
    // fail rather than silently replace. Also: the delivery URL is public
    // to anyone holding it, so an unguessable id is the only thing
    // standing between a complaint photo and a scraper walking sequential
    // names. That is obscurity, not access control. Say so in the
    // defence; the alternative is Cloudinary's authenticated delivery
    // type, which needs the API secret to sign every view.
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
      ..fields['source'] = 'smartsumbong-mobile'
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
      throw MediaUploadException(_friendly(message));
    }

    final url = json['secure_url'] as String?;
    if (url == null || !_pinnedUrl.hasMatch(url)) {
      throw MediaUploadException(
        'The media service returned an address this app will not accept. '
        'Check the upload preset configuration.',
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
      publicId: json['public_id'] as String? ?? publicId,
    );
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
