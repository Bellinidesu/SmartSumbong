// SmartSumbong — Dispatch window (branch C).
//
// An accepted dispatch goes on from its card to here: the map on top
// with directions, then the steps (Accepted → On the way → Arrived →
// Resolved), the case, and a live thread of what the tanod sends and
// what the barangay replies — the shape a ride-hailing trip screen has,
// for a tanod on a job. The composer is pinned at the bottom; Resolve
// is its own sheet, because it closes the case.
//
// The thread is 0069's dispatch_updates. The barangay sees all of it;
// the resident sees only the steps, which reach them as status_logs
// remarks and notifications. Every ticket opens on its card first —
// Accept / Reroute while pending, Open dispatch once accepted.

part of 'dispatch_order.dart';

/// Rose (7 Oct 2026): the tanod's dispatch page without the in-app
/// navigation card and the chat bar. Switched off, not removed: true brings
/// both back. The barangay's instructions and the step updates still show.
const bool kTanodNavAndChat = false;

/// Rose (7 Oct 2026): Resolve next to I'm on the way confused her, so the
/// page shows one next step until the tanod has arrived. Switched off,
/// not removed: true puts Resolve back beside the first two steps.
const bool kResolveBeforeArrival = false;

/// The orange Navigate pill on the map repeated the big Navigate button
/// under it. Off: the map keeps Open in Maps only. True brings it back.
const bool kMapNavigatePill = false;

MediaUploader _proofUploader() => MediaUploader(
  cloudName: _cloudName,
  uploadPreset: _uploadPreset,
  videoUploadPreset: _videoUploadPresetRaw.isEmpty
      ? null
      : _videoUploadPresetRaw,
);

/// Camera or gallery (the CAPSTONE G12 feedback that attaching media
/// forced the camera open), the permission ask, then the pick — through
/// MediaUploader so EXIF is stripped (media_upload.dart's header). Null
/// when the tanod backs out; throws when the picker fails.
Future<File?> _pickProof(BuildContext context, {required bool video}) async {
  final s = context.ts;
  final source = await showFigmaSourceSheet(
    context,
    takeLabel: s.dispatchTakePhoto,
    galleryLabel: s.dispatchChooseFromGallery,
  );
  if (source == null || !context.mounted) return null;
  final camera = source == ImageSource.camera;
  final granted = await PermissionGate.ensure(
    context,
    permission: camera ? AppPermission.camera : AppPermission.photos,
    title: camera ? s.dispatchCameraAccessTitle : s.dispatchPhotoAccessTitle,
    rationale: video
        ? (camera
              ? s.dispatchCameraAccessVideoRationale
              : s.dispatchGalleryAccessVideoRationale)
        : (camera
              ? s.dispatchCameraAccessPhotoRationale
              : s.dispatchGalleryAccessPhotoRationale),
  );
  if (!granted || !context.mounted) return null;
  final up = _proofUploader();
  return video ? up.pickVideo(source: source) : up.pick(source: source);
}

// ---------- directions ------------------------------------------

/// The walking route and the maps hand-off, shared by the card's map
/// pane and the window.
mixin _Directions<T extends StatefulWidget> on State<T> {
  final _mapCtl = BrgyMapController();
  LatLng? _me;
  double? _meAccuracy;
  List<LatLng> _route = const [];
  double? _routeMetres;
  double? _routeSeconds;
  bool _routing = false;
  String? _routeNote;

  /// Where the complaint is, once loaded.
  LatLng? get _casePoint;

  String? get _routeLine {
    final metres = _routeMetres, seconds = _routeSeconds;
    if (metres == null || seconds == null) return null;
    return context.ts.dispatchRouteSummary(
      metres < 950
          ? '${(metres / 10).round() * 10} m'
          : '${(metres / 1000).toStringAsFixed(1)} km',
      (seconds / 60).ceil().clamp(1, 999),
    );
  }

  /// Under the card's map: the walking route on request, and a hand-off
  /// to the phone's own maps app for turn-by-turn directions.
  Widget _directions() {
    final to = _casePoint;
    if (to == null) return const SizedBox.shrink();
    final s = context.ts;
    final navy = context.colors.navy;
    final small = TextStyle(
      fontFamily: 'Urbanist',
      fontSize: 12.5,
      color: navy,
    );
    final line = _routeLine;
    return Column(
      children: [
        const SizedBox(height: 10),
        if (line != null)
          Text(
            line,
            style: small.copyWith(fontWeight: FontWeight.w700, fontSize: 14),
          )
        else if (_routing)
          Text(s.dispatchFindingYou, style: small)
        else if (_routeNote != null)
          Text(_routeNote!, style: small, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Pill(
              label: s.dispatchGetDirections,
              width: 150,
              fontSize: 13,
              colour: kFigmaOrange,
              onTap: _routing ? null : () => _getRoute(to),
            ),
            const SizedBox(width: 10),
            _Pill(
              label: s.dispatchOpenMaps,
              width: 150,
              fontSize: 13,
              colour: navy,
              onTap: () => _openMaps(to),
            ),
          ],
        ),
        if (_route.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            s.dispatchRouteSource,
            style: small.copyWith(fontSize: 10.5, color: context.colors.muted),
          ),
        ],
      ],
    );
  }

  /// One location fix (a key moment: it also refreshes the tanod's
  /// position for dispatch), then the walking route from OpenStreetMap's
  /// free FOSSGIS router. Nothing runs until the tanod asks.
  Future<void> _getRoute(LatLng to) async {
    final s = context.ts;
    setState(() {
      _routing = true;
      _routeNote = null;
    });
    try {
      if (!kDemo) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever ||
            !await Geolocator.isLocationServiceEnabled()) {
          if (mounted) setState(() => _routeNote = s.dispatchLocationNeeded);
          return;
        }
      }
      final pos = kDemo
          ? demoPosition(to)
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            ).timeout(const Duration(seconds: 15));
      unawaited(DutyController.instance.keyMoment());
      final me = LatLng(pos.latitude, pos.longitude);

      // A fix far outside the barangay (a phone that has not found
      // itself yet, an emulator's default spot) is no start for a walk:
      // routing and fitting the map to a route across the sea froze the
      // app. Say so instead.
      if (Geolocator.distanceBetween(
            me.latitude,
            me.longitude,
            to.latitude,
            to.longitude,
          ) >
          15000) {
        if (mounted) setState(() => _routeNote = s.dispatchTooFar);
        return;
      }
      if (mounted) {
        setState(() {
          _me = me;
          _meAccuracy = pos.accuracy;
        });
      }

      final uri = Uri.parse(
        'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
        '${me.longitude},${me.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'SmartSumbong/1.0 (Barangay 183 tanod app; dispatch directions)',
            },
          )
          .timeout(const Duration(seconds: 12));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final routes = body['routes'] as List?;
      if (res.statusCode != 200 || routes == null || routes.isEmpty) {
        throw const FormatException('no route');
      }
      final r = routes.first as Map<String, dynamic>;
      final coords = ((r['geometry'] as Map)['coordinates'] as List)
          .map(
            (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _route = coords;
        _routeMetres = (r['distance'] as num?)?.toDouble();
        _routeSeconds = (r['duration'] as num?)?.toDouble();
      });
      _mapCtl.fit([...coords, to, me], padding: 40);
    } catch (_) {
      if (mounted) {
        setState(() {
          _route = const [];
          _routeMetres = null;
          _routeSeconds = null;
          _routeNote = s.dispatchRouteFailed;
        });
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  /// Turn-by-turn in the phone's maps app (Google Maps where installed).
  Future<void> _openMaps(LatLng to) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1'
      '&destination=${to.latitude},${to.longitude}&travelmode=walking',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

// ---------- the window ------------------------------------------

typedef _Media = ({String url, bool isVideo});

/// One row of the thread.
class _Post {
  _Post({
    required this.kind,
    required this.at,
    this.step,
    this.body,
    this.mine = false,
    this.media = const [],
  });

  /// 'note', 'step', 'instructions', 'asked' or 'answered'.
  final String kind;
  final DateTime at;
  final String? step;
  final String? body;
  final bool mine;
  final List<_Media> media;
}

class DispatchWindow extends StatefulWidget {
  const DispatchWindow({super.key, required this.ticket, this.startOnTheWay = false});

  final Ticket ticket;

  /// From Dispatch accepted's I'm on the way: mark the step and open
  /// Navigate as soon as the case has loaded.
  final bool startOnTheWay;

  @override
  State<DispatchWindow> createState() => _DispatchWindowState();
}

class _DispatchWindowState extends State<DispatchWindow>
    with _Directions<DispatchWindow> {
  Map<String, dynamic>? _report;
  List<_Media> _evidence = const [];
  Map<String, dynamic>? _detailRequest;

  /// The complaint's own status (0073: a resolved dispatch waits for the
  /// admin's approval) and this tanod's escalation request, if one waits.
  String? _reportStatus;
  Map<String, dynamic>? _escalation;
  List<_Post> _posts = const [];
  String? _step;
  String _state = 'accepted';
  bool _loading = true;
  bool _sending = false;
  bool _stepping = false;
  bool _changed = false;
  bool _caseOpen = false;
  String? _error;

  bool _navStarting = false;

  final _text = TextEditingController();
  final _pics = <File>[];
  final _scroll = ScrollController();
  RealtimeChannel? _live;
  Timer? _liveDebounce;

  String get _dispatchId => widget.ticket.dispatchId;
  bool get _open => _state == 'accepted';

  @override
  LatLng? get _casePoint {
    final lat = (_report?['latitude'] as num?)?.toDouble();
    final lon = (_report?['longitude'] as num?)?.toDouble();
    return lat == null || lon == null ? null : LatLng(lat, lon);
  }

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (mounted && widget.startOnTheWay) _onTheWay();
    });
    _listen();
    TanodOutbox.instance.addListener(_outboxChanged);
    unawaited(TanodOutbox.instance.flush());
  }

  void _outboxChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_load());
  }

  @override
  void dispose() {
    TanodOutbox.instance.removeListener(_outboxChanged);
    _liveDebounce?.cancel();
    final ch = _live;
    if (ch != null) unawaited(Supabase.instance.client.removeChannel(ch));
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// New thread rows, a reroute or a closed dispatch, and the resident's
  /// reply to a details request, as they happen.
  void _listen() {
    void kick(_) {
      _liveDebounce?.cancel();
      _liveDebounce = Timer(const Duration(milliseconds: 300), _load);
    }

    _live = Supabase.instance.client.channel('dispatch-window-$_dispatchId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'dispatch_updates',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'dispatch_id',
          value: _dispatchId,
        ),
        callback: kick,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'dispatches',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: _dispatchId,
        ),
        callback: kick,
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'detail_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'report_id',
          value: widget.ticket.reportId,
        ),
        callback: kick,
      )
      ..subscribe();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final me = client.auth.currentUser?.id;
      Future<Map<String, dynamic>?> detailQ() async {
        try {
          return await client
              .from('detail_requests')
              .select('id, message, requested_at, response, responded_at')
              .eq('report_id', widget.ticket.reportId)
              .order('requested_at', ascending: false)
              .limit(1)
              .maybeSingle();
        } catch (_) {
          return null;
        }
      }

      final got = await Future.wait<Object?>([
        client
            .from('reports')
            .select(
              'tracking_id, subject, description, created_at, '
              'latitude, longitude, location_label, status',
            )
            .eq('id', widget.ticket.reportId)
            .single(),
        client
            .from('report_media')
            .select('media_url, mime_type')
            .eq('report_id', widget.ticket.reportId),
        client
            .from('dispatches')
            .select('state, step')
            .eq('id', _dispatchId)
            .single(),
        client
            .from('dispatch_updates')
            .select('id, author_id, kind, step, body, created_at')
            .eq('dispatch_id', _dispatchId)
            .order('created_at'),
        client
            .from('dispatch_media')
            .select('update_id, media_url, mime_type')
            .eq('dispatch_id', _dispatchId)
            .not('update_id', 'is', null),
        detailQ(),
        client
            .from('escalation_requests')
            .select('id, reason, status, decision_note, created_at')
            .eq('dispatch_id', _dispatchId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
      ], eagerError: true);

      final media = <String, List<_Media>>{};
      for (final m in got[4] as List<Map<String, dynamic>>) {
        (media[m['update_id'] as String] ??= []).add((
          url: m['media_url'] as String,
          isVideo: isVideoMime(m['mime_type'] as String?),
        ));
      }
      final detail = got[5] as Map<String, dynamic>?;
      final instructions = widget.ticket.instructions?.trim() ?? '';

      final posts = <_Post>[
        if (instructions.isNotEmpty)
          _Post(
            kind: 'instructions',
            at: widget.ticket.assignedAt ?? DateTime.now(),
            body: instructions,
          ),
        for (final u in got[3] as List<Map<String, dynamic>>)
          _Post(
            kind: u['kind'] as String,
            step: u['step'] as String?,
            body: u['body'] as String?,
            at: DateTime.parse(u['created_at'] as String),
            mine: u['author_id'] == me,
            media: media[u['id'] as String] ?? const [],
          ),
        if (detail != null) ...[
          _Post(
            kind: 'asked',
            at: DateTime.parse(detail['requested_at'] as String),
            body: detail['message'] as String?,
          ),
          if (detail['responded_at'] != null)
            _Post(
              kind: 'answered',
              at: DateTime.parse(detail['responded_at'] as String),
              body: detail['response'] as String?,
            ),
        ],
      ]..sort((a, b) => a.at.compareTo(b.at));

      final d = got[2] as Map<String, dynamic>;
      if (!mounted) return;
      final grew = posts.length > _posts.length;
      setState(() {
        _report = got[0] as Map<String, dynamic>;
        _evidence = [
          for (final m in got[1] as List<Map<String, dynamic>>)
            (
              url: m['media_url'] as String,
              isVideo: isVideoMime(m['mime_type'] as String?),
            ),
        ];
        _detailRequest = detail;
        _reportStatus = (got[0] as Map<String, dynamic>)['status'] as String?;
        _escalation = got[6] as Map<String, dynamic>?;
        _state = d['state'] as String? ?? 'accepted';
        _step = d['step'] as String?;
        _posts = posts;
        _loading = false;
      });
      if (grew) _toBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  // ---------- actions -------------------------------------------

  Future<void> _send() async {
    if (_sending) return;
    final text = _text.text.trim();
    if (text.isEmpty && _pics.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final up = _proofUploader();
      final rows = <Map<String, dynamic>>[];
      for (final f in _pics) {
        rows.add((await up.upload(f, kind: MediaKind.fieldProof)).toJson());
      }
      await Supabase.instance.client.rpc(
        'post_dispatch_update',
        params: {'p_dispatch': _dispatchId, 'p_body': text, 'p_media': rows},
      );
      _changed = true;
      _text.clear();
      _pics.clear();
      await _load();
    } catch (e) {
      if (Outbox.isNetworkError(e)) {
        // No signal: kept on the phone, sent by itself when it returns.
        await TanodOutbox.instance.enqueue(
          kind: 'update',
          dispatchId: _dispatchId,
          body: text,
          photos: [..._pics],
        );
        _text.clear();
        _pics.clear();
        _savedOffline();
      } else if (mounted) {
        setState(() => _error = e is MediaUploadException
            ? context.ts.dispatchUpdateUploadFailed(e.message)
            : context.ts.windowSendFailed);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _savedOffline() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(context.ts.outboxSaved)));
  }

  Future<void> _addPic() async {
    if (_pics.length >= 3) return;
    try {
      final f = await _pickProof(context, video: false);
      if (f != null && mounted) setState(() => _pics.add(f));
    } catch (_) {
      if (mounted) setState(() => _error = context.ts.dispatchMediaOpenFailed);
    }
  }

  // ---------- navigation ----------------------------------------

  /// One fix and the walking route with its turns, then the navigation
  /// page (dispatch_nav.dart). Starting to walk is being on the way, so
  /// that step is set too. On arrival, the tanod is asked whether to
  /// mark it.
  Future<void> _navigate() async {
    final to = _casePoint;
    if (to == null || _navStarting) return;
    final s = context.ts;
    setState(() {
      _navStarting = true;
      _error = null;
    });
    NavRoute route;
    Position pos;
    try {
      if (!kDemo) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever ||
            !await Geolocator.isLocationServiceEnabled()) {
          if (mounted) setState(() => _error = s.dispatchLocationNeeded);
          return;
        }
      }
      pos = kDemo
          ? demoPosition(to)
          : await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(
                accuracy: LocationAccuracy.high,
              ),
            ).timeout(const Duration(seconds: 15));
      if (Geolocator.distanceBetween(
            pos.latitude,
            pos.longitude,
            to.latitude,
            to.longitude,
          ) >
          15000) {
        if (mounted) setState(() => _error = s.dispatchTooFar);
        return;
      }
      route = await fetchNavRoute(LatLng(pos.latitude, pos.longitude), to);
    } catch (_) {
      if (mounted) setState(() => _error = s.navStartFailed);
      return;
    } finally {
      if (mounted) setState(() => _navStarting = false);
    }
    if (!mounted) return;

    // A dispatch step is one of the few moments a location is sent.
    unawaited(DutyController.instance.keyMoment());
    if (_step == null && _open) unawaited(_setStep('on_the_way'));

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _NavScreen(
          to: to,
          route: route,
          start: pos,
          step: _stepIndex,
          title: '${widget.ticket.subject} · ${widget.ticket.trackingId}',
        ),
      ),
    );
    if (!mounted) return;
    // I've arrived on the Navigate sheet (offered only once the GPS has
    // the tanod at the report) marks the step and lands on the job page
    // in on-site mode.
    if (result == 'arrived' && _open && _step != 'arrived') {
      await _setStep('arrived');
    } else if (result == 'job' || result == null) {
      setState(() {});
    }
  }

  /// 0 accepted, 1 on the way, 2 arrived, 3 resolved.
  int get _stepIndex => _state == 'resolved'
      ? 3
      : switch (_step) {
          'arrived' => 2,
          'on_the_way' => 1,
          _ => 0,
        };

  /// I'm on the way: the step, then straight into Navigate.
  Future<void> _onTheWay() async {
    if (_step == null) await _setStep('on_the_way');
    if (mounted) await _navigate();
  }

  Future<void> _setStep(String step) async {
    if (_stepping) return;
    setState(() {
      _stepping = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'set_dispatch_step',
        params: {'p_dispatch': _dispatchId, 'p_step': step},
      );
      // A dispatch step is one of the few moments a location is sent.
      unawaited(DutyController.instance.keyMoment());
      _changed = true;
      await _load();
    } catch (e) {
      if (Outbox.isNetworkError(e)) {
        await TanodOutbox.instance.enqueue(
            kind: 'step', dispatchId: _dispatchId, step: step);
        if (mounted) setState(() => _step = step);
        _savedOffline();
      } else if (mounted) {
        setState(() => _error = context.ts.windowStepFailed);
      }
    } finally {
      if (mounted) setState(() => _stepping = false);
    }
  }

  /// Use case "Manage Escalation Request": the tanod asks the barangay to
  /// take this beyond its level (0073). The admin decides.
  Future<void> _requestEscalation() async {
    final s = context.ts;
    final reason = TextEditingController();
    String? office;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: ctx.colors.bg,
          title: Text(s.escTitle,
              style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  color: ctx.colors.navy)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.escBody,
                    style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 13.5,
                        color: ctx.colors.navy)),
                const SizedBox(height: 12),
                TextField(
                  controller: reason,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: s.escReason,
                    // A box, not the theme's pill (phone run, 7 Oct 2026).
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: ctx.d.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: ctx.d.accent, width: 2)),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: office,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.escOffice,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: ctx.d.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: ctx.d.accent, width: 2)),
                  ),
                  items: [
                    // Rose (7 Oct 2026): the certificate's five reasons only.
                    for (final o in const [
                      ('Lupong Tagapamayapa', 'Katarungang Pambarangay'),
                      ('Philippine National Police', 'PNP — a criminal offense'),
                      ('VAWC Desk', 'VAWC — violence against women and children'),
                      ('Office of the Ombudsman', 'Grievance against a public officer'),
                      ('Regular Courts', 'Outside the barangay'),
                    ])
                      DropdownMenuItem(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setD(() => office = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.dispatchCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: _red,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(s.escSend),
            ),
          ],
        ),
      ),
    );
    final text = reason.text.trim();
    reason.dispose();
    if (go != true || !mounted) return;
    if (text.isEmpty) {
      setState(() => _error = s.escReasonRequired);
      return;
    }
    try {
      await Supabase.instance.client.rpc('request_escalation', params: {
        'p_dispatch': _dispatchId,
        'p_reason': text,
        'p_office': office,
      });
      _changed = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.escSent)));
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _error = e.message.contains('already waiting')
            ? s.escAlreadyWaiting
            : s.escFailed);
      }
    } catch (_) {
      if (mounted) setState(() => _error = s.escFailed);
    }
  }

  Future<void> _resolve() async {
    final done = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _ResolveSheet(ticket: widget.ticket)),
    );
    if (done == null || done == 'false' || !mounted) return;
    _changed = true;
    if (done == 'queued') {
      _savedOffline();
      return;
    }
    await showDDialog(
      context,
      title: context.ts.windowResolveSent(widget.ticket.trackingId),
      body: context.ts.windowAwaitingApproval,
      primary: context.ts.dispatchBack,
      icon: Icons.task_alt_rounded,
      iconColor: DColors.greenVivid,
    );
    if (mounted) await _load();
  }

  /// Asks the resident for more details (0065's
  /// request_additional_details). The resident is notified and answers
  /// from their app; the question and the reply show in the thread.
  Future<void> _requestDetails() async {
    final s = context.ts;
    final message = await showDialog<String>(
      context: context,
      builder: (_) => const _DetailsRequestDialog(),
    );
    if (message == null || message.trim().isEmpty || !mounted) return;
    try {
      await Supabase.instance.client.rpc(
        'request_additional_details',
        params: {'p_report': widget.ticket.reportId, 'p_message': message},
      );
      if (!mounted) return;
      _changed = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.dispatchDetailsSent)));
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message.contains('already a request')
                ? s.dispatchDetailsAlreadyOpen
                : s.dispatchDetailsFailed,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(s.dispatchDetailsFailed)));
    }
  }

  void _openMedia(_Media m) {
    if (m.isVideo) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: m.url)));
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: cloudinarySized(m.url, width: 1400),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- layout --------------------------------------------

  // Branch D (Ace's "On the job"): the map with the route and Navigate on
  // top while the tanod is on the way; once arrived the page turns to the
  // dispatch (ON SITE) — the map folds into a small "Navigate again" card
  // for a return visit. The vivid steps, one big next-step button, the
  // escalation link, the case folded, the thread, the composer pinned.
  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final onsite = _stepIndex >= 2;
    // One fixed height, clipped. Navigation is its own page
    // (dispatch_nav.dart) with its own full-size map: MapLibre's view did
    // not survive being resized in place.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: d.bg,
        body: Column(
          children: [
            if (!onsite)
              SizedBox(
                height: 230,
                child: ClipRect(child: _mapArea()),
              )
            else
              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Align(alignment: Alignment.centerLeft, child: DBack(onTap: () => Navigator.of(context).pop(_changed))),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                        children: [
                          _topBar(),
                          const SizedBox(height: 16),
                          _stepper(),
                          const SizedBox(height: 16),
                          if (_open) _stepActions(),
                          if (kTanodNavAndChat && _open && onsite && _casePoint != null) ...[
                            const SizedBox(height: 12),
                            _againCard(),
                          ],
                          const SizedBox(height: 14),
                          _caseCard(),
                          const SizedBox(height: 18),
                          Text(context.tr('UPDATES', 'MGA UPDATE'), style: DType.label(d.muted)),
                          const SizedBox(height: 8),
                          ..._thread(),
                        ],
                      ),
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
              ),
            if (!kTanodNavAndChat && _open)
              const SafeArea(top: false, child: SizedBox(height: 8))
            else
              _open ? _composer() : _closedBar(),
          ],
        ),
      ),
    );
  }

  Widget _mapArea() {
    final d = context.d;
    final to = _casePoint;
    final line = _routeLine;
    return Stack(
      children: [
        Positioned.fill(
          child: to == null
              ? Container(
                  color: d.field,
                  alignment: Alignment.center,
                  child: Text(context.ts.dispatchNoLocation, style: DType.body(d.muted, size: 12.5)),
                )
              : BrgyMap(
                  controller: _mapCtl,
                  initialCenter: to,
                  initialZoom: 16.5,
                  pins: [BrgyMapPin(id: 'case', point: to)],
                  route: _route,
                  accuracyCentre: _me,
                  accuracyMetres: _me == null ? null : (_meAccuracy ?? 15).clamp(8, 40).toDouble(),
                  attributionBottom: 60,
                ),
        ),
        Positioned(
          left: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: DBack(onImage: true, onTap: () => Navigator.of(context).pop(_changed)),
        ),
        if (to != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (line != null || _routing || _routeNote != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: d.card,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .18), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Text(line ?? (_routing ? context.ts.dispatchFindingYou : _routeNote!),
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 12.5, w: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
              ],
              if (kMapNavigatePill)
                Row(children: [
                  Expanded(
                    child: _MapPill(
                      icon: Icons.navigation_rounded,
                      label: _navStarting ? context.ts.dispatchFindingYou : context.ts.navNavigate,
                      orange: true,
                      onTap: _navStarting || !_open ? null : _navigate,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _MapPill(icon: Icons.map_outlined, label: context.ts.dispatchOpenMaps, onTap: () => _openMaps(to))),
                ])
              else
                Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(width: 168, child: _MapPill(icon: Icons.map_outlined, label: context.ts.dispatchOpenMaps, onTap: () => _openMaps(to))),
                ),
            ]),
          ),
      ],
    );
  }

  /// The ON THE JOB / ON SITE / DONE label, the subject, ticket and street.
  Widget _topBar() {
    final d = context.d;
    final near = _report?['location_label'] as String?;
    final i = _stepIndex;
    final green = d.dark ? const Color(0xFF5FD68A) : DColors.green;
    final label = i >= 3
        ? context.tr('DONE', 'TAPOS NA')
        : i >= 2
            ? context.tr('ON SITE', 'NASA LUGAR')
            : context.tr('ON THE JOB', 'NASA TRABAHO');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, color: green, boxShadow: [BoxShadow(color: green.withValues(alpha: .25), spreadRadius: 4)]),
        ),
        const SizedBox(width: 9),
        Text(label, style: DType.label(green)),
        const Spacer(),
        // 0072: the admin's target date has passed.
        if (_open && widget.ticket.dueAt != null && widget.ticket.dueAt!.isBefore(DateTime.now()))
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: DColors.red, borderRadius: BorderRadius.circular(99)),
            child: Text(context.ts.ticketOverdue, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white)),
          ),
      ]),
      const SizedBox(height: 6),
      Text(widget.ticket.subject, style: DType.body(d.ink, size: 22, w: FontWeight.w800).copyWith(height: 1.2)),
      const SizedBox(height: 3),
      Text.rich(TextSpan(children: [
        TextSpan(text: widget.ticket.trackingId, style: DType.mono(d.link, size: 13)),
        if (near != null && near.isNotEmpty) TextSpan(text: '  ·  ${context.ts.dispatchNear(near)}', style: DType.body(d.muted, size: 13)),
      ])),
    ]);
  }

  /// Accepted → On the way → Arrived → Resolved, in their vivid colours.
  Widget _stepper() {
    final s = context.ts;
    final waitingApproval = _state == 'resolved' && _reportStatus != null && _reportStatus != 'resolved' && _reportStatus != 'closed';
    return DSteps(
      step: _stepIndex,
      labels: [s.windowStepAccepted, s.windowStepOnTheWay, s.windowStepArrived, s.windowStepResolved],
      captions: [null, null, null, if (waitingApproval) context.tr('Awaiting approval', 'Hinihintay ang pag-apruba')],
    );
  }

  /// One big next-step button and Resolve (allowed at any step), then the
  /// escalation link. On the way, the button resumes Navigate; I've
  /// arrived comes from the Navigate sheet once the GPS sees arrival, and
  /// a small "already there" link covers a phone without a fix.
  Widget _stepActions() {
    final s = context.ts;
    final d = context.d;
    final i = _stepIndex;
    final esc = _escalation;
    final escNote = esc == null
        ? null
        : switch (esc['status']) {
            'pending' => s.escWaiting,
            'denied' => s.escDenied((esc['decision_note'] as String?) ?? ''),
            _ => null,
          };
    Widget main;
    final arrivedLink = TextButton(
      onPressed: _stepping ? null : () => _setStep('arrived'),
      child: Text(context.tr('Already there? Mark I’ve arrived', 'Nandito ka na? Markahan ang Nandito na ako'),
          style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 13, color: d.link)),
    );
    if (i == 0 && !kResolveBeforeArrival) {
      main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DButton(s.windowActionOnTheWay, busy: _stepping || _navStarting, onTap: _onTheWay, expand: true, height: 56, radius: 14, fontSize: 17),
        arrivedLink,
      ]);
    } else if (i == 1 && !kResolveBeforeArrival) {
      main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        DButton(context.tr('Navigate', 'Mag-navigate'),
            icon: Icons.navigation_rounded, busy: _navStarting, onTap: _casePoint == null ? null : _navigate, expand: true, height: 56, radius: 14, fontSize: 17),
        arrivedLink,
      ]);
    } else if (i == 0) {
      main = Row(children: [
        Expanded(flex: 27, child: DButton(s.windowActionOnTheWay, busy: _stepping || _navStarting, onTap: _onTheWay, expand: true, height: 52, radius: 14, fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(flex: 20, child: DButton(s.windowResolve, kind: DButtonKind.greenLine, onTap: _resolve, expand: true, height: 52, radius: 14, fontSize: 16)),
      ]);
    } else if (i == 1) {
      main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            flex: 27,
            child: DButton(context.tr('Navigate', 'Mag-navigate'),
                icon: Icons.navigation_rounded, busy: _navStarting, onTap: _casePoint == null ? null : _navigate, expand: true, height: 52, radius: 14, fontSize: 16),
          ),
          const SizedBox(width: 8),
          Expanded(flex: 20, child: DButton(s.windowResolve, kind: DButtonKind.greenLine, onTap: _resolve, expand: true, height: 52, radius: 14, fontSize: 16)),
        ]),
        TextButton(
          onPressed: _stepping ? null : () => _setStep('arrived'),
          child: Text(context.tr('Already there? Mark I’ve arrived', 'Nandito ka na? Markahan ang Nandito na ako'),
              style: TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w700, fontSize: 13, color: d.link)),
        ),
      ]);
    } else {
      main = DButton(context.tr('Resolve · add proof', 'Iresolba · maglagay ng patunay'), onTap: _resolve, expand: true, height: 58, radius: 14, fontSize: 17);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      main,
      if (escNote != null)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(escNote,
              textAlign: TextAlign.center,
              style: DType.body(esc?['status'] == 'denied' ? DColors.red : d.ink2, size: 12.5, w: FontWeight.w700)),
        ),
      if (esc == null || esc['status'] != 'pending')
        Center(
          child: TextButton.icon(
            onPressed: _requestEscalation,
            icon: const Icon(Icons.north_east_rounded, size: 17),
            label: Text(s.escButton, style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 14)),
            style: TextButton.styleFrom(foregroundColor: d.dark ? const Color(0xFFFF8A8A) : DColors.red),
          ),
        ),
    ]);
  }

  /// On site: the place, and Navigate again for a return visit.
  Widget _againCard() {
    final d = context.d;
    final near = _report?['location_label'] as String?;
    return DSheet(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(shape: BoxShape.circle, color: DColors.orange.withValues(alpha: .16)),
          child: const Icon(Icons.place_outlined, color: Color(0xFFB26A00), size: 21),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(near != null && near.isNotEmpty ? context.ts.dispatchNear(near) : widget.ticket.trackingId,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: DType.body(d.ink, size: 14, w: FontWeight.w800)),
            Text(context.tr('Coming back another day? Navigate again.', 'Babalik sa ibang araw? Mag-navigate ulit.'),
                style: DType.body(d.muted, size: 11.5)),
          ]),
        ),
        DButton(context.tr('Navigate again', 'Mag-navigate ulit'), kind: DButtonKind.line, small: true, busy: _navStarting, onTap: _navigate),
      ]),
    );
  }

  /// The complaint itself, folded until asked for.
  Widget _caseCard() {
    final s = context.ts;
    final c = context.colors;
    final waiting =
        _detailRequest != null && _detailRequest!['responded_at'] == null;
    return Container(
      decoration: BoxDecoration(
        color: context.d.card,
        border: Border.all(color: context.d.line, width: 1.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _caseOpen = !_caseOpen),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.assignment_outlined, color: c.navy, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.windowCase,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: c.navy,
                      ),
                    ),
                  ),
                  Icon(
                    _caseOpen ? Icons.expand_less : Icons.expand_more,
                    color: c.navy,
                  ),
                ],
              ),
            ),
          ),
          if (_caseOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Field(
                    label: s.dispatchComplainantLabel,
                    value: s.reportsFilerAnonymous,
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: s.reportsDescriptionLabel,
                    value: '“${widget.ticket.description}”',
                  ),
                  const SizedBox(height: 12),
                  _Field(
                    label: s.reportsDeadlineLabel,
                    value: _deadlineOf(widget.ticket.dueAt),
                  ),
                  if (_evidence.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _thumbs(_evidence, 64),
                  ],
                  if (_open && !waiting)
                    _Link(
                      icon: Icons.help_outline,
                      label: s.dispatchRequestDetails,
                      onTap: _requestDetails,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _thumbs(List<_Media> items, double size) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (final m in items)
        GestureDetector(
          onTap: () => _openMedia(m),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: m.isVideo
                ? Container(
                    width: size,
                    height: size,
                    color: Colors.black87,
                    child: const Icon(
                      Icons.play_circle_fill,
                      color: Colors.white70,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: cloudinarySized(m.url, width: 300),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => Container(color: context.colors.bg),
                    errorWidget: (_, _, _) => Container(
                      width: size,
                      height: size,
                      color: context.colors.bg,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: context.colors.muted,
                      ),
                    ),
                  ),
          ),
        ),
    ],
  );

  List<Widget> _thread() {
    final waiting = TanodOutbox.instance.forDispatch(_dispatchId);
    if (waiting.isNotEmpty) {
      return [..._threadPosts(), for (final w in waiting) _waitingBubble(w)];
    }
    return _threadPosts();
  }

  /// Something the phone is still holding for this dispatch (0073).
  Widget _waitingBubble(TanodOutboxItem w) {
    final s = context.ts;
    final c = context.colors;
    final label = switch (w.kind) {
      'step' => w.step == 'arrived' ? s.windowStepArrived : s.windowStepOnTheWay,
      'resolve' => s.windowResolve,
      _ => (w.body ?? '').isEmpty ? s.outboxPhotos(w.photos.length) : w.body!,
    };
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        decoration: BoxDecoration(
          border: Border.all(color: c.navy.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontFamily: 'Urbanist', fontSize: 14, color: c.navy)),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(w.error == null ? Icons.schedule : Icons.error_outline,
                    size: 14, color: w.error == null ? c.muted : _red),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    w.error == null ? s.outboxWaiting : s.outboxRefused(w.error!),
                    style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 11.5,
                        color: w.error == null ? c.muted : _red),
                  ),
                ),
                if (w.error != null)
                  TextButton(
                    onPressed: () => TanodOutbox.instance.discard(w.id),
                    child: Text(s.outboxDiscard),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _threadPosts() {
    final s = context.ts;
    final c = context.colors;
    if (_posts.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          child: Text(
            s.windowEmpty,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontSize: 13,
              color: c.muted,
            ),
          ),
        ),
      ];
    }
    return [
      for (final p in _posts)
        switch (p.kind) {
          'step' => _systemLine(
            p.step == 'arrived' ? s.windowStepArrived : s.windowStepOnTheWay,
            p.at,
            Icons.flag_outlined,
          ),
          'asked' => _bubble(p, who: s.windowYouAsked, mine: true),
          'answered' => _bubble(
            p,
            who: s.dispatchDetailsReply,
            mine: false,
            fallback: s.dispatchDetailsMediaOnly,
          ),
          'instructions' => _bubble(p, who: s.windowInstructions, mine: false),
          _ => _bubble(
            p,
            who: p.mine ? s.windowYou : s.windowBarangay,
            mine: p.mine,
          ),
        },
    ];
  }

  // Branch D: steps as a quiet centred line; the tanod's posts in the
  // role colour on the right; the barangay's white on the left, its
  // instructions in the amber of the dispatch order's directives.
  Widget _systemLine(String text, DateTime at, IconData icon) {
    final d = context.d;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: d.muted),
          const SizedBox(width: 6),
          Text('$text · ${_time(at)}', style: DType.body(d.muted, size: 12, w: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _bubble(
    _Post p, {
    required String who,
    required bool mine,
    String? fallback,
  }) {
    final d = context.d;
    final instr = !mine && who == context.ts.windowInstructions;
    final fg = mine ? Colors.white : d.ink;
    final body = (p.body ?? '').trim();
    final bg = mine
        ? (d.tanod ? (d.dark ? const Color(0xFF2E343C) : const Color(0xFF14181D)) : DColors.brandNavy)
        : instr
            ? Color.alphaBlend(DColors.orange.withValues(alpha: .12), d.card)
            : d.card;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: BoxDecoration(
          color: bg,
          border: mine ? null : Border.all(color: instr ? DColors.orange.withValues(alpha: .4) : d.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who,
              style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: mine ? Colors.white.withValues(alpha: .8) : const Color(0xFFE07400))),
          if (body.isNotEmpty || fallback != null) ...[
            const SizedBox(height: 2),
            Text(body.isNotEmpty ? body : fallback!, style: DType.body(fg, size: instr ? 15.5 : 14.5, w: instr ? FontWeight.w700 : FontWeight.w500)),
          ],
          if (p.media.isNotEmpty) ...[
            const SizedBox(height: 6),
            _thumbs(p.media, 84),
          ],
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.bottomRight,
            child: Text(_time(p.at), style: DType.body(fg.withValues(alpha: .65), size: 10.5)),
          ),
        ]),
      ),
    );
  }

  Widget _composer() {
    final d = context.d;
    final s = context.ts;
    return Container(
      decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_pics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  for (var i = 0; i < _pics.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(clipBehavior: Clip.none, children: [
                        ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(_pics[i], width: 56, height: 56, fit: BoxFit.cover)),
                        Positioned(
                          top: -6,
                          right: -6,
                          child: GestureDetector(
                            onTap: _sending ? null : () => setState(() => _pics.removeAt(i)),
                            child: const CircleAvatar(radius: 10, backgroundColor: Color(0x99000000), child: Icon(Icons.close, size: 12, color: Colors.white)),
                          ),
                        ),
                      ]),
                    ),
                ]),
              ),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Material(
                color: d.field,
                shape: CircleBorder(side: BorderSide(color: d.line)),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sending || _pics.length >= 3 ? null : _addPic,
                  child: SizedBox(width: 44, height: 44, child: Icon(Icons.photo_camera_outlined, color: d.link)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _text,
                  enabled: !_sending,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  style: DType.body(d.ink, size: 14.5),
                  decoration: InputDecoration(
                    hintText: s.windowComposerHint,
                    hintStyle: DType.body(d.muted, size: 14),
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: d.field,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide(color: d.line)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: BorderSide(color: d.line)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(23), borderSide: const BorderSide(color: DColors.orange, width: 1.6)),
                  ),
                  onChanged: (_) => setState(() => _error = null),
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: DColors.orange,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _sending ? null : _send,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: _sending
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF141B34)))
                          : const Icon(Icons.send_rounded, color: Color(0xFF141B34), size: 21),
                    ),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _closedBar() => SafeArea(
    top: false,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      color: context.colors.field,
      child: Text(
        _state == 'resolved' && _reportStatus != 'resolved'
            ? context.ts.windowAwaitingApproval
            : context.ts.windowClosed,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Urbanist',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: context.colors.navy,
        ),
      ),
    ),
  );

  // ---------- dates ---------------------------------------------

  /// The deadline, with Overdue once the admin's date has passed.
  String _deadlineOf(DateTime? d) => d != null && d.isBefore(DateTime.now())
      ? '${_dateOf(d)} · ${context.ts.ticketOverdue}'
      : _dateOf(d);

  String _dateOf(DateTime? d) {
    if (d == null) return context.ts.reportsDeadlineNotSet;
    final l = d.toLocal();
    return '${context.ts.monthFull(l.month)} ${l.day}, ${l.year}';
  }

  String _time(DateTime at) {
    final l = at.toLocal();
    final now = DateTime.now();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final hm =
        '$h:${l.minute.toString().padLeft(2, '0')} '
        '${l.hour < 12 ? 'AM' : 'PM'}';
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return hm;
    }
    return '${context.ts.monthFull(l.month).substring(0, 3)} ${l.day}, $hm';
  }
}

// ---------- resolve ---------------------------------------------

/// The final field report: a note and optional proof, then
/// submit_field_report() — which closes the dispatch and tells the
/// resident the case is resolved. The card's old Submit Update form,
/// as a sheet.
class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet({required this.ticket});

  final Ticket ticket;

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  final _update = TextEditingController();
  final _photos = <File>[];

  // Optional field-proof video. One only — a tanod filing from the field
  // has neither the time nor the data budget to shoot more than one
  // short clip.
  File? _video;
  bool _busy = false;
  String? _error;

  /// The proof rows are already saved (then only the report is left).
  bool _mediaSaved = false;

  @override
  void dispose() {
    _update.dispose();
    super.dispose();
  }

  Future<void> _add({required bool video}) async {
    try {
      final f = await _pickProof(context, video: video);
      if (f == null || !mounted) return;
      setState(() {
        if (video) {
          _video = f;
        } else {
          _photos.add(f);
        }
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = context.ts.dispatchMediaOpenFailed);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_update.text.trim().isEmpty) {
      setState(() => _error = context.ts.dispatchUpdateDescribeRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // Photos first, the RPC last. submit_field_report() closes the
      // dispatch and moves the report to resolved; a resolved dispatch
      // is not editable, so if that ran and the upload then failed the
      // case would close with the proof permanently missing.
      if (_photos.isNotEmpty || _video != null) {
        final uploader = _proofUploader();
        final rows = <Map<String, dynamic>>[];
        for (final f in _photos) {
          final up = await uploader.upload(f, kind: MediaKind.fieldProof);
          rows.add({'dispatch_id': widget.ticket.dispatchId, ...up.toJson()});
        }
        if (_video != null) {
          final up = await uploader.uploadVideo(
            _video!,
            kind: MediaKind.fieldProof,
          );
          rows.add({'dispatch_id': widget.ticket.dispatchId, ...up.toJson()});
        }
        await client.from('dispatch_media').insert(rows);
        _mediaSaved = true;
      }

      await client.rpc(
        'submit_field_report',
        params: {
          'p_dispatch': widget.ticket.dispatchId,
          'p_text': _update.text.trim(),
        },
      );
      // A dispatch step is one of the few moments a location is sent.
      unawaited(DutyController.instance.keyMoment());

      if (mounted) Navigator.of(context).pop('sent');
    } catch (e) {
      if (Outbox.isNetworkError(e)) {
        // No signal: the whole resolution waits on the phone. If the proof
        // rows already went in, only the report itself is left to send.
        await TanodOutbox.instance.enqueue(
          kind: 'resolve',
          dispatchId: widget.ticket.dispatchId,
          body: _update.text.trim(),
          photos: _mediaSaved ? const [] : [..._photos],
          video: _mediaSaved ? null : _video,
        );
        if (mounted) Navigator.of(context).pop('queued');
        return;
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is MediaUploadException
            ? context.ts.dispatchUpdateUploadFailed(e.message)
            : context.ts.dispatchUpdateSubmitFailed;
      });
    }
  }

  // Branch D: Resolve is its own screen (Ace, 4 Oct) — back to the job at
  // the top and at the bottom, nothing lost. Photos (optional: a tanod who
  // moved an obstruction has nothing to photograph), one video, the report,
  // then Submit for approval (0073: the admin approves the resolution).
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    final green = DColors.greenVivid;
    Widget label(String t, [String? sub]) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t, style: DType.body(d.ink, size: 15, w: FontWeight.w800)),
            if (sub != null) Text(sub, style: DType.body(d.muted, size: 12)),
          ]),
        );
    // Full width while empty, as on the resident's report form; a tile
    // beside the photos once there are some (phone run, 7 Oct 2026).
    Widget tile({required IconData icon, required String text, required String limit, VoidCallback? onTap, bool wide = false}) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: DottedBox(
            color: d.line,
            child: Container(
              width: wide ? double.infinity : 104,
              height: 104,
              decoration: BoxDecoration(color: d.field, borderRadius: BorderRadius.circular(14)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, color: d.muted, size: 26),
                const SizedBox(height: 4),
                Text(text, textAlign: TextAlign.center, style: DType.body(d.muted, size: 11.5, w: FontWeight.w700)),
                Text(limit, style: DType.body(d.muted, size: 10)),
              ]),
            ),
          ),
        );

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        backgroundColor: d.bg,
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      icon: Icon(Icons.chevron_left_rounded, color: d.ink2, size: 26),
                      label: Text(context.tr('On the job', 'Nasa trabaho'), style: DType.body(d.ink2, size: 14, w: FontWeight.w800)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    ),
                  ),
                  Text(context.tr('RESOLVE', 'IRESOLBA'), style: DType.label(green)),
                  const SizedBox(height: 4),
                  Text(widget.ticket.subject, style: DType.h1(d.ink).copyWith(fontSize: 24)),
                  Text(widget.ticket.trackingId, style: DType.mono(d.muted, size: 13)),
                  const SizedBox(height: 6),
                  Text(s.windowResolveBody, style: DType.body(d.ink2, size: 13.5)),
                  const SizedBox(height: 20),
                  label(s.dispatchPhotoEvidenceLabel, s.dispatchMaxPhotoSize),
                  Wrap(spacing: 10, runSpacing: 10, children: [
                    for (var i = 0; i < _photos.length; i++)
                      Stack(clipBehavior: Clip.none, children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(_photos[i], width: 104, height: 104, fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 5,
                          right: 5,
                          child: GestureDetector(
                            onTap: _busy ? null : () => setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(radius: 12, backgroundColor: Color(0x99000000), child: Icon(Icons.close_rounded, size: 15, color: Colors.white)),
                          ),
                        ),
                      ]),
                    if (_photos.isNotEmpty && _photos.length < 3)
                      tile(icon: Icons.add_a_photo_outlined, text: s.dispatchAttachMedia, limit: '', onTap: _busy ? null : () => _add(video: false)),
                  ]),
                  if (_photos.isEmpty)
                    tile(icon: Icons.add_a_photo_outlined, text: s.dispatchAttachMedia, limit: '', wide: true, onTap: _busy ? null : () => _add(video: false)),
                  const SizedBox(height: 18),
                  label(context.tr('Video', 'Video'), s.dispatchMaxVideoSize),
                  InkWell(
                    onTap: _busy ? null : (_video == null ? () => _add(video: true) : null),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: d.field,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _video != null ? green : d.line, width: 1.6),
                      ),
                      child: Row(children: [
                        Icon(Icons.videocam_outlined, color: _video != null ? green : d.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(_video != null ? s.dispatchVideoAttached : s.dispatchAttachVideo,
                              style: DType.body(_video != null ? d.ink : d.muted, size: 14, w: FontWeight.w700)),
                        ),
                        if (_video != null)
                          IconButton(
                            onPressed: _busy ? null : () => setState(() => _video = null),
                            icon: Icon(Icons.close_rounded, color: d.muted, size: 20),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 18),
                  label(s.dispatchProvideReportLabel, context.tr('What you found and what you did', 'Ano ang nakita at ginawa mo')),
                  TextField(
                    controller: _update,
                    enabled: !_busy,
                    maxLength: 300,
                    minLines: 4,
                    maxLines: 8,
                    onChanged: (_) => setState(() => _error = null),
                    style: DType.body(d.ink, size: 14.5),
                    decoration: InputDecoration(
                      hintText: s.dispatchInputHint,
                      hintStyle: DType.body(d.muted, size: 14),
                      filled: true,
                      fillColor: d.field,
                      contentPadding: const EdgeInsets.all(14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: green, width: 2)),
                    ),
                  ),
                  Text(
                    context.tr('The barangay approves your report before the case closes. No signal? It saves on this phone and sends by itself.',
                        'Inaaprubahan ng barangay ang ulat bago isara ang kaso. Walang signal? Mase-save ito at kusang ipapadala.'),
                    style: DType.body(d.muted, size: 12),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                // Phone run (7 Oct 2026): under the list it scrolled out of
                // sight; here it sits right above the button that caused it.
                if (_error != null) ...[
                  Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
                  const SizedBox(height: 10),
                ],
                // Equal halves, like every other pair in the app ("B..." before).
                Row(children: [
                  Expanded(child: DButton(context.tr('Back', 'Bumalik'), kind: DButtonKind.ghost, expand: true, onTap: _busy ? null : () => Navigator.of(context).pop())),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DButton(context.tr('Submit', 'Ipasa'), kind: DButtonKind.green, expand: true, busy: _busy, onTap: _busy ? null : _submit),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A dashed edge around an empty attach tile.
class DottedBox extends StatelessWidget {
  const DottedBox({super.key, required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(foregroundPainter: _Dash(color), child: child);
}

class _Dash extends CustomPainter {
  _Dash(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(14)));
    for (final m in path.computeMetrics()) {
      for (var t = 0.0; t < m.length; t += 10) {
        canvas.drawPath(m.extractPath(t, t + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_Dash old) => old.color != color;
}


/// Navigate / Open in Maps over the job's map.
class _MapPill extends StatelessWidget {
  const _MapPill({required this.icon, required this.label, required this.onTap, this.orange = false});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool orange;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF141B34);
    return Material(
      color: orange ? DColors.orange : Colors.white,
      borderRadius: BorderRadius.circular(99),
      elevation: 4,
      shadowColor: Colors.black38,
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: onTap,
        child: SizedBox(
          height: 42,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, size: 17, color: ink),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Urbanist', fontWeight: FontWeight.w800, fontSize: 13.5, color: ink)),
            ),
          ]),
        ),
      ),
    );
  }
}
