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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  @override
  void initState() {
    super.initState();
    _description =
        TextEditingController(text: widget.choice.descriptionPrefill);
    _locate();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  // ---------- location ---------------------------------------

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
      setState(() => _banner = 'You can attach up to $_maxPhotos photos.');
      return;
    }
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.photos,
      title: 'Photo access',
      rationale: 'SmartSumbong needs access to your photos to attach '
          'evidence to this report.',
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
  }

  // ---------- video --------------------------------------------

  Future<void> _addVideo() async {
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.photos,
      title: 'Photo and video access',
      rationale: 'SmartSumbong needs access to your videos to attach '
          'evidence to this report.',
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
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  void _removeVideo() {
    setState(() {
      _video = null;
      _uploadedVideo = null;
    });
  }

  // ---------- submit -----------------------------------------

  bool _validate() {
    _errors.clear();
    if (_description.text.trim().length < 10) {
      _errors['description'] =
          'Please describe the issue in a little more detail.';
    }
    if (!_acknowledged) {
      _errors['ack'] = 'Please confirm the information is accurate.';
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
      setState(() => _banner = 'Could not submit your report. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _translate(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('maximum of') && m.contains('photos')) {
      return 'You can attach up to $_maxPhotos photos.';
    }
    if (m.contains('35 mb')) {
      return 'Your photos and video are too large altogether. '
          'Remove one and try again.';
    }
    if (m.contains('_url_pinned')) {
      return 'Your photos could not be attached. Please retake them.';
    }
    if (m.contains('row-level security') || m.contains('policy')) {
      return 'Your account is not able to file reports yet. '
          'Please check with the barangay.';
    }
    return 'Could not submit your report. Please try again.';
  }

  // ---------- build ------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

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
                      'Complete the details below.',
                      textAlign: TextAlign.center,
                      style: t.titleMedium?.copyWith(fontSize: 15),
                    ),
                    const SizedBox(height: 24),

                    if (_banner != null) ...[
                      _Banner(_banner!),
                      const SizedBox(height: 16),
                    ],

                    const _StepLabel(1, 'Choose location'),
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
                    const SizedBox(height: 24),

                    const _StepLabel(2, 'Describe what happened'),
                    const SizedBox(height: 12),
                    _DescriptionBox(
                      controller: _description,
                      error: _errors['description'],
                      enabled: !_busy,
                    ),
                    const SizedBox(height: 24),

                    const _StepLabel(3, 'Attach your photo'),
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

                    const Text(
                      'Would you like to remain anonymous when reporting '
                      'this incident?',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.25,
                        color: Tokens.navy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Switch(
                          value: _anonymous,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _anonymous = v),
                          activeThumbColor: Tokens.bg,
                          activeTrackColor: Tokens.navy,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _anonymous
                                ? 'Your name will be hidden from public '
                                    'records. The barangay can still see it.'
                                : 'Your name will be shown with this report.',
                            style: const TextStyle(
                                fontSize: 11, color: Tokens.muted),
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
                          foregroundColor: Tokens.navy,
                          backgroundColor: Tokens.field,
                          minimumSize: const Size.fromHeight(45),
                          side: const BorderSide(color: Tokens.navy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        child: const Text('Back'),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Tokens.bg),
                              )
                            : const Text('Submit'),
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
        '$number.  $text',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: Tokens.navy,
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
          border: Border.all(color: Tokens.navy),
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
                        color: Tokens.navy.withValues(alpha: 0.12),
                        borderColor: Tokens.navy.withValues(alpha: 0.4),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
              ],
            ),

            // The pin is drawn over the map rather than as a marker, so
            // it stays put while the map slides beneath it.
            const Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Icon(Icons.location_on, size: 36, color: Tokens.navy),
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
      return const Text('Finding your location…',
          style: TextStyle(fontSize: 12, color: Tokens.muted));
    }

    if (denied) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Location is off, so the map is showing the barangay centre. '
            'Drag the map to put the pin where the issue is.',
            style: TextStyle(fontSize: 12, color: Tokens.hint, height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 33,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Tokens.bg,
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
              child: const Text('Enable Location'),
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
        'Accurate to about ${accuracyMetres!.round()} m. '
        'Drag the map if the pin is not in the right place.',
        style: const TextStyle(fontSize: 12, color: Tokens.muted, height: 1.3),
      );
    }

    return const Text(
      'Pin placed by hand. Drag the map to adjust.',
      style: TextStyle(fontSize: 12, color: Tokens.muted),
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
            color: Tokens.field,
            border: Border.all(color: error == null ? Tokens.navy : Tokens.hint),
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
                  style: const TextStyle(fontSize: 12, color: Tokens.navy),
                  decoration: const InputDecoration(
                    hintText: 'Describe the issue in detail.',
                    hintStyle: TextStyle(fontSize: 12, color: Tokens.muted),
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
                    '${value.text.characters.length}/$_maxDescription',
                    style: const TextStyle(fontSize: 10, color: Tokens.navy),
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
                style: const TextStyle(color: Tokens.hint, fontSize: 11)),
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
                    icon: const Icon(Icons.cancel, color: Tokens.navy),
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
                color: Tokens.field,
                borderRadius: BorderRadius.circular(25),
              ),
              child: CustomPaint(
                painter: _DashedBorder(),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_box_outlined, color: Tokens.navy, size: 22),
                    SizedBox(height: 6),
                    Text('Attach Media',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: Tokens.navy,
                        )),
                    Text('(Max: 10 MB)',
                        style: TextStyle(
                          fontSize: 10,
                          fontStyle: FontStyle.italic,
                          color: Tokens.navy,
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
          color: Tokens.field,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.videocam, color: Tokens.navy),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'A video is attached to this report.',
                style: TextStyle(fontSize: 12, color: Tokens.navy),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Tokens.navy),
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
          color: Tokens.field,
          borderRadius: BorderRadius.circular(25),
        ),
        child: CustomPaint(
          painter: _DashedBorder(),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_outlined, color: Tokens.navy, size: 22),
              SizedBox(height: 6),
              Text('Attach a short video (optional)',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Tokens.navy,
                  )),
              Text('(Max: 25 MB, about 30 seconds)',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Tokens.navy,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.navy
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
              const Expanded(
                child: Text(
                  'I acknowledge that the information I am submitting is, '
                  'to the best of my knowledge, accurate and complete. I '
                  'understand that this information will be processed for '
                  'the purpose of investigating and addressing my report.',
                  style: TextStyle(
                      fontSize: 12, color: Tokens.navy, height: 1.3),
                ),
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 4),
              child: Text(error!,
                  style: const TextStyle(color: Tokens.hint, fontSize: 11)),
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
          color: Tokens.hint.withValues(alpha: 0.08),
          border: Border.all(color: Tokens.hint),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(message,
            style: const TextStyle(color: Tokens.hint, fontSize: 13)),
      );
}
