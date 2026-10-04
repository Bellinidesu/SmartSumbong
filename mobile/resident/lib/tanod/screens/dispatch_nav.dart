// SmartSumbong — Walking navigation to a dispatch (branch C).
//
// Its own full-screen page over the dispatch window rather than the
// window's map grown to fill the screen: MapLibre's native view did not
// survive being resized in place (blank or stale frames, overlays lost),
// and a map that is full size from the start has nothing to resize.
//
// The route and its turns come from navigation.dart. Fixes stay on the
// phone and stop when this page closes. Pops 'arrived' when the tanod
// taps I've arrived (only offered within 25 m of the complaint), 'job'
// when they swipe the sheet up to the job page, null when they exit.

part of 'dispatch_order.dart';

class _NavScreen extends StatefulWidget {
  const _NavScreen({
    required this.to,
    required this.route,
    required this.start,
    required this.step,
    required this.title,
  });

  final LatLng to;
  final NavRoute route;
  final Position start;

  /// The dispatch's step when navigation opened: 0 accepted, 1 on the
  /// way, 2 arrived (navigating back for a second visit).
  final int step;

  /// "Clogged Drainage · BRG-2026-0101", for the sheet.
  final String title;

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
  final bool _done = false;

  /// Within 25 m of the complaint: I've arrived turns on.
  bool _arrived = false;
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
      _posSub = (kDemo
              ? demoWalk(widget.route)
              : Geolocator.getPositionStream(
                  locationSettings: AndroidSettings(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 3,
                    intervalDuration: const Duration(seconds: 1),
                  ),
                ))
          .listen(_onPos, onError: (_) {});
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
      if (!_arrived) {
        _say(voice.navArrive);
        HapticFeedback.mediumImpact();
      }
      if (_follow) _mapCtl.follow(me, bearing: route.bearingAt(fix));
      setState(() {
        _arrived = true;
        _me = me;
        _meAccuracy = p.accuracy;
        _fix = fix;
        _route = const [];
      });
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

  // Branch D (Ace's Navigate): the map fills the screen; a navy card at
  // the top gives the next turn and the one after; the job rides in a
  // sheet across the bottom quarter with its status. While walking the
  // button is a greyed "On the way…"; once the GPS has the tanod within
  // 25 m it becomes I've arrived. Swipe the sheet up for the job page.
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    final route = _nav;
    final fix = _fix;
    final next = fix == null ? null : route.nextStep(fix);
    final toNext = next == null || fix == null ? null : route.metresTo(next, fix);
    NavStep? after;
    if (next != null) {
      final i = route.steps.indexOf(next);
      if (i >= 0 && i + 1 < route.steps.length && !route.steps[i + 1].isArrive) after = route.steps[i + 1];
    }
    final left = fix == null ? route.metres : route.metresLeft(fix);
    final mins = (left / route.pace / 60).ceil().clamp(1, 999);
    final eta = DateTime.now().add(Duration(minutes: mins));
    final h = eta.hour % 12 == 0 ? 12 : eta.hour % 12;
    final etaText = '$h:${eta.minute.toString().padLeft(2, '0')} ${eta.hour < 12 ? 'AM' : 'PM'}';
    final step = widget.step;

    final String mainLabel;
    final VoidCallback? mainTap;
    var waiting = false;
    if (step >= 2) {
      mainLabel = context.tr('Back to the job', 'Bumalik sa trabaho');
      mainTap = () => Navigator.of(context).pop('job');
    } else if (_arrived) {
      mainLabel = s.windowActionArrived;
      mainTap = () => Navigator.of(context).pop('arrived');
    } else {
      mainLabel = context.tr('On the way…', 'Papunta na…');
      mainTap = null;
      waiting = true;
    }

    return Scaffold(
      backgroundColor: d.bg,
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            Positioned.fill(
              child: BrgyMap(
                controller: _mapCtl,
                initialCenter: LatLng(widget.start.latitude, widget.start.longitude),
                initialZoom: 18,
                pins: [BrgyMapPin(id: 'case', point: widget.to)],
                route: _route,
                me: _me,
                accuracyCentre: _me,
                accuracyMetres: _me == null ? null : (_meAccuracy ?? 15).clamp(8, 40).toDouble(),
                onMoved: (_) {
                  if (_follow) setState(() => _follow = false);
                },
              ),
            ),
            // The next turn, and the one after it.
            Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _arrived
                          ? const [Color(0xFF22A055), Color(0xFF1F8A45), Color(0xFF146B33)]
                          : const [Color(0xFF0A3FB0), Color(0xFF00308F), Color(0xFF0A1E5C)],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0x5900245A), blurRadius: 22, offset: Offset(0, 10))],
                  ),
                  child: Row(children: [
                    Icon(_arrived ? Icons.place_rounded : (next?.icon ?? Icons.navigation_rounded), color: Colors.white, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          _arrived ? s.navArrive : (toNext != null ? navDistance(toNext) : navDistance(left)),
                          style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w900, fontSize: 26, height: 1.05, color: Colors.white),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _arrived
                              ? widget.title
                              : _rerouting
                                  ? s.navRerouting
                                  : (next ?? route.steps.lastOrNull)?.instruction(s) ?? s.navStart,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 16, color: Colors.white),
                        ),
                      ]),
                    ),
                    IconButton(
                      tooltip: s.navMute,
                      icon: Icon(_muted ? Icons.volume_off_rounded : Icons.volume_up_rounded, color: Colors.white),
                      onPressed: () {
                        setState(() => _muted = !_muted);
                        if (_muted) unawaited(_tts.stop());
                      },
                    ),
                  ]),
                ),
                if (after != null && !_arrived)
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A1E5C),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Color(0x4D00245A), blurRadius: 12, offset: Offset(0, 5))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(context.tr('Then ', 'Pagkatapos '),
                          style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white70)),
                      Icon(after.icon, size: 16, color: Colors.white),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(after.instruction(s),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 13.5, color: Colors.white)),
                      ),
                    ]),
                  ),
              ]),
            ),
            if (!_follow)
              Positioned(
                right: 14,
                bottom: 30,
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      setState(() => _follow = true);
                      final me = _me;
                      if (me != null && fix != null) _mapCtl.follow(me, bearing: route.bearingAt(fix));
                    },
                    child: const SizedBox(width: 48, height: 48, child: Icon(Icons.navigation_rounded, color: DColors.brandNavy)),
                  ),
                ),
              ),
          ]),
        ),
        // The job, a quarter of the screen.
        Transform.translate(
          offset: const Offset(0, -18),
          child: GestureDetector(
            onVerticalDragEnd: (e) {
              if ((e.primaryVelocity ?? 0) < -150) Navigator.of(context).pop('job');
            },
            child: Container(
              decoration: BoxDecoration(
                color: d.card,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 24, offset: const Offset(0, -8))],
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    InkWell(
                      onTap: () => Navigator.of(context).pop('job'),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Column(children: [
                          Container(width: 44, height: 5, decoration: BoxDecoration(color: d.line, borderRadius: BorderRadius.circular(5))),
                          const SizedBox(height: 4),
                          Text(context.tr('Swipe up for the job', 'I-swipe pataas para sa trabaho'),
                              style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11, color: d.muted)),
                        ]),
                      ),
                    ),
                    DSteps(
                      step: step >= 2 ? 2 : 1,
                      labels: [s.windowStepAccepted, s.windowStepOnTheWay, s.windowStepArrived, s.windowStepResolved],
                    ),
                    const SizedBox(height: 10),
                    Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                      Text(_arrived ? context.tr('You’re here', 'Narito ka na') : '$mins min',
                          style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w900, fontSize: 26, color: d.dark ? const Color(0xFF5FD68A) : DColors.green)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_arrived ? context.tr('at the report', 'sa report') : '${navDistance(left)} · ${s.navArriveAt(etaText)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink2, size: 15, w: FontWeight.w700)),
                      ),
                    ]),
                    Row(children: [
                      Container(width: 10, height: 10, decoration: const BoxDecoration(shape: BoxShape.circle, color: DColors.orange)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink2, size: 13.5))),
                    ]),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: waiting
                            ? Container(
                                height: 52,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: d.field,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: d.line, width: 1.5),
                                ),
                                child: Text(mainLabel, style: DType.body(d.muted, size: 16, w: FontWeight.w800)),
                              )
                            : _Pulse(on: _arrived && step < 2, child: DButton(mainLabel, onTap: mainTap, expand: true, height: 52, radius: 14, fontSize: 16)),
                      ),
                      const SizedBox(width: 8),
                      DButton(context.tr('Exit', 'Lumabas'), kind: DButtonKind.danger, height: 52, radius: 14, fontSize: 16, onTap: () => Navigator.of(context).pop()),
                    ]),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// A soft orange ring that breathes around I've arrived.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.on) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: DColors.orange.withValues(alpha: .55 * (1 - _c.value)), spreadRadius: 10 * _c.value)],
        ),
        child: child,
      ),
      child: widget.child,
    );
  }
}
