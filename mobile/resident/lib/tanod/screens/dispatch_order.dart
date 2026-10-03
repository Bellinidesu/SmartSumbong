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
import '../../i18n.dart' show AppLocale;
import '../navigation.dart';
import '../tanod_outbox.dart';
import '../../outbox.dart' show Outbox;

import '../tanod_strings.dart';
import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../../d/d_categories.dart';
import '../../models/complaint_category.dart';
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
              'latitude, longitude, location_label, is_anonymous, category',
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

  // Branch D: the dispatch order is the preview's full page — the case's
  // category colour across the top, DISPATCH ORDER, the subject, three
  // round actions (map, media, instructions), the details, the admin's
  // directives, and Reroute / Accept pinned at the bottom. Accept goes
  // straight on to the job page.
  @override
  Widget build(BuildContext context) {
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
              // the category header
              SizedBox(
                height: 170 + MediaQuery.paddingOf(context).top,
                child: Stack(children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color.lerp(col, Colors.white, .12)!, col, Color.lerp(col, Colors.black, .28)!],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Image.asset('assets/images/texture.png',
                        fit: BoxFit.cover, color: Colors.white.withValues(alpha: .14), colorBlendMode: BlendMode.srcIn),
                  ),
                  Positioned(
                    left: 12,
                    top: MediaQuery.paddingOf(context).top + 8,
                    child: DBack(onImage: true, onTap: order ? _close : () => setState(() => _pane = _Pane.order)),
                  ),
                  if (_report != null)
                    Positioned(
                      left: 16,
                      bottom: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .35), borderRadius: BorderRadius.circular(99)),
                        child: Text(cat.label, style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 11.5, color: Colors.white)),
                      ),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                child: _body(),
              ),
            ]),
          ),
          if (order) _orderBar(),
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
    _Pane.accepted => _acceptedPane(),
  };

  // ---------- panes ---------------------------------------------

  /// DISPATCH ORDER, the subject, the ticket and when it was filed.
  Widget _header() {
    final d = context.d;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(context.tr('DISPATCH ORDER', 'DISPATCH ORDER'), style: DType.label(d.muted)),
      const SizedBox(height: 4),
      Text(widget.ticket.subject, style: DType.h1(d.ink).copyWith(fontSize: 24)),
      const SizedBox(height: 3),
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
                DWell(icon, size: 46),
                const SizedBox(height: 6),
                Text(label, textAlign: TextAlign.center, style: DType.body(d.link, size: 12.5, w: FontWeight.w800)),
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
        child: Row(children: [
          act(Icons.map_outlined, context.ts.reportsViewMap, () => setState(() => _pane = _Pane.map)),
          act(Icons.photo_library_outlined, context.ts.reportsViewMedia, () => setState(() => _pane = _Pane.media)),
          act(Icons.assignment_outlined, context.ts.reportsViewInstructions, () => setState(() => _pane = _Pane.instructions)),
        ]),
      ),
      if (near != null && near.isNotEmpty)
        DRow(icon: Icons.place_outlined, title: context.ts.dispatchNear(near), sub: _routeLine ?? 'Barangay 183'),
      // "Complainant: Anonymous" on every row, and not because every
      // complaint is anonymous — users_self_read is `id = auth.uid() or
      // is_admin()`, so a tanod cannot read the filer's row at all.
      DRow(icon: Icons.person_outline_rounded, title: '${context.ts.dispatchComplainantLabel}${context.ts.reportsFilerAnonymous}'),
      DRow(icon: Icons.event_outlined, title: '${context.ts.reportsDeadlineLabel}${_deadlineOf(widget.ticket.dueAt)}'),
      const SizedBox(height: 12),
      Text('“${widget.ticket.description}”', style: DType.body(d.ink2, size: 14.5)),
      const SizedBox(height: 14),
      DNote(
        title: context.ts.dispatchAdminDirectivesTitle,
        body: instructions.isEmpty ? context.ts.dispatchNoDirectives : instructions,
      ),
      if (_error != null) ...[
        const SizedBox(height: 10),
        Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 12.5, w: FontWeight.w700)),
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
                pins: [BrgyMapPin(id: 'case', point: p)],
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

  /// Accepted: straight on to the job page (one frame of the message, for
  /// the slow phone that is still pushing).
  Widget _acceptedPane() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pane == _Pane.accepted) _toWindow();
    });
    final d = context.d;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(children: [
        const Icon(Icons.task_alt_rounded, size: 56, color: DColors.greenVivid),
        const SizedBox(height: 12),
        Text(context.ts.dispatchAcceptedTitle(widget.ticket.trackingId, widget.ticket.subject), textAlign: TextAlign.center, style: DType.h2(d.ink)),
        const SizedBox(height: 6),
        Text(context.ts.dispatchAcceptedBody, textAlign: TextAlign.center, style: DType.body(d.muted, size: 14)),
      ]),
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
