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

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
// latlong2 exports its own generic Path<LatLng>, which shadows the one
// in dart:ui and breaks the dashed border below. The resident map screen
// hides it the same way.
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'tickets_screen.dart';

const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

const _red = Color(0xFFFF4949);
const _green = Color(0xFF1FA84E);

/// Which body the card is showing.
enum _Pane {
  order,
  map,
  media,
  instructions,
  rerouteConfirm,
  accepted,
  update,
  submitted,
}

/// Opens the dispatch order over whatever is behind it. Returns true if
/// anything changed, so the caller can reload.
Future<bool> showDispatchOrder(BuildContext context, Ticket ticket) async {
  final changed = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: const Color(0x66FFFFFF),
    barrierLabel: 'Dispatch order',
    pageBuilder: (_, __, ___) => _DispatchOrder(ticket: ticket),
  );
  return changed ?? false;
}

class _DispatchOrder extends StatefulWidget {
  const _DispatchOrder({required this.ticket});

  final Ticket ticket;

  @override
  State<_DispatchOrder> createState() => _DispatchOrderState();
}

class _DispatchOrderState extends State<_DispatchOrder> {
  _Pane _pane = _Pane.order;

  /// Where View Map / View Attached Media / View Instructions return to.
  /// Usually [_Pane.order] — but an already-accepted ticket opens
  /// straight into [_Pane.update] (see initState), and a tanod who taps
  /// View Map from there and then Back should land back on the update
  /// form, not on the order pane's Accept/Reroute buttons, which would
  /// raise on a ticket that is not in 'pending' any more.
  _Pane _returnPane = _Pane.order;

  Map<String, dynamic>? _report;
  List<({String url, bool isVideo})> _evidence = const [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  final _reason = TextEditingController();
  final _update = TextEditingController();
  final _photos = <File>[];

  // Optional field-proof video. One only — dispatch_media has no
  // notion of "several videos" the way it does photos, and a tanod
  // filing an update from the field has neither the time nor the
  // data budget to shoot more than one short clip.
  File? _video;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // Already accepted tickets arrive here from Reports and go straight
    // to the update pane — the order pane's Accept and Reroute would
    // both raise, since neither RPC touches a row in 'accepted'. Kim's
    // note during the QA exchange (26 Aug 2026) was that this pane used
    // to show nothing about what the report even was — see the summary
    // box _updatePane() now opens with, sourced from the same _report /
    // _evidence load() every pane already uses.
    if (widget.ticket.state == DispatchState.accepted) {
      _pane = _Pane.update;
      _returnPane = _Pane.update;
    }
    _load();
  }

  @override
  void dispose() {
    _reason.dispose();
    _update.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final report = await client
          .from('reports')
          .select('tracking_id, subject, description, created_at, '
              'latitude, longitude, is_anonymous')
          .eq('id', widget.ticket.reportId)
          .single();
      final media = await client
          .from('report_media')
          .select('media_url, mime_type')
          .eq('report_id', widget.ticket.reportId);

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

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('accept_dispatch',
          params: {'p_dispatch': widget.ticket.dispatchId});
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
            ? 'This ticket is no longer yours to accept. It may have '
                'timed out or been reassigned.'
            : 'Could not accept this ticket. Please try again.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not accept this ticket. Please try again.';
      });
    }
  }

  Future<void> _reroute() async {
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'A reason is required to reroute.');
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
      await Supabase.instance.client.rpc('reroute_dispatch', params: {
        'p_dispatch': widget.ticket.dispatchId,
        'p_reason': _reason.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reroute this ticket. Please try again.';
      });
    }
  }

  Future<void> _submitUpdate() async {
    if (_update.text.trim().isEmpty) {
      setState(() => _error = 'Please describe what was done.');
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
        final uploader = MediaUploader(
          cloudName: _cloudName,
          uploadPreset: _uploadPreset,
        );
        final rows = <Map<String, dynamic>>[];
        for (final f in _photos) {
          final up = await uploader.upload(f, kind: MediaKind.fieldProof);
          rows.add({
            'dispatch_id': widget.ticket.dispatchId,
            ...up.toJson(),
          });
        }
        if (_video != null) {
          final up =
              await uploader.uploadVideo(_video!, kind: MediaKind.fieldProof);
          rows.add({
            'dispatch_id': widget.ticket.dispatchId,
            ...up.toJson(),
          });
        }
        await client.from('dispatch_media').insert(rows);
      }

      await client.rpc('submit_field_report', params: {
        'p_dispatch': widget.ticket.dispatchId,
        'p_text': _update.text.trim(),
      });

      if (!mounted) return;
      setState(() {
        _busy = false;
        _changed = true;
        _pane = _Pane.submitted;
      });
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${e.message} Your report has not been sent yet.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not submit your report. Please try again.';
      });
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 3) return;
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.camera,
      title: 'Camera access',
      rationale: 'SmartSumbong needs camera access to attach photo proof '
          'to this dispatch.',
    );
    if (!granted || !mounted) return;
    try {
      final x = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 90);
      if (x == null || !mounted) return;
      setState(() {
        _photos.add(File(x.path));
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  Future<void> _addVideo() async {
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.camera,
      title: 'Camera access',
      rationale: 'SmartSumbong needs camera access to attach video proof '
          'to this dispatch.',
    );
    if (!granted || !mounted) return;
    try {
      final uploader = MediaUploader(
        cloudName: _cloudName,
        uploadPreset: _uploadPreset,
      );
      final f = await uploader.pickVideo(source: ImageSource.camera);
      if (f == null || !mounted) return;
      setState(() {
        _video = f;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  void _removeVideo() => setState(() => _video = null);

  void _close() => Navigator.of(context).pop(_changed);

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
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Tokens.bg,
                  border: Border.all(color: reroute ? _red : Tokens.navy,
                      width: 2),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
        _Pane.map => _framed(_mapPane()),
        _Pane.media => _framed(_mediaPane()),
        _Pane.instructions => _framed(_instructionsPane()),
        _Pane.rerouteConfirm => _reroutePane(),
        _Pane.accepted => _acceptedPane(),
        _Pane.update => _updatePane(),
        _Pane.submitted => _submittedPane(),
      };

  // ---------- panes ---------------------------------------------

  Widget _header() => Column(
        children: [
          Text(
            'DISPATCH ORDER:\n${widget.ticket.trackingId}',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              fontSize: 19,
              height: 1.2,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Submitted on: ${_date(_report?['created_at'] as String?)}',
            style: const TextStyle(fontSize: 11, color: Tokens.navy),
          ),
        ],
      );

  /// The map, media and instructions panes are the same card with the
  /// inner box swapped and a single Back.
  Widget _framed(Widget inner) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          const SizedBox(height: 14),
          inner,
          const SizedBox(height: 16),
          _Pill(
            label: 'Back',
            filled: true,
            colour: Tokens.navy,
            onTap: () => setState(() => _pane = _returnPane),
          ),
        ],
      );

  Widget _orderPane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        const SizedBox(height: 14),

        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(color: Tokens.navy),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Complainant: Anonymous" on every row, and not because
              // every complaint is anonymous — users_self_read is
              // `id = auth.uid() or is_admin()`, so a tanod cannot read
              // the filer's row at all. A name here needs that policy
              // loosened, which is the barangay's call.
              _Field(label: 'Complainant: ', value: 'Anonymous'),
              const SizedBox(height: 6),
              _Field(
                label: 'Description: ',
                value: '\u201C${widget.ticket.description}\u201D',
              ),
              const SizedBox(height: 6),
              _Field(
                label: 'Deadline: ',
                value: _dateOf(widget.ticket.dueAt),
              ),
              const SizedBox(height: 10),

              _Link(
                icon: Icons.place_outlined,
                label: 'View Map',
                onTap: () => setState(() {
                  _returnPane = _Pane.order;
                  _pane = _Pane.map;
                }),
              ),
              _Link(
                icon: Icons.camera_alt_outlined,
                label: 'View Attached Media',
                onTap: () => setState(() {
                  _returnPane = _Pane.order;
                  _pane = _Pane.media;
                }),
              ),
              _Link(
                icon: Icons.my_location,
                label: 'View Instructions',
                onTap: () => setState(() {
                  _returnPane = _Pane.order;
                  _pane = _Pane.instructions;
                }),
              ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: _red)),
        ],
        const SizedBox(height: 14),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _Pill(
              label: 'Reroute',
              filled: true,
              colour: _red,
              width: 108,
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _pane = _Pane.rerouteConfirm;
                        _error = null;
                      }),
            ),
            const SizedBox(width: 16),
            _Pill(
              label: 'Accept',
              filled: true,
              colour: _green,
              width: 108,
              busy: _busy,
              onTap: _busy ? null : _accept,
            ),
          ],
        ),
        const SizedBox(height: 10),
        _Pill(
          label: 'Back',
          filled: true,
          colour: Tokens.navy,
          width: 108,
          onTap: _close,
        ),
      ],
    );
  }

  Widget _mapPane() {
    final lat = (_report?['latitude'] as num?)?.toDouble();
    final lon = (_report?['longitude'] as num?)?.toDouble();

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 240,
        width: double.infinity,
        child: lat == null || lon == null
            ? Container(
                color: Tokens.field,
                child: const Center(
                  child: Text('No location on this report',
                      style:
                          TextStyle(fontSize: 12, color: Tokens.muted)),
                ),
              )
            : FlutterMap(
                options: MapOptions(
                  initialCenter: LatLng(lat, lon),
                  initialZoom: 17,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                  ),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'ph.smartsumbong.tanod',
                  ),
                  MarkerLayer(markers: [
                    Marker(
                      point: LatLng(lat, lon),
                      width: 38,
                      height: 38,
                      child: const Icon(Icons.location_on,
                          size: 38, color: Tokens.navy),
                    ),
                  ]),
                ],
              ),
      ),
    );
  }

  Widget _mediaPane() {
    if (_loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_evidence.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: Tokens.field,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('The resident attached no photos.',
              style: TextStyle(fontSize: 12, color: Tokens.muted)),
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: PageView(
        children: [
          for (final item in _evidence)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
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
                          child: Icon(Icons.play_circle_fill,
                              size: 48, color: Colors.white70),
                        ),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: item.url,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      placeholder: (_, __) => Container(
                        color: Tokens.field,
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Tokens.field,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: Tokens.muted),
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

    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        border: Border.all(color: Tokens.navy),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Admin Directives:',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: Tokens.navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              text.isEmpty
                  ? 'The admin left no directives on this ticket. Use your '
                      'judgement and record what you find.'
                  : text,
              style: const TextStyle(
                  fontSize: 11.5, height: 1.45, color: Tokens.navy),
            ),
            const SizedBox(height: 10),
            const Text(
              'Note for Responder: Proceed with caution. Your safety and '
              'the safety of the people at the scene come before the '
              'deadline.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                fontStyle: FontStyle.italic,
                color: _red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reroutePane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Are you sure you want to reroute this assigned complaint to '
          'another Tanod?',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 17,
            height: 1.25,
            color: _red,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'This action cannot be undone and will be logged.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, height: 1.35, color: _red),
        ),
        const SizedBox(height: 14),

        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Please provide your reason',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: _red,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Box(
          colour: _red,
          child: TextField(
            controller: _reason,
            maxLines: 4,
            maxLength: 200,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Input here...',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: _red)),
        ],
        const SizedBox(height: 14),

        _Pill(
          label: 'Confirm',
          filled: true,
          colour: _red,
          busy: _busy,
          onTap: _busy ? null : _reroute,
        ),
        const SizedBox(height: 10),
        _Pill(
          label: 'Cancel',
          filled: false,
          colour: _red,
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

  Widget _acceptedPane() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Text(
            '${widget.ticket.trackingId} - ${widget.ticket.subject} has '
            'been accepted.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              fontSize: 19,
              height: 1.25,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kindly ensure that the necessary actions are taken in a '
            'timely manner.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.4, color: Tokens.navy),
          ),
          const SizedBox(height: 28),
          _Pill(
            label: 'Back',
            filled: true,
            colour: Tokens.navy,
            onTap: _close,
          ),
          const SizedBox(height: 12),
        ],
      );

  Widget _updatePane() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        const SizedBox(height: 12),

        // What Kim's QA note (26 Aug 2026) was missing: an
        // already-accepted ticket used to open straight into this form
        // with no reminder of what the report even was. Same summary
        // box the order pane shows, same _report/_evidence this pane
        // already loads — just never displayed here before.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(color: Tokens.navy),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(label: 'Complainant: ', value: 'Anonymous'),
              const SizedBox(height: 6),
              _Field(
                label: 'Description: ',
                value: '“${widget.ticket.description}”',
              ),
              const SizedBox(height: 6),
              _Field(
                label: 'Deadline: ',
                value: _dateOf(widget.ticket.dueAt),
              ),
              const SizedBox(height: 10),

              _Link(
                icon: Icons.place_outlined,
                label: 'View Map',
                onTap: () => setState(() {
                  _returnPane = _Pane.update;
                  _pane = _Pane.map;
                }),
              ),
              _Link(
                icon: Icons.camera_alt_outlined,
                label: 'View Attached Media',
                onTap: () => setState(() {
                  _returnPane = _Pane.update;
                  _pane = _Pane.media;
                }),
              ),
              _Link(
                icon: Icons.my_location,
                label: 'View Instructions',
                onTap: () => setState(() {
                  _returnPane = _Pane.update;
                  _pane = _Pane.instructions;
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        const Text(
          'Submit an update',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: Tokens.navy,
          ),
        ),
        const SizedBox(height: 14),

        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Please provide a report',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: Tokens.navy,
            ),
          ),
        ),
        const SizedBox(height: 6),
        _Box(
          colour: Tokens.navy,
          child: TextField(
            controller: _update,
            maxLines: 4,
            maxLength: 300,
            enabled: !_busy,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Input here...',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
        ),
        const SizedBox(height: 12),

        Align(
          alignment: Alignment.centerLeft,
          child: const Text(
            'Submit a photo evidence of the complaint response',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
              color: Tokens.navy,
            ),
          ),
        ),
        const SizedBox(height: 8),

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
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(_photos[i],
                          width: 72, height: 62, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: Material(
                        color: Tokens.navy,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: const Padding(
                            padding: EdgeInsets.all(3),
                            child: Icon(Icons.close,
                                size: 14, color: Tokens.bg),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

              // Optional. A tanod who moved an obstruction or spoke to a
              // neighbour has nothing to photograph, and requiring one
              // would only teach them to photograph something else.
              if (_photos.length < 3)
                InkWell(
                  onTap: _busy ? null : _addPhoto,
                  child: CustomPaint(
                    painter: _DashedBorder(colour: Tokens.navy),
                    child: SizedBox(
                      width: 118,
                      height: 62,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Tokens.navy,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.add,
                                size: 14, color: Tokens.bg),
                          ),
                          const SizedBox(width: 6),
                          const Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Attach Media',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    color: Tokens.navy,
                                  )),
                              Text('(Max. 10 MB)',
                                  style: TextStyle(
                                      fontSize: 8, color: Tokens.navy)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Same single-clip reasoning as the resident report screen's
              // _VideoAttach: one optional video, not a strip of them.
              if (_video != null)
                Container(
                  width: 118,
                  height: 62,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Tokens.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Icon(Icons.videocam, color: Tokens.navy, size: 18),
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Text('Video attached',
                              style:
                                  TextStyle(fontSize: 9, color: Tokens.navy)),
                        ),
                      ),
                      InkWell(
                        onTap: _removeVideo,
                        child: const Icon(Icons.close,
                            size: 14, color: Tokens.navy),
                      ),
                    ],
                  ),
                )
              else
                InkWell(
                  onTap: _busy ? null : _addVideo,
                  child: CustomPaint(
                    painter: _DashedBorder(colour: Tokens.navy),
                    child: SizedBox(
                      width: 118,
                      height: 62,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: Tokens.navy,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.videocam,
                                size: 14, color: Tokens.bg),
                          ),
                          const SizedBox(width: 6),
                          const Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Attach Video',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                    color: Tokens.navy,
                                  )),
                              Text('(Max. 25 MB)',
                                  style: TextStyle(
                                      fontSize: 8, color: Tokens.navy)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: _red)),
        ],
        const SizedBox(height: 16),

        _Pill(
          label: 'Submit',
          filled: true,
          colour: Tokens.navy,
          busy: _busy,
          onTap: _busy ? null : _submitUpdate,
        ),
        const SizedBox(height: 8),
        _Pill(
          label: 'Back',
          filled: false,
          colour: Tokens.navy,
          onTap: _busy ? null : _close,
        ),
      ],
    );
  }

  Widget _submittedPane() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          Text(
            '${widget.ticket.trackingId}\nReport has been submitted.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w800,
              fontSize: 19,
              height: 1.3,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 28),
          _Pill(
            label: 'Back',
            filled: true,
            colour: Tokens.navy,
            onTap: _close,
          ),
          const SizedBox(height: 12),
        ],
      );

  // ---------- dates ---------------------------------------------

  static String _date(String? iso) => _dateOf(DateTime.tryParse(iso ?? ''));

  static String _dateOf(DateTime? d) {
    if (d == null) return 'not set';
    const m = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final l = d.toLocal();
    return '${m[l.month - 1]} ${l.day}, ${l.year}';
  }
}

// ---------- small parts ----------------------------------------

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 11, height: 1.4, color: Tokens.navy),
          children: [
            TextSpan(
                text: label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      );
}

class _Link extends StatelessWidget {
  const _Link({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Icon(icon, size: 15, color: Tokens.navy),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Tokens.navy,
                  decoration: TextDecoration.underline,
                  decorationColor: Tokens.navy,
                ),
              ),
            ],
          ),
        ),
      );
}

class _Box extends StatelessWidget {
  const _Box({required this.colour, required this.child});

  final Color colour;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        decoration: BoxDecoration(
          border: Border.all(color: colour),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.filled,
    required this.colour,
    required this.onTap,
    this.width,
    this.busy = false,
  });

  final String label;
  final bool filled;
  final Color colour;
  final VoidCallback? onTap;
  final double? width;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final shape =
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(50));
    final child = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: filled ? Tokens.bg : colour),
          )
        : Text(label);

    final button = filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: colour,
              foregroundColor: Tokens.bg,
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: shape,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: colour,
              side: BorderSide(color: colour, width: 1.5),
              minimumSize: const Size(0, 40),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              shape: shape,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            child: child,
          );

    return width == null
        ? SizedBox(width: double.infinity, child: button)
        : SizedBox(width: width, child: button);
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
      const Radius.circular(10),
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
