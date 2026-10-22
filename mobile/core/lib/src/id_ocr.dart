// SmartSumbong — on-device OCR triage for identification photos.
//
// This is the client half of migration 0039 ("OCR as a verification
// flagger"). That migration's own header is explicit about what this is
// NOT: real government-database identity verification. PSA's own lookup
// is a manual, staff-typed process with no SLA, and an automated check
// needs a paid BSP-licensed API partner — neither is a free path this
// project can take. What IS free: reading back what an ID photo SAYS,
// on the applicant's own device, and flagging anything worth a second
// look before the admin opens it. The admin still decides everything —
// this only tells them where to look first.
//
// PaddleOCR's PP-OCRv6 small models on ONNX Runtime do the reading
// (22 Oct 2026, replacing Google ML Kit: open source end to end): no
// network call, nothing about the photo or its contents ever leaves the
// phone. They were measured against four kinds of invented card in
// tools/ocr_lab; the reading of the lines is id_reader.dart, the same
// logic as the engine's. Advisory only, per 0039's own framing — a
// failed or low-confidence read must never block registration, so every
// failure path here degrades to an honest "couldn't read it" result
// rather than throwing. Phones older than Android 8 (the engine's own
// minimum) and non-Android builds skip the reading the same way: a
// person checks the ID.
//
// On again (22 Oct 2026). The portal has the same switch
// (ID_OCR_ENABLED in admin/includes/accounts.php).

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:paddle_ocr_native/paddle_ocr_native.dart';

import 'auth.dart' show IdDocumentType;
import 'id_reader.dart';
import 'media_upload.dart' show viewableMediaUrl;

const bool kIdOcrEnabled = true;

/// What on-device OCR found on an ID photo, shaped to be written straight
/// to the matching `users.ocr_*` columns (migrations 0039/0040) once the
/// account exists. Every field is nullable/empty by default because OCR
/// is allowed to find nothing — an all-empty result is a valid, honest
/// result, not an error.
class IdOcrResult {
  const IdOcrResult({
    this.detectedType,
    this.flags = const [],
    this.extractedName,
    this.extractedNumber,
  });

  final IdDocumentType? detectedType;
  final List<String> flags;
  final String? extractedName;
  final String? extractedNumber;

  /// Adds `type_mismatch` when [detectedType] disagrees with what the
  /// applicant actually picked in the dropdown, evaluated against
  /// [selected] at the moment you are about to submit — not against
  /// whatever was selected back when the photo was first taken (see
  /// [runIdOcr]'s doc comment for why those can differ). A null
  /// [detectedType] (OCR ran but recognised no known header) never adds
  /// this flag on its own — that is what `unreadable` or an otherwise
  /// unflagged result already covers.
  IdOcrResult withSelectedType(IdDocumentType selected) {
    if (detectedType == null || detectedType == selected) return this;
    return IdOcrResult(
      detectedType: detectedType,
      flags: [...flags, 'type_mismatch'],
      extractedName: extractedName,
      extractedNumber: extractedNumber,
    );
  }

  /// Column names matched exactly to migration 0039. `ocr_processed_at`
  /// is stamped at write time, not at the moment OCR itself ran, since
  /// the two can be seconds apart (OCR runs right after the photo is
  /// captured; the write happens only once the account exists — see
  /// AuthService.submitIdOcrResult).
  Map<String, dynamic> toColumns() => {
        'ocr_detected_type': detectedType?.wire,
        'ocr_flags': flags,
        'ocr_extracted_name': extractedName,
        'ocr_extracted_number': extractedNumber,
        'ocr_processed_at': DateTime.now().toUtc().toIso8601String(),
      };
}

// Measured on the OCR lab's invented cards (22 Oct 2026): the detector shrinks
// to 736 px on the longest side and the lines are read one at a time, which
// kept peak memory near 220 MB with no loss of accuracy against the defaults.
const _config = PaddleOcrConfig(detLimitSideLen: 736, recBatchSize: 1);

Future<bool>? _engineReady;

/// True when the engine can run on this phone: Android 8 or newer. Starts it on
/// first use; a failure is remembered for the session, not retried per photo.
Future<bool> _startEngine() {
  return _engineReady ??= () async {
    try {
      if (!Platform.isAndroid) return false;
      final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
      if (sdk < 26) return false;
      await PaddleOcr().init(config: _config);
      return true;
    } catch (_) {
      return false;
    }
  }();
}

/// Runs on-device text recognition on [image] and compares what it found
/// against [enteredFullName] ("Last Name, First Name" per migration
/// 0032). Deliberately does NOT take the applicant's selected document
/// type — the photo is usually picked before the dropdown is finalised
/// (or changed afterward), so comparing against a snapshot taken here
/// could compare against a value the applicant later changed. Compare
/// [IdOcrResult.detectedType] against the final selection yourself, at
/// the point you are about to submit it (see register_screen.dart).
///
/// Never throws: a corrupt file or the reading itself failing comes back
/// as the same result an unreadable photo would produce, rather than
/// surfacing an error to the applicant. Returns null when this phone cannot
/// run the reader at all (older than Android 8, or the engine failed to
/// start): that is "no reading", not "unreadable", so nothing is flagged and
/// nothing is written, and a person checks the ID as before.
Future<IdOcrResult?> runIdOcr(
  File image, {
  required String enteredFullName,
}) async {
  try {
    if (!await _startEngine()) return null;
    final run = await PaddleOcr().recognize(image.path).timeout(const Duration(seconds: 40));
    // top of the card first, as the reader expects
    final found = [...run.results]..sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
    final card = readCard([for (final r in found) r.text]);
    if (card.isEmpty) return const IdOcrResult(flags: ['unreadable']);

    IdDocumentType? detected;
    for (final t in IdDocumentType.values) {
      if (t.wire == card.type) detected = t;
    }
    final flags = <String>[];
    if (card.name == null || !_namesOverlap(card.name!, enteredFullName)) flags.add('name_mismatch');
    if (card.number == null) flags.add('no_id_number');
    return IdOcrResult(
      detectedType: detected,
      flags: flags,
      extractedName: card.name,
      extractedNumber: card.number,
    );
  } catch (_) {
    return const IdOcrResult(flags: ['unreadable']);
  }
}

/// Re-runs [runIdOcr] against an ID photo that isn't already a local
/// file — [imageUrl] is expected to be `users.id_image_url`, the
/// barangay's own Cloudinary address (see media_upload.dart), not a
/// Supabase Storage object, so a plain unauthenticated HTTPS GET is all
/// that's needed to fetch it.
///
/// Built for the admin-requested re-check flow (migration 0050): an
/// account that registered before this OCR feature existed (or whose
/// first read flagged something worth a second look) has a photo
/// sitting in storage but no local [File] to hand [runIdOcr] — this
/// downloads it to a throwaway temp file, runs the same on-device pass,
/// and cleans up after itself either way.
///
/// Returns null only when the photo itself could not be fetched
/// (offline, a bad or expired address) — that is a network failure, not
/// an OCR result, and callers should leave any pending re-check request
/// alone so the next app open simply tries again. A photo that WAS
/// fetched but reads back as gibberish still comes back as a normal
/// [IdOcrResult] with the `unreadable` flag, exactly as [runIdOcr]
/// already behaves for a bad photo taken fresh.
Future<IdOcrResult?> runIdOcrFromUrl(
  String imageUrl, {
  required String enteredFullName,
}) async {
  File? temp;
  try {
    // A private ID photo (0117) needs a signed link first.
    final link = await viewableMediaUrl(imageUrl);
    if (link == null) return null;
    final response = await http.get(Uri.parse(link));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return null;
    }
    final dir = await getTemporaryDirectory();
    temp = File(
      '${dir.path}/ocr_rescan_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await temp.writeAsBytes(response.bodyBytes);
    return await runIdOcr(temp, enteredFullName: enteredFullName);
  } catch (_) {
    return null;
  } finally {
    if (temp != null) {
      unawaited(temp.delete().catchError((_) => temp!));
    }
  }
}

/// Loose token-overlap check, not an exact-string compare — "Dela Cruz,
/// Juan" (the app's own "Last Name, First Name" entry format, migration
/// 0032) and an ID printed "JUAN DELA CRUZ" or "DELA CRUZ JUAN" should
/// both read as matching, since word order on a printed ID is not
/// something an applicant controls.
bool _namesOverlap(String ocrName, String enteredFullName) {
  final a = _nameTokens(ocrName);
  final b = _nameTokens(enteredFullName);
  if (a.isEmpty || b.isEmpty) return false;
  final shared = a.intersection(b).length;
  final smaller = math.min(a.length, b.length);
  return smaller > 0 && shared / smaller >= 0.5;
}

Set<String> _nameTokens(String s) => s
    .toUpperCase()
    .replaceAll(RegExp(r'[^A-Z\s]'), ' ')
    .split(RegExp(r'\s+'))
    .where((t) => t.length > 1)
    .toSet();
