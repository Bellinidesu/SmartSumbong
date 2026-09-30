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
      final pos = await Geolocator.getCurrentPosition(
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
  const DispatchWindow({super.key, required this.ticket});

  final Ticket ticket;

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
    _load();
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
      pos = await Geolocator.getCurrentPosition(
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

    final arrived = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _NavScreen(to: to, route: route, start: pos),
      ),
    );
    if (arrived != true || !mounted || !_open || _step == 'arrived') return;

    final mark = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.bg,
        title: Text(
          s.navArrive,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w800,
            color: ctx.colors.navy,
          ),
        ),
        content: Text(
          s.navArrivedBody,
          style: TextStyle(fontFamily: 'Urbanist', color: ctx.colors.navy),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.navNotYet),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: kFigmaOrange,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.windowActionArrived),
          ),
        ],
      ),
    );
    if (mark == true) await _setStep('arrived');
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
                    border: const OutlineInputBorder(),
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: office,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.escOffice,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in const [
                      'VAWC Desk',
                      'Philippine National Police',
                      'City Social Welfare Office',
                      'Lupong Tagapamayapa',
                      'City Environment Office',
                      'Bureau of Fire Protection',
                      'City Health Office',
                    ])
                      DropdownMenuItem(value: o, child: Text(o)),
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
    final done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      builder: (_) => _ResolveSheet(ticket: widget.ticket),
    );
    if (done == null || !mounted) return;
    _changed = true;
    if (done == 'queued') {
      _savedOffline();
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.bg,
        title: Text(
          ctx.ts.windowResolveSent(widget.ticket.trackingId),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w800,
            color: ctx.colors.navy,
          ),
        ),
        actions: [
          Center(
            child: _Pill(
              label: ctx.ts.dispatchBack,
              colour: ctx.colors.navy,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    );
    if (mounted) Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // One fixed height, clipped. Navigation is its own page
    // (dispatch_nav.dart) with its own full-size map: MapLibre's view did
    // not survive being resized in place.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: c.bg,
        body: Column(
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.34,
              child: ClipRect(child: _mapArea()),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        children: [
                          _topBar(),
                          const SizedBox(height: 12),
                          _stepper(),
                          const SizedBox(height: 12),
                          if (_open) _stepActions(),
                          const SizedBox(height: 14),
                          _caseCard(),
                          const SizedBox(height: 16),
                          ..._thread(),
                        ],
                      ),
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: _red),
                ),
              ),
            _open ? _composer() : _closedBar(),
          ],
        ),
      ),
    );
  }

  Widget _mapArea() {
    final c = context.colors;
    final to = _casePoint;
    final line = _routeLine;
    return Stack(
      children: [
        Positioned.fill(
          child: to == null
              ? Container(
                  color: c.field,
                  alignment: Alignment.center,
                  child: Text(
                    context.ts.dispatchNoLocation,
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                )
              : BrgyMap(
                  controller: _mapCtl,
                  initialCenter: to,
                  initialZoom: 16.5,
                  pins: [BrgyMapPin(id: 'case', point: to)],
                  route: _route,
                  accuracyCentre: _me,
                  accuracyMetres: _me == null
                      ? null
                      : (_meAccuracy ?? 15).clamp(8, 40).toDouble(),
                  attributionBottom: 52,
                ),
        ),
        Positioned(
          left: 12,
          top: MediaQuery.paddingOf(context).top + 8,
          child: _roundButton(
            Icons.arrow_back,
            () => Navigator.of(context).pop(_changed),
          ),
        ),
        if (to != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (line != null || _routing || _routeNote != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: c.bg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: kFigmaShadow,
                    ),
                    child: Text(
                      line ??
                          (_routing
                              ? context.ts.dispatchFindingYou
                              : _routeNote!),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: c.navy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  children: [
                    Expanded(
                      child: _chip(
                        Icons.navigation,
                        _navStarting
                            ? context.ts.dispatchFindingYou
                            : context.ts.navNavigate,
                        kFigmaOrange,
                        _navStarting || !_open ? null : _navigate,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _chip(
                        Icons.map_outlined,
                        context.ts.dispatchOpenMaps,
                        c.navy,
                        () => _openMaps(to),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) => Material(
    color: context.colors.bg,
    shape: const CircleBorder(),
    elevation: 3,
    child: InkWell(
      customBorder: const CircleBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Icon(icon, color: context.colors.navy, size: 22),
      ),
    ),
  );

  Widget _chip(
    IconData icon,
    String label,
    Color colour,
    VoidCallback? onTap,
  ) => Material(
    color: colour,
    borderRadius: BorderRadius.circular(20),
    elevation: 3,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: colour == kFigmaOrange ? Colors.white : context.colors.bg,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: colour == kFigmaOrange
                      ? Colors.white
                      : context.colors.bg,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  /// Ticket number, subject and street.
  Widget _topBar() {
    final c = context.colors;
    final near = _report?['location_label'] as String?;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 0072: the admin's target date has passed.
              if (_open &&
                  widget.ticket.dueAt != null &&
                  widget.ticket.dueAt!.isBefore(DateTime.now()))
                Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    context.ts.ticketOverdue,
                    style: const TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              Text(
                context.ts.dispatchTicketNumber(widget.ticket.trackingId),
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  color: c.navy,
                ),
              ),
              Text(
                widget.ticket.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: c.navy,
                ),
              ),
              if (near != null && near.isNotEmpty)
                Text(
                  context.ts.dispatchNear(near),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontSize: 12.5,
                    color: c.muted,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Accepted → On the way → Arrived → Resolved.
  Widget _stepper() {
    final s = context.ts;
    final c = context.colors;
    final at = _state == 'resolved'
        ? 3
        : switch (_step) {
            'arrived' => 2,
            'on_the_way' => 1,
            _ => 0,
          };
    final labels = [
      s.windowStepAccepted,
      s.windowStepOnTheWay,
      s.windowStepArrived,
      s.windowStepResolved,
    ];
    return Row(
      children: [
        for (var i = 0; i < 4; i++) ...[
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i == 0
                            ? Colors.transparent
                            : (i <= at
                                  ? kFigmaOrange
                                  : c.muted.withValues(alpha: 0.3)),
                      ),
                    ),
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i <= at ? kFigmaOrange : c.bg,
                        border: Border.all(
                          color: i <= at
                              ? kFigmaOrange
                              : c.muted.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: i <= at
                          ? const Icon(
                              Icons.check,
                              size: 12,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i == 3
                            ? Colors.transparent
                            : (i < at
                                  ? kFigmaOrange
                                  : c.muted.withValues(alpha: 0.3)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: i == at ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 11.5,
                    color: i <= at ? c.navy : c.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// The next step, and Resolve — allowed at any step.
  Widget _stepActions() {
    final s = context.ts;
    final next = switch (_step) {
      null => ('on_the_way', s.windowActionOnTheWay),
      'on_the_way' => ('arrived', s.windowActionArrived),
      _ => null,
    };
    final esc = _escalation;
    final escNote = esc == null
        ? null
        : switch (esc['status']) {
            'pending' => s.escWaiting,
            'denied' => s.escDenied((esc['decision_note'] as String?) ?? ''),
            _ => null,
          };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepButtons(next),
        const SizedBox(height: 6),
        if (escNote != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(escNote,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: esc?['status'] == 'denied' ? _red : context.colors.navy,
                )),
          ),
        if (esc == null || esc['status'] != 'pending')
          TextButton.icon(
            onPressed: _requestEscalation,
            icon: const Icon(Icons.outbound_outlined, size: 18),
            label: Text(s.escButton),
            style: TextButton.styleFrom(foregroundColor: _red),
          ),
      ],
    );
  }

  Widget _stepButtons((String, String)? next) {
    final s = context.ts;
    return Row(
      children: [
        if (next != null) ...[
          Expanded(
            child: _wideButton(
              label: next.$2,
              colour: kFigmaOrange,
              busy: _stepping,
              onTap: () => _setStep(next.$1),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: _wideButton(
            label: s.windowResolve,
            colour: _green,
            filled: next == null,
            onTap: _resolve,
          ),
        ),
      ],
    );
  }

  Widget _wideButton({
    required String label,
    required Color colour,
    required VoidCallback onTap,
    bool filled = true,
    bool busy = false,
  }) => SizedBox(
    height: 46,
    child: Material(
      color: filled ? colour : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(23),
        side: BorderSide(color: colour, width: 2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(23),
        onTap: busy ? null : onTap,
        child: Center(
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: filled ? Colors.white : colour,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: filled ? Colors.white : colour,
                  ),
                ),
        ),
      ),
    ),
  );

  /// The complaint itself, folded until asked for.
  Widget _caseCard() {
    final s = context.ts;
    final c = context.colors;
    final waiting =
        _detailRequest != null && _detailRequest!['responded_at'] == null;
    return Container(
      decoration: BoxDecoration(
        color: c.field,
        border: Border.all(color: c.navy),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
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
                    placeholder: (_, __) => Container(color: context.colors.bg),
                    errorWidget: (_, __, ___) => Container(
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
    final s = context.ts;
    final c = context.colors;
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

  Widget _systemLine(String text, DateTime at, IconData icon) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: kFigmaOrange.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: kFigmaOrange),
              const SizedBox(width: 5),
              Text(
                '$text · ${_time(at)}',
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: c.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(
    _Post p, {
    required String who,
    required bool mine,
    String? fallback,
  }) {
    final c = context.colors;
    final fg = mine ? c.bg : c.navy;
    final body = (p.body ?? '').trim();
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
        decoration: BoxDecoration(
          color: mine ? c.navy : c.field,
          border: mine
              ? null
              : Border.all(color: c.navy.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              who,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
                color: mine ? fg.withValues(alpha: 0.8) : kFigmaOrange,
              ),
            ),
            if (body.isNotEmpty || fallback != null) ...[
              const SizedBox(height: 2),
              Text(
                body.isNotEmpty ? body : fallback!,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 1.3,
                  color: fg,
                ),
              ),
            ],
            if (p.media.isNotEmpty) ...[
              const SizedBox(height: 6),
              _thumbs(p.media, 84),
            ],
            const SizedBox(height: 3),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                _time(p.at),
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 10.5,
                  color: fg.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    final c = context.colors;
    final s = context.ts;
    return Material(
      color: c.bg,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_pics.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < _pics.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  _pics[i],
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: -6,
                                right: -6,
                                child: GestureDetector(
                                  onTap: _sending
                                      ? null
                                      : () => setState(() => _pics.removeAt(i)),
                                  child: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: c.navy,
                                    child: Icon(
                                      Icons.close,
                                      size: 12,
                                      color: c.bg,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(Icons.add_a_photo_outlined, color: c.navy),
                    onPressed: _sending || _pics.length >= 3 ? null : _addPic,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      enabled: !_sending,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontSize: 14,
                        color: c.navy,
                      ),
                      decoration: InputDecoration(
                        hintText: s.windowComposerHint,
                        counterText: '',
                        isDense: true,
                        filled: true,
                        fillColor: c.field,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: c.navy),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(
                            color: c.navy.withValues(alpha: 0.5),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: BorderSide(color: c.navy, width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setState(() => _error = null),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Material(
                      color: kFigmaOrange,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _sending ? null : _send,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(30, 14, 30, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.windowResolveTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  height: 1,
                  color: c.navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                s.windowResolveBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontSize: 13.5,
                  color: c.navy,
                ),
              ),
              const SizedBox(height: 20),
              _InputBox(
                label: s.dispatchProvideReportLabel,
                colour: c.navy,
                controller: _update,
                hint: s.dispatchInputHint,
                maxLength: 300,
                enabled: !_busy,
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  s.dispatchPhotoEvidenceLabel,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: c.navy,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(25),
                            child: Image.file(
                              _photos[i],
                              width: 107,
                              height: 107,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: GestureDetector(
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _photos.removeAt(i)),
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: c.navy,
                                child: Icon(Icons.close, size: 14, color: c.bg),
                              ),
                            ),
                          ),
                        ],
                      ),
                    // Optional. A tanod who moved an obstruction or spoke
                    // to a neighbour has nothing to photograph.
                    if (_photos.length < 3)
                      _AttachTile(
                        icon: Icons.add,
                        label: s.dispatchAttachMedia,
                        limit: s.dispatchMaxPhotoSize,
                        onTap: _busy ? null : () => _add(video: false),
                      ),
                    if (_video != null)
                      Container(
                        width: 138,
                        height: 107,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: c.field,
                          border: Border.all(color: c.navy),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.videocam, color: c.navy, size: 20),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Text(
                                  s.dispatchVideoAttached,
                                  style: TextStyle(
                                    fontFamily: 'Urbanist',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                    color: c.navy,
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: _busy
                                  ? null
                                  : () => setState(() => _video = null),
                              customBorder: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: c.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      _AttachTile(
                        icon: Icons.videocam,
                        label: s.dispatchAttachVideo,
                        limit: s.dispatchMaxVideoSize,
                        onTap: _busy ? null : () => _add(video: true),
                      ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: _red),
                ),
              ],
              const SizedBox(height: 24),
              _Pill(
                label: s.windowResolve,
                colour: _green,
                width: 200,
                height: 50,
                fontSize: 16,
                busy: _busy,
                onTap: _busy ? null : _submit,
              ),
              const SizedBox(height: 10),
              _Pill(
                label: s.dispatchCancel,
                colour: c.navy,
                filled: false,
                width: 200,
                height: 50,
                fontSize: 16,
                onTap: _busy ? null : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
