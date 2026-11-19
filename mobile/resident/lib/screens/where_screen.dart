// SmartSumbong — Submit Report, step 2 of 3: where is it?
//
// 19 Nov 2026, from the design Ace approved (Where is it?: A1 located, A typing, A2 outside). It used to be a
// card on the details screen; it is a full screen of its own now, between the first page (the category and the
// concerns) and the details (what happened, photos).
//
// The map fills the phone. The pin is fixed and the resident slides the map under it (easier one-handed than
// dragging a small target with a thumb that covers it); the accuracy circle is on the ground around a GPS fix,
// because a phone under tree cover can be fifty metres out and a resident who can see that has a reason to drag.
// Always at the top: Back and a field to type an address or landmark, with places to pick as it is typed
// (lib/place_search.dart: the barangay's own search, then Photon). At the bottom, a sheet that says where the pin
// is in words ("Near 8th Street"; PlaceWords there), how sure the phone is, and Confirm.
//
// OUTSIDE BARANGAY 183 is caught live (Rose, 7 Oct 2026, now as it happens rather than at submit): the pin turns
// grey and lifts, the sheet says so, and Confirm is off until the pin is back inside. The details screen still
// refuses a spot outside the barangay when the report is sent, as a safety net.
//
// Barangay 183's centre — from OSM relation 2988704, the residential centre the portal's Spatial Distribution
// uses — is where the map starts when location is denied or unavailable. It is always wrong, which is the
// point: it forces a deliberate move rather than silently filing a complaint at a plausible-looking place.
//
// ON EXIF. It is tempting to read GPS out of the uploaded photo and move the pin there. Two reasons not to:
// media_upload.dart strips EXIF before upload precisely so an anonymous complaint does not carry the
// complainant's home coordinates, and Android's photo picker removes location before Flutter sees the file
// anyway unless the app asks for ACCESS_MEDIA_LOCATION — a permission prompt that would tell the resident
// exactly what it was doing. Live position is more accurate and costs nothing.
//
// THE CONTRACT. Page one pushes '/submit-report/details' with a CategoryChoice (and has not changed); main.dart
// answers that with this screen. Confirm pushes '/submit-report/details' with [DetailsArgs] (the choice and the
// [WhereResult]). The details screen's Change pushes '/submit-report/where' with [WhereArgs] (returnResult) and
// gets the new [WhereResult] back when this screen pops.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../models/barangay_profile.dart';
import '../models/complaint_category.dart';
import '../place_search.dart';
import '../preview/demo.dart';
import '../widgets/brgy_map.dart';
import '../widgets/complaints_strip.dart';
import '../widgets/d_form.dart';

/// What the resident chose: the pin, how sure the phone was of it (null once the pin is moved by hand), and the
/// few words for it ("8th Street"; null when none could be found, shown as "Near your pin").
@immutable
class WhereResult {
  const WhereResult({required this.pin, this.accuracyMetres, this.near});

  final LatLng pin;
  final double? accuracyMetres;
  final String? near;
}

/// What the details screen opens with.
@immutable
class DetailsArgs {
  const DetailsArgs(this.choice, this.where, {this.picks});

  final CategoryChoice choice;
  final WhereResult where;

  /// The picks shared with the first page (see [WhereArgs.picks]).
  final ValueNotifier<CategoryChoice>? picks;
}

/// What this screen opens with. [current] is a pin already chosen (the details screen's Change); with
/// [returnResult] Confirm hands the new [WhereResult] back instead of going on to the details.
@immutable
class WhereArgs {
  const WhereArgs(this.choice, {this.current, this.returnResult = false, this.picks});

  final CategoryChoice choice;

  /// The picks, shared with the first page and the details: "Your complaints" changes them here and there, and the
  /// first page shows the same ones when See all categories brings the resident back to it. Null: not shared.
  final ValueNotifier<CategoryChoice>? picks;
  final WhereResult? current;
  final bool returnResult;
}

/// "Zone 20, Barangay 183 · Villamor, Pasay City" from the barangay's own profile (0148).
String whereAreaLine() {
  final parts = BarangayProfile.place.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  if (parts.length < 2) return '${BarangayProfile.name} · ${BarangayProfile.place}';
  return '${parts.first}, ${BarangayProfile.name} · ${parts.skip(1).join(', ')}';
}

/// "Zone 20, Barangay 183": the short form, for the details screen's row.
String whereZoneLine() {
  final parts = BarangayProfile.place.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  return parts.length < 2 ? BarangayProfile.name : '${parts.first}, ${BarangayProfile.name}';
}

/// "Near 8th Street", or "Near your pin" when no words were found.
String whereNearLine(BuildContext context, String? near) =>
    near == null || near.trim().isEmpty ? context.tr('Near your pin', 'Malapit sa iyong pin') : context.tr('Near $near', 'Malapit sa $near');

class WhereScreen extends StatefulWidget {
  const WhereScreen({super.key, required this.args});

  final WhereArgs args;

  @override
  State<WhereScreen> createState() => _WhereScreenState();
}

class _WhereScreenState extends State<WhereScreen> {
  final _map = BrgyMapController();
  late CategoryChoice _choice = widget.args.choice;
  final _field = TextEditingController();
  final _focus = FocusNode();

  LatLng _pin = brgyCentre;
  double? _accuracyMetres;
  String? _near;
  bool _locating = false;
  bool _locationDenied = false;

  /// The phone is somewhere else (or nowhere we can tell): the map starts at the barangay centre and says so.
  bool _farAway = false;

  /// The resident moved the map or picked a place while the phone was still looking for a fix: that fix is no
  /// longer wanted.
  bool _userMoved = false;

  List<List<LatLng>> _rings = const [];
  List<PlaceHit> _suggestions = const [];
  Timer? _suggestDebounce;
  int _suggestSeq = 0;
  bool _geocoding = false;
  String? _geocodeError;
  bool _settingText = false;

  Timer? _nearTimer;
  int _nearSeq = 0;

  bool get _outside => !insideBrgy(_rings, _pin);

  @override
  void initState() {
    super.initState();
    final cur = widget.args.current;
    brgyBoundary().then((r) {
      if (mounted) setState(() => _rings = r);
    });
    widget.args.picks?.addListener(_picksChanged);
    _field.addListener(_onTyped);
    _focus.addListener(() => setState(() {}));
    if (cur != null) {
      // Change, from the details screen: start where the pin is.
      _pin = cur.pin;
      _accuracyMetres = cur.accuracyMetres;
      _near = cur.near;
      if (cur.near == null) _resolveNear();
    } else {
      _locate();
    }
  }

  @override
  void dispose() {
    widget.args.picks?.removeListener(_picksChanged);
    _suggestDebounce?.cancel();
    _nearTimer?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ---------- the complaints ---------------------------------------

  /// Picked again elsewhere (the details screen over this one).
  void _picksChanged() {
    final v = widget.args.picks?.value;
    if (v != null && mounted) setState(() => _choice = v);
  }

  /// Changed in the "Your complaints" sheet here.
  void _setChoice(CategoryChoice c) {
    setState(() => _choice = c);
    widget.args.picks?.value = c;
  }

  /// See all categories: back to the first page, with the picks it already has.
  void _seeAll() => Navigator.of(context).popUntil((r) => r.settings.name == '/submit-report' || r.isFirst);

  // ---------- where the pin is ----------------------------------

  /// Puts the pin at [p]. [near] is the name when it is already known (a place picked from the list).
  void _setPin(LatLng p, {double? accuracy, String? near}) {
    setState(() {
      _pin = p;
      _accuracyMetres = accuracy;
      _near = near;
    });
    if (near == null) _resolveNear();
  }

  /// The few words for the pin, without ever holding anything up: a landmark on the phone first, then (only once
  /// the map has stopped moving, one request a second at most, a newer pin cancelling this one) a reverse lookup.
  void _resolveNear() {
    _nearTimer?.cancel();
    final seq = ++_nearSeq;
    final at = _pin;
    () async {
      final landmark = await PlaceWords.landmarkAt(at);
      if (!mounted || seq != _nearSeq) return;
      if (landmark != null) {
        setState(() => _near = landmark);
        return;
      }
      _nearTimer = Timer(const Duration(milliseconds: 700), () async {
        final street = await PlaceWords.reverse(at, stale: () => !mounted || seq != _nearSeq);
        if (!mounted || seq != _nearSeq || street == null) return;
        setState(() => _near = street);
      });
    }();
  }

  /// The map was slid by hand: the pin follows its centre.
  void _onMapMoved(LatLng p) {
    _userMoved = true;
    if (_focus.hasFocus || _suggestions.isNotEmpty) {
      _focus.unfocus();
      setState(() {
        _suggestions = const [];
        _geocodeError = null;
      });
    }
    _setPin(p);
  }

  Future<void> _locate() async {
    _userMoved = false;
    setState(() {
      _locating = true;
      _locationDenied = false;
      _farAway = false;
    });
    try {
      if (kDemo) {
        // The Dart preview has no GPS: a fix on 13th Street.
        if (!mounted) return;
        _fix(const LatLng(14.5281, 121.0149), 12);
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
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _fallback(denied: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      final rings = _rings.isNotEmpty ? _rings : await brgyBoundary();
      if (!mounted) return;
      final here = LatLng(pos.latitude, pos.longitude);
      if (!insideBrgy(rings, here)) {
        // Rose (7 Oct 2026): a phone far away put the pin in another country. Start from the barangay instead.
        _fallback(denied: false, farAway: true);
        return;
      }
      _fix(here, pos.accuracy);
    } catch (_) {
      // Timed out, or no fix indoors. Not an error the resident can act on beyond moving the pin themselves.
      _fallback(denied: false);
    }
  }

  void _fix(LatLng at, double accuracy) {
    if (!mounted) return;
    if (_userMoved) {
      // They put the pin where they wanted while the phone was still looking.
      setState(() => _locating = false);
      return;
    }
    setState(() => _locating = false);
    _setPin(at, accuracy: accuracy);
    _map.move(at, 17);
  }

  void _fallback({required bool denied, bool farAway = false}) {
    if (!mounted) return;
    if (_userMoved) {
      setState(() {
        _locating = false;
        _locationDenied = denied;
      });
      return;
    }
    setState(() {
      _locating = false;
      _locationDenied = denied;
      _farAway = farAway;
    });
    _setPin(brgyCentre);
    _map.move(brgyCentre, 16);
  }

  /// "Take me back to 183": the pin back inside, at the barangay's centre.
  void _backInside() {
    _userMoved = true;
    _focus.unfocus();
    _setPin(brgyCentre);
    _map.move(brgyCentre, 16);
  }

  // ---------- the address -----------------------------------------

  Future<List<PlaceHit>> _lookup(String q) =>
      PlaceSearch.lookup(q, near: _pin, rings: _rings, tr: (en, fil) => context.tr(en, fil));

  void _onTyped() {
    setState(() {}); // the clear button
    if (_settingText) return;
    _suggestDebounce?.cancel();
    final q = _field.text.trim();
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
      } catch (_) {
        // Quietly: the search key says so if it fails again.
      }
    });
  }

  void _pickPlace(PlaceHit p) {
    _focus.unfocus();
    _suggestDebounce?.cancel();
    _suggestSeq++;
    _settingText = true;
    _field.text = p.title;
    _settingText = false;
    _userMoved = true;
    setState(() {
      _suggestions = const [];
      _geocodeError = null;
      _locating = false;
    });
    _setPin(p.at, near: p.title);
    _map.move(p.at, 17);
  }

  Future<void> _searchAddress() async {
    final q = _field.text.trim();
    if (q.isEmpty) return;
    if (_suggestions.isNotEmpty) {
      _pickPlace(_suggestions.first);
      return;
    }
    _focus.unfocus();
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
      setState(() => _geocodeError = context.s.reportDetailsAddressLookupFailed);
    } finally {
      if (mounted) setState(() => _geocoding = false);
    }
  }

  void _clearField() {
    _field.clear();
    setState(() {
      _suggestions = const [];
      _geocodeError = null;
    });
  }

  void _closeSuggestions() {
    _focus.unfocus();
    setState(() {
      _suggestions = const [];
      _geocodeError = null;
    });
  }

  // ---------- confirm ---------------------------------------------

  void _confirm() {
    final res = WhereResult(pin: _pin, accuracyMetres: _accuracyMetres, near: _near);
    if (widget.args.returnResult) {
      Navigator.of(context).pop(res);
    } else {
      Navigator.of(context).pushNamed('/submit-report/details', arguments: DetailsArgs(_choice, res, picks: widget.args.picks));
    }
  }

  // ---------- build -----------------------------------------------

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final choice = _choice;
    final col = categoryColour(choice.category);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final outside = _outside;
    final typing = _suggestions.isNotEmpty || _geocodeError != null;

    // The pin sits in the middle of the map that can be seen, between the search bar and the sheet; the native
    // map's own centre is the pin's place, so the map is laid out taller than the screen, centred there.
    final barTop = pad.top + 8;
    const barH = 44.0;
    final sheetNominal = 316.0 + pad.bottom;
    final free = size.height - sheetNominal - (barTop + barH);
    final pinY = barTop + barH + (free > 120 ? free : 120) / 2;
    final mapH = 2 * (pinY > size.height - pinY ? pinY : size.height - pinY);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: d.dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: d.dark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: d.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(children: [
          Positioned(
            left: 0,
            right: 0,
            top: pinY - mapH / 2,
            height: mapH,
            child: BrgyMap(
              use: BrgyMapUse.pick,
              controller: _map,
              initialCenter: _pin,
              onMoved: _onMapMoved,
              accuracyCentre: _accuracyMetres == null ? null : _pin,
              accuracyMetres: _accuracyMetres,
              // the map's credit sits above the locate button, clear of the sheet
              controlsPadding: EdgeInsets.only(bottom: sheetNominal + 76 + (pinY + mapH / 2 - size.height)),
            ),
          ),

          // dims the map while the places are open; a tap on it puts them away
          if (typing)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSuggestions,
                child: ColoredBox(color: d.dark ? const Color(0x73000000) : const Color(0x4D141B34)),
              ),
            ),

          // the pin, fixed; the map slides under it
          Positioned(
            left: 0,
            right: 0,
            top: pinY - 34,
            height: 68,
            child: IgnorePointer(child: Center(child: _WherePin(choice: choice, colour: col, outside: outside))),
          ),

          // back and the typing field
          Positioned(
            left: 16,
            right: 16,
            top: barTop,
            child: Row(children: [
              _RoundButton(
                label: MaterialLocalizations.of(context).backButtonTooltip,
                size: 44,
                onTap: () => Navigator.of(context).maybePop(),
                child: Icon(Icons.chevron_left_rounded, size: 28, color: d.ink),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SearchBar(
                  controller: _field,
                  focus: _focus,
                  busy: _geocoding,
                  onSubmit: _searchAddress,
                  onClear: _clearField,
                ),
              ),
            ]),
          ),

          if (typing)
            Positioned(
              left: 16,
              right: 16,
              top: barTop + barH + 8,
              child: _Suggestions(
                places: _suggestions,
                error: _geocodeError,
                maxHeight: (size.height - MediaQuery.viewInsetsOf(context).bottom - (barTop + barH + 24)).clamp(120.0, 420.0),
                onPick: _pickPlace,
              ),
            ),

          // the locate button, and the sheet under it
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!outside)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16, bottom: 12),
                    child: _RoundButton(
                      label: context.tr('Use my location', 'Gamitin ang aking lokasyon'),
                      size: 48,
                      onTap: _locating ? null : _locate,
                      child: _locating
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: d.ink))
                          : Icon(Icons.my_location_rounded, size: 22, color: d.ink),
                    ),
                  ),
                ),
              _Sheet(
                maxHeight: size.height * .72,
                bottomInset: pad.bottom,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(context.tr('Step 2 of 3 · Where is it?', 'Hakbang 2 ng 3 · Saan ito?').toUpperCase(),
                      style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: .96, height: 1, color: d.muted)),
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerLeft, child: ComplaintsStrip(choice: choice, onChanged: _setChoice, onSeeAll: _seeAll)),
                  if (outside) ..._outsideBody(d) else ..._insideBody(d, typing),
                ]),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _insideBody(DColors d, bool typing) {
    final String note;
    if (typing) {
      note = context.tr('Pick a suggestion and the pin moves there. The address updates.', 'Pumili ng mungkahi at lilipat doon ang pin. Magbabago ang address.');
    } else if (_locating) {
      note = context.s.reportDetailsFindingLocation;
    } else if (_locationDenied) {
      note = context.s.reportDetailsLocationOffNote;
    } else if (_farAway) {
      note = context.tr(
          'You seem to be outside ${BarangayProfile.name}, so the map shows the barangay centre. Drag the map or type the address above.',
          'Mukhang nasa labas ka ng ${BarangayProfile.name}, kaya nasa gitna ng barangay ang mapa. I-drag ang mapa o i-type ang address sa itaas.');
    } else if (_accuracyMetres != null) {
      note = context.tr('Accurate to about ${_accuracyMetres!.round()} m. Drag the map to move the pin, or type the address above.',
          'Tumpak sa humigit-kumulang ${_accuracyMetres!.round()} m. I-drag ang mapa para ilipat ang pin, o i-type ang address sa itaas.');
    } else {
      note = context.tr('Pin placed by hand. Drag the map to adjust, or type the address above.', 'Manwal na inilagay ang pin. I-drag ang mapa para ayusin, o i-type ang address sa itaas.');
    }
    return [
      const SizedBox(height: 4),
      Text(whereNearLine(context, _near),
          maxLines: 2, overflow: TextOverflow.ellipsis, style: DType.h1(d.ink).copyWith(fontSize: 26, height: 30 / 26)),
      const SizedBox(height: 4),
      Text(whereAreaLine(), style: DType.body(d.ink2, size: 14).copyWith(height: 20 / 14)),
      const SizedBox(height: 12),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(Icons.place_outlined, size: 18, color: d.muted)),
        const SizedBox(width: 8),
        Expanded(child: Text(note, style: DType.body(d.muted, size: 13).copyWith(height: 18 / 13))),
      ]),
      const SizedBox(height: 16),
      DFormButton(context.tr('Confirm this spot', 'Kumpirmahin ang lugar na ito'), onTap: _locating ? null : _confirm),
    ];
  }

  List<Widget> _outsideBody(DColors d) {
    final red = const Color(0xFFC4172A);
    return [
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 10),
        child: Row(children: [
          Icon(Icons.place_outlined, size: 18, color: d.muted),
          const SizedBox(width: 8),
          Expanded(child: Text(whereNearLine(context, _near), maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink2, size: 13, w: FontWeight.w600))),
        ]),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: red.withValues(alpha: d.dark ? .22 : .10), borderRadius: BorderRadius.circular(16)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(shape: BoxShape.circle, color: red),
            child: const Icon(Icons.error_outline_rounded, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('That spot is outside ${BarangayProfile.name}', 'Nasa labas ng ${BarangayProfile.name} ang lugar na iyon'),
                  style: DType.body(d.ink, size: 16, w: FontWeight.w800).copyWith(height: 22 / 16)),
              const SizedBox(height: 2),
              Text(
                  context.tr('A tanod can only be sent inside the barangay. Move the pin into the clear area of the map.',
                      'Sa loob lang ng barangay maaaring ipadala ang tanod. Ilipat ang pin sa malinaw na bahagi ng mapa.'),
                  style: DType.body(d.ink2, size: 13.5).copyWith(height: 19 / 13.5)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      DFormButton(context.tr('Take me back to ${BarangayProfile.name}', 'Ibalik ako sa ${BarangayProfile.name}'),
          kind: DFormKind.ghost, icon: Icons.my_location_rounded, onTap: _backInside),
      const SizedBox(height: 3),
      DFormButton(context.tr('Confirm this spot', 'Kumpirmahin ang lugar na ito'), onTap: null),
    ];
  }
}

// ---------- pieces -------------------------------------------

/// The pin over the map, fixed at its middle: the portal's disc in the category's colour with its symbol. Outside
/// the barangay it turns grey and lifts, with its shadow left on the ground where the spot is.
class _WherePin extends StatelessWidget {
  const _WherePin({required this.choice, required this.colour, required this.outside});

  final CategoryChoice choice;
  final Color colour;
  final bool outside;

  @override
  Widget build(BuildContext context) {
    final pin = BrgyMapPin(
      id: 'pick',
      point: brgyCentre,
      colour: outside ? const Color(0xFF8A90A0) : colour,
      glyph: choice.category.icon,
    );
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
        // where the spot is, when the pin is lifted off it
        if (outside)
          Container(
            width: 30,
            height: 9,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              gradient: const RadialGradient(colors: [Color(0x61000000), Color(0x00000000)]),
            ),
          ),
        AnimatedSlide(
          duration: const Duration(milliseconds: 160),
          offset: Offset(0, outside ? -.28 : 0),
          child: BrgyMapPinPreview(pin, scale: 1.2),
        ),
      ]),
    );
  }
}

/// A round control over the map: Back, Use my location. Drawn 44 or 48 across, so it is also what a finger hits.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.label, required this.size, required this.onTap, required this.child});

  final String label;
  final double size;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: d.elevation(2)),
        child: Material(
          color: d.surface(1),
          shape: const CircleBorder(),
          child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: size, height: size, child: Center(child: child))),
        ),
      ),
    );
  }
}

/// The typing field: always at the top, over the map.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.focus, required this.busy, required this.onSubmit, required this.onClear});

  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final VoidCallback onSubmit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final hint = context.tr('Type an address or landmark', 'Mag-type ng address o landmark');
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      height: 44,
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        color: d.surface(1),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          if (focus.hasFocus) const BoxShadow(color: DColors.orange, spreadRadius: 2),
          ...d.elevation(2),
        ],
      ),
      child: Row(children: [
        ExcludeSemantics(child: Icon(Icons.search_rounded, size: 20, color: d.ink)),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focus,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSubmit(),
            textAlignVertical: TextAlignVertical.center,
            cursorColor: DColors.orange,
            style: DType.body(d.ink, size: 14, w: FontWeight.w600).copyWith(height: 1.2),
            decoration: InputDecoration(
              isCollapsed: true,
              hintText: hint,
              hintStyle: DType.body(d.muted, size: 14).copyWith(height: 1.2),
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
        if (busy)
          SizedBox(width: 40, height: 40, child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: d.ink))))
        else if (controller.text.isNotEmpty)
          Semantics(
            button: true,
            label: context.tr('Clear', 'Burahin'),
            excludeSemantics: true,
            child: InkResponse(
              onTap: onClear,
              radius: 22,
              child: SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: d.field),
                    child: Icon(Icons.close_rounded, size: 16, color: d.ink2),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// The places offered as the address is typed (Rose, 7 Oct 2026), or the note that none was found.
class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.places, required this.error, required this.maxHeight, required this.onPick});

  final List<PlaceHit> places;
  final String? error;
  final double maxHeight;
  final ValueChanged<PlaceHit> onPick;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: d.surface(3), borderRadius: BorderRadius.circular(20), boxShadow: d.elevation(3)),
      child: places.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Text(error ?? '', style: DType.body(d.ink2, size: 13.5)),
            )
          : SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < places.length; i++)
                  Material(
                    color: i == 0 ? d.field : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onPick(places[i]),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: i == 0 ? d.card : d.field),
                              child: Icon(Icons.place_outlined, size: 18, color: d.ink),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(places[i].title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 14, w: FontWeight.w800).copyWith(height: 18 / 14)),
                                Text(places[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.muted, size: 12.5).copyWith(height: 16 / 12.5)),
                              ]),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
    );
  }
}

/// The bottom sheet: a card with rounded top corners lifted over the map. Scrolls when large text or a short
/// phone leave less room than it needs.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child, required this.maxHeight, required this.bottomInset});

  final Widget child;
  final double maxHeight;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: d.surface(1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: (d.dark ? Colors.black : const Color(0xFF141B34)).withValues(alpha: d.dark ? .5 : .18), blurRadius: 24, offset: const Offset(0, -6))],
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 22, 20, 16 + bottomInset),
        child: child,
      ),
    );
  }
}
