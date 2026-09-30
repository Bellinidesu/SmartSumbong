// SmartSumbong — Dispatch Order.
//
// Figma: TANOD - VIEW DISPATCH, MAP OPENED, MEDIA OPENED, INSTRUCTIONS
// OPENED, REROUTED EMERGENCY, COMPLAINT ACCEPTED, SUBMIT PHOTO EVIDENCE,
// REPORT SUBMITTED.
//
// One card over a dimmed Home, swapping its body rather than pushing
// screens. That is the design's shape and it suits the task: a tanod
// deciding whether to take a ticket looks at the map, then the photo,
// then the instructions, and back — a navigation stack four deep for
// three glances would be worse.
//
// Every mutation goes through an RPC. dispatches_admin_write is the only
// direct-write policy on the table, and 0003 says so plainly: a tanod
// acts through accept_dispatch(), reroute_dispatch() and
// submit_field_report(), never by UPDATE.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
// latlong2 exports its own generic Path<LatLng>, which shadows the one
// in dart:ui and breaks the dashed border below. The resident map screen
// hides it the same way.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:url_launcher/url_launcher.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../duty.dart';
import '../../i18n.dart' show AppLocale;
import '../navigation.dart';
import '../tanod_outbox.dart';
import '../../outbox.dart' show Outbox;

import '../tanod_strings.dart';
import '../../theme.dart';
import '../../widgets/brgy_map.dart';
import '../../widgets/figma_ui.dart';
import 'tickets_screen.dart';

part 'dispatch_nav.dart';
part 'dispatch_window.dart';

const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');
// Optional: falls back to the photo preset (which now also accepts video,
// per the Cloudinary preset widened 27 Aug 2026) when this dart-define is
// not set, so builds that have not been updated with the new key yet do
// not break.
const _videoUploadPresetRaw = String.fromEnvironment(
  'CLOUDINARY_UPLOAD_PRESET_VIDEO',
);

const _red = kFigmaRed;
const _green = Color(0xFF058F00);

/// Which body the card is showing.
enum _Pane { order, map, media, instructions, rerouteConfirm, accepted }

/// Which pane [showDispatchOrder] should land on, for a caller that
/// wants a specific view rather than the ticket's default (the order
/// pane for a pending ticket, the update pane for an accepted one).
///
/// Added 9 Sep 2026: Reports' View Map / View Attached Media / View
/// Instructions links used to all call [showDispatchOrder] the same way
/// no matter which was tapped, so all three landed on whichever pane the
/// ticket's state defaulted to (the update form, for anything in
/// Reports) — flagged in the CAPSTONE G12 chat. This lets a caller say
/// which pane it actually meant.
enum DispatchTarget { order, map, media, instructions }

/// Opens the dispatch order over whatever is behind it. Returns true if
/// anything changed, so the caller can reload.
Future<bool> showDispatchOrder(
  BuildContext context,
  Ticket ticket, {
  DispatchTarget target = DispatchTarget.order,
}) async {
  final changed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    // The frames fade Home to 30% behind the card.
    barrierColor: context.colors.bg.withValues(alpha: 0.7),
    barrierLabel: context.ts.dispatchBarrierLabel,
    pageBuilder: (_, __, ___) => _DispatchOrder(ticket: ticket, target: target),
  );
  return changed ?? false;
}

class _DispatchOrder extends StatefulWidget {
  const _DispatchOrder({
    required this.ticket,
    this.target = DispatchTarget.order,
  });

  final Ticket ticket;
  final DispatchTarget target;

  @override
  State<_DispatchOrder> createState() => _DispatchOrderState();
}

class _DispatchOrderState extends State<_DispatchOrder>
    with _Directions<_DispatchOrder> {
  _Pane _pane = _Pane.order;

  Map<String, dynamic>? _report;

  List<({String url, bool isVideo})> _evidence = const [];

  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  final _reason = TextEditingController();

  @override
  LatLng? get _casePoint {
    final lat = (_report?['latitude'] as num?)?.toDouble();
    final lon = (_report?['longitude'] as num?)?.toDouble();
    return lat == null || lon == null ? null : LatLng(lat, lon);
  }

  @override
  void initState() {
    super.initState();
    // A caller that asked for a specific pane (Reports' View Map / View
    // Attached Media / View Instructions links) lands there directly;
    // Back returns to the order pane. An accepted ticket keeps the card
    // (branch C): its order pane offers Open dispatch, into the window,
    // in place of Reroute and Accept.
    _pane = switch (widget.target) {
      DispatchTarget.map => _Pane.map,
      DispatchTarget.media => _Pane.media,
      DispatchTarget.instructions => _Pane.instructions,
      DispatchTarget.order => _Pane.order,
    };
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final got = await Future.wait<Object?>([
        client
            .from('reports')
            .select(
              'tracking_id, subject, description, created_at, '
              'latitude, longitude, location_label, is_anonymous',
            )
            .eq('id', widget.ticket.reportId)
            .single(),
        client
            .from('report_media')
            .select('media_url, mime_type')
            .eq('report_id', widget.ticket.reportId),
      ], eagerError: true);
      final report = got[0] as Map<String, dynamic>;
      final media = got[1] as List<Map<String, dynamic>>;

      if (!mounted) return;
      setState(() {
        _report = report;
        _evidence = [
          for (final m in media)
            (
              url: m['media_url'] as String,
              isVideo: isVideoMime(m['mime_type'] as String?),
            ),
        ];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- actions -------------------------------------------

  // Each action returns early while one is running: the buttons only
  // disable on the next rebuild, and a second tap inside that frame
  // would otherwise call the RPC — or upload every photo — twice.
  Future<void> _accept() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'accept_dispatch',
        params: {'p_dispatch': widget.ticket.dispatchId},
      );
      // A dispatch step is one of the few moments a location is sent.
      unawaited(DutyController.instance.keyMoment());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _changed = true;
        _pane = _Pane.accepted;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message.contains('already actioned')
            ? context.ts.dispatchAcceptStale
            : context.ts.dispatchAcceptFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.ts.dispatchAcceptFailed;
      });
    }
  }

  Future<void> _reroute() async {
    if (_busy) return;
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = context.ts.dispatchRerouteReasonRequired);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // p_to omitted: the ticket goes back to the admin queue rather
      // than to a named colleague. A tanod cannot see the roster or who
      // is free, so choosing one would be a guess.
      await Supabase.instance.client.rpc(
        'reroute_dispatch',
        params: {
          'p_dispatch': widget.ticket.dispatchId,
          'p_reason': _reason.text.trim(),
        },
      );
      unawaited(DutyController.instance.keyMoment());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.ts.dispatchRerouteFailed;
      });
    }
  }

  void _close() => Navigator.of(context).pop(_changed);

  /// On into the dispatch window, in the card's place.
  void _toWindow() => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => DispatchWindow(ticket: widget.ticket)),
    result: true,
  );

  // ---------- shell ---------------------------------------------

  @override
  Widget build(BuildContext context) {
    final reroute = _pane == _Pane.rerouteConfirm;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              // Figma "Frame 950": 352 wide at x=30, #F3F3F3, a 2px ink
              // edge (red on the reroute pane), radius 50, the design
              // shadow; content 32 in.
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 352),
                decoration: BoxDecoration(
                  color: context.colors.bg,
                  border: Border.all(
                    color: reroute ? _red : context.colors.navy,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(50),
                  boxShadow: kFigmaShadow,
                ),
                padding: const EdgeInsets.fromLTRB(30, 36, 30, 28),
                child: _body(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() => switch (_pane) {
    _Pane.order => _orderPane(),
    _Pane.map => _framed(Column(children: [_mapPane(), _directions()])),
    _Pane.media => _framed(_mediaPane()),
    _Pane.instructions => _framed(_instructionsPane()),
    _Pane.rerouteConfirm => _reroutePane(),
    _Pane.accepted => _acceptedPane(),
  };

  // ---------- panes ---------------------------------------------

  // The frame's title: "DISPATCH ORDER:" over "Ticket #…", 28/800 with
  // tight leading, each line shrinking rather than wrapping when a
  // tracking ID is long; "Submitted on" 14/500 under it.
  Widget _header() {
    final style = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w800,
      fontSize: 28,
      height: 24.5 / 28,
      color: context.colors.navy,
    );
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(context.ts.dispatchOrderHeaderLabel, style: style),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            context.ts.dispatchTicketNumber(widget.ticket.trackingId),
            style: style,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.ts.dispatchSubmittedOn(
            _date(_report?['created_at'] as String?),
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 15 / 14,
            color: context.colors.navy,
          ),
        ),
        // The street saved with the complaint (0068), when there is one.
        if ((_report?['location_label'] as String?)?.isNotEmpty ?? false) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place_outlined, size: 15, color: context.colors.navy),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  context.ts.dispatchNear(_report!['location_label'] as String),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: context.colors.navy,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// The map, media and instructions panes are the same card with the
  /// inner box swapped and a single Back.
  Widget _framed(Widget inner) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _header(),
      const SizedBox(height: 14),
      inner,
      const SizedBox(height: 30),
      _Pill(
        label: context.ts.dispatchBack,
        colour: context.colors.navy,
        onTap: () => setState(() => _pane = _Pane.order),
      ),
    ],
  );

  /// The frame's inner box: #FBFBFB, 1px ink edge, radius 20; text 27 in.
  Widget _innerBox({required Widget child, double? height}) => Container(
    width: double.infinity,
    height: height,
    padding: const EdgeInsets.fromLTRB(27, 18, 20, 16),
    decoration: BoxDecoration(
      color: context.colors.field,
      border: Border.all(color: context.colors.navy),
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );

  Widget _orderPane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        const SizedBox(height: 14),

        _innerBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Complainant: Anonymous" on every row, and not because
              // every complaint is anonymous — users_self_read is
              // `id = auth.uid() or is_admin()`, so a tanod cannot read
              // the filer's row at all. A name here needs that policy
              // loosened, which is the barangay's call.
              _Field(
                label: context.ts.dispatchComplainantLabel,
                value: context.ts.reportsFilerAnonymous,
              ),
              const SizedBox(height: 15),
              _Field(
                label: context.ts.reportsDescriptionLabel,
                value: '\u201C${widget.ticket.description}\u201D',
              ),
              const SizedBox(height: 15),
              _Field(
                label: context.ts.reportsDeadlineLabel,
                value: _deadlineOf(widget.ticket.dueAt),
              ),
              const SizedBox(height: 8),

              _Link(
                icon: Icons.location_on_outlined,
                label: context.ts.reportsViewMap,
                onTap: () => setState(() => _pane = _Pane.map),
              ),
              _Link(
                icon: Icons.photo_camera_outlined,
                label: context.ts.reportsViewMedia,
                onTap: () => setState(() => _pane = _Pane.media),
              ),
              _Link(
                icon: Icons.my_location_rounded,
                label: context.ts.reportsViewInstructions,
                onTap: () => setState(() => _pane = _Pane.instructions),
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: _red),
          ),
        ],
        const SizedBox(height: 14),

        // The frame's 112x37 Reroute and Accept, 36 apart, Back under them.
        // Once accepted, one way on: the dispatch window.
        if (widget.ticket.state == DispatchState.accepted)
          _Pill(
            label: context.ts.windowOpen,
            colour: kFigmaOrange,
            width: 214,
            height: 50,
            radius: 20,
            fontSize: 16,
            onTap: _toWindow,
          )
        else
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 36,
            runSpacing: 12,
            children: [
              _Pill(
                label: context.ts.dispatchReroute,
                colour: _red,
                onTap: _busy
                    ? null
                    : () => setState(() {
                        _pane = _Pane.rerouteConfirm;
                        _error = null;
                      }),
              ),
              _Pill(
                label: context.ts.dispatchAccept,
                colour: _green,
                busy: _busy,
                onTap: _busy ? null : _accept,
              ),
            ],
          ),
        const SizedBox(height: 14),
        _Pill(
          label: context.ts.dispatchBack,
          colour: context.colors.navy,
          onTap: _close,
        ),
      ],
    );
  }

  Widget _mapPane() {
    final lat = _casePoint?.latitude;
    final lon = _casePoint?.longitude;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: lat == null || lon == null
            ? Container(
                color: context.colors.field,
                child: Center(
                  child: Text(
                    context.ts.dispatchNoLocation,
                    style: TextStyle(fontSize: 12, color: context.colors.muted),
                  ),
                ),
              )
            // MapLibre on OpenFreeMap vector tiles (widgets/brgy_map.dart),
            // light or ink-dark with the app; the design's tilted pin on
            // the case. The frame's 1px ink edge, drawn over the map.
            : Container(
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: context.colors.navy),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: BrgyMap(
                  controller: _mapCtl,
                  initialCenter: LatLng(lat, lon),
                  pins: [BrgyMapPin(id: 'case', point: LatLng(lat, lon))],
                  route: _route,
                  accuracyCentre: _me,
                  accuracyMetres: _me == null
                      ? null
                      : (_meAccuracy ?? 15).clamp(8, 40).toDouble(),
                  cornerRadius: 20,
                  cornerColour: context.colors.bg,
                ),
              ),
      ),
    );
  }

  Widget _mediaPane() {
    if (_loading) {
      return const SizedBox(
        height: 300,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_evidence.isEmpty) {
      return Container(
        height: 300,
        decoration: BoxDecoration(
          color: context.colors.field,
          border: Border.all(color: context.colors.navy),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: Text(
            context.ts.dispatchNoMedia,
            style: TextStyle(fontSize: 12, color: context.colors.muted),
          ),
        ),
      );
    }
    return SizedBox(
      height: 300,
      child: PageView(
        children: [
          for (final item in _evidence)
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: item.isVideo
                  ? GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => VideoPlayerScreen(url: item.url),
                        ),
                      ),
                      child: Container(
                        color: Colors.black87,
                        width: double.infinity,
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill,
                            size: 48,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      // The card's width, not the 1920 upload.
                      imageUrl: cloudinarySized(item.url, width: 900),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                        color: context.colors.field,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: context.colors.field,
                        child: Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: context.colors.muted,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _instructionsPane() {
    final text = widget.ticket.instructions?.trim() ?? '';

    // Figma INSTRUCTIONS OPENED: the 287x326 box, "Admin Directives:" and
    // the steps 14 (700 / 500), the responder note red italic under them.
    return Container(
      constraints: const BoxConstraints(maxHeight: 326),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(27, 18, 20, 16),
      decoration: BoxDecoration(
        color: context.colors.field,
        border: Border.all(color: context.colors.navy),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.ts.dispatchAdminDirectivesTitle,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 15 / 14,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                text.isEmpty ? context.ts.dispatchNoDirectives : text,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                  height: 15 / 14,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.ts.dispatchResponderNote,
                style: const TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                  height: 1.25,
                  fontStyle: FontStyle.italic,
                  color: _red,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Figma REROUTED EMERGENCY: the red title 28/800, the body 16/500, the
  // 266x128 reason box (radius 25, red edge), then the 214x50 Confirm and
  // Cancel.
  Widget _reroutePane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.ts.dispatchRerouteConfirmTitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w800,
            fontSize: 28,
            height: 25 / 28,
            color: _red,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.ts.dispatchRerouteConfirmBody,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 16,
            height: 15 / 16,
            color: _red,
          ),
        ),
        const SizedBox(height: 30),
        _InputBox(
          label: context.ts.dispatchRerouteReasonLabel,
          colour: _red,
          controller: _reason,
          hint: context.ts.dispatchInputHint,
          maxLength: 200,
          enabled: !_busy,
          onChanged: (_) => setState(() => _error = null),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: _red),
          ),
        ],
        const SizedBox(height: 30),
        _Pill(
          label: context.ts.dispatchConfirm,
          colour: _red,
          width: 214,
          height: 50,
          radius: 20,
          fontSize: 16,
          busy: _busy,
          onTap: _busy ? null : _reroute,
        ),
        const SizedBox(height: 15),
        _Pill(
          label: context.ts.dispatchCancel,
          colour: _red,
          filled: false,
          width: 214,
          height: 50,
          radius: 20,
          fontSize: 16,
          onTap: _busy
              ? null
              : () => setState(() {
                  _pane = _Pane.order;
                  _error = null;
                }),
        ),
      ],
    );
  }

  // Figma COMPLAINT ACCEPTED: the message 28/800 and 16/500 centred in the
  // 556-tall card, the 180x50 Back under it.
  Widget _acceptedPane() => _message(
    title: context.ts.dispatchAcceptedTitle(
      widget.ticket.trackingId,
      widget.ticket.subject,
    ),
    body: context.ts.dispatchAcceptedBody,
    action: context.ts.windowOpen,
    onAction: _toWindow,
  );

  Widget _message({
    required String title,
    String? body,
    String? action,
    VoidCallback? onAction,
  }) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 480),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w800,
            fontSize: 28,
            height: 24.5 / 28,
            color: context.colors.navy,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 16,
              height: 15 / 16,
              color: context.colors.navy,
            ),
          ),
        ],
        const SizedBox(height: 60),
        _Pill(
          label: action ?? context.ts.dispatchBack,
          colour: action == null ? context.colors.navy : kFigmaOrange,
          width: 180,
          height: 50,
          fontSize: 16,
          onTap: onAction ?? _close,
        ),
      ],
    ),
  );

  // ---------- dates ---------------------------------------------

  String _date(String? iso) => _dateOf(DateTime.tryParse(iso ?? ''));

  /// The deadline, with Overdue once the admin's date has passed.
  String _deadlineOf(DateTime? d) => d != null && d.isBefore(DateTime.now())
      ? '${_dateOf(d)} · ${context.ts.ticketOverdue}'
      : _dateOf(d);

  String _dateOf(DateTime? d) {
    if (d == null) return context.ts.reportsDeadlineNotSet;
    final l = d.toLocal();
    return '${context.ts.monthFull(l.month)} ${l.day}, ${l.year}';
  }
}

// ---------- small parts ----------------------------------------

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  // The frame's 14/500 body, the label 700, 15 leading.
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      style: TextStyle(
        fontFamily: 'Urbanist',
        fontWeight: FontWeight.w500,
        fontSize: 14,
        height: 15 / 14,
        color: context.colors.navy,
      ),
      children: [
        TextSpan(
          text: label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: value),
      ],
    ),
  );
}

/// The frame's link row: a 22px icon, the label 14/700 underlined; rows
/// 46 apart.
class _Link extends StatelessWidget {
  const _Link({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ink),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: ink,
                  decoration: TextDecoration.underline,
                  decorationColor: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The frames' labelled input box: the label 14/700, a 128-tall #FBFBFB
/// box with a 1px edge and radius 25, the hint 12/400, the count 10/300
/// at the bottom right. [colour] is ink, or red on the reroute pane.
class _InputBox extends StatelessWidget {
  const _InputBox({
    required this.label,
    required this.colour,
    required this.controller,
    required this.hint,
    required this.maxLength,
    required this.enabled,
    required this.onChanged,
    this.autofocus = false,
  });

  final bool autofocus;
  final String label;
  final Color colour;
  final TextEditingController controller;
  final String hint;
  final int maxLength;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 14,
                height: 21.84 / 14,
                color: colour,
              ),
            ),
          ),
        Container(
          height: 128,
          padding: const EdgeInsets.fromLTRB(17, 10, 11, 4),
          decoration: BoxDecoration(
            color: context.colors.field,
            border: Border.all(color: colour),
            borderRadius: BorderRadius.circular(25),
          ),
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            maxLines: null,
            expands: true,
            maxLength: maxLength,
            enabled: enabled,
            textAlignVertical: TextAlignVertical.top,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: colour,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.35,
              color: context.colors.navy,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: colour,
              ),
              counterStyle: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w300,
                fontSize: 10,
                height: 1,
                color: colour,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// The frames' pill: [colour] filled with a 1px #F3F3F3 edge and the
/// design shadow, 14/700 (112x37) by default; [filled] false draws the
/// light twin — #FBFBFB with a [colour] edge and label.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.colour,
    required this.onTap,
    this.filled = true,
    this.width = 112,
    this.height = 37,
    this.radius = 50,
    this.fontSize = 14,
    this.busy = false,
  });

  final String label;
  final Color colour;
  final VoidCallback? onTap;
  final bool filled;
  final double width;
  final double height;
  final double radius;
  final double fontSize;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // On the app's own ink (pale at night) the label takes the page
    // colour; on red or green it stays the frame's #F3F3F3.
    final onFill = colour == c.navy ? c.bg : const Color(0xFFF3F3F3);
    final bg = filled ? colour : c.field;
    final fg = filled ? onFill : colour;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: width, minHeight: height),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: kFigmaShadow,
        ),
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            disabledBackgroundColor: bg.withValues(alpha: 0.55),
            disabledForegroundColor: fg.withValues(alpha: 0.8),
            minimumSize: Size(width, height),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            elevation: 0,
            side: BorderSide(color: filled ? const Color(0xFFF3F3F3) : colour),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radius),
            ),
            textStyle: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
            ),
          ),
          child: busy
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                )
              : Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

/// The frame's 146x107 attach tile: dashed edge, radius 25, the small
/// filled square with its icon, the label 12/700 and the limit 10/400.
class _AttachTile extends StatelessWidget {
  const _AttachTile({
    required this.icon,
    required this.label,
    required this.limit,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String limit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(25),
      child: CustomPaint(
        painter: _DashedBorder(colour: ink),
        child: SizedBox(
          // 146 in the frame; 138 so two sit side by side in the card.
          width: 138,
          height: 107,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Icon(icon, size: 16, color: context.colors.bg),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        height: 1.3,
                        color: ink,
                      ),
                    ),
                    Text(
                      limit,
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        fontSize: 10,
                        color: ink,
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

/// The dashed attach-media box. Flutter has no dashed border, and the
/// alternative is a package for one rectangle.
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.colour});

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(25),
    );
    final path = Path()..addRRect(rect);

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + 5).clamp(0, metric.length)),
          paint,
        );
        d += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorder old) => old.colour != colour;
}

/// The question box for asking the resident for more details: one field
/// (300 characters, the table's limit), Cancel and Send.
class _DetailsRequestDialog extends StatefulWidget {
  const _DetailsRequestDialog();

  @override
  State<_DetailsRequestDialog> createState() => _DetailsRequestDialogState();
}

class _DetailsRequestDialogState extends State<_DetailsRequestDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final c = context.colors;
    return Dialog(
      backgroundColor: c.bg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(50),
        side: BorderSide(color: c.navy, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 34, 28, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              s.dispatchRequestDetailsTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w800,
                fontSize: 24,
                height: 1.05,
                color: c.navy,
              ),
            ),
            const SizedBox(height: 18),
            _InputBox(
              label: '',
              colour: c.navy,
              controller: _text,
              hint: s.dispatchRequestDetailsHint,
              maxLength: 300,
              enabled: true,
              autofocus: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 13,
              runSpacing: 12,
              children: [
                _Pill(
                  label: s.dispatchRequestDetailsCancel,
                  filled: false,
                  colour: c.navy,
                  onTap: () => Navigator.of(context).pop(),
                ),
                _Pill(
                  label: s.dispatchRequestDetailsSend,
                  colour: c.navy,
                  onTap: _text.text.trim().isEmpty
                      ? null
                      : () => Navigator.of(context).pop(_text.text.trim()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
