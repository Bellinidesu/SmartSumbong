// SmartSumbong — Walking navigation to a dispatch (branch C).
//
// Its own full-screen page over the dispatch window rather than the
// window's map grown to fill the screen: MapLibre's native view did not
// survive being resized in place (blank or stale frames, overlays lost),
// and a map that is full size from the start has nothing to resize.
//
// The route and its turns come from navigation.dart. Fixes stay on the
// phone and stop when this page closes. Pops true on arrival (within
// 25 m of the complaint), false when the tanod ends it.

part of 'dispatch_order.dart';

class _NavScreen extends StatefulWidget {
  const _NavScreen({
    required this.to,
    required this.route,
    required this.start,
  });

  final LatLng to;
  final NavRoute route;
  final Position start;

  @override
  State<_NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends State<_NavScreen> {
  final _mapCtl = BrgyMapController();
  late NavRoute _nav = widget.route;
  NavFix? _fix;
  LatLng? _me;
  double? _meAccuracy;
  List<LatLng> _route = const [];
  bool _follow = true;
  bool _muted = false;
  bool _rerouting = false;
  bool _done = false;
  int _offCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  final _spoken = <String>{};
  StreamSubscription<Position>? _posSub;
  final _tts = FlutterTts();
  TanodStrings? _voice;

  @override
  void initState() {
    super.initState();
    _route = widget.route.line;
    unawaited(WakelockPlus.enable());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _voiceUp();
      if (!mounted) return;
      _onPos(widget.start);
      final first = _nav.steps.isEmpty ? null : _nav.steps.first;
      _say(
        first?.instruction(_voice ?? context.ts) ??
            (_voice ?? context.ts).navStart,
      );
      _posSub = Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 3,
          intervalDuration: const Duration(seconds: 1),
        ),
      ).listen(_onPos, onError: (_) {});
    });
  }

  @override
  void dispose() {
    unawaited(_posSub?.cancel());
    unawaited(WakelockPlus.disable());
    unawaited(_tts.stop());
    super.dispose();
  }

  /// The phone's voice, in the app's language where the phone has it.
  Future<void> _voiceUp() async {
    final s = context.ts;
    try {
      await _tts.setSpeechRate(0.5);
      var voice = s;
      if (s.locale == AppLocale.fil &&
          await _tts.isLanguageAvailable('fil-PH') == true) {
        await _tts.setLanguage('fil-PH');
      } else {
        // No Filipino voice on the phone: English words, not Tagalog
        // read out by an English voice.
        voice = const TanodStrings(AppLocale.en);
        await _tts.setLanguage('en-US');
      }
      _voice = voice;
    } catch (_) {
      _voice = s;
    }
  }

  void _say(String text) {
    if (!_muted) unawaited(_tts.speak(text));
  }

  void _onPos(Position p) {
    if (!mounted || _done) return;
    final to = widget.to;
    final me = LatLng(p.latitude, p.longitude);
    final route = _nav;
    final fix = route.locate(me);
    final voice = _voice ?? context.ts;

    // Within 25 m of the complaint: there.
    if (Geolocator.distanceBetween(
          me.latitude,
          me.longitude,
          to.latitude,
          to.longitude,
        ) <
        25) {
      _done = true;
      _say(voice.navArrive);
      Navigator.of(context).pop(true);
      return;
    }

    // Off the line three fixes running, with a fix good enough to say
    // so: a new route from here, at most every 15 seconds.
    if (fix.offRoute > 35 && p.accuracy < 40) {
      _offCount++;
      if (_offCount >= 3 &&
          !_rerouting &&
          DateTime.now().difference(_lastReroute).inSeconds > 15) {
        unawaited(_reroute(me));
      }
    } else {
      _offCount = 0;
    }

    final next = route.nextStep(fix);
    if (next != null && !next.isArrive) {
      final d = route.metresTo(next, fix);
      final key = '${next.index}';
      if (d <= 30 && _spoken.add('$key-now')) {
        _say(next.instruction(voice));
      } else if (d <= 120 && d > 45 && _spoken.add('$key-soon')) {
        _say(voice.navIn(navDistance(d), next.instruction(voice)));
      }
    }

    if (_follow) {
      final heading = p.speed > 0.7 && p.heading >= 0
          ? p.heading
          : route.bearingAt(fix);
      _mapCtl.follow(me, bearing: heading);
    }
    setState(() {
      _me = me;
      _meAccuracy = p.accuracy;
      _fix = fix;
      _route = route.ahead(fix);
    });
  }

  Future<void> _reroute(LatLng me) async {
    _rerouting = true;
    _lastReroute = DateTime.now();
    _say((_voice ?? context.ts).navRerouting);
    if (mounted) setState(() {});
    try {
      final route = await fetchNavRoute(me, widget.to);
      if (!mounted) return;
      _spoken.clear();
      _offCount = 0;
      setState(() => _nav = route);
    } catch (_) {
      // Keep the old route; the next fixes will try again.
    } finally {
      _rerouting = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final c = context.colors;
    final route = _nav;
    final fix = _fix;
    final next = fix == null ? null : route.nextStep(fix);
    final toNext = next == null || fix == null
        ? null
        : route.metresTo(next, fix);
    final left = fix == null ? route.metres : route.metresLeft(fix);
    final mins = (left / route.pace / 60).ceil().clamp(1, 999);
    final eta = DateTime.now().add(Duration(minutes: mins));
    final h = eta.hour % 12 == 0 ? 12 : eta.hour % 12;
    final etaText =
        '$h:${eta.minute.toString().padLeft(2, '0')} '
        '${eta.hour < 12 ? 'AM' : 'PM'}';
    const white = Colors.white;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: BrgyMap(
              controller: _mapCtl,
              initialCenter: LatLng(
                widget.start.latitude,
                widget.start.longitude,
              ),
              initialZoom: 18,
              pins: [BrgyMapPin(id: 'case', point: widget.to)],
              route: _route,
              me: _me,
              accuracyCentre: _me,
              accuracyMetres: _me == null
                  ? null
                  : (_meAccuracy ?? 15).clamp(8, 40).toDouble(),
              onMoved: (_) {
                if (_follow) setState(() => _follow = false);
              },
            ),
          ),
          // The next turn.
          Positioned(
            left: 12,
            right: 12,
            top: MediaQuery.paddingOf(context).top + 8,
            child: Material(
              color: const Color(0xFF14181D),
              elevation: 6,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Icon(
                      next?.icon ?? Icons.navigation,
                      color: kFigmaOrange,
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (toNext != null)
                            Text(
                              navDistance(toNext),
                              style: const TextStyle(
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w800,
                                fontSize: 26,
                                color: white,
                              ),
                            ),
                          Text(
                            _rerouting
                                ? s.navRerouting
                                : (next ?? route.steps.lastOrNull)?.instruction(
                                        s,
                                      ) ??
                                      s.navStart,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Urbanist',
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_follow)
            Positioned(
              right: 16,
              bottom: 92 + MediaQuery.paddingOf(context).bottom,
              child: FloatingActionButton.extended(
                heroTag: null,
                backgroundColor: c.bg,
                foregroundColor: c.navy,
                icon: const Icon(Icons.my_location),
                label: Text(s.navRecentre),
                onPressed: () {
                  setState(() => _follow = true);
                  final me = _me;
                  if (me != null && fix != null) {
                    _mapCtl.follow(me, bearing: route.bearingAt(fix));
                  }
                },
              ),
            ),
          // Arrival time, what is left, voice, and End.
          Positioned(
            left: 0,
            bottom: 0,
            width: MediaQuery.sizeOf(context).width,
            height: 76 + MediaQuery.paddingOf(context).bottom,
            child: Material(
              color: c.bg,
              elevation: 10,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 14, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.navArriveAt(etaText),
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                                color: c.navy,
                              ),
                            ),
                            Text(
                              '${navDistance(left)} · $mins min',
                              style: TextStyle(
                                fontFamily: 'Urbanist',
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: s.navMute,
                        icon: Icon(
                          _muted ? Icons.volume_off : Icons.volume_up,
                          color: c.navy,
                        ),
                        onPressed: () {
                          setState(() => _muted = !_muted);
                          if (_muted) unawaited(_tts.stop());
                        },
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          // The theme's buttons are full width
                          // (Size.fromHeight), which a Row cannot lay out.
                          minimumSize: const Size(0, 44),
                          backgroundColor: _red,
                          foregroundColor: white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 22,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text(
                          s.navEnd,
                          style: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
