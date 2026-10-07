// SmartSumbong — Submit Report, step 2: the details.
//
// Figma node 2277:3268.
//
// ON THE MAP.
//
// OpenStreetMap vector tiles from OpenFreeMap, drawn by MapLibre
// (widgets/brgy_map.dart): no API key, no billing account, nothing to
// expire when the person who set it up graduates. That is the same
// reasoning as everywhere else in this project — it has to work at zero
// pesos and survive turnover.
//
// The pin starts at the resident's own position, because the
// overwhelming case is someone standing in front of the problem. It is
// draggable, because the second case is someone who walked home first.
// The accuracy circle is not decoration: GPS on a phone under tree cover
// or between buildings can be fifty metres out, and a resident who can
// see that has a reason to drag rather than trusting a pin that looks
// authoritative.
//
// Barangay 183's centre — 14.51646, 121.01621, from OSM relation 2988704
// — is the fallback when location is denied or unavailable. It is always
// wrong, which is the point: it forces a deliberate drag rather than
// silently filing a complaint at a plausible-looking place.
//
// ON EXIF. It is tempting to read GPS out of the uploaded photo and move
// the pin there. Two reasons not to: media_upload.dart strips EXIF
// before upload precisely so an anonymous complaint does not carry the
// complainant's home coordinates, and Android's photo picker removes
// location before Flutter sees the file anyway unless the app asks for
// ACCESS_MEDIA_LOCATION — a permission prompt that would tell the
// resident exactly what it was doing. Live position is more accurate and
// costs nothing.
//
// ON THE MANUAL ADDRESS FALLBACK. Figma (2547:103) offers a typed
// address as a second way out of "location is off," alongside
// re-requesting the permission — added during the parity pass (27 Aug
// 2026) via OpenStreetMap's own Nominatim geocoder, the same zero-cost
// family as the map tiles above and the barangay-boundary lookup
// elsewhere in this app. A typed address only ever moves the pin on
// this screen; it is never sent to file_report() as text and
// report_media/reports carry only lat/lng, so nothing downstream needs
// to know a pin came from a search box rather than a drag. A failed or
// ambiguous lookup leaves the pin exactly where it was and just says
// so — the resident can still drag it, same as before this existed.
// Deliberately not autocomplete-as-you-type: Nominatim's usage policy
// caps public requests at roughly one per second, and a single
// on-submit search respects that without needing to think about
// debouncing.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../preview/demo.dart';
import '../i18n.dart';
import '../models/complaint_category.dart';
import '../outbox.dart';
import '../theme.dart';
import '../widgets/brgy_map.dart';
import '../widgets/figma_ui.dart';
import '../location_lookup.dart';

/// Barangay 183, Zone 20, Villamor, Pasay City — from OSM relation
/// 2988704. Used only when the resident's own position is unavailable.
// Not the relation's centroid (14.51646, 121.01621) — that sits on the
// NAIA apron, so a resident with location off was offered a pin beside
// Terminal 3. This is the residential centre the admin portal's Spatial
// Distribution uses; the two must stay in step.
const _barangayCentre = LatLng(14.526905, 121.015543);

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
  });

  final CategoryChoice choice;
  final MediaUploader uploader;

  @override
  State<ReportDetailsScreen> createState() => _ReportDetailsScreenState();
}

class _ReportDetailsScreenState extends State<ReportDetailsScreen> {
  final _map = BrgyMapController();
  late final TextEditingController _description;

  LatLng _pin = _barangayCentre;
  double? _accuracyMetres;
  bool _locating = true;
  bool _locationDenied = false;

  final _addressSearch = TextEditingController();
  bool _geocoding = false;
  String? _geocodeError;

  // Rose (7 Oct 2026): the address can always be typed, with places to
  // pick from, and the pin has to be inside Barangay 183.
  List<List<LatLng>> _rings = const [];
  bool _outside = false;
  List<_Place> _suggestions = const [];
  Timer? _suggestDebounce;
  bool _settingAddress = false;
  int _suggestSeq = 0;
  final _suggestKey = GlobalKey();

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
    _addressSearch.addListener(_onAddressTyped);
    brgyBoundary().then((r) {
      if (mounted) setState(() => _rings = r);
    });
    _locate();
    _restoreDraftIfAny();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _suggestDebounce?.cancel();
    _description.dispose();
    _addressSearch.dispose();
    super.dispose();
  }

  // ---------- location ---------------------------------------

  /// Places matching what is typed, from Photon (komoot's open-source
  /// geocoder over OpenStreetMap, made for search-as-you-type), limited to
  /// the barangay's box and then to its outline.
  Future<List<_Place>> _lookup(String q) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '8',
      'lang': 'en',
      'lat': '${_barangayCentre.latitude}',
      'lon': '${_barangayCentre.longitude}',
      'bbox': '120.9996,14.5019,121.0328,14.5310',
    });
    final res = await http.get(uri, headers: {
      'User-Agent': 'SmartSumbong-Resident/1.0 (Barangay 183, Pasay City)',
    }).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) throw Exception('geocode ${res.statusCode}');
    final features = (jsonDecode(res.body) as Map)['features'] as List? ?? const [];
    final out = <_Place>[];
    for (final f in features) {
      final c = (f['geometry']?['coordinates'] as List?)?.cast<num>();
      if (c == null || c.length < 2) continue;
      final at = LatLng(c[1].toDouble(), c[0].toDouble());
      if (!insideBrgy(_rings, at)) continue;
      final pr = (f['properties'] as Map?) ?? const {};
      final name = (pr['name'] ?? '').toString();
      final street = [pr['housenumber'], pr['street']].where((e) => e != null && '$e'.isNotEmpty).join(' ');
      final title = name.isNotEmpty ? name : (street.isNotEmpty ? street : q);
      final sub = [if (name.isNotEmpty && street.isNotEmpty) street, 'Barangay 183, Pasay City'].join(' · ');
      if (out.any((o) => o.title == title && o.sub == sub)) continue;
      out.add(_Place(title, sub, at));
      if (out.length == 5) break;
    }
    return out;
  }

  void _onAddressTyped() {
    if (_settingAddress) return;
    _suggestDebounce?.cancel();
    final q = _addressSearch.text.trim();
    if (q.length < 3) {
      if (_suggestions.isNotEmpty || _geocodeError != null) {
        setState(() {
          _suggestions = const [];
          _geocodeError = null;
        });
      }
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 450), () async {
      final seq = ++_suggestSeq;
      try {
        final found = await _lookup(q);
        if (!mounted || seq != _suggestSeq) return;
        setState(() {
          _suggestions = found;
          _geocodeError = found.isEmpty ? context.s.reportDetailsAddressNotFound : null;
        });
        // Above the keyboard, so the list can be seen while typing.
        if (found.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final c = _suggestKey.currentContext;
            if (c != null) Scrollable.ensureVisible(c, alignment: 1, duration: const Duration(milliseconds: 250));
          });
        }
      } catch (_) {
        // Quietly: the search button says so if it fails again.
      }
    });
  }

  void _pickPlace(_Place p) {
    FocusScope.of(context).unfocus();
    _settingAddress = true;
    _addressSearch.text = p.title;
    _settingAddress = false;
    setState(() {
      _pin = p.at;
      _accuracyMetres = null;
      _outside = false;
      _suggestions = const [];
      _geocodeError = null;
      _errors.remove('location');
    });
    _map.move(_pin, 17);
  }

  Future<void> _searchAddress() async {
    final q = _addressSearch.text.trim();
    if (q.isEmpty) return;
    if (_suggestions.isNotEmpty) {
      _pickPlace(_suggestions.first);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _geocoding = true;
      _geocodeError = null;
    });
    try {
      final found = await _lookup(q);
      if (!mounted) return;
      if (found.isEmpty) {
        setState(() => _geocodeError = context.s.reportDetailsAddressNotFound);
        return;
      }
      _pickPlace(found.first);
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _geocodeError = context.s.reportDetailsAddressLookupFailed);
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  Future<void> _locate() async {
    setState(() {
      _locating = true;
      _locationDenied = false;
    });

    try {
      if (kDemo) {
        // The Dart preview has no GPS: a fix on 13th Street.
        if (!mounted) return;
        setState(() {
          _pin = const LatLng(14.5281, 121.0149);
          _accuracyMetres = 12;
          _locating = false;
        });
        _map.move(_pin, 17);
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        _fallback(denied: true);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        _fallback(denied: true);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      if (!mounted) return;
      final rings = _rings.isNotEmpty ? _rings : await brgyBoundary();
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      if (!insideBrgy(rings, here)) {
        // Rose (7 Oct 2026): a phone far away put the pin in another
        // country. Start from the barangay instead.
        _fallback(denied: false, outside: true);
        return;
      }
      setState(() {
        _pin = here;
        _accuracyMetres = pos.accuracy;
        _locating = false;
        _outside = false;
      });
      _map.move(_pin, 17);
    } catch (_) {
      // Timed out, or no fix indoors. Not an error the resident can act
      // on beyond dragging the pin themselves.
      _fallback(denied: false);
    }
  }

  void _fallback({required bool denied, bool outside = false}) {
    if (!mounted) return;
    setState(() {
      _pin = _barangayCentre;
      _accuracyMetres = null;
      _locating = false;
      _locationDenied = denied;
      _outside = outside;
    });
    _map.move(_pin, 15);
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
      // previously-saved draft instead of writing a blank one back.
      if (description.isEmpty && _photos.isEmpty && _video == null) {
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
      final restoredDescription = (draft['description'] as String?) ?? '';

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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.s.reportDetailsDraftRestored),
            action: SnackBarAction(
              label: context.s.reportDetailsDraftDiscard,
              onPressed: () {
                setState(() {
                  _description.clear();
                  _photos.clear();
                  _uploaded.clear();
                  _video = null;
                  _uploadedVideo = null;
                });
                _clearDraft();
              },
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      });
    } catch (_) {
      // A corrupt or unreadable draft is treated the same as no draft —
      // the form just starts blank, same as before this existed.
    }
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
          'This spot is outside Barangay 183. Move the pin inside the barangay or type the address.',
          'Nasa labas ng Barangay 183 ang lugar na ito. Ilipat ang pin sa loob ng barangay o i-type ang address.');
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
          decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: d.line)),
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
                Align(alignment: Alignment.centerLeft, child: DBack(onTap: _busy ? () {} : null)),
                const SizedBox(height: 12),
                Row(children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: col)),
                  const SizedBox(width: 8),
                  Text(widget.choice.category.label.toUpperCase(), style: DType.label(d.muted)),
                ]),
                const SizedBox(height: 6),
                DHeading(widget.choice.title, lead: s.reportDetailsCompleteBelow),
                const SizedBox(height: 14),
                if (_banner != null) ...[
                  _Banner(_banner!),
                  const SizedBox(height: 14),
                ],
                section(1, s.reportDetailsStep1, [
                  _MapCard(
                    controller: _map,
                    pin: _pin,
                    accuracyMetres: _accuracyMetres,
                    locating: _locating,
                    onMoved: (p) => setState(() {
                      _pin = p;
                      _outside = false;
                      _errors.remove('location');
                      // The circle described the GPS fix, not a hand placed
                      // pin. Keeping it would claim an accuracy that no
                      // longer applies.
                      _accuracyMetres = null;
                    }),
                  ),
                  const SizedBox(height: 6),
                  if (_outside && !_locating)
                    Text(
                      context.tr('You seem to be outside Barangay 183, so the map shows the barangay centre. Drag the pin or type the address.',
                          'Mukhang nasa labas ka ng Barangay 183, kaya nasa gitna ng barangay ang mapa. I-drag ang pin o i-type ang address.'),
                      style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5),
                    )
                  else
                    _LocationStatus(locating: _locating, denied: _locationDenied, accuracyMetres: _accuracyMetres, onRetry: _locate),
                  if (!_locating) ...[
                    const SizedBox(height: 14),
                    _ManualAddressField(
                      controller: _addressSearch,
                      busy: _geocoding,
                      error: _geocodeError,
                      enabled: !_busy,
                      onSearch: _searchAddress,
                    ),
                    if (_suggestions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _Suggestions(key: _suggestKey, places: _suggestions, onPick: _pickPlace),
                    ],
                  ],
                  if (_errors['location'] != null) ...[
                    const SizedBox(height: 8),
                    Text(_errors['location']!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
                  ],
                ]),
                const SizedBox(height: 12),
                section(2, s.reportDetailsStep2, [
                  _DescriptionBox(controller: _description, error: _errors['description'], enabled: !_busy),
                ]),
                const SizedBox(height: 12),
                section(3, s.reportDetailsStep3, [
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

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.controller,
    required this.pin,
    required this.accuracyMetres,
    required this.locating,
    required this.onMoved,
  });

  final BrgyMapController controller;
  final LatLng pin;
  final double? accuracyMetres;
  final bool locating;
  final ValueChanged<LatLng> onMoved;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Container(
        height: 218,
        // In front of the map, which would otherwise cover it.
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: context.colors.navy),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Stack(
          children: [
            // Dragging the map moves the pin: the pin stays centred and
            // the resident positions the map under it. Easier one-handed
            // than dragging a small target with a thumb that covers it.
            // The accuracy circle is on the ground, around the GPS fix.
            BrgyMap(
              controller: controller,
              initialCenter: pin,
              onMoved: onMoved,
              accuracyCentre: accuracyMetres == null ? null : pin,
              accuracyMetres: accuracyMetres,
              cornerRadius: 25,
              cornerColour: context.colors.bg,
            ),

            // The pin is drawn over the map rather than as a marker, so
            // it stays put while the map slides beneath it.
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                // Navy on the light map, the pale ink on the night one.
                child: Icon(Icons.location_on,
                    size: 36, color: context.colors.navy),
              ),
            ),

            if (locating)
              Container(
                color: Colors.black.withValues(alpha: 0.25),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationStatus extends StatelessWidget {
  const _LocationStatus({
    required this.locating,
    required this.denied,
    required this.accuracyMetres,
    required this.onRetry,
  });

  final bool locating;
  final bool denied;
  final double? accuracyMetres;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (locating) {
      return Text(context.s.reportDetailsFindingLocation,
          style: TextStyle(fontSize: 12, color: context.colors.muted));
    }

    if (denied) {
      // Figma SUBMIT REPORT - LOCATION CAN'T BE ENABLED: a centred
      // 222x33 red pill (1px #F3F3F3 edge) right under the map. Tapping
      // it still retries, for a resident who has since turned location
      // on. The note, which the frame does not show, follows it.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SizedBox(
              height: 33,
              child: FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4949),
                  foregroundColor: context.colors.bg,
                  minimumSize: const Size(222, 33),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  elevation: 0,
                  side: BorderSide(color: context.colors.bg),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                  textStyle: const TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                child: Text(context.s.reportDetailsLocationCannotBeEnabled),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.s.reportDetailsLocationOffNote,
            style: TextStyle(fontSize: 12, color: context.colors.hint, height: 1.3),
          ),
        ],
      );
    }

    if (accuracyMetres != null) {
      // Honest about the fix. A resident who can see the phone is fifty
      // metres out has a reason to drag; one who sees eight metres can
      // leave it alone.
      return Text(
        context.s.reportDetailsAccuracyNote(accuracyMetres!.round()),
        style: TextStyle(fontSize: 12, color: context.colors.muted, height: 1.3),
      );
    }

    return Text(
      context.s.reportDetailsPinPlacedNote,
      style: TextStyle(fontSize: 12, color: context.colors.muted),
    );
  }
}

/// Figma's second way out of "location is off" (2547:103), alongside
/// _LocationStatus's "Enable Location" button above. Only shown once
/// location has actually been denied — see this file's header for why
/// a typed address never reaches file_report() as text.
class _ManualAddressField extends StatelessWidget {
  const _ManualAddressField({
    required this.controller,
    required this.busy,
    required this.error,
    required this.enabled,
    required this.onSearch,
  });

  final TextEditingController controller;
  final bool busy;
  final String? error;
  final bool enabled;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Figma 2547:103 "manual input": a 14/700 section label and a
        // 322x34 pill field (#FBFBFB, 1px navy, 20 in, 12/400 hint).
        // The search icon stays: it is how the typed address is looked up.
        Text(context.s.reportDetailsManualAddressLabel,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 19 / 14,
              color: context.colors.navy,
            )),
        SizedBox(
          height: 34,
          child: TextField(
            controller: controller,
            enabled: enabled && !busy,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            textAlignVertical: TextAlignVertical.center,
            style: TextStyle(fontSize: 12, color: context.colors.navy),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              hintText: context.s.reportDetailsManualAddressHint,
              hintStyle: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w400,
                fontSize: 12,
                fontStyle: FontStyle.normal,
                color: context.colors.navy,
              ),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 40, minHeight: 34),
              suffixIcon: busy
                  ? Padding(
                      padding: const EdgeInsets.all(9),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: context.colors.navy),
                      ),
                    )
                  : IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(Icons.search, color: context.colors.navy),
                      onPressed: enabled ? onSearch : null,
                    ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4),
            child: Text(error!,
                style: TextStyle(color: context.colors.hint, fontSize: 11)),
          ),
      ],
    );
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
                              fontFamily: 'Urbanist',
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              height: 14 / 12,
                              color: context.colors.navy,
                            )),
                        Text(context.s.reportDetailsMaxPhotoSize,
                            style: TextStyle(
                              fontFamily: 'Urbanist',
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
                    fontFamily: 'Urbanist',
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
                      fontFamily: 'Urbanist',
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


/// One place offered under the address box.
class _Place {
  const _Place(this.title, this.sub, this.at);
  final String title;
  final String sub;
  final LatLng at;
}

/// Rose (7 Oct 2026): a list to pick from as the address is typed.
class _Suggestions extends StatelessWidget {
  const _Suggestions({super.key, required this.places, required this.onPick});

  final List<_Place> places;
  final ValueChanged<_Place> onPick;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: d.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < places.length; i++) ...[
          if (i > 0) Divider(height: 1, color: d.line),
          InkWell(
            onTap: () => onPick(places[i]),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  Icon(Icons.place_outlined, size: 20, color: d.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(places[i].title, style: DType.body(d.ink, size: 14, w: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(places[i].sub, style: DType.body(d.muted, size: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
