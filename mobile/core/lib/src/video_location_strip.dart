// SmartSumbong — video location stripping.
//
// Added 27 Aug 2026, closing the gap media_upload.dart's own header has
// flagged since video support landed the day before: photos get their
// EXIF stripped before upload, video did not, and "whether a given
// video actually carries GPS... has not been verified against a real
// device" sat there as an open anonymity weakness.
//
// WHY NOT RE-ENCODE. The obvious fix — run every video through a video
// codec (an ffmpeg build, a compression plugin) — was rejected. Those
// packages ship a native binary per CPU architecture, tens of megabytes
// added to the APK for a barangay pilot app that otherwise deliberately
// costs nothing, to do a job that does not need re-encoding at all:
// removing a metadata atom is a text-editing problem, not a video
// problem. Re-encoding would also cost the resident's phone real time
// and battery on every attachment, and re-compress video that is
// already going through Cloudinary's own transformation.
//
// WHAT THIS ACTUALLY DOES. An MP4/MOV/3GP file (the "ISO base media
// file format") is a tree of typed, sized boxes — moov (the whole
// file's structure and metadata), mdat (the actual audio/video sample
// bytes), and others. Android's MediaRecorder, when an app calls
// setLocation() (or some camera apps do this by default), writes the
// coordinates into a "udta" (user data) box, almost always nested
// directly under moov or under one of moov's "trak" children. udta is
// not read by any decoder — stripping it changes nothing about how the
// video plays, the same way stripping EXIF changes nothing about how a
// photo displays. So: parse the box tree, delete every udta box found
// under moov or under a trak, and write out everything else completely
// unchanged, mdat included, byte for byte.
//
// THE ONE COMPLICATION. Every sample's byte position is recorded as an
// absolute file offset in a "stco" or "co64" table, deep inside
// moov/trak/mdia/minf/stbl. If moov sits before mdat in the file (true
// of some recorders and of anything already processed for streaming —
// "faststart"), removing bytes from moov shifts mdat backward, and
// those recorded offsets go stale unless corrected by the same amount.
// If moov sits after mdat (the common case for a phone's own, not yet
// post-processed, camera recordings), mdat never moves and nothing
// needs correcting. Both cases are handled below.
//
// SAFETY. A resident's evidence video is not something to gamble with
// for the sake of a metadata tag nobody but this file cares about. Every
// parsing step here can fail closed: an unrecognised structure, a
// fragmented MP4 (moof-based; a different, unhandled offset model), a
// size that doesn't add up, anything at all outside what is explicitly
// understood, and the whole attempt is abandoned — the caller gets the
// original bytes back, unmodified, not a best guess. The one case that
// commits to writing new bytes out is verified afterwards by re-parsing
// the rebuilt file's own box list before it is trusted; a check that
// fails discards the rewrite and falls back the same way. A video with
// no location metadata at all (most videos, most of the time) costs one
// read-only pass and returns the original file untouched.

import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Strips embedded location metadata from [input] and returns a file
/// with it removed — or, whenever anything about the file isn't exactly
/// what this parser confidently understands, the very same [input]
/// unchanged. Never throws; a video that can't be safely edited is still
/// a video worth uploading.
Future<File> stripVideoLocation(File input) async {
  Uint8List bytes;
  try {
    bytes = await input.readAsBytes();
  } catch (_) {
    return input;
  }

  final stripped = _stripLocationBytes(bytes);
  if (stripped == null) return input;

  try {
    final dir = await getTemporaryDirectory();
    final out = File('${dir.path}/${_uuid.v4()}_nogeo.mp4');
    await out.writeAsBytes(stripped, flush: true);
    return out;
  } catch (_) {
    // Writing the sanitised copy failed for some reason (disk space,
    // permissions) -- upload the original rather than fail the report
    // entirely over a privacy nice-to-have.
    return input;
  }
}

class _Box {
  _Box(this.type, this.start, this.headerLen, this.totalLen);
  final String type;
  final int start;
  final int headerLen;
  final int totalLen;
  int get payloadStart => start + headerLen;
  int get end => start + totalLen;
}

/// Parses the sibling box list covering `[start, end)` of [bytes].
/// Returns null the instant anything doesn't look like a clean,
/// fully-consumed ISO-BMFF box sequence -- see this file's header for
/// why that always means "leave the file alone" rather than a guess.
List<_Box>? _readBoxes(Uint8List bytes, int start, int end) {
  final boxes = <_Box>[];
  final data = ByteData.sublistView(bytes);
  var pos = start;
  while (pos < end) {
    if (end - pos < 8) return null;
    final size32 = data.getUint32(pos);
    final type = String.fromCharCodes(bytes, pos + 4, pos + 8);

    var headerLen = 8;
    int totalLen;
    if (size32 == 1) {
      if (end - pos < 16) return null;
      final big = data.getUint64(pos + 8);
      if (big > (end - pos)) return null;
      totalLen = big;
      headerLen = 16;
    } else if (size32 == 0) {
      totalLen = end - pos; // extends to the end of this range
    } else {
      totalLen = size32;
    }

    if (totalLen < headerLen || pos + totalLen > end) return null;
    boxes.add(_Box(type, pos, headerLen, totalLen));
    pos += totalLen;
  }
  return boxes;
}

Uint8List _reboxed(_Box box, int newTotalLen, Uint8List newPayload) {
  final header = ByteData(8);
  header.setUint32(0, newTotalLen);
  final out = BytesBuilder(copy: false);
  out.add(header.buffer.asUint8List());
  out.add(box.type.codeUnits);
  out.add(newPayload);
  return out.toBytes();
}

/// Returns the children of `[start, end)` with every direct-child box of
/// type [targetType] dropped, recursing one level deeper into any box
/// whose type is in [recurseInto] (moov -> trak, specifically -- the
/// only place besides moov itself this app has ever seen a udta box).
/// Null on anything unparseable.
Uint8List? _stripChildren(
  Uint8List bytes,
  int start,
  int end,
  String targetType,
  Set<String> recurseInto,
) {
  final boxes = _readBoxes(bytes, start, end);
  if (boxes == null) return null;

  final out = BytesBuilder(copy: false);
  for (final box in boxes) {
    if (box.type == targetType) continue; // dropped

    if (recurseInto.contains(box.type)) {
      if (box.headerLen != 8) return null; // a 64-bit-sized trak: bail
      final child = _stripChildren(
          bytes, box.payloadStart, box.end, targetType, recurseInto);
      if (child == null) return null;
      final removedHere = (box.end - box.payloadStart) - child.length;
      if (removedHere == 0) {
        out.add(bytes.sublist(box.start, box.end));
      } else {
        out.add(_reboxed(box, box.totalLen - removedHere, child));
      }
      continue;
    }

    out.add(bytes.sublist(box.start, box.end));
  }
  return out.toBytes();
}

/// Rewrites every stco/co64 chunk-offset entry found anywhere under
/// moov/trak/mdia/minf/stbl by subtracting [shift] -- used only when
/// moov sat before mdat and shrank, so every recorded sample offset
/// needs to move back by exactly the number of bytes moov lost.
Uint8List? _patchChunkOffsets(Uint8List moovBytes, int shift) {
  final children = _patchContainer(
      moovBytes, 8, moovBytes.length, shift, ['trak', 'mdia', 'minf', 'stbl']);
  if (children == null) return null;
  // _patchContainer only ever rewrites offset VALUES inside stco/co64
  // payloads -- it never changes a box's length -- so moov's own
  // 8-byte header (size + "moov") is copied through unchanged here.
  final out = BytesBuilder(copy: false);
  out.add(moovBytes.sublist(0, 8));
  out.add(children);
  return out.toBytes();
}

Uint8List? _patchContainer(
  Uint8List bytes,
  int start,
  int end,
  int shift,
  List<String> chain,
) {
  final boxes = _readBoxes(bytes, start, end);
  if (boxes == null) return null;

  final out = BytesBuilder(copy: false);
  for (final box in boxes) {
    if (box.type == 'stco' || box.type == 'co64') {
      final patched = _patchOffsetBox(bytes, box, shift);
      if (patched == null) return null;
      out.add(patched);
      continue;
    }
    if (chain.isNotEmpty && box.type == chain.first) {
      if (box.headerLen != 8) return null;
      final child = _patchContainer(
          bytes, box.payloadStart, box.end, shift, chain.sublist(1));
      if (child == null) return null;
      // Sizes never change in this pass -- only the offset values
      // inside stco/co64 payloads are rewritten -- so every header
      // here is copied through exactly as it was.
      out.add(bytes.sublist(box.start, box.payloadStart));
      out.add(child);
      continue;
    }
    out.add(bytes.sublist(box.start, box.end));
  }
  return out.toBytes();
}

Uint8List? _patchOffsetBox(Uint8List bytes, _Box box, int shift) {
  if (box.headerLen != 8) return null;
  final payload =
      Uint8List.fromList(bytes.sublist(box.payloadStart, box.end));
  if (payload.length < 8) return null;

  final data = ByteData.sublistView(payload);
  final count = data.getUint32(4);
  final entrySize = box.type == 'stco' ? 4 : 8;
  if (payload.length != 8 + count * entrySize) return null;

  for (var i = 0; i < count; i++) {
    final at = 8 + i * entrySize;
    if (box.type == 'stco') {
      final v = data.getUint32(at);
      if (v < shift) return null; // would go negative -- not our model
      data.setUint32(at, v - shift);
    } else {
      final v = data.getUint64(at);
      if (v < shift) return null;
      data.setUint64(at, v - shift);
    }
  }

  final out = BytesBuilder(copy: false);
  out.add(bytes.sublist(box.start, box.payloadStart));
  out.add(payload);
  return out.toBytes();
}

Uint8List? _stripLocationBytes(Uint8List bytes) {
  final top = _readBoxes(bytes, 0, bytes.length);
  if (top == null) return null;

  // Fragmented MP4 (moof + mdat pairs, sample offsets relative to each
  // moof rather than one flat stco/co64 table) uses a model this file
  // does not patch. Leave it alone rather than patch the wrong table.
  if (top.any((b) => b.type == 'moof')) return null;

  final moovs = top.where((b) => b.type == 'moov').toList();
  final mdats = top.where((b) => b.type == 'mdat').toList();
  if (moovs.length != 1 || mdats.isEmpty) return null;
  final moov = moovs.single;
  if (moov.headerLen != 8) return null;

  final newChildren = _stripChildren(
      bytes, moov.payloadStart, moov.end, 'udta', {'trak'});
  if (newChildren == null) return null;

  final removed = (moov.end - moov.payloadStart) - newChildren.length;
  if (removed == 0) return null; // nothing found; original file stands

  var newMoov = _reboxed(moov, moov.totalLen - removed, newChildren);

  // moov before mdat: mdat, and every absolute offset pointing into it,
  // shifts back by [removed] bytes once moov shrinks. moov after mdat
  // (the common case for an unprocessed phone recording): mdat never
  // moves, nothing to patch.
  if (moov.start < mdats.first.start) {
    final patched = _patchChunkOffsets(newMoov, removed);
    if (patched == null) return null;
    newMoov = patched;
  }

  final rebuilt = BytesBuilder(copy: false);
  rebuilt.add(bytes.sublist(0, moov.start));
  rebuilt.add(newMoov);
  rebuilt.add(bytes.sublist(moov.end, bytes.length));
  final out = rebuilt.toBytes();

  // Trust nothing that wasn't checked: re-parse the rebuilt file's own
  // top-level boxes exactly as any untouched file would be read. A
  // rewrite that fails this is discarded, not shipped as a best guess.
  if (_readBoxes(out, 0, out.length) == null) return null;

  return out;
}
