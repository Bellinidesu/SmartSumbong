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
import 'package:flutter/services.dart';
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
import '../../i18n.dart' show AppLocale, AppLocaleScope;
import '../navigation.dart';
import '../tanod_outbox.dart';
import '../../outbox.dart' show Outbox;

import '../tanod_strings.dart';
import '../../d/d_theme.dart';
import '../../preview/demo.dart';
import '../../d/d_success.dart';
import '../../d/d_ui.dart';
import '../../d/d_categories.dart';
import '../../models/complaint_category.dart';
import '../../theme.dart';
import '../../widgets/brgy_map.dart';
import '../../widgets/figma_ui.dart';
import 'tickets_screen.dart';
import '../../smart_text.dart';

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

/// Rose's Figma (VIEW ASSIGNED REPORT, 17 Nov 2026): an accepted dispatch opens as this same Dispatch Order page with four
/// stacked buttons (Send "Arrived at scene", Send an update, Request more details, Escalate) instead of the map-and-steps job
/// page. Switched, not removed: false sends Open dispatch / Open the job back to [DispatchWindow] as before.
const bool kSimpleJobPage = true;

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
    barrierColor: context.d.bg,
    barrierLabel: context.ts.dispatchBarrierLabel,
    pageBuilder: (_, _, _) => _DispatchOrder(ticket: ticket, target: target),
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

  /// The job page's state (kSimpleJobPage): the dispatch's own state and step, and whether it was accepted on this card.
  String? _dispState;
  String? _step;
  bool _acceptedHere = false;
  bool _acting = false;

  bool get _isAccepted => widget.ticket.state == DispatchState.accepted || _acceptedHere || _dispState == 'accepted';
  bool get _jobMode => kSimpleJobPage && _isAccepted;

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
              'latitude, longitude, location_label, is_anonymous, is_sensitive, category',
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

      Map<String, dynamic>? disp;
      try {
        disp = await client.from('dispatches').select('state, step').eq('id', widget.ticket.dispatchId).maybeSingle();
      } catch (_) {
        disp = null;   // the card still works without it; the job buttons assume an open dispatch
      }

      if (!mounted) return;
      setState(() {
        _dispState = disp?['state'] as String?;
        _step = disp?['step'] as String?;
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
        _acceptedHere = true;
        _dispState = 'accepted';
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

  /// On to the job. Rose's Figma (kSimpleJobPage): the job is this page with its four buttons, and I'm on the way tells the
  /// resident first. Switched off: into the dispatch window, in the card's place.
  void _toWindow({bool startOnTheWay = false}) {
    if (kSimpleJobPage) {
      if (startOnTheWay) {
        _onTheWay();
      } else {
        setState(() {
          _pane = _Pane.order;
          _error = null;
        });
      }
      return;
    }
    _toFullJob(startOnTheWay: startOnTheWay);
  }

  /// The map-and-steps job page (still reachable from the simple page's quiet link).
  void _toFullJob({bool startOnTheWay = false}) => Navigator.of(context).pushReplacement(
    MaterialPageRoute(builder: (_) => DispatchWindow(ticket: widget.ticket, startOnTheWay: startOnTheWay)),
    result: true,
  );

  // ---------- the job (Rose's Figma) ------------------------------

  /// One step for the resident to hear about: on the way, arrived. With no signal it waits on the phone and goes by itself.
  Future<bool> _setStep(String step) async {
    try {
      await Supabase.instance.client.rpc('set_dispatch_step', params: {'p_dispatch': widget.ticket.dispatchId, 'p_step': step});
      unawaited(DutyController.instance.keyMoment());   // a dispatch step is one of the few moments a location is sent
      _changed = true;
      if (mounted) setState(() => _step = step);
      return true;
    } catch (e) {
      if (Outbox.isNetworkError(e)) {
        await TanodOutbox.instance.enqueue(kind: 'step', dispatchId: widget.ticket.dispatchId, step: step);
        _changed = true;
        if (mounted) {
          setState(() => _step = step);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.ts.outboxSaved)));
        }
        return true;
      }
      if (mounted) setState(() => _error = context.ts.windowStepFailed);
      return false;
    }
  }

  /// The Figma's small popup: "Resident has been notified." and Back.
  Future<void> _notified() => showDialog<void>(
        context: context,
        builder: (ctx) => FigmaDialog(
          title: context.tr('Resident has been notified.', 'Naabisuhan na ang residente.'),
          primaryLabel: context.tr('Back', 'Bumalik'),
          onPrimary: () => Navigator.of(ctx).pop(),
        ),
      );

  /// Dispatch accepted's I'm on the way: the step, the popup, then the job page.
  Future<void> _onTheWay() async {
    if (_acting) return;
    setState(() => _acting = true);
    final ok = _step == 'on_the_way' || _step == 'arrived' ? true : await _setStep('on_the_way');
    if (!mounted) return;
    setState(() {
      _acting = false;
      _pane = _Pane.order;
    });
    if (ok) await _notified();
  }

  /// Send "Arrived at scene": a confirm, the step, then the popup.
  Future<void> _arrive() async {
    if (_acting) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => FigmaDialog(
        title: context.tr('Let the complainant know you’ve arrived at the scene.', 'Ipaalam sa nagreklamo na nakarating ka na sa lugar.'),
        primaryLabel: context.tr('Confirm', 'Kumpirmahin'),
        onPrimary: () => Navigator.of(ctx).pop(true),
        secondaryLabel: context.tr('Back', 'Bumalik'),
        onSecondary: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _acting = true);
    final ok = await _setStep('arrived');
    if (!mounted) return;
    setState(() => _acting = false);
    if (ok) await _notified();
  }

  /// Send an update: the field report with its photo and video proof, for the barangay's approval (submit_field_report).
  Future<void> _sendUpdate() async {
    final done = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => _ResolveSheet(ticket: widget.ticket)));
    if (done == null || done == 'false' || !mounted) return;
    _changed = true;
    if (done == 'queued') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.ts.outboxSaved)));
      return;
    }
    await showDSuccessPage(
      context,
      title: context.tr('Sent for approval', 'Naipasa para aprubahan'),
      body: context.ts.windowAwaitingApproval,
      button: context.tr('Back to the job', 'Bumalik sa trabaho'),
      ticketId: widget.ticket.trackingId,
      tone: DTicketTone.awaitingApproval,
      status: context.tr('Waiting for approval', 'Hinihintay ang pag-apruba'),
    );
    if (mounted) await _load();
  }

  /// Request more details: the shared popup, then request_additional_details; the resident answers from their app.
  Future<void> _requestDetails() async {
    final s = context.ts;
    final message = await showDialog<String>(context: context, builder: (_) => const _DetailsRequestDialog());
    if (message == null || message.trim().isEmpty || !mounted) return;
    String note;
    try {
      await Supabase.instance.client.rpc('request_additional_details', params: {'p_report': widget.ticket.reportId, 'p_message': message});
      _changed = true;
      note = s.dispatchDetailsSent;
    } on PostgrestException catch (e) {
      note = e.message.contains('already a request') ? s.dispatchDetailsAlreadyOpen : s.dispatchDetailsFailed;
    } catch (_) {
      note = s.dispatchDetailsFailed;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
  }

  /// Escalate: the Request escalation page, then request_escalation; the barangay decides.
  Future<void> _escalate() async {
    final s = context.ts;
    final res = await Navigator.of(context).push<(String, String?)>(MaterialPageRoute(builder: (_) => _EscalationPage(ticket: widget.ticket)));
    if (res == null || !mounted) return;
    final text = res.$1.trim();
    if (text.isEmpty) {
      setState(() => _error = s.escReasonRequired);
      return;
    }
    String note;
    try {
      await Supabase.instance.client.rpc('request_escalation', params: {'p_dispatch': widget.ticket.dispatchId, 'p_reason': text, 'p_office': res.$2});
      _changed = true;
      note = s.escSent;
    } on PostgrestException catch (e) {
      note = e.message.contains('already waiting') ? s.escAlreadyWaiting : s.escFailed;
    } catch (_) {
      note = s.escFailed;
    }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
  }

  /// The four stacked buttons (Rose's Figma), or what the job is waiting for once the report is in.
  Widget _jobActions() {
    final d = context.d;
    if (_dispState != null && _dispState != 'accepted') {
      return DNote(
        title: _dispState == 'resolved' ? context.tr('Sent for approval', 'Naipasa para aprubahan') : context.tr('This dispatch is closed', 'Sarado na ang dispatch na ito'),
        body: _dispState == 'resolved'
            ? context.tr('The barangay approves your report before the case closes.', 'Inaaprubahan ng barangay ang ulat bago isara ang kaso.')
            : context.tr('Nothing more is needed from you on this one.', 'Wala nang kailangan mula sa iyo rito.'),
      );
    }
    final arrived = _step == 'arrived';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DButton(
        arrived ? context.tr('Arrived at scene · sent', 'Nakarating na · naipadala') : context.tr('Send “Arrived at scene”', 'Ipadala ang “Nakarating na”'),
        kind: DButtonKind.accent,
        expand: true,
        busy: _acting,
        onTap: arrived || _acting ? null : _arrive,
      ),
      const SizedBox(height: 10),
      DButton(context.tr('Send an update', 'Magpadala ng update'), expand: true, onTap: _acting ? null : _sendUpdate),
      const SizedBox(height: 10),
      DButton(context.tr('Request more details', 'Humingi ng karagdagang detalye'),
          kind: DButtonKind.line, expand: true, onTap: _acting ? null : _requestDetails),
      const SizedBox(height: 10),
      DButton(context.tr('Escalate', 'I-escalate'), kind: DButtonKind.danger, expand: true, onTap: _acting ? null : _escalate),
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          onPressed: _acting ? null : () => _toFullJob(),
          child: Text(context.tr('Directions and updates', 'Direksyon at mga update'), style: DType.body(d.link, size: 13, w: FontWeight.w700)),
        ),
      ),
    ]);
  }

  // ---------- shell ---------------------------------------------

  // Branch D: the dispatch order is the preview's full page — the case's
  // category colour across the top, DISPATCH ORDER, the subject, three
  // round actions (map, media, instructions), the details, the admin's
  // directives, and Reroute / Accept pinned at the bottom. Accept goes
  // straight on to the job page.
  @override
  Widget build(BuildContext context) {
    if (_pane == _Pane.accepted) return _acceptedScreen();
    final d = context.d;
    final cat = ComplaintCategory.parse(_report?['category'] as String?);
    final col = categoryColour(cat);
    final order = _pane == _Pane.order;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!order && _pane != _Pane.accepted) {
          setState(() {
            _pane = _Pane.order;
            _error = null;
          });
        } else {
          _close();
        }
      },
      child: Scaffold(
        backgroundColor: d.bg,
        body: Column(children: [
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              // the category header (`.shero`, 170)
              DHero(
                colour: col,
                height: 170 + MediaQuery.paddingOf(context).top,
                glyph: categoryGlyph(cat),
                children: [
                  Positioned(
                    left: 12,
                    top: MediaQuery.paddingOf(context).top + 10,
                    child: DHeroButton(icon: Icons.chevron_left_rounded, onTap: order ? _close : () => setState(() => _pane = _Pane.order)),
                  ),
                  if (_report != null) Positioned(left: 12, bottom: 10, child: DHeroChip(cat.label)),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: _body(),
              ),
            ]),
          ),
          if (order && !_jobMode) _orderBar(),
        ]),
      ),
    );
  }

  Widget _body() => switch (_pane) {
    _Pane.order => _orderPane(),
    _Pane.map => _framed(Column(children: [_mapPane(), _directions()])),
    _Pane.media => _framed(_mediaPane()),
    _Pane.instructions => _framed(_instructionsPane()),
    _Pane.rerouteConfirm => _reroutePane(),
    _Pane.accepted => const SizedBox.shrink(),
  };

  // ---------- panes ---------------------------------------------

  /// DISPATCH ORDER, the subject, the ticket and when it was filed.
  Widget _header() {
    final d = context.d;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('DISPATCH ORDER', 'DISPATCH ORDER'), style: DType.label(d.muted)),
      const SizedBox(height: 10),
      Text(widget.ticket.subject, style: DType.body(d.ink, size: 19, w: FontWeight.w800).copyWith(height: 1.25)),
      if (_report?['is_sensitive'] == true) ...[
        const SizedBox(height: 10),
        const Align(alignment: Alignment.centerLeft, child: DSensitivePill()),
      ],
      const SizedBox(height: 10),
      Text.rich(TextSpan(children: [
        TextSpan(text: widget.ticket.trackingId, style: DType.mono(d.link, size: 13)),
        TextSpan(text: '  ·  ${context.ts.dispatchSubmittedOn(_date(_report?['created_at'] as String?))}', style: DType.body(d.muted, size: 13)),
      ])),
    ]);
  }

  /// The map, media and instructions panes: the header, the pane, Back.
  Widget _framed(Widget inner) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _header(),
      const SizedBox(height: 16),
      inner,
      const SizedBox(height: 20),
      DButton(context.ts.dispatchBack, kind: DButtonKind.ghost, expand: true, onTap: () => setState(() => _pane = _Pane.order)),
    ],
  );

  Widget _orderPane() {
    final d = context.d;
    final near = _report?['location_label'] as String?;
    final instructions = widget.ticket.instructions?.trim() ?? '';
    Widget act(IconData icon, String label, VoidCallback onTap) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(children: [
                DWell(icon, size: 42),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, style: DType.body(d.link, size: 12, w: FontWeight.w700)),
              ]),
            ),
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: d.line))),
        // Icons on one line even when a label wraps to two.
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          act(Icons.map_outlined, context.ts.reportsViewMap, () => setState(() => _pane = _Pane.map)),
          act(Icons.photo_library_outlined, context.ts.reportsViewMedia, () => setState(() => _pane = _Pane.media)),
          act(Icons.assignment_outlined, context.ts.reportsViewInstructions, () => setState(() => _pane = _Pane.instructions)),
        ]),
      ),
      if (near != null && near.isNotEmpty)
        DRow(icon: Icons.place_outlined, title: context.ts.dispatchNear(near), sub: _routeLine),
      // "Complainant: Anonymous" on every row, and not because every
      // complaint is anonymous — users_self_read is `id = auth.uid() or
      // is_admin()`, so a tanod cannot read the filer's row at all.
      DRow(icon: Icons.person_outline_rounded, title: '${context.ts.dispatchComplainantLabel}${context.ts.reportsFilerAnonymous}'),
      DRow(icon: Icons.event_outlined, title: '${context.ts.reportsDeadlineLabel}${_deadlineOf(widget.ticket.dueAt)}'),
      const SizedBox(height: 10),
      Text('“${widget.ticket.description}”', style: DType.body(d.ink2, size: 14, w: FontWeight.w400).copyWith(height: 1.5)),
      const SizedBox(height: 10),
      DNote(
        title: context.ts.dispatchAdminDirectivesTitle,
        body: instructions.isEmpty ? context.ts.dispatchNoDirectives : instructions,
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
      ],
      if (_jobMode) ...[
        const SizedBox(height: 18),
        _jobActions(),
      ],
    ]);
  }

  /// Reroute / Accept, pinned. Once accepted, one way on: the job page.
  Widget _orderBar() {
    final d = context.d;
    return Container(
      decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: widget.ticket.state == DispatchState.accepted
              ? DButton(context.ts.windowOpen, expand: true, onTap: _toWindow)
              : Row(children: [
                  Expanded(
                    child: DButton(context.ts.dispatchReroute,
                        kind: DButtonKind.ghost,
                        expand: true,
                        onTap: _busy
                            ? null
                            : () => setState(() {
                                  _pane = _Pane.rerouteConfirm;
                                  _error = null;
                                })),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: DButton(context.ts.dispatchAccept, expand: true, busy: _busy, onTap: _busy ? null : _accept)),
                ]),
        ),
      ),
    );
  }

  Widget _mapPane() {
    final d = context.d;
    final p = _casePoint;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: p == null
            ? Container(color: d.field, child: Center(child: Text(context.ts.dispatchNoLocation, style: DType.body(d.muted, size: 12.5))))
            : BrgyMap(
                controller: _mapCtl,
                initialCenter: p,
                pins: [_casePin(p, ComplaintCategory.parse(_report?['category'] as String?))],
                route: _route,
                accuracyCentre: _me,
                accuracyMetres: _me == null ? null : (_meAccuracy ?? 15).clamp(8, 40).toDouble(),
                cornerRadius: 18,
                cornerColour: d.bg,
              ),
      ),
    );
  }

  Widget _mediaPane() {
    final d = context.d;
    if (_loading) return const SizedBox(height: 300, child: Center(child: CircularProgressIndicator()));
    if (_evidence.isEmpty) {
      return Container(
        height: 220,
        decoration: BoxDecoration(color: d.field, border: Border.all(color: d.line), borderRadius: BorderRadius.circular(18)),
        child: Center(child: Text(context.ts.dispatchNoMedia, style: DType.body(d.muted, size: 13))),
      );
    }
    return SizedBox(
      height: 300,
      child: PageView(children: [
        for (final item in _evidence)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: item.isVideo
                  ? GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(url: item.url))),
                      child: Container(
                        color: Colors.black87,
                        child: const Center(child: Icon(Icons.play_circle_fill_rounded, size: 54, color: Colors.white70)),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: cloudinarySized(item.url, width: 900),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, _) => Container(color: d.field, child: const Center(child: CircularProgressIndicator(strokeWidth: 2))),
                      errorWidget: (_, _, _) => Container(color: d.field, child: Center(child: Icon(Icons.broken_image_outlined, color: d.muted))),
                    ),
            ),
          ),
      ]),
    );
  }

  Widget _instructionsPane() {
    final d = context.d;
    final text = widget.ticket.instructions?.trim() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      DNote(title: context.ts.dispatchAdminDirectivesTitle, body: text.isEmpty ? context.ts.dispatchNoDirectives : text),
      const SizedBox(height: 12),
      Text(context.ts.dispatchResponderNote,
          style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5).copyWith(fontStyle: FontStyle.italic)),
    ]);
  }

  /// Reroute: are you sure, why, Confirm / Cancel. Logged and final.
  Widget _reroutePane() {
    final d = context.d;
    final red = d.dark ? const Color(0xFFFF8A8A) : DColors.red;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(context.ts.dispatchRerouteConfirmTitle, style: DType.h2(red)),
      const SizedBox(height: 6),
      Text(context.ts.dispatchRerouteConfirmBody, style: DType.body(d.ink2, size: 14)),
      const SizedBox(height: 16),
      Text(context.ts.dispatchRerouteReasonLabel, style: DType.body(d.ink, size: 14.5, w: FontWeight.w800)),
      const SizedBox(height: 8),
      TextField(
        controller: _reason,
        enabled: !_busy,
        maxLength: 200,
        minLines: 3,
        maxLines: 6,
        onChanged: (_) => setState(() => _error = null),
        style: DType.body(d.ink, size: 14.5),
        decoration: InputDecoration(
          hintText: context.ts.dispatchInputHint,
          hintStyle: DType.body(d.muted, size: 14),
          filled: true,
          fillColor: d.field,
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: red, width: 2)),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 4),
        Text(_error!, style: DType.body(red, size: 12.5, w: FontWeight.w700)),
      ],
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: DButton(context.ts.dispatchCancel,
              kind: DButtonKind.ghost,
              expand: true,
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _pane = _Pane.order;
                        _error = null;
                      })),
        ),
        const SizedBox(width: 10),
        Expanded(child: DButton(context.ts.dispatchConfirm, kind: DButtonKind.danger, expand: true, busy: _busy, onTap: _busy ? null : _reroute)),
      ]),
    ]);
  }

  /// Accepted (Ace, 4 Oct): a green top with the tick, the case and that
  /// the barangay can see it; what happens next in three steps; the
  /// admin's directives; then I'm on the way (straight into Navigate) or
  /// Not yet (the job page).
  Widget _acceptedScreen() {
    final d = context.d;
    final s = context.ts;
    final near = _report?['location_label'] as String?;
    final instructions = widget.ticket.instructions?.trim() ?? '';
    Widget step(int n, Color c, String title, String sub) => DSheet(
          radius: 14,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c),
              child: Center(child: Text('$n', style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: DType.body(d.ink, size: 15, w: FontWeight.w700)),
                Text(sub, style: DType.body(d.muted, size: 12.5)),
              ]),
            ),
          ]),
        );
    final cs = d.steps;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _toWindow();
      },
      child: Scaffold(
        backgroundColor: d.bg,
        body: Column(children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF2BC46B), Color(0xFF1F8A45), Color(0xFF146B33)]),
              boxShadow: [BoxShadow(color: Color(0x591F8A45), blurRadius: 30, offset: Offset(0, 12))],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              // centred (Rose, 16 Nov 2026: "ala sha sa gitna"): the Stack had no alignment and its Column shrank to the left
              child: Stack(alignment: Alignment.topCenter, children: [
                Positioned.fill(
                  child: Image.asset('assets/images/texture.png', fit: BoxFit.cover, color: Colors.white.withValues(alpha: .10), colorBlendMode: BlendMode.srcIn),
                ),
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      const SizedBox(width: double.infinity),
                      const _AcceptedTick(),
                      const SizedBox(height: 14),
                      Text(context.tr('Dispatch accepted', 'Tinanggap ang dispatch'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Inter Tight', fontWeight: FontWeight.w900, fontSize: 30, color: Colors.white)),
                      const SizedBox(height: 4),
                      Text(widget.ticket.subject,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontFamily: 'Inter Tight', fontWeight: FontWeight.w800, fontSize: 19, color: Colors.white)),
                      Text(
                        near != null && near.isNotEmpty ? '${widget.ticket.trackingId} · ${s.dispatchNear(near)}' : widget.ticket.trackingId,
                        textAlign: TextAlign.center,
                        style: DType.mono(Colors.white.withValues(alpha: .88), size: 13),
                      ),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              children: [
                Text(context.tr('WHAT’S NEXT', 'SUSUNOD'), style: DType.label(d.muted)),
                const SizedBox(height: 10),
                step(1, cs[1], context.tr('Tap I’m on the way when you leave', 'Pindutin ang Papunta na ako pag-alis mo'),
                    context.tr('The app shows you the way there.', 'Ituturo ng app ang daan.')),
                const SizedBox(height: 8),
                step(2, cs[2], context.tr('Tap I’ve arrived at the place', 'Pindutin ang Nandito na ako pagdating'),
                    context.tr('It turns on once you’re there.', 'Bubukas ito pagdating mo.')),
                const SizedBox(height: 8),
                step(3, cs[3], context.tr('Resolve with a photo', 'Iresolba nang may litrato'),
                    context.tr('The barangay approves it.', 'Aaprubahan ito ng barangay.')),
                const SizedBox(height: 12),
                DNote(title: s.dispatchAdminDirectivesTitle, body: instructions.isEmpty ? s.dispatchNoDirectives : instructions),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: d.card, border: Border(top: BorderSide(color: d.line))),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DButton(s.windowActionOnTheWay, expand: true, height: 54, radius: 16, fontSize: 17, busy: _acting, onTap: _acting ? null : () => _toWindow(startOnTheWay: true)),
                  const SizedBox(height: 8),
                  // Rose's Figma: an outlined Open the job, not a quiet text link
                  DButton(context.tr('Open the job', 'Buksan ang trabaho'), kind: DButtonKind.line, expand: true, height: 46, radius: 16, onTap: _toWindow),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

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
        fontFamily: 'Inter',
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
                  fontFamily: 'Inter',
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

/// The frames' pill: [colour] filled with a 1px #F3F3F3 edge and the
/// design shadow, 14/700 (112x37) by default; [filled] false draws the
/// light twin — #FBFBFB with a [colour] edge and label.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.colour,
    required this.onTap,
    this.width = 112,
    this.fontSize = 14,
  });

  final String label;
  final Color colour;
  final VoidCallback? onTap;
  bool get filled => true;
  final double width;
  final double height = 37;
  final double radius = 50;
  final double fontSize;

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
              fontFamily: 'Inter',
              fontWeight: FontWeight.w700,
              fontSize: fontSize,
            ),
          ),
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

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

  // P1 (Ace, 7 Oct 2026): the shared popup card, the box inside it.
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    final d = context.d;
    return FigmaDialog(
      title: s.dispatchRequestDetailsTitle,
      icon: Icons.help_outline_rounded,
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: 200,   // the Figma's 0/200
        minLines: 3,
        maxLines: 5,
        onChanged: (_) => setState(() {}),
        style: DType.body(d.ink, size: 14.5),
        decoration: InputDecoration(
          hintText: s.dispatchRequestDetailsHint,
          hintStyle: DType.body(d.muted, size: 14),
          filled: true,
          fillColor: d.field,
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: d.line)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: DColors.orange, width: 2)),
        ),
      ),
      primaryLabel: s.dispatchRequestDetailsSend,
      onPrimary: _text.text.trim().isEmpty ? null : () => Navigator.of(context).pop(_text.text.trim()),
      secondaryLabel: context.tr('Back', 'Bumalik'),   // the Figma's Send / Back
      onSecondary: () => Navigator.of(context).pop(),
    );
  }
}


/// The tick on Dispatch accepted: a white disc that pops in, the check
/// drawing itself, two rings rippling out.
class _AcceptedTick extends StatefulWidget {
  const _AcceptedTick();

  @override
  State<_AcceptedTick> createState() => _AcceptedTickState();
}

class _AcceptedTickState extends State<_AcceptedTick> with TickerProviderStateMixin {
  late final _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  late final _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _pop.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pop, _ripple]),
        builder: (_, _) {
          final p = Curves.elasticOut.transform((_pop.value / .7).clamp(0.0, 1.0));
          final tick = ((_pop.value - .45) / .55).clamp(0.0, 1.0);
          Widget ring(double phase) {
            final t = (_ripple.value + phase) % 1;
            return Transform.scale(
              scale: .7 + .65 * t,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: .55 * (1 - t)), width: 3)),
              ),
            );
          }

          return Stack(fit: StackFit.expand, children: [
            ring(0),
            ring(.5),
            Center(
              child: Transform.scale(
                scale: p,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Color(0x2E000000), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: CustomPaint(painter: _TickPainter(tick)),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .28, size.height * .52)
      ..lineTo(size.width * .44, size.height * .67)
      ..lineTo(size.width * .74, size.height * .36);
    final paint = Paint()
      ..color = const Color(0xFF1F8A45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final m in path.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * t), paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.t != t;
}
