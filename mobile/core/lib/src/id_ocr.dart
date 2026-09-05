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
// Google ML Kit's on-device text recognizer does the reading: no network
// call, nothing about the photo or its contents ever leaves the phone.
// Advisory only, per 0039's own framing — a failed or low-confidence
// read must never block registration, so every failure path here
// degrades to an honest "couldn't read it" result rather than throwing.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'auth.dart' show IdDocumentType;

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

/// Header phrases that reliably appear on a genuine copy of each document
/// type this app accepts (migration 0019's six-value enum). Several
/// phrasings per type on purpose — a cropped or glare-washed photo can
/// still read back part of a header even when the rest is lost.
const Map<IdDocumentType, List<String>> _headerHints = {
  IdDocumentType.driversLicense: [
    "DRIVER'S LICENSE",
    'DRIVERS LICENSE',
    'LAND TRANSPORTATION OFFICE',
    'NON-PROFESSIONAL',
    'PROFESSIONAL DRIVER',
  ],
  IdDocumentType.passport: [
    'PASSPORT',
    'DEPARTMENT OF FOREIGN AFFAIRS',
    'REPUBLIKA NG PILIPINAS',
  ],
  IdDocumentType.philsys: [
    'PHILIPPINE IDENTIFICATION CARD',
    'PHILSYS',
    'PAMBANSANG PAGKAKAKILANLAN',
  ],
  IdDocumentType.postalId: [
    'POSTAL ID',
    'PHLPOST',
    'PHILIPPINE POSTAL',
  ],
  IdDocumentType.barangayId: [
    'BARANGAY ID',
    'BARANGAY IDENTIFICATION',
    'BARANGAY CLEARANCE',
  ],
  IdDocumentType.barangayAppointment: [
    'APPOINTMENT',
    'DESIGNATION',
    'TANOD',
  ],
};

/// Runs on-device text recognition on [image] and compares what it found
/// against [enteredFullName] ("Last Name, First Name" per migration
/// 0032). Deliberately does NOT take the applicant's selected document
/// type — the photo is usually picked before the dropdown is finalised
/// (or changed afterward), so comparing against a snapshot taken here
/// could compare against a value the applicant later changed. Compare
/// [IdOcrResult.detectedType] against the final selection yourself, at
/// the point you are about to submit it (see register_screen.dart).
///
/// Never throws: a corrupt file, the on-device model failing to load, or
/// anything else internal comes back as the same result an unreadable
/// photo would produce, rather than surfacing an error to the applicant.
Future<IdOcrResult> runIdOcr(
  File image, {
  required String enteredFullName,
}) async {
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final result = await recognizer.processImage(InputImage.fromFile(image));
    final text = result.text;
    final upper = text.toUpperCase();

    // Fewer than a dozen letters/digits total is treated as "nothing
    // usable came back" — even a mediocre real ID photo reads back far
    // more than that once ML Kit runs on it.
    final alnumCount = upper.codeUnits.where((c) {
      final ch = String.fromCharCode(c);
      return RegExp(r'[A-Z0-9]').hasMatch(ch);
    }).length;
    if (alnumCount < 12) {
      return const IdOcrResult(flags: ['unreadable']);
    }

    IdDocumentType? detected;
    for (final entry in _headerHints.entries) {
      if (entry.value.any(upper.contains)) {
        detected = entry.key;
        break;
      }
    }

    final flags = <String>[];

    final extractedName = _extractName(text);
    if (extractedName == null ||
        !_namesOverlap(extractedName, enteredFullName)) {
      flags.add('name_mismatch');
    }

    final extractedNumber = _extractIdNumber(text);
    if (extractedNumber == null) {
      flags.add('no_id_number');
    }

    return IdOcrResult(
      detectedType: detected,
      flags: flags,
      extractedName: extractedName,
      extractedNumber: extractedNumber,
    );
  } catch (_) {
    return const IdOcrResult(flags: ['unreadable']);
  } finally {
    unawaited(recognizer.close());
  }
}

/// Best-effort name line: the longest mostly-alphabetic, all-caps line
/// that isn't part of one of the known headers. Philippine IDs print the
/// holder's name in caps far more reliably than they label a "Name:"
/// field ML Kit could key off of, so this is a cheap heuristic rather
/// than a field lookup — it is shown to the admin to eyeball, never
/// compared against any registry.
String? _extractName(String text) {
  String? best;
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.length < 4 || line.length > 60) continue;
    if (line != line.toUpperCase()) continue;

    final withoutSpaces = line.replaceAll(' ', '');
    final letters = withoutSpaces.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (withoutSpaces.isEmpty || letters.length < withoutSpaces.length * 0.7) {
      continue;
    }

    final isHeader =
        _headerHints.values.any((hints) => hints.any(line.contains));
    if (isHeader) continue;

    if (best == null || line.length > best.length) best = line;
  }
  return best;
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

/// A run of 6+ digits, optionally dash/space-separated — covers PhilSys's
/// 16-digit PCN, driver's-license numbers, postal ID numbers, and most
/// other Philippine ID numbering schemes without needing a pattern per
/// document type. Advisory only, same as everything else here: never
/// checked against a registry, just surfaced for the admin to eyeball.
String? _extractIdNumber(String text) {
  final match = RegExp(r'\b\d[\d\- ]{4,}\d\b').firstMatch(text);
  if (match == null) return null;
  final raw = match.group(0)!;
  final digitsOnly = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digitsOnly.length < 6) return null;
  return raw.trim();
}
