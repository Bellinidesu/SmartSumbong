// SmartSumbong — ticket detail.
//
// "View Ticket Details" plus the three actions that hang off it:
// Accept Dispatch Ticket, Reroute Dispatch Ticket, Upload Report Status
// to Admin.
//
// Every mutation goes through an RPC. dispatches_admin_write is the only
// direct-write policy on the table, and the comment in 0003 says so
// plainly: a tanod acts through accept_dispatch(), reroute_dispatch()
// and submit_field_report(), never by UPDATE. Each validates that the
// caller owns the dispatch and that it is in a state the action makes
// sense from, and raises otherwise — so the error text below is
// reporting a real refusal, not guessing at one.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'tickets_screen.dart';

const _cloudName = String.fromEnvironment('CLOUDINARY_CLOUD_NAME');
const _uploadPreset = String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

class TicketScreen extends StatefulWidget {
  const TicketScreen({super.key, required this.ticket});

  final Ticket ticket;

  @override
  State<TicketScreen> createState() => _TicketScreenState();
}

class _TicketScreenState extends State<TicketScreen> {
  Map<String, dynamic>? _report;
  List<String> _evidence = const [];
  bool _loading = true;
  bool _busy = false;
  bool _changed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;

      // reports_resident_read admits the assigned tanod, and
      // report_media_read admits them to the resident's evidence.
      final report = await client
          .from('reports')
          .select('tracking_id, subject, description, category, '
              'latitude, longitude, created_at, status, is_anonymous')
          .eq('id', widget.ticket.reportId)
          .single();

      final media = await client
          .from('report_media')
          .select('media_url')
          .eq('report_id', widget.ticket.reportId);

      if (!mounted) return;
      setState(() {
        _report = report;
        _evidence = [for (final m in media) m['media_url'] as String];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this ticket.';
      });
    }
  }

  Future<void> _accept() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc('accept_dispatch',
          params: {'p_dispatch': widget.ticket.dispatchId});
      if (!mounted) return;
      _changed = true;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        // The RPC raises this when the row is gone, belongs to someone
        // else, or has already moved on — most often because the accept
        // window expired while the ticket sat open.
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
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => const _RerouteSheet(),
    );
    if (reason == null || reason.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // p_to omitted: the ticket returns to the admin queue rather than
      // being handed to a named tanod. A tanod cannot see the roster or
      // who is free, so choosing a colleague would be a guess.
      await Supabase.instance.client.rpc('reroute_dispatch', params: {
        'p_dispatch': widget.ticket.dispatchId,
        'p_reason': reason.trim(),
      });
      if (!mounted) return;
      _changed = true;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not reroute this ticket. Please try again.';
      });
    }
  }

  Future<void> _resolve() async {
    final result = await showModalBottomSheet<_Resolution>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tokens.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => const _ResolveSheet(),
    );
    if (result == null || result.text.trim().isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;

      // Photos first, the RPC last. submit_field_report() closes the
      // dispatch and moves the report to resolved; if that ran and the
      // upload then failed, the case would be closed with the proof
      // missing and no way for the tanod to add it — resolved
      // dispatches are not editable. This way a failure leaves
      // everything untouched and the tanod simply tries again.
      if (result.photos.isNotEmpty) {
        final uploader = MediaUploader(
          cloudName: _cloudName,
          uploadPreset: _uploadPreset,
        );

        final rows = <Map<String, dynamic>>[];
        for (final f in result.photos) {
          final up = await uploader.upload(f, kind: MediaKind.fieldProof);
          rows.add({
            'dispatch_id': widget.ticket.dispatchId,
            ...up.toJson(),
          });
        }
        await client.from('dispatch_media').insert(rows);
      }

      await client.rpc('submit_field_report', params: {
        'p_dispatch': widget.ticket.dispatchId,
        'p_text': result.text.trim(),
      });

      if (!mounted) return;
      _changed = true;
      Navigator.of(context).pop(true);
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final r = _report;
    final ticket = widget.ticket;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (_, __) {},
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Tokens.bg,
          foregroundColor: Tokens.navy,
          elevation: 0,
          title: Text('Ticket', style: t.headlineLarge?.copyWith(fontSize: 20)),
          leading: BackButton(
            onPressed: () => Navigator.of(context).pop(_changed),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                      decoration: BoxDecoration(
                        color: Tokens.navy,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '(${ticket.trackingId}) ${ticket.subject}',
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              height: 1.25,
                              color: Tokens.bg,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '\u201C${r?['description'] ?? ''}\u201D',
                            style: const TextStyle(
                                fontSize: 13,
                                height: 1.4,
                                color: Tokens.bg),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    if (ticket.instructions?.trim().isNotEmpty ?? false) ...[
                      _Section(title: 'Instructions from the admin'),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Tokens.field,
                          border: Border.all(color: Tokens.navy),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          ticket.instructions!,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.4,
                              color: Tokens.navy),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    _Section(title: 'Where'),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: 200,
                        child: _map(r),
                      ),
                    ),
                    const SizedBox(height: 18),

                    if (_evidence.isNotEmpty) ...[
                      _Section(title: 'What the resident sent'),
                      SizedBox(
                        height: 110,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _evidence.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) => ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.network(
                              _evidence[i],
                              width: 140,
                              height: 110,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 140,
                                color: Tokens.field,
                                child: const Center(
                                  child: Icon(Icons.broken_image_outlined,
                                      color: Tokens.muted),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],

                    if (_error != null) ...[
                      Text(_error!,
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Tokens.hint)),
                      const SizedBox(height: 12),
                    ],

                    if (ticket.awaitingResponse) ...[
                      FilledButton(
                        onPressed: _busy ? null : _accept,
                        style: FilledButton.styleFrom(
                          backgroundColor: Tokens.orange,
                          foregroundColor: Tokens.navy,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Tokens.navy),
                              )
                            : const Text('Accept Ticket'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _busy ? null : _reroute,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Reroute'),
                      ),
                    ] else ...[
                      FilledButton(
                        onPressed: _busy ? null : _resolve,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Tokens.bg),
                              )
                            : const Text('Submit Resolution'),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _map(Map<String, dynamic>? r) {
    final lat = (r?['latitude'] as num?)?.toDouble();
    final lon = (r?['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) {
      return Container(
        color: Tokens.field,
        child: const Center(
          child: Text('No location on this report',
              style: TextStyle(fontSize: 12, color: Tokens.muted)),
        ),
      );
    }

    final at = LatLng(lat, lon);
    return FlutterMap(
      options: MapOptions(
        initialCenter: at,
        initialZoom: 17,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'ph.smartsumbong.tanod',
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: at,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on,
                  size: 40, color: Tokens.navy),
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: Tokens.navy,
          ),
        ),
      );
}

/// Reroute. The justification is mandatory in the database — 0002 has a
/// CHECK that a rerouted row cannot exist without a reason, and the RPC
/// raises before touching anything if the text is blank. Enforced here
/// too so the tanod is told before the round trip.
class _RerouteSheet extends StatefulWidget {
  const _RerouteSheet();

  @override
  State<_RerouteSheet> createState() => _RerouteSheetState();
}

class _RerouteSheetState extends State<_RerouteSheet> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Reroute this ticket',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'The ticket goes back to the admin queue. Say why so whoever '
            'picks it up next knows what you found.',
            style:
                TextStyle(fontSize: 12, height: 1.4, color: Tokens.muted),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reason,
            maxLines: 3,
            maxLength: 200,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Reason for rerouting',
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          if (_error != null)
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: Tokens.hint)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    if (_reason.text.trim().isEmpty) {
                      setState(() =>
                          _error = 'A reason is required to reroute.');
                      return;
                    }
                    Navigator.of(context).pop(_reason.text);
                  },
                  child: const Text('Reroute'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the resolve sheet hands back.
class _Resolution {
  const _Resolution(this.text, this.photos);

  final String text;
  final List<File> photos;
}

/// Resolution: the narrative plus photo proof.
///
/// "Upload Report Status to Admin" asks for both, and 0024 already lets
/// the filing resident see the proof on their own resolved complaint —
/// so this is the photo that answers "was it actually fixed?" rather
/// than an internal record.
///
/// Photos are optional. A tanod who resolved something with nothing to
/// show for it — moved an obstruction, spoke to a neighbour — should not
/// be blocked from closing the ticket, and blocking would only teach
/// them to photograph something irrelevant.
class _ResolveSheet extends StatefulWidget {
  const _ResolveSheet();

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

class _ResolveSheetState extends State<_ResolveSheet> {
  final _text = TextEditingController();
  final _photos = <File>[];
  final _picker = ImagePicker();
  String? _error;

  static const _maxPhotos = 3;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _add(ImageSource source) async {
    if (_photos.length >= _maxPhotos) return;
    try {
      final x = await _picker.pickImage(source: source, imageQuality: 90);
      if (x == null || !mounted) return;
      setState(() {
        _photos.add(File(x.path));
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the camera.');
    }
  }

  void _pickSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.bg,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: Tokens.navy),
              title: const Text('Take a photo'),
              onTap: () {
                Navigator.of(sheet).pop();
                _add(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined, color: Tokens.navy),
              title: const Text('Choose from gallery'),
              onTap: () {
                Navigator.of(sheet).pop();
                _add(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Submit your resolution',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: Tokens.navy,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Describe what you found and what was done. The resident '
              'sees the barangay\u2019s update and any photos you attach.',
              style: TextStyle(fontSize: 12, height: 1.4, color: Tokens.muted),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _text,
              maxLines: 4,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What did you find and do?',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 6),

            const Text(
              'Photo proof (optional)',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Tokens.navy,
              ),
            ),
            const SizedBox(height: 8),

            SizedBox(
              height: 84,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _photos.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              _photos[i],
                              width: 84,
                              height: 84,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: -6,
                            right: -6,
                            child: Material(
                              color: Tokens.navy,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () =>
                                    setState(() => _photos.removeAt(i)),
                                child: const Padding(
                                  padding: EdgeInsets.all(3),
                                  child: Icon(Icons.close,
                                      size: 15, color: Tokens.bg),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_photos.length < _maxPhotos)
                    InkWell(
                      onTap: _pickSource,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          border: Border.all(color: Tokens.navy),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.add,
                            size: 26, color: Tokens.navy),
                      ),
                    ),
                ],
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(fontSize: 12, color: Tokens.hint)),
            ],
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_text.text.trim().isEmpty) {
                        setState(() =>
                            _error = 'Please describe what was done.');
                        return;
                      }
                      Navigator.of(context).pop(
                        _Resolution(_text.text, List.of(_photos)),
                      );
                    },
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
