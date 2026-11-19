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
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
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
import '../widgets/complaints_strip.dart';
import '../widgets/d_form.dart';
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
    this.picks,
  });

  final CategoryChoice choice;
  final MediaUploader uploader;

  /// Where the resident put the pin on the previous step. Null only for a screen opened without that step: the
  /// barangay centre, which Change then moves.
  final WhereResult? where;

  /// The picks shared with the first page and the Where screen (see [WhereArgs.picks]).
  final ValueNotifier<CategoryChoice>? picks;

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  /// What was picked on the first page (the main concern and the others, 0163). "Your complaints" changes it here
  /// and on the Where screen; the first page shows the same picks if the resident goes back to it.
  late CategoryChoice _choice = widget.choice;

  /// 0163: the other concerns, picked on the first page under the same category (Rose, 18 Nov 2026).
  List<ExtraConcern> get _extras => _choice.extras;

  /// How the description opens: the main concern the form was opened with ("Illegal Parking — ").
  late final String _prefill = widget.choice.descriptionPrefill;
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
    _description = TextEditingController(text: _prefill);
    _description.addListener(_scheduleDraftSave);
    widget.picks?.addListener(_picksChanged);
    brgyBoundary().then((r) {
      if (mounted) setState(() => _rings = r);
    });
    _restoreDraftIfAny();
  }

  @override
  void dispose() {
    widget.picks?.removeListener(_picksChanged);
    _draftDebounce?.cancel();
    _description.dispose();
    super.dispose();
  }

  // ---------- the complaints -------------------------------------

  void _picksChanged() {
    final v = widget.picks?.value;
    if (v != null && mounted) setState(() => _choice = v);
  }

  void _setChoice(CategoryChoice c) {
    setState(() => _choice = c);
    widget.picks?.value = c;
    _scheduleDraftSave();
  }

  /// See all categories: back to the first page, which has the same picks.
  void _seeAll() => Navigator.of(context).popUntil((r) => r.settings.name == '/submit-report' || r.isFirst);

  // ---------- location ---------------------------------------

  /// Change: the Where screen again, with the pin where it is; the new one comes back when it is confirmed.
  Future<void> _changeLocation() async {
    final res = await Navigator.of(context).pushNamed<WhereResult>(
      '/submit-report/where',
      arguments: WhereArgs(_choice, current: _where, returnResult: true, picks: widget.picks),
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


  /// Take photo and Gallery are two tiles now, so the source is known: the camera or the gallery, with the same
  /// permission asks as when one sheet offered both.
  Future<void> _addPhoto(ImageSource source) async {
    if (_photos.length >= _maxPhotos) {
      setState(() => _banner = context.s.reportDetailsPhotoLimit(_maxPhotos));
      return;
    }
    if (!mounted) return;
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
      final typed = description.isNotEmpty && description != _prefill.trim();
      // The other concerns are not kept: they are picked on the first page, which a draft does not reopen.
      if (!typed && _photos.isEmpty && _video == null) {
        await prefs.remove(_draftPrefsKey);
        return;
      }
      await prefs.setString(
        _draftPrefsKey,
        jsonEncode({
          'category': _choice.category.wire,
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
      if (draft['category'] != _choice.category.wire) return;

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
      final restoredDescription = saved.trim() == _prefill.trim() ? '' : saved;
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
      _description.text = _prefill;
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
      category: _choice.category.wire,
      subject: _choice.subject,
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
      optionId: _choice.optionId,
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
          ...concernParams(_choice.optionId, [for (final x in _extras) x.toJson()]),
          'p_category': _choice.category.wire,
          'p_subject': _choice.subject,
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
  // The report form, as the approved artifact draws it (FinalTop, D1, D2): Back and "Step 3 of 3", the category as
  // the title, "Complete the details below.", the complaints strip in one row, the spot as one row with Change, then
  // 1 Describe what happened (a preview that opens the big pop-up), 2 Attach your photo (and the optional video),
  // the anonymous card, the acknowledgement, and Back / Submit pinned at the bottom.

  /// The big pop-up for the description (DP): the text is the form's own, so Done and the cross both keep it.
  Future<void> _openDescribe() async {
    FocusScope.of(context).unfocus();
    _description.selection = TextSelection.collapsed(offset: _description.text.length);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.d.bg,
      barrierColor: Colors.black.withValues(alpha: context.d.dark ? .55 : .40),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _DescribeSheet(controller: _description, choice: _choice),
    );
    if (mounted) setState(() => _errors.remove('description'));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final col = categoryColour(_choice.category);
    final catName = context.tr(_choice.category.label, _choice.category.labelFil);

    return DPage(
      bottomBar: DFormBar(
        backLabel: s.reportDetailsBack,
        onBack: _busy ? null : () => Navigator.of(context).pop(),
        okLabel: s.reportDetailsSubmit,
        onOk: _busy ? null : _submit,
        busy: _busy,
      ),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            Row(children: [
              DFormBack(onTap: _busy ? () {} : null),
              const Spacer(),
              // page one is step 1, Where is it? step 2
              DStepChip(context.tr('Step 3 of 3', 'Hakbang 3 ng 3')),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
              const SizedBox(width: 10),
              Expanded(child: Text(catName, style: DType.h1(d.ink).copyWith(fontSize: 28, height: 34 / 28, letterSpacing: -.28))),
            ]),
            const SizedBox(height: 4),
            Text(s.reportDetailsCompleteBelow, style: DType.body(d.ink2, size: 14).copyWith(height: 20 / 14)),
            const SizedBox(height: 8),
            // The picks in one row; tapping them opens "Your complaints". Back / See all categories change them there.
            Align(alignment: Alignment.centerLeft, child: ComplaintsStrip(choice: _choice, onChanged: _setChoice, onSeeAll: _seeAll)),
            const SizedBox(height: 22),
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
            _Section(1, s.reportDetailsStep2, col, [
              _DescribePreview(controller: _description, error: _errors['description'], enabled: !_busy, onTap: _openDescribe),
            ]),
            const SizedBox(height: 12),
            _Section(2, s.reportDetailsStep3, col, [
              _PhotoStrip(
                photos: _photos,
                max: _maxPhotos,
                enabled: !_busy,
                onCamera: () => _addPhoto(ImageSource.camera),
                onGallery: () => _addPhoto(ImageSource.gallery),
                onRemove: _removePhoto,
              ),
              const _Divider(),
              _VideoRow(video: _video, enabled: !_busy, onAdd: _addVideo, onRemove: _removeVideo),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: _cardDeco(d, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.reportDetailsAnonymousQuestion, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800).copyWith(height: 20 / 14.5)),
                const SizedBox(height: 10),
                Row(children: [
                  _Switch(
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
                  Expanded(child: Text(_anonymous ? s.reportDetailsHiddenNote : s.reportDetailsShownNote, style: DType.body(d.muted, size: 12.5).copyWith(height: 17 / 12.5))),
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
    );
  }
}

// ---------- pieces -------------------------------------------

/// The artifact's card: the card colour, a hairline, a soft shadow.
BoxDecoration _cardDeco(DColors d, double radius) => BoxDecoration(
      color: d.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: d.line),
      boxShadow: [BoxShadow(color: d.dark ? const Color(0x73000000) : const Color(0x23141B34), blurRadius: 10, offset: const Offset(0, 2))],
    );

/// A numbered card: the step's number in the category's colour, its title, and what it holds.
class _Section extends StatelessWidget {
  const _Section(this.n, this.title, this.colour, this.body);

  final int n;
  final String title;
  final Color colour;
  final List<Widget> body;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco(d, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
            child: Center(child: Text('$n', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 13, height: 1, color: Colors.white))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(title, style: DType.body(d.ink, size: 16, w: FontWeight.w800).copyWith(height: 1.2))),
        ]),
        ...body,
      ]),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Container(height: 1, color: context.d.line));
}

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
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 5),
        decoration: _cardDeco(d, 20),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
            child: const Icon(Icons.place_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(near, maxLines: 2, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 15, w: FontWeight.w800).copyWith(height: 20 / 15)),
                Text(zone, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.muted, size: 12.5).copyWith(height: 17 / 12.5)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Align(
            alignment: Alignment.topCenter,
            child: DFormButton(context.tr('Change', 'Baguhin'), kind: DFormKind.ghost, small: true, fit: true, onTap: enabled ? onChange : null),
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

/// "1 Describe what happened": the text so far (three lines at most) in the form's field look, "Tap to write more"
/// at its corner; a tap opens the big pop-up.
class _DescribePreview extends StatelessWidget {
  const _DescribePreview({required this.controller, required this.error, required this.enabled, required this.onTap});

  final TextEditingController controller;
  final String? error;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final red = d.dark ? const Color(0xFFFF8A8A) : DColors.red;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final text = value.text.trim();
            return Semantics(
              button: true,
              enabled: enabled,
              label: '${context.s.reportDetailsStep2}. ${text.isEmpty ? context.s.reportDetailsDescribeHint : text}',
              hint: text.isEmpty ? context.tr('Tap to write', 'I-tap para magsulat') : context.tr('Tap to write more', 'I-tap para dagdagan'),
              excludeSemantics: true,
              child: Material(
                color: d.field,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: error == null ? d.line : red, width: 1.5)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: enabled ? onTap : null,
                  child: SizedBox(
                    height: 104,
                    child: Stack(children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Text(
                          text.isEmpty ? context.s.reportDetailsDescribeHint : text,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: DType.body(text.isEmpty ? d.muted : d.ink, size: 14).copyWith(height: 1.45),
                        ),
                      ),
                      Positioned(
                        right: 14,
                        bottom: 10,
                        child: Text(text.isEmpty ? context.tr('Tap to write', 'I-tap para magsulat') : context.tr('Tap to write more', 'I-tap para dagdagan'),
                            style: DType.body(d.muted, size: 12, w: FontWeight.w700).copyWith(height: 1)),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(error!, style: DType.body(red, size: 12.5, w: FontWeight.w600)),
          ),
      ]),
    );
  }
}

/// The big pop-up for the description (DP): the title and a 44 px close, every picked concern as context, a large
/// text area with an orange border and the count, one line of help, and Done above the keyboard.
class _DescribeSheet extends StatelessWidget {
  const _DescribeSheet({required this.controller, required this.choice});

  final TextEditingController controller;
  final CategoryChoice choice;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final size = MediaQuery.sizeOf(context);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    final top = MediaQuery.paddingOf(context).top;
    final bottom = kb > 0 ? 0.0 : MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SizedBox(
        height: size.height - top - kb,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 12, 18, 9 + bottom),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                  child: Text(context.s.reportDetailsStep2,
                      style: DType.h2(d.ink).copyWith(fontSize: 21, height: 28 / 21, letterSpacing: -.21))),
              Semantics(
                button: true,
                label: context.tr('Close', 'Isara'),
                excludeSemantics: true,
                child: Material(
                  color: d.card,
                  shape: CircleBorder(side: BorderSide(color: d.line)),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(width: 44, height: 44, child: Icon(Icons.close_rounded, size: 20, color: d.ink)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: ComplaintsStrip(choice: choice, all: true)),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: DColors.orange, width: 2)),
                child: Stack(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      textAlignVertical: TextAlignVertical.top,
                      inputFormatters: [LengthLimitingTextInputFormatter(_maxDescription)],
                      cursorColor: DColors.orange,
                      style: DType.body(d.ink, size: 15).copyWith(height: 1.5),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        hintText: context.s.reportDetailsDescribeHint,
                        hintStyle: DType.body(d.muted, size: 15).copyWith(height: 1.5),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                        focusedErrorBorder: InputBorder.none,
                        filled: false,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 10,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: controller,
                      builder: (context, v, _) {
                        final n = v.text.characters.length;
                        return Text(
                          // the count, and the limit once it is near
                          n >= _maxDescription - 50
                              ? context.tr('$n / $_maxDescription characters', '$n / $_maxDescription na character')
                              : context.tr('$n characters', '$n na character'),
                          style: DType.body(d.muted, size: 12, w: FontWeight.w700).copyWith(height: 1),
                        );
                      },
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 10),
            Text(
                context.tr('Helpful to add: when it started, who or what is involved, a landmark nearby.',
                    'Makakatulong idagdag: kailan ito nagsimula, sino o ano ang sangkot, at kalapit na landmark.'),
                style: DType.body(d.muted, size: 12.5).copyWith(height: 18 / 12.5)),
            const SizedBox(height: 8),
            DFormButton(context.tr('Done', 'Tapos na'), onTap: () => Navigator.of(context).pop()),
          ]),
        ),
      ),
    );
  }
}

/// The photos as 96 x 72 thumbnails with a remove cross, then the dashed Take photo and Gallery tiles, and the
/// count under them.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.photos, required this.max, required this.enabled, required this.onCamera, required this.onGallery, required this.onRemove});

  final List<File> photos;
  final int max;
  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 12),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < photos.length; i++)
          SizedBox(
            width: 96,
            height: 72,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.file(photos[i], fit: BoxFit.cover, errorBuilder: (_, _, _) => ColoredBox(color: d.field)),
                ),
              ),
              // a 44 px touch round a 22 px cross, over the thumbnail's corner
              Positioned(
                top: -14,
                right: -14,
                child: Semantics(
                  button: true,
                  label: context.tr('Remove photo ${i + 1}', 'Alisin ang larawan ${i + 1}'),
                  excludeSemantics: true,
                  child: InkResponse(
                    onTap: enabled ? () => onRemove(i) : null,
                    radius: 22,
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Center(
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(shape: BoxShape.circle, color: d.card, border: Border.all(color: d.line), boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 3)]),
                          child: Icon(Icons.close_rounded, size: 14, color: d.ink),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        _Tile(icon: Icons.photo_camera_outlined, label: context.tr('Take photo', 'Kumuha ng larawan'), onTap: enabled ? onCamera : null),
        _Tile(icon: Icons.image_outlined, label: context.tr('Gallery', 'Gallery'), onTap: enabled ? onGallery : null),
      ]),
      const SizedBox(height: 8),
      Text(context.tr('${photos.length} of $max photos', '${photos.length} sa $max larawan'), style: DType.body(d.muted, size: 12.5).copyWith(height: 18 / 12.5)),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? .5 : 1,
        child: Material(
          color: d.field,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: CustomPaint(
              painter: _DashedBorder(color: d.dark ? const Color(0xFF3C414A) : const Color(0xFFC3CBDD)),
              child: SizedBox(
                width: 96,
                height: 72,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, size: 22, color: d.ink),
                  const SizedBox(height: 4),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 12.5, w: FontWeight.w700).copyWith(height: 1)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The optional video: a round video icon, the two lines, and a small outlined Add (or, once one is attached, the
/// note and Remove). One video per report: file_report()/report_media has no notion of several.
class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.video, required this.enabled, required this.onAdd, required this.onRemove});

  final File? video;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final s = context.s;
    final has = video != null;
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: d.field),
        child: Icon(Icons.videocam_outlined, size: 20, color: d.ink),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(has ? s.reportDetailsVideoAttachedNote : s.reportDetailsAttachVideoOptional, style: DType.body(d.ink, size: 14, w: FontWeight.w800).copyWith(height: 19 / 14)),
          if (!has) Text(s.reportDetailsMaxVideoSize, style: DType.body(d.muted, size: 12.5).copyWith(height: 17 / 12.5)),
        ]),
      ),
      const SizedBox(width: 12),
      has
          ? DFormButton(context.tr('Remove', 'Alisin'), kind: DFormKind.ghost, small: true, fit: true, onTap: enabled ? onRemove : null)
          : DFormButton(context.tr('Add', 'Idagdag'), kind: DFormKind.ghost, small: true, fit: true, icon: Icons.add_rounded, onTap: enabled ? onAdd : null),
    ]);
  }
}

class _DashedBorder extends CustomPainter {
  // A CustomPainter has no BuildContext of its own, so the theme-aware colour is resolved by the widget building it.
  const _DashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()..addRRect(RRect.fromRectAndRadius((Offset.zero & size).deflate(.75), const Radius.circular(16)));
    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        canvas.drawPath(metric.extractPath(at, (at + dash).clamp(0, metric.length)), paint);
        at += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.color != color;
}

/// The artifact's switch: 52 x 32, a 24 px knob. Drawn 32 high, touched 44 high.
class _Switch extends StatelessWidget {
  const _Switch({required this.on, required this.onTap, required this.label});

  final bool on;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      toggled: on,
      label: label,
      enabled: onTap != null,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Opacity(
          opacity: onTap == null ? .5 : 1,
          child: SizedBox(
            width: 52,
            height: 44,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 32,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFF1F8A45) : (d.dark ? const Color(0xFF3C414A) : const Color(0xFFC3CBDD)),
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Color(0x59000000), blurRadius: 3, offset: Offset(0, 1))]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The acknowledgement: a 22 px navy box with a tick, and the sentence, which takes the tap too.
class _Acknowledgement extends StatelessWidget {
  const _Acknowledgement({required this.value, required this.onChanged, this.error, this.enabled = true});

  final bool value;
  final ValueChanged<bool?> onChanged;
  final String? error;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final navy = d.dark ? const Color(0xFF8FADFF) : const Color(0xFF00308F);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        checked: value,
        enabled: enabled,
        label: context.s.reportDetailsAcknowledgement,
        excludeSemantics: true,
        onTap: enabled ? () => onChanged(!value) : null,
        child: InkWell(
          onTap: enabled ? () => onChanged(!value) : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: value ? navy : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: value ? null : Border.all(color: navy, width: 2),
                  ),
                  child: value ? Icon(Icons.check_rounded, size: 16, color: d.dark ? const Color(0xFF101215) : Colors.white) : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.s.reportDetailsAcknowledgement,
                  style: DType.body(navy, size: 13).copyWith(height: 1.45),
                ),
              ),
            ]),
          ),
        ),
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(left: 36, top: 4),
          child: Text(error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w600)),
        ),
    ]);
  }
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
