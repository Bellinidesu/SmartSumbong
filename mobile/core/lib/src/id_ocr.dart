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
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
    // "DRIVER'S LICENSE" and "LAND TRANSPORTATION OFFICE" both confirmed
    // printed, verbatim, against a real LTO card photo.
    "DRIVER'S LICENSE",
    'DRIVERS LICENSE',
    'LAND TRANSPORTATION OFFICE',
    // The reviewed photo's crop didn't include a "NON-PROFESSIONAL" /
    // "PROFESSIONAL" line — not contradicted, just not yet seen directly
    // the way the two hints above now have been.
    'NON-PROFESSIONAL',
    'PROFESSIONAL DRIVER',
  ],
  IdDocumentType.passport: [
    'PASSPORT',
    // The Filipino word actually printed on the cover, below the seal
    // ("PILIPINAS" above it, "PASAPORTE" below) — confirmed 6 Sep, and
    // distinctive to a passport specifically, unlike the masthead text.
    'PASAPORTE',
    'DEPARTMENT OF FOREIGN AFFAIRS',
    // 'REPUBLIKA NG PILIPINAS' deliberately NOT listed here — it's the
    // standard national masthead nearly every Philippine government ID
    // prints, PhilSys included (see the 6 Sep false positive this
    // caused: a genuine PhilSys card matched here first, since passport
    // is checked before philsys below, before ever reaching philsys's
    // own, actually-distinctive hints). A phrase belongs in this list
    // only if it doesn't also appear on one of the other five documents.
  ],
  IdDocumentType.philsys: [
    'PHILIPPINE IDENTIFICATION CARD',
    'PAMBANSANG PAGKAKAKILANLAN',
    // 'PHILSYS' removed 6 Sep — that's the name of the government
    // registration SYSTEM, never text actually printed on the physical
    // card itself (the card is called "PhilID"). Confirmed against a
    // real card photo; this hint had simply never matched anything.
  ],
  IdDocumentType.postalId: [
    // All three confirmed against a real PHLPOST card sample: the card's
    // title is "POSTAL IDENTITY CARD" (contains "POSTAL ID"), it also
    // carries a repeated "POSTAL ID" watermark, the "PHLPOST" wordmark
    // appears top-right, and the issuer line reads "Philippine Postal
    // Corporation" (contains "PHILIPPINE POSTAL").
    'POSTAL ID',
    'PHLPOST',
    'PHILIPPINE POSTAL',
  ],
  IdDocumentType.barangayId: [
    // Still no real Barangay 183 ID sample to check against — these are
    // the same generic guesses as before (barangay IDs aren't
    // nationally standardised: every barangay designs its own), not
    // confirmed printed on an actual Barangay 183 card.
    'BARANGAY ID',
    'BARANGAY IDENTIFICATION',
    // 'BARANGAY CLEARANCE' removed 6 Sep — that's a different real
    // document (a certificate of residency/good standing, not an ID
    // card), so it had no business being a hint for this type at all.
    //
    // 'BARANGAY 183' / 'VILLAMOR' / 'PASAY CITY' (added 5 Sep as
    // placeholders, on the idea that a real Barangay 183 card would at
    // least print its own barangay's name) removed again 6 Sep on a
    // second look: this app's entire user base lives in Barangay 183,
    // Pasay — which means those three phrases are near-guaranteed to
    // print in the ADDRESS field of every other document type too (the
    // PHLPost Postal ID sample confirmed this outright: its own address
    // line reads "BRGY. RIVERA ... PASAY CITY"). That isn't a rare
    // edge case worth a one-line caution, like the first pass treated
    // it — for this specific population it's closer to the norm, so
    // keeping those hints here would have meant Postal IDs, PhilSys
    // cards, driver's licenses, all regularly misdetected as Barangay
    // ID whenever their own real header hints failed to fuzzy-match
    // first. An address fact about who uses this app can never be a
    // reliable signal for which document TYPE someone uploaded; better
    // to have no positive signal at all here than a false one this
    // likely. Left as an open item until a real card sample provides
    // actual header/title text instead of a proxy for it.
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
      if (entry.value.any((hint) => _fuzzyContains(upper, hint))) {
        detected = entry.key;
        break;
      }
    }

    final flags = <String>[];

    // Label-anchored first (reads the printed field labels themselves —
    // "Apelyido/Last Name" etc. — and takes the line directly under each
    // one), falling back to the old longest-caps-line guess only when no
    // label was found at all (a non-PhilSys ID, or a crop that lost the
    // labels). See both extractors' own doc comments for why the label
    // approach is materially more reliable than picking by line length.
    final lines = _sortedLines(result);
    final extractedName = _extractNameByLabel(lines) ?? _extractName(text);
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
    final response = await http.get(Uri.parse(imageUrl));
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

/// The printed field labels PhilSys puts directly above each part of the
/// holder's name (see the photo this was written against: "Apelyido/Last
/// Name" above "LEDIAC", "Mga Pangalan/Given Names" above "ACE AHMERSON",
/// "Gitnang Apelyido/Middle Name" above "ELLO") — three separate short
/// lines, which is exactly why [_extractName]'s "longest all-caps line"
/// heuristic reliably grabs the one long address line instead. English
/// and Filipino phrasing both listed since ML Kit reads whichever the
/// card actually shows a clean line for.
const Map<String, List<String>> _nameLabelHints = {
  'last': ['APELYIDO', 'LAST NAME'],
  'given': ['MGA PANGALAN', 'GIVEN NAME', 'GIVEN NAMES', 'PANGALAN'],
  'middle': ['GITNANG APELYIDO', 'MIDDLE NAME'],
  // Last-resort only — see the assembly step at the end of
  // _extractNameByLabel. A plain "Name" label with no Last/Given/Middle
  // split is the most generic convention an ID card can use, which is
  // exactly the realistic case for a Barangay ID or tanod appointment
  // letter: neither has a national standard to read real field labels
  // off of the way PhilSys does, so this leans on a near-universal
  // English word instead of guessing barangay-specific text (see the
  // address-based hints removed from _headerHints above, 6 Sep, for why
  // that kind of guess doesn't hold up for this app's population).
  // Deliberately just the bare word, no Filipino equivalent added here:
  // 'PANGALAN' alone already sits in 'given' above and gets tried first.
  'full': ['NAME'],
};

/// Every recognised line across every block, top-to-bottom by its
/// position on the photo. ML Kit's blocks are not guaranteed to already
/// be in a single reading order for a multi-block layout, but an ID
/// card's fields are effectively one column, so sorting every line by
/// its own vertical position is enough to put "a label" directly before
/// "the value printed under it", which is all [_extractNameByLabel]
/// actually needs.
List<String> _sortedLines(RecognizedText result) {
  final lines = <TextLine>[
    for (final block in result.blocks) ...block.lines,
  ];
  lines.sort((a, b) => a.boundingBox.top.compareTo(b.boundingBox.top));
  return [for (final l in lines) l.text.trim()];
}

/// Reads the name off the printed field labels themselves rather than
/// guessing by line length (see [_nameLabelHints]'s doc comment for why
/// that guess fails). For each label this recognises, the very next
/// line is taken as that field's value — skipped if it doesn't actually
/// look like a name (mostly letters, in caps) — so a misread label with
/// garbage immediately after it contributes nothing rather than garbage.
/// PhilSys is the only one of the six accepted document types confirmed
/// to print the Last/Given/Middle split this reads first; a document
/// whose own combined header line happens to contain "Last Name" or
/// "Given Name(s)" verbatim (the driver's license and Postal ID samples
/// checked 6 Sep both do, just combined into one header rather than
/// split across three) benefits too, incidentally. Anything else falls
/// through to the generic 'full' entry (a bare "Name" label) before
/// giving up and handing back to [_extractName] in the caller.
///
/// Assembled as Last + Given + Middle when any of those three matched;
/// the generic 'full' match is used only when none of them did, since a
/// real Last/Given/Middle read is always more specific. [_namesOverlap]'s
/// token-overlap check is order-independent, so none of this needs to
/// match the applicant's own "Last Name, First Name" entry format
/// exactly.
String? _extractNameByLabel(List<String> lines) {
  final parts = <String, String>{};
  for (var i = 0; i < lines.length - 1; i++) {
    final line = lines[i].toUpperCase();
    for (final entry in _nameLabelHints.entries) {
      if (parts.containsKey(entry.key)) continue;
      if (!entry.value.any((hint) => _fuzzyContains(line, hint))) continue;

      final value = lines[i + 1].trim();
      if (value.length < 2 || value.length > 40) continue;
      if (value != value.toUpperCase()) continue;
      final withoutSpaces = value.replaceAll(' ', '');
      final letters = withoutSpaces.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (withoutSpaces.isEmpty || letters.length < withoutSpaces.length * 0.7) {
        continue;
      }
      parts[entry.key] = value;
    }
  }
  final assembled =
      [parts['last'], parts['given'], parts['middle']]
          .whereType<String>()
          .join(' ')
          .trim();
  return assembled.isNotEmpty ? assembled : parts['full'];
}

/// Approximate substring match: true if some contiguous span of
/// [haystack] is within a small edit distance of [needle], not just an
/// exact `.contains()`. A glare-washed or slightly blurred photo reads
/// back header and label text with a handful of wrong characters far
/// more often than it reads back nothing at all — "PAMBANSANG
/// PAGKAKAKILANLAN" missing one or two letters should still count as a
/// match, an exact substring check never would. Short needles (under 6
/// characters) are excluded from fuzzing since a couple of tolerated
/// errors against a very short phrase risks matching almost anything.
bool _fuzzyContains(String haystack, String needle, {double maxErrorRate = 0.22}) {
  if (needle.isEmpty) return false;
  if (haystack.contains(needle)) return true;
  if (needle.length < 6) return false;

  final maxErrors = (needle.length * maxErrorRate).floor();
  if (maxErrors == 0) return false;

  final minLen = math.max(1, needle.length - maxErrors);
  final maxLen = math.min(haystack.length, needle.length + maxErrors);
  for (var start = 0; start <= haystack.length - minLen; start++) {
    for (var len = minLen; len <= maxLen && start + len <= haystack.length; len++) {
      if (_levenshtein(haystack.substring(start, start + len), needle) <= maxErrors) {
        return true;
      }
    }
  }
  return false;
}

/// Classic edit distance, iterative two-row form (no need to keep the
/// full matrix — only ever compared against short header/label phrases,
/// never whole-document text, so this stays cheap).
int _levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var prev = List<int>.generate(b.length + 1, (j) => j);
  for (var i = 1; i <= a.length; i++) {
    final curr = List<int>.filled(b.length + 1, 0);
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      curr[j] = math.min(math.min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    prev = curr;
  }
  return prev[b.length];
}

/// Best-effort name line: the longest mostly-alphabetic, all-caps line
/// that isn't part of one of the known headers. Philippine IDs print the
/// holder's name in caps far more reliably than they label a "Name:"
/// field ML Kit could key off of, so this is a cheap heuristic rather
/// than a field lookup — it is shown to the admin to eyeball, never
/// compared against any registry. Kept as the fallback for the five
/// document types [_extractNameByLabel] doesn't handle (see its own doc
/// comment) — see id_ocr's 6 Sep revision for why this alone was not
/// enough on its own for PhilSys specifically.
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
