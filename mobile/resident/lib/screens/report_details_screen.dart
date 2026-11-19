// SmartSumbong — Submit Report, step 3 of 3: the details.
//
// Figma node 2277:3268.
//
// The map and the address search moved out (19 Nov 2026): "Where is it?" is a screen of its own, the second step
// (screens/where_screen.dart; the search in place_search.dart). This screen shows what was chosen there as one
// row, "Near 8th Street" with Change, which opens that screen again with the pin where it is and gets the new
// one back. The pin goes to file_report() as latitude and longitude only; a typed address or a landmark's name
// never does (report_media/reports carry nothing else), and the photos' EXIF is stripped before upload
// (media_upload.dart), so an anonymous complaint carries no one's home. The outside-the-barangay refusal stays
// here as a safety net, at submit, though the Where screen already will not confirm such a spot.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../models/complaint_category.dart';
import '../outbox.dart';
import '../theme.dart';
import '../widgets/brgy_map.dart';
import '../widgets/figma_ui.dart';
import '../location_lookup.dart';
import '../models/barangay_profile.dart';
import 'where_screen.dart';

/// Matches operational_settings.max_report_photos, which the database
/// enforces. Kept in step by hand; a mismatch shows up as a rejected
/// insert after the photos have already uploaded.
const _maxPhotos = 5;

const _maxDescription = 500;

/// A half-filled report — typed description, picked photos, a video, the
/// anonymity choice — used to be gone the moment the app was killed or a
/// weak barangay connection dropped mid-fill. Nothing else on this screen
/// changed to make that true; it was just never saved anywhere. One draft
/// slot, not one per category: a resident filing a second report while an
/// old draft sits unsent is the rare case, and this only ever restores
/// into a screen whose category still matches what was saved (checked in
/// `_restoreDraftIfAny` below) — a mismatch just leaves the draft alone
/// rather than guessing which report a stray photo belonged to.
const _draftPrefsKey = 'report_draft_v1';

class ReportDetailsScreen extends StatefulWidget {
  const ReportDetailsScreen({
    super.key,
    required this.choice,
    required this.uploader,
    this.where,
  });

  final CategoryChoice choice;
  final MediaUploader uploader;

  /// Where the resident put the pin on the previous step. Null only for a screen opened without that step: the
  /// barangay centre, which Change then moves.
  final WhereResult? where;

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  /// 0163: the other concerns, picked on the first page under the same category (Rose, 18 Nov 2026).
  List<ExtraConcern> get _extras => widget.choice.extras;
  late final TextEditingController _description;

  /// The spot chosen on the Where screen (step 2); Change replaces it.
  late WhereResult _where = widget.where ?? const WhereResult(pin: brgyCentre);
  LatLng get _pin => _where.pin;

  // The barangay's outline, for the safety-net check at submit.
  List<List<LatLng>> _rings = const [];

  final _photos = <File>[];
  final _uploaded = <UploadedMedia>[]; // held across retries

  // Optional. One video per report — file_report()/report_media has
  // no notion of "several" the way photos do, and a single short clip
  // already covers what a photo strip can't (motion, sound, a longer
  // pan across a scene).
  File? _video;
  UploadedMedia? _uploadedVideo; // held across retries, same reasoning

  bool _anonymous = false;
  bool _acknowledged = false;
  bool _busy = false;
  String? _banner;
  final _errors = <String, String>{};

  Timer? _draftDebounce;
  bool _restoringDraft = false;

  @override
  void initState() {
    super.initState();
    _description =
        TextEditingController(text: widget.choice.descriptionPrefill);
    _description.addListener(_scheduleDraftSave);
    brgyBoundary().then((r) {
      if (mounted) setState(() => _rings = r);
    });
    _restoreDraftIfAny();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _description.dispose();
    super.dispose();
  }

  // ---------- location ---------------------------------------

  /// Change: the Where screen again, with the pin where it is; the new one comes back when it is confirmed.
  Future<void> _changeLocation() async {
    final res = await Navigator.of(context).pushNamed<WhereResult>(
      '/submit-report/where',
      arguments: WhereArgs(widget.choice, current: _where, returnResult: true),
    );
    if (res == null || !mounted) return;
    setState(() {
      _where = res;
      _errors.remove('location');
    });
  }

  // ---------- photos -----------------------------------------

  /// Gallery-only until 9 Sep 2026 — a resident filing a complaint had no
  /// way to take a fresh photo, only to attach one already on the phone.
  /// register_screen.dart already offers this choice for the ID/selfie
  /// step, and the reasoning there applies here too: [MediaUploader.pick]
  /// strips EXIF and re-encodes regardless of source (see
  /// media_upload.dart's EXIF header), so a camera shot is exactly as
  /// safe — including for the anonymous option — as a gallery pick.
  Future<ImageSource?> _chooseSource(BuildContext context) =>
      showFigmaSourceSheet(
        context,
        takeLabel: context.s.reportDetailsTakePhoto,
        galleryLabel: context.s.reportDetailsChooseFromGallery,
      );


  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) {
      setState(() => _banner = context.s.reportDetailsPhotoLimit(_maxPhotos));
      return;
    }
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;
    final s = context.s;
    final granted = await PermissionGate.ensure(
      context,
      permission:
          source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.reportDetailsCameraAccessTitle
          : s.reportDetailsPhotoAccessTitle,
      rationale: source == ImageSource.camera
          ? s.reportDetailsCameraAccessPhotoRationale
          : s.reportDetailsPhotoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pick(source: source);
      if (f == null) return;
      setState(() {
        _photos.add(f);
        _errors.remove('photos');
      });
      _scheduleDraftSave();
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  void _removePhoto(int i) {
    setState(() {
      _photos.removeAt(i);
      // Uploaded URLs are positional. Dropping a photo after some have
      // uploaded would misalign them, so start that part over — the
      // photos themselves are still on the device.
      _uploaded.clear();
    });
    _scheduleDraftSave();
  }

  // ---------- video --------------------------------------------

  Future<void> _addVideo() async {
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;
    final s = context.s;
    final granted = await PermissionGate.ensure(
      context,
      permission:
          source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.reportDetailsCameraAccessTitle
          : s.reportDetailsVideoAccessTitle,
      rationale: source == ImageSource.camera
          ? s.reportDetailsCameraAccessVideoRationale
          : s.reportDetailsVideoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pickVideo(source: source);
      if (f == null) return;
      setState(() {
        _video = f;
        _uploadedVideo = null; // a new file invalidates any prior upload
      });
      _scheduleDraftSave();
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  void _removeVideo() {
    setState(() {
      _video = null;
      _uploadedVideo = null;
    });
    _scheduleDraftSave();
  }

  // ---------- draft (save/restore an in-progress report) --------
  //
  // Debounced rather than saved on every keystroke — a resident typing a
  // description doesn't need a disk write per character, just "the app
  // was killed mid-sentence" coverage. Photo/video changes save
  // immediately since those are already discrete, infrequent actions.

  void _scheduleDraftSave() {
    if (_restoringDraft) return; // don't save the draft we just loaded
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 600), _saveDraft);
  }

  Future<void> _saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final description = _description.text.trim();
      // An empty, untouched form is nothing worth remembering — drop any
      // previously-saved draft instead of writing a blank one back. Only
      // the issue's own prefill ("Potholes —") is untouched too.
      final typed = description.isNotEmpty && description != widget.choice.descriptionPrefill.trim();
      // The other concerns are not kept: they are picked on the first page, which a draft does not reopen.
      if (!typed && _photos.isEmpty && _video == null) {
        await prefs.remove(_draftPrefsKey);
        return;
      }
      await prefs.setString(
        _draftPrefsKey,
        jsonEncode({
          'category': widget.choice.category.wire,
          'description': description,
          'photoPaths': _photos.map((f) => f.path).toList(),
          'videoPath': _video?.path,
          'anonymous': _anonymous,
        }),
      );
    } catch (_) {
      // A draft that fails to save just means nothing to restore later —
      // never worth interrupting the resident over.
    }
  }

  Future<void> _restoreDraftIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftPrefsKey);
      if (raw == null) return;
      final draft = jsonDecode(raw) as Map<String, dynamic>;

      // Only ever restores into the same category it was saved from —
      // a mismatch (resident backed out and picked a different category)
      // leaves the old draft alone rather than guessing where it belongs.
      if (draft['category'] != widget.choice.category.wire) return;

      // Picked files can live in a cache directory the OS is free to
      // clear between launches. Each path is checked before it's trusted
      // — a photo that's gone is silently dropped, never shown as a
      // broken thumbnail.
      final photoPaths = (draft['photoPaths'] as List?)?.cast<String>() ?? [];
      final restoredPhotos = <File>[];
      for (final p in photoPaths) {
        final f = File(p);
        if (await f.exists()) restoredPhotos.add(f);
      }
      File? restoredVideo;
      final videoPath = draft['videoPath'] as String?;
      if (videoPath != null && await File(videoPath).exists()) {
        restoredVideo = File(videoPath);
      }
      final saved = (draft['description'] as String?) ?? '';
      // A draft that only ever held the issue's prefill (saved before that counted as untouched) is nothing to restore.
      final restoredDescription = saved.trim() == widget.choice.descriptionPrefill.trim() ? '' : saved;
      // An older draft's 'concerns' are left alone: the other concerns are picked on the first page now (Rose,
      // 18 Nov 2026), and what was picked there a moment ago is what this report files with.

      final restoredSomething = restoredPhotos.isNotEmpty ||
          restoredVideo != null ||
          restoredDescription.isNotEmpty;
      if (!restoredSomething || !mounted) return;

      _restoringDraft = true;
      setState(() {
        if (restoredDescription.isNotEmpty) {
          _description.text = restoredDescription;
        }
        _photos.addAll(restoredPhotos);
        _video = restoredVideo;
        _anonymous = (draft['anonymous'] as bool?) ?? _anonymous;
      });
      _restoringDraft = false;

      // Rose (18 Nov 2026): this note could not be put away, so people tapped Discard to be rid of it. A snackbar
      // with an action stays until the action is tapped (SnackBar.persist defaults to true when there is one), and
      // it had no close button, so Discard was the only way out, and it sat over Back / Submit. Now it goes by
      // itself after six seconds, has a close button, and Discard asks first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.s.reportDetailsDraftRestored),
            persist: false,
            showCloseIcon: true,
            actionOverflowThreshold: 1, // one line: the note, Discard, the cross
            closeIconColor: context.colors.bg,
            action: SnackBarAction(label: context.s.reportDetailsDraftDiscard, onPressed: _confirmDiscardDraft),
            duration: const Duration(seconds: 6),
          ),
        );
      });
    } catch (_) {
      // A corrupt or unreadable draft is treated the same as no draft —
      // the form just starts blank, same as before this existed.
    }
  }

  /// Discard, from the draft-restored note: asked first, and anything but Discard (Keep editing, a tap outside,
  /// Back) leaves the form as it is.
  Future<void> _confirmDiscardDraft() async {
    final keep = await showDDialog(
      context,
      title: context.tr('Discard your unfinished report?', 'Itapon ang hindi pa natatapos na ulat?'),
      body: context.tr('The description, photos and video you added will be removed from this form.',
          'Aalisin sa form na ito ang paglalarawan, mga larawan at video na idinagdag mo.'),
      primary: context.tr('Keep editing', 'Ituloy ang pag-edit'),
      secondary: context.s.reportDetailsDraftDiscard,
      secondaryKind: DButtonKind.danger,
      icon: Icons.delete_outline_rounded,
      iconColor: const Color(0xFFC62828),
    );
    if (keep != false || !mounted) return;
    setState(() {
      _description.text = widget.choice.descriptionPrefill;
      _photos.clear();
      _uploaded.clear();
      _video = null;
      _uploadedVideo = null;
    });
    unawaited(_clearDraft());
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftPrefsKey);
    } catch (_) {
      // Nothing to do — worst case a stale draft offers itself again
      // next time, which _restoreDraftIfAny's own checks handle safely.
    }
  }

  // ---------- submit -----------------------------------------

  bool _validate() {
    _errors.clear();
    if (!insideBrgy(_rings, _pin)) {
      _errors['location'] = context.tr(
          'This spot is outside ${BarangayProfile.name}. Move the pin inside the barangay or type the address.',
          'Nasa labas ng ${BarangayProfile.name} ang lugar na ito. Ilipat ang pin sa loob ng barangay o i-type ang address.');
    }
    if (_description.text.trim().length < 10) {
      _errors['description'] = context.s.reportDetailsDescriptionValidation;
    }
    if (!_acknowledged) {
      _errors['ack'] = context.s.reportDetailsAckValidation;
    }
    setState(() {});
    return _errors.isEmpty;
  }

  /// This submission's id for file_report()'s p_client_ref (0066): the
  /// same for every retry from this form, so no retry can file twice.
  final _clientRef = Outbox.newRef();

  /// No signal: keep the report on the phone (lib/outbox.dart), to be
  /// sent by itself when the connection returns, and go home.
  Future<void> _queue() async {
    await Outbox.instance.enqueue(
      id: _clientRef,
      category: widget.choice.category.wire,
      subject: widget.choice.subject,
      description: _description.text.trim(),
      latitude: _pin.latitude,
      longitude: _pin.longitude,
      anonymous: _anonymous,
      photos: _photos,
      video: _video,
      uploaded: [
        if (_uploaded.length == _photos.length)
          for (final m in _uploaded) m.toJson(),
      ],
      uploadedVideo: _uploadedVideo?.toJson(),
      optionId: widget.choice.optionId,
      concerns: [for (final x in _extras) x.toJson()],
    );
    unawaited(_clearDraft());
    if (!mounted) return;
    final s = context.s;
    Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    Outbox.messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(s.outboxQueued),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  Future<void> _submit() async {
    // The button only disables on the next rebuild; a second tap landing
    // before it would otherwise file the same complaint twice.
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    setState(() {
      _busy = true;
      _banner = null;
    });

    // Plainly offline: straight to the outbox, no failed upload first.
    if (!await Outbox.isOnline()) {
      try {
        await _queue();
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    try {
      // Upload first, same ordering as registration: file_report() writes
      // the complaint and its media in one transaction, so a photo that
      // fails must fail before the complaint exists. Uploaded URLs are
      // held so a retry does not re-send them.
      if (_uploaded.length != _photos.length) {
        _uploaded.clear();
        for (final f in _photos) {
          _uploaded.add(
            await widget.uploader.upload(f, kind: MediaKind.reportPhoto),
          );
        }
      }
      if (_video != null && _uploadedVideo == null) {
        _uploadedVideo = await widget.uploader
            .uploadVideo(_video!, kind: MediaKind.reportPhoto);
      }

      // Cloudinary's count of the stored asset, not a placeholder.
      // report_media_bytes_check rejects zero, and enforce_media_cap()
      // sums this column for the 35 MB combined ceiling (migration
      // 0033) — a zero here would make that cap meaningless as well
      // as failing the insert.
      final media = [
        for (final m in _uploaded) m.toJson(),
        if (_uploadedVideo != null) _uploadedVideo!.toJson(),
      ];

      final row = await Supabase.instance.client.rpc(
        'file_report',
        params: {
          ...concernParams(widget.choice.optionId, [for (final x in _extras) x.toJson()]),
          'p_category': widget.choice.category.wire,
          'p_subject': widget.choice.subject,
          'p_description': _description.text.trim(),
          'p_latitude': _pin.latitude,
          'p_longitude': _pin.longitude,
          'p_is_anonymous': _anonymous,
          'p_media': media,
          'p_client_ref': _clientRef,
        },
      );

      // Filed successfully — the whole reason this draft existed is gone.
      unawaited(_clearDraft());
      // The street it was filed on, saved for the portal and tanods (0068).
      unawaited(ReverseGeocode.labelReport(Supabase.instance.client, row));

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/report-submitted',
        (r) => r.settings.name == '/home',
        arguments: row is Map ? row['tracking_id'] : null,
      );
    } on MediaUploadException catch (e) {
      // A back gesture mid-upload disposes this screen; the error still
      // arrives afterwards.
      if (!mounted) return;
      // The connection dropped mid-upload: keep what uploaded, queue the
      // rest rather than asking the resident to start over.
      if (e.isRetryable) return _queue();
      setState(() => _banner = e.message);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _banner = _translate(e.message));
    } catch (e) {
      if (!mounted) return;
      if (Outbox.isNetworkError(e)) return _queue();
      // Not the exception text: with no signal that was a raw
      // "ClientException with SocketException: Failed host lookup ..."
      // line, project URL included, on the resident's screen.
      setState(() => _banner = context.s.reportDetailsSubmitFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _translate(String raw) {
    final m = raw.toLowerCase();
    final s = context.s;
    if (m.contains('maximum of') && m.contains('photos')) {
      return s.reportDetailsPhotoLimit(_maxPhotos);
    }
    if (m.contains('35 mb')) {
      return s.reportDetailsTooLarge;
    }
    if (m.contains('_url_pinned')) {
      return s.reportDetailsPhotosCorrupt;
    }
    if (m.contains('row-level security') || m.contains('policy')) {
      return s.reportDetailsAccountNotAllowed;
    }
    if (isOneCategoryRefusal(raw)) {
      return s.reportDetailsOneCategory;
    }
    return s.reportDetailsSubmitFailed;
  }

  // ---------- build ------------------------------------------

  // Branch D: the report form in the preview's look — back, the issue in
  // its category colour, then the three steps as numbered white cards
  // (where, what happened, photos and video), the anonymous switch and
  // the acknowledgement, and Back / Submit pinned at the bottom.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final col = categoryColour(widget.choice.category);
    Widget section(int n, String title, List<Widget> body) => Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: d.cardBox(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(shape: BoxShape.circle, color: col),
                child: Center(child: Text('$n', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: DType.body(d.ink, size: 15, w: FontWeight.w800))),
            ]),
            const SizedBox(height: 12),
            ...body,
          ]),
        );

    return DPage(
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
              children: [
                Row(children: [
                  DBack(onTap: _busy ? () {} : null),
                  const Spacer(),
                  // page one is step 1, Where is it? step 2
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: d.line)),
                    child: Text(context.tr('Step 3 of 3', 'Hakbang 3 ng 3'), style: DType.body(d.ink2, size: 12, w: FontWeight.w800).copyWith(height: 1)),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
                  const SizedBox(width: 8),
                  Text(context.tr(widget.choice.category.label, widget.choice.category.labelFil).toUpperCase(), style: DType.label(d.muted)),
                ]),
                const SizedBox(height: 6),
                DHeading(widget.choice.issue == null ? context.tr(widget.choice.category.label, widget.choice.category.labelFil) : context.tr(widget.choice.issue!, widget.choice.issueFil ?? widget.choice.issue!), lead: s.reportDetailsCompleteBelow),
                // The other concerns picked on the first page; Back changes them.
                if (_extras.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final x in _extras)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: col.withValues(alpha: d.dark ? .22 : .12),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: col.withValues(alpha: .6)),
                        ),
                        child: Text('+ ${context.tr(x.option?.en ?? x.category.label, x.option?.fil ?? x.category.labelFil)}',
                            style: DType.body(d.ink, size: 12.5, w: FontWeight.w700)),
                      ),
                  ]),
                ],
                const SizedBox(height: 14),
                if (_banner != null) ...[
                  _Banner(_banner!),
                  const SizedBox(height: 14),
                ],
                _LocationRow(
                  colour: col,
                  near: whereNearLine(context, _where.near),
                  zone: whereZoneLine(),
                  error: _errors['location'],
                  enabled: !_busy,
                  onChange: _changeLocation,
                ),
                const SizedBox(height: 12),
                section(1, s.reportDetailsStep2, [
                  _DescriptionBox(controller: _description, error: _errors['description'], enabled: !_busy),
                ]),
                const SizedBox(height: 12),
                section(2, s.reportDetailsStep3, [
                  _PhotoStrip(photos: _photos, max: _maxPhotos, enabled: !_busy, onAdd: _addPhoto, onRemove: _removePhoto),
                  const SizedBox(height: 12),
                  _VideoAttach(video: _video, enabled: !_busy, onAdd: _addVideo, onRemove: _removeVideo),
                ]),
                const SizedBox(height: 12),
                DSheet(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.reportDetailsAnonymousQuestion, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800)),
                    const SizedBox(height: 6),
                    Row(children: [
                      DToggle(
                        on: _anonymous,
                        label: s.reportDetailsAnonymousQuestion,
                        onTap: _busy
                            ? null
                            : () {
                                setState(() => _anonymous = !_anonymous);
                                _scheduleDraftSave();
                              },
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_anonymous ? s.reportDetailsHiddenNote : s.reportDetailsShownNote, style: DType.body(d.muted, size: 12))),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                _Acknowledgement(
                  value: _acknowledged,
                  error: _errors['ack'],
                  enabled: !_busy,
                  onChanged: (v) => setState(() {
                    _acknowledged = v ?? false;
                    _errors.remove('ack');
                  }),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
            child: SafeArea(
              top: false,
              child: Row(children: [
                Expanded(child: DButton(s.reportDetailsBack, kind: DButtonKind.ghost, expand: true, onTap: _busy ? null : () => Navigator.of(context).pop())),
                const SizedBox(width: 10),
                Expanded(child: DButton(s.reportDetailsSubmit, expand: true, busy: _busy, onTap: _busy ? null : _submit)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ---------- pieces -------------------------------------------

/// The spot chosen on the Where screen, as one row: the pin in the category's colour, "Near X" and the zone, and
/// Change, which opens that screen again.
class _LocationRow extends StatelessWidget {
  const _LocationRow({required this.colour, required this.near, required this.zone, required this.error, required this.enabled, required this.onChange});

  final Color colour;
  final String near;
  final String zone;
  final String? error;
  final bool enabled;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        decoration: d.cardBox(20),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
            child: const Icon(Icons.place_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(near, maxLines: 2, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 15, w: FontWeight.w800).copyWith(height: 20 / 15)),
              Text(zone, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.muted, size: 12.5).copyWith(height: 17 / 12.5)),
            ]),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: context.tr('Change the location', 'Baguhin ang lokasyon'),
            button: true,
            excludeSemantics: true,
            onTap: enabled ? onChange : null,
            child: DButton(context.tr('Change', 'Baguhin'), kind: DButtonKind.ghost, small: true, onTap: enabled ? onChange : null),
          ),
        ]),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 4),
          child: Text(error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
        ),
    ]);
  }
}

class _DescriptionBox extends StatelessWidget {
  const _DescriptionBox({
    required this.controller,
    this.error,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 128,
          decoration: BoxDecoration(
            color: context.colors.field,
            border: Border.all(color: error == null ? context.colors.navy : context.colors.hint),
            borderRadius: BorderRadius.circular(25),
          ),
          padding: const EdgeInsets.fromLTRB(17, 11, 17, 6),
          child: Column(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  maxLines: null,
                  expands: true,
                  maxLength: _maxDescription,
                  textAlignVertical: TextAlignVertical.top,
                  style: TextStyle(fontSize: 12, color: context.colors.navy),
                  decoration: InputDecoration(
                    hintText: context.s.reportDetailsDescribeHint,
                    hintStyle: TextStyle(fontSize: 12, color: context.colors.muted),
                    // The Container above draws the box. Clearing
                    // `border` alone is not enough: the global
                    // InputDecorationTheme sets enabledBorder and
                    // focusedBorder too, and those take precedence, so
                    // the theme's pill was being drawn inside the box.
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    counterText: '',
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (_, value, _) => Text(
                    context.s.reportDetailsCounter(
                        value.text.characters.length, _maxDescription),
                    style: TextStyle(fontSize: 10, color: context.colors.navy),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 17, top: 4),
            child: Text(error!,
                style: TextStyle(color: context.colors.hint, fontSize: 11)),
          ),
      ],
    );
  }
}

class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({
    required this.photos,
    required this.max,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final List<File> photos;
  final int max;
  final bool enabled;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (var i = 0; i < photos.length; i++)
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(photos[i], fit: BoxFit.cover),
                ),
                Positioned(
                  top: -6,
                  right: -6,
                  child: IconButton(
                    icon: Icon(Icons.cancel, color: context.colors.navy),
                    onPressed: enabled ? () => onRemove(i) : null,
                  ),
                ),
              ],
            ),
          ),
        if (photos.length < max)
          InkWell(
            onTap: enabled ? onAdd : null,
            borderRadius: BorderRadius.circular(25),
            child: Container(
              // Full width, like the video tile below, until there are
              // photos to sit beside.
              width: photos.isEmpty ? double.infinity : 174,
              height: photos.isEmpty ? 96 : 128,
              decoration: BoxDecoration(
                color: context.colors.field,
                borderRadius: BorderRadius.circular(25),
              ),
              child: CustomPaint(
                painter: _DashedBorder(color: context.colors.navy),
                // The frame's tile: its own 20x20 icon, 8 left of the
                // two lines, the pair centred in the 174x128 tile.
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/images/icon-attach.png',
                        width: 20, height: 20, color: context.colors.navy),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.s.reportDetailsAttachMedia,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              height: 14 / 12,
                              color: context.colors.navy,
                            )),
                        Text(context.s.reportDetailsMaxPhotoSize,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w400,
                              fontSize: 10,
                              height: 1,
                              fontStyle: FontStyle.italic,
                              color: context.colors.navy,
                            )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One optional video, styled to match [_PhotoStrip]'s "Attach Media"
/// tile. Deliberately singular — file_report()/report_media has no
/// notion of "several videos" the way photos do.
class _VideoAttach extends StatelessWidget {
  const _VideoAttach({
    required this.video,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final File? video;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (video != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.field,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(Icons.videocam, color: context.colors.navy),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.s.reportDetailsVideoAttachedNote,
                style: TextStyle(fontSize: 12, color: context.colors.navy),
              ),
            ),
            IconButton(
              icon: Icon(Icons.cancel, color: context.colors.navy),
              onPressed: enabled ? onRemove : null,
            ),
          ],
        ),
      );
    }
    return InkWell(
      onTap: enabled ? onAdd : null,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.field,
          borderRadius: BorderRadius.circular(25),
        ),
        child: CustomPaint(
          painter: _DashedBorder(color: context.colors.navy),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_outlined, color: context.colors.navy, size: 22),
              const SizedBox(height: 6),
              Text(context.s.reportDetailsAttachVideoOptional,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: context.colors.navy,
                  )),
              Text(context.s.reportDetailsMaxVideoSize,
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: context.colors.navy,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  // A CustomPainter has no BuildContext of its own, so the theme-aware
  // colour has to be resolved by the widget building it (which does
  // have one) and passed in here — the same reason ReportStatus.
  // labelColour became a method rather than a getter.
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(25),
    );
    final path = Path()..addRRect(rrect);

    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder oldDelegate) =>
      oldDelegate.color != color;
}

class _Acknowledgement extends StatelessWidget {
  const _Acknowledgement({
    required this.value,
    required this.onChanged,
    this.error,
    this.enabled = true,
  });

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String? error;
  final bool enabled;

  // Phone run (7 Oct 2026): the 12 px box was too small to see or hit.
  // Now a 22 px box, and the whole sentence takes the tap.
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: enabled ? () => onChanged(!value) : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: IgnorePointer(
                    child: Checkbox(
                      value: value,
                      onChanged: enabled ? onChanged : null,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      side: BorderSide(color: context.colors.navy, width: 1.6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.s.reportDetailsAcknowledgement,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      height: 1.45,
                      color: context.colors.navy,
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 2),
              child: Text(error!,
                  style: TextStyle(color: context.colors.hint, fontSize: 12)),
            ),
        ],
      );
}

class _Banner extends StatelessWidget {
  const _Banner(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.hint.withValues(alpha: 0.08),
          border: Border.all(color: context.colors.hint),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message,
            style: TextStyle(color: context.colors.hint, fontSize: 13)),
      );
}
