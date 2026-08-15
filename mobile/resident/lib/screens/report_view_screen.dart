// SmartSumbong — View a report.
//
// Figma 2436:752 (Under Review), 2613:773 (In Progress), 2461:490
// (Completed), 2613:616 (Rejected), 2461:382 (Cancelled), and the photo
// viewer from 2613:709.
//
// ONE SCREEN, NOT SIX. Rose drew a frame per state, but they differ only
// in the status word, which actions the menu offers, and one line of
// copy underneath. Six files would drift apart the first time the card
// styling changed; this reads the status and says the right thing.
//
// WHAT THE RESIDENT SEES BEYOND THE DESIGN. The status timeline comes
// from status_logs, which the Track Complaint Status use case describes
// as "a linear progress timeline showing tracking updates" and which
// status_logs_read already permits. Rose's frames do not show it, so it
// sits below the fold as history rather than competing with the card.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'reports_screen.dart' show ReportStatus;

class ReportViewScreen extends StatefulWidget {
  const ReportViewScreen({super.key, required this.reportId});

  final String reportId;

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  Map<String, dynamic>? _report;
  List<String> _photos = const [];
  List<String> _proof = const [];
  List<Map<String, dynamic>> _timeline = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    setState(() => _error = null);

    try {
      final r = await client
          .from('reports')
          .select('id, tracking_id, subject, description, status, '
              'latitude, longitude, is_anonymous, created_at, '
              'resolved_at, closed_at, reopened_count')
          .eq('id', widget.reportId)
          .maybeSingle();

      if (r == null) {
        setState(() => _error = 'That report could not be found.');
        return;
      }

      final media = await client
          .from('report_media')
          .select('media_url')
          .eq('report_id', widget.reportId);

      // Proof of resolution, readable by the resident since 0024. A
      // resident told their complaint was fixed should be able to see
      // the fix.
      final proof = await client
          .from('dispatch_media')
          .select('media_url, dispatches!inner(report_id)')
          .eq('dispatches.report_id', widget.reportId);

      final logs = await client
          .from('status_logs')
          .select('old_status, new_status, remark, created_at')
          .eq('report_id', widget.reportId)
          .order('created_at');

      if (!mounted) return;
      setState(() {
        _report = r;
        _photos = [for (final m in media) m['media_url'] as String];
        _proof = [for (final m in proof) m['media_url'] as String];
        _timeline = List<Map<String, dynamic>>.from(logs);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load this report. Pull to retry.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        surfaceTintColor: Tokens.bg,
        elevation: 0,
        foregroundColor: Tokens.navy,
        title: Text('View your Reports',
            style: t.labelLarge?.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: Tokens.navy,
          child: _body(t),
        ),
      ),
    );
  }

  Widget _body(TextTheme t) {
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Tokens.hint)),
      ]);
    }
    if (_report == null) {
      return const Center(child: CircularProgressIndicator(color: Tokens.navy));
    }

    final r = _report!;
    final status = ReportStatus.parse(r['status'] as String?);
    final lat = (r['latitude'] as num?)?.toDouble();
    final lng = (r['longitude'] as num?)?.toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(44, 8, 44, 32),
      children: [
        _ReportCard(
          trackingId: r['tracking_id'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          description: r['description'] as String? ?? '',
          status: status,
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
          isAnonymous: r['is_anonymous'] == true,
          latitude: lat,
          longitude: lng,
          photos: _photos,
          onViewPhoto: (i) => _openPhoto(_photos, i),
        ),

        // The line under the card, which is the only real difference
        // between Rose's six frames.
        const SizedBox(height: 12),
        _StatusNote(
          status: status,
          hasProof: _proof.isNotEmpty,
          reopenedCount: (r['reopened_count'] as num?)?.toInt() ?? 0,
          onViewProof: () => _openPhoto(_proof, 0),
        ),

        if (_timeline.isNotEmpty) ...[
          const SizedBox(height: 28),
          Text('History', style: t.labelLarge?.copyWith(fontSize: 16)),
          const SizedBox(height: 12),
          _Timeline(entries: _timeline),
        ],
      ],
    );
  }

  void _openPhoto(List<String> urls, int index) {
    if (urls.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoViewer(urls: urls, initial: index),
    ));
  }
}

// ---------- pieces -------------------------------------------

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.trackingId,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.isAnonymous,
    required this.latitude,
    required this.longitude,
    required this.photos,
    required this.onViewPhoto,
  });

  final String trackingId;
  final String subject;
  final String description;
  final ReportStatus status;
  final DateTime? createdAt;
  final bool isAnonymous;
  final double? latitude;
  final double? longitude;
  final List<String> photos;
  final ValueChanged<int> onViewPhoto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 16),
      decoration: BoxDecoration(
        color: Tokens.navy,
        border: Border.all(color: Tokens.bg),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 2.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: '('),
              TextSpan(
                text: '$trackingId - ${status.label}',
                style: TextStyle(color: status.labelColour),
              ),
              const TextSpan(text: ') '),
              TextSpan(text: subject),
            ]),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              height: 1.1,
              color: Tokens.bg,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                createdAt == null
                    ? ''
                    : 'Submitted on ${_formatDate(createdAt!)}',
                style: const TextStyle(fontSize: 12, color: Tokens.bg),
              ),
              if (isAnonymous) ...[
                const SizedBox(width: 8),
                const Icon(Icons.visibility_off_outlined,
                    size: 13, color: Tokens.bg),
                const SizedBox(width: 3),
                const Text('Anonymous',
                    style: TextStyle(fontSize: 11, color: Tokens.bg)),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '\u201C$description\u201D',
            style: const TextStyle(
                fontSize: 12, height: 1.25, color: Tokens.bg),
          ),

          if (latitude != null && longitude != null) ...[
            const SizedBox(height: 14),
            _MiniMap(point: LatLng(latitude!, longitude!)),
          ],

          if (photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 134,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => onViewPhoto(i),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.network(
                      photos[i],
                      width: 200,
                      height: 134,
                      fit: BoxFit.cover,
                      loadingBuilder: (_, child, progress) => progress == null
                          ? child
                          : Container(
                              width: 200,
                              height: 134,
                              color: Tokens.bg.withValues(alpha: 0.2),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: Tokens.bg, strokeWidth: 2),
                              ),
                            ),
                      errorBuilder: (_, __, ___) => Container(
                        width: 200,
                        height: 134,
                        color: Tokens.bg.withValues(alpha: 0.15),
                        child: const Icon(Icons.broken_image_outlined,
                            color: Tokens.bg),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime utc) {
    final d = utc.toLocal();
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

/// Where the complaint was filed. Not interactive — the resident chose
/// this pin already, and letting them drag it here would imply they
/// could still change it.
class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.point});
  final LatLng point;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(25),
      child: Container(
        height: 189,
        decoration: BoxDecoration(
          border: Border.all(color: Tokens.bg),
          borderRadius: BorderRadius.circular(25),
        ),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 17,
            interactionOptions:
                const InteractionOptions(flags: InteractiveFlag.none),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'ph.smartsumbong.resident',
              maxZoom: 19,
            ),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: 36,
                height: 36,
                alignment: Alignment.topCenter,
                child: const Icon(Icons.location_on,
                    size: 36, color: Tokens.navy),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The one line that differs between Rose's six frames.
class _StatusNote extends StatelessWidget {
  const _StatusNote({
    required this.status,
    required this.hasProof,
    required this.reopenedCount,
    required this.onViewProof,
  });

  final ReportStatus status;
  final bool hasProof;
  final int reopenedCount;
  final VoidCallback onViewProof;

  @override
  Widget build(BuildContext context) {
    final (text, action) = switch (status) {
      ReportStatus.pendingReview || ReportStatus.validated => (
          'The barangay is reviewing your report.',
          null,
        ),
      ReportStatus.assigned ||
      ReportStatus.inProgress ||
      ReportStatus.offlineInvestigation =>
        ('A barangay tanod has been assigned and is working on this.', null),
      ReportStatus.resolved || ReportStatus.closed || ReportStatus.archived =>
        hasProof
            ? ('Your report has been resolved. ', 'View Photo')
            : ('Your report has been resolved.', null),
      ReportStatus.rejected => (
          'This report was not accepted. Please visit the barangay hall '
              'if you would like to know why.',
          null,
        ),
      ReportStatus.cancelled => (
          'You cancelled this report.',
          null,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          margin: const EdgeInsets.only(left: 40),
          padding: const EdgeInsets.fromLTRB(14, 12, 18, 12),
          decoration: BoxDecoration(
            color: Tokens.field,
            border: Border.all(color: Tokens.navy),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: text),
              if (action != null)
                TextSpan(
                  text: action,
                  style: const TextStyle(
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w700,
                  ),
                  recognizer: null,
                ),
              if (action != null) const TextSpan(text: ' for the proof.'),
            ]),
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontSize: 12, height: 1.25, color: Tokens.navy),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onViewProof,
            child: const Text('View Photo'),
          ),
        if (reopenedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              reopenedCount == 1
                  ? 'This report has been reopened once.'
                  : 'This report has been reopened $reopenedCount times.',
              style: const TextStyle(fontSize: 11, color: Tokens.muted),
            ),
          ),
      ],
    );
  }
}

/// From status_logs. The Track Complaint Status use case calls for "a
/// linear progress timeline showing tracking updates" and "formal
/// remarks appended by responding personnel or administrators".
class _Timeline extends StatelessWidget {
  const _Timeline({required this.entries});
  final List<Map<String, dynamic>> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++)
          _TimelineRow(
            entry: entries[i],
            isFirst: i == 0,
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.isFirst,
    required this.isLast,
  });

  final Map<String, dynamic> entry;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final status = ReportStatus.parse(entry['new_status'] as String?);
    final when = DateTime.tryParse(entry['created_at'] as String? ?? '');
    final remark = entry['remark'] as String?;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: const BoxDecoration(
                    color: Tokens.navy,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  const Expanded(
                    child: VerticalDivider(
                      color: Tokens.navy,
                      thickness: 1,
                      width: 10,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    status.label,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Tokens.navy,
                    ),
                  ),
                  if (when != null)
                    Text(
                      _formatWhen(when),
                      style: const TextStyle(fontSize: 11, color: Tokens.muted),
                    ),
                  if (remark != null && remark.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        remark,
                        style: const TextStyle(
                            fontSize: 12, height: 1.3, color: Tokens.navy),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatWhen(DateTime utc) {
    final d = utc.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h24 = d.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 < 12 ? 'AM' : 'PM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} \u2022 $h12:$mm $ampm';
  }
}

/// Figma 2613:709 — full-screen photo with pinch to zoom.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.urls, required this.initial});

  final List<String> urls;
  final int initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        controller: PageController(initialPage: initial),
        itemCount: urls.length,
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 4,
          child: Center(
            child: Image.network(
              urls[i],
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
              errorBuilder: (_, __, ___) => const Center(
                child: Text('Could not load this photo.',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
