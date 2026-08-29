// SmartSumbong — Submit Report, step 2: the details.
//
// Figma node 2277:3268.
//
// ON THE MAP.
//
// OpenStreetMap tiles through flutter_map: no API key, no billing
// account, nothing to expire when the person who set it up graduates.
// That is the same reasoning as everywhere else in this project — it has
// to work at zero pesos and survive turnover.
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
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../models/complaint_category.dart';
import '../theme.dart';

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
  final _map = MapController();
  late final TextEditingController _description;

  LatLng _pin = _barangayCentre;
  double? _accuracyMetres;
  bool _locating = true;
  bool _locationDenied = false;

  final _addressSearch = TextEditingController();
  bool _geocoding = false;
  String? _geocodeError;

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
    _locate();
    _restoreDraftIfAny();
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    _description.dispose();
    _addressSearch.dispose();
    super.dispose();
  }

  // ---------- location ---------------------------------------

  Future<void> _searchAddress() async {
    final q = _addressSearch.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _geocoding = true;
      _geocodeError = null;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'format': 'json',
        'limit': '1',
        'countrycodes': 'ph',
        // Biases the search toward the barangay without forcing the
        // resident to type it — Nominatim treats this as ordinary query
        // text, not a hard filter, so a mismatch costs relevance, not a
        // failure.
        'q': '$q, Barangay 183, Pasay City, Philippines',
      });
      final res = await http.get(uri, headers: {
        // Required by Nominatim's usage policy for any non-browser
        // client — identifies the app, not decoration.
        'User-Agent': 'SmartSumbong-Resident/1.0 (Barangay 183, Pasay City)',
      }).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) throw Exception('geocode ${res.statusCode}');
      final results = jsonDecode(res.body) as List;
      if (results.isEmpty) {
        if (!mounted) return;
        setState(() => _geocodeError = context.s.reportDetailsAddressNotFound);
        return;
      }

      final hit = results.first as Map<String, dynamic>;
      final lat = double.tryParse(hit['lat'] as String? ?? '');
      final lon = double.tryParse(hit['lon'] as String? ?? '');
      if (lat == null || lon == null) throw Exception('geocode: bad coords');

      if (!mounted) return;
      setState(() {
        _pin = LatLng(lat, lon);
        // The circle described a GPS fix. A typed address is not one.
        _accuracyMetres = null;
      });
      _map.move(_pin, 17);
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
      setState(() {
        _pin = LatLng(pos.latitude, pos.longitude);
        _accuracyMetres = pos.accuracy;
        _locating = false;
      });
      _map.move(_pin, 17);
    } catch (_) {
      // Timed out, or no fix indoors. Not an error the resident can act
      // on beyond dragging the pin themselves.
      _fallback(denied: false);
    }
  }

  void _fallback({required bool denied}) {
    if (!mounted) return;
    setState(() {
      _pin = _barangayCentre;
      _accuracyMetres = null;
      _locating = false;
      _locationDenied = denied;
    });
    _map.move(_pin, 15);
  }

  // ---------- photos -----------------------------------------

  Future<void> _addPhoto() async {
    if (_photos.length >= _maxPhotos) {
      setState(() => _banner = context.s.reportDetailsPhotoLimit(_maxPhotos));
      return;
    }
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.photos,
      title: context.s.reportDetailsPhotoAccessTitle,
      rationale: context.s.reportDetailsPhotoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pick();
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
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.photos,
      title: context.s.reportDetailsVideoAccessTitle,
      rationale: context.s.reportDetailsVideoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pickVideo();
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
    if (_description.text.trim().length < 10) {
      _errors['description'] = context.s.reportDetailsDescriptionValidation;
    }
    if (!_acknowledged) {
      _errors['ack'] = context.s.reportDetailsAckValidation;
    }
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_validate()) return;

    setState(() {
      _busy = true;
      _banner = null;
    });

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
        },
      );

      // Filed successfully — the whole reason this draft existed is gone.
      unawaited(_clearDraft());

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/report-submitted',
        (r) => r.settings.name == '/home',
        arguments: row is Map ? row['tracking_id'] : null,
      );
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    } on PostgrestException catch (e) {
      setState(() => _banner = _translate(e.message));
    } catch (e) {
      setState(
          () => _banner = context.s.reportDetailsSubmitFailedWithError('$e'));
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(42, 32, 42, 16),
                  children: [
                    Text(
                      widget.choice.title,
                      textAlign: TextAlign.center,
                      style: t.headlineLarge?.copyWith(fontSize: 26),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      s.reportDetailsCompleteBelow,
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 24),

                    if (_banner != null) ...[
                      _Banner(_banner!),
                      const SizedBox(height: 16),
                    ],

                    _StepLabel(1, s.reportDetailsStep1),
                    const SizedBox(height: 12),
                    _MapCard(
                      controller: _map,
                      pin: _pin,
                      accuracyMetres: _accuracyMetres,
                      locating: _locating,
                      onMoved: (p) => setState(() {
                        _pin = p;
                        // The circle described the GPS fix, not a hand
                        // placed pin. Keeping it would claim an accuracy
                        // that no longer applies.
                        _accuracyMetres = null;
                      }),
                    ),
                    const SizedBox(height: 10),
                    _LocationStatus(
                      locating: _locating,
                      denied: _locationDenied,
                      accuracyMetres: _accuracyMetres,
                      onRetry: _locate,
                    ),
                    if (_locationDenied && !_locating) ...[
                      const SizedBox(height: 10),
                      _ManualAddressField(
                        controller: _addressSearch,
                        busy: _geocoding,
                        error: _geocodeError,
                        enabled: !_busy,
                        onSearch: _searchAddress,
                      ),
                    ],
                    const SizedBox(height: 24),

                    _StepLabel(2, s.reportDetailsStep2),
                    const SizedBox(height: 12),
                    _DescriptionBox(
                      controller: _description,
                      error: _errors['description'],
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 24),

                    _StepLabel(3, s.reportDetailsStep3),
                    const SizedBox(height: 12),
                    _PhotoStrip(
                      photos: _photos,
                      max: _maxPhotos,
                      enabled: !_busy,
                      onAdd: _addPhoto,
                      onRemove: _removePhoto,
                    ),
                    const SizedBox(height: 16),
                    _VideoAttach(
                      video: _video,
                      enabled: !_busy,
                      onAdd: _addVideo,
                      onRemove: _removeVideo,
                    ),
                    const SizedBox(height: 24),

                    Text(
                      s.reportDetailsAnonymousQuestion,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.25,
                        color: context.colors.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Switch(
                          value: _anonymous,
                          onChanged: _busy
                              ? null
                              : (v) {
                                  setState(() => _anonymous = v);
                                  _scheduleDraftSave();
                                },
                          activeThumbColor: context.colors.bg,
                          activeTrackColor: context.colors.navy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _anonymous
                                ? s.reportDetailsHiddenNote
                                : s.reportDetailsShownNote,
                            style: TextStyle(
                                fontSize: 11, color: context.colors.muted),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _Acknowledgement(
                      value: _acknowledged,
                      error: _errors['ack'],
                      enabled: !_busy,
                      onChanged: (v) => setState(() {
                        _acknowledged = v ?? false;
                        _errors.remove('ack');
                      }),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(42, 0, 42, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _busy ? null : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.colors.navy,
                          backgroundColor: context.colors.field,
                          minimumSize: const Size.fromHeight(45),
                          side: BorderSide(color: context.colors.navy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        child: Text(s.reportDetailsBack),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: context.colors.bg),
                              )
                            : Text(s.reportDetailsSubmit),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- pieces -------------------------------------------

class _StepLabel extends StatelessWidget {
  const _StepLabel(this.number, this.text);
  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        context.s.reportDetailsStepLabel(number, text),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: context.colors.navy,
        ),
      );
}

class _MapCard extends StatelessWidget {
  const _MapCard({
    required this.controller,
    required this.pin,
    required this.accuracyMetres,
    required this.locating,
    required this.onMoved,
  });

  final MapController controller;
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
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.navy),
          borderRadius: BorderRadius.circular(25),
        ),
        child: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: pin,
                initialZoom: 17,
                // Dragging the map moves the pin: the pin stays centred
                // and the resident positions the map under it. Easier
                // one-handed than dragging a small target with a thumb
                // that covers it.
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture) onMoved(camera.center);
                },
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // OSM's tile policy requires a real identifying agent.
                  userAgentPackageName: 'ph.smartsumbong.resident',
                  maxZoom: 19,
                ),
                if (accuracyMetres != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: pin,
                        radius: accuracyMetres!,
                        useRadiusInMeter: true,
                        color: context.colors.navy.withValues(alpha: 0.12),
                        borderColor: context.colors.navy.withValues(alpha: 0.4),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
              ],
            ),

            // The pin is drawn over the map rather than as a marker, so
            // it stays put while the map slides beneath it.
            Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Icon(Icons.location_on, size: 36, color: context.colors.navy),
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
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.s.reportDetailsLocationOffNote,
            style: TextStyle(fontSize: 12, color: context.colors.hint, height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 33,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: context.colors.bg,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50),
                ),
                textStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: Text(context.s.reportDetailsEnableLocation),
            ),
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
        Text(context.s.reportDetailsManualAddressLabel,
            style: TextStyle(fontSize: 12, color: context.colors.muted)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled && !busy,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSearch(),
          style: TextStyle(fontSize: 13, color: context.colors.navy),
          decoration: InputDecoration(
            hintText: context.s.reportDetailsManualAddressHint,
            suffixIcon: busy
                ? Padding(
                    padding: EdgeInsets.all(13),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.colors.navy),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.search, color: context.colors.navy),
                    onPressed: enabled ? onSearch : null,
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
                  builder: (_, value, __) => Text(
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
              width: 174,
              height: 128,
              decoration: BoxDecoration(
                color: context.colors.field,
                borderRadius: BorderRadius.circular(25),
              ),
              child: CustomPaint(
                painter: _DashedBorder(color: context.colors.navy),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_box_outlined, color: context.colors.navy, size: 22),
                    const SizedBox(height: 6),
                    Text(context.s.reportDetailsAttachMedia,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: context.colors.navy,
                        )),
                    Text(context.s.reportDetailsMaxPhotoSize,
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: context.colors.navy,
                        )),
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
                    fontFamily: 'Poppins',
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

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.s.reportDetailsAcknowledgement,
                  style: TextStyle(
                      fontSize: 12, color: context.colors.navy, height: 1.3),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: Text(error!,
                  style: TextStyle(color: context.colors.hint, fontSize: 11)),
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
