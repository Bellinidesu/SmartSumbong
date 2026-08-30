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
//
// LIVE WHILE OPEN (29 Aug 2026 — see home_screen.dart's header for the
// broader reasoning). This is the one screen where "seconds matter" is
// most literally true: a resident staring at this exact report while a
// tanod is dispatched should watch it move, not sit on a stale card
// until they remember to pull down. A channel filtered to this single
// report id (on reports) plus this single report's own log rows (on
// status_logs) reloads the whole screen through the same _load() the
// pull-to-refresh already used — one fetch path, not two that could
// drift apart — the moment either changes.

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:share_plus/share_plus.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../location_lookup.dart';
import '../models/complaint_category.dart';
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
  List<({String url, bool isVideo})> _photos = const [];
  List<({String url, bool isVideo})> _proof = const [];
  List<Map<String, dynamic>> _timeline = const [];
  Map<String, dynamic>? _feedback;
  String? _error;

  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeLive();
  }

  @override
  void dispose() {
    _liveDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    super.dispose();
  }

  void _subscribeLive() {
    _liveChannel = Supabase.instance.client
        .channel('report-live-${widget.reportId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'reports',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: widget.reportId,
        ),
        callback: (_) => _scheduleLiveReload(),
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'status_logs',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'report_id',
          value: widget.reportId,
        ),
        callback: (_) => _scheduleLiveReload(),
      )
      ..subscribe();
  }

  // A status transition writes both a reports row and a status_logs row
  // in the same transaction — debounced so those two realtime events
  // become one reload, not two back-to-back fetches.
  void _scheduleLiveReload() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    setState(() => _error = null);

    try {
      final r = await client
          .from('reports')
          .select('id, tracking_id, subject, description, status, '
              'category, latitude, longitude, is_anonymous, created_at, '
              'resolved_at, closed_at, reopened_count')
          .eq('id', widget.reportId)
          .maybeSingle();

      if (r == null) {
        setState(() => _error = context.s.reportViewNotFound);
        return;
      }

      final media = await client
          .from('report_media')
          .select('media_url, mime_type')
          .eq('report_id', widget.reportId);

      // Proof of resolution, readable by the resident since 0024. A
      // resident told their complaint was fixed should be able to see
      // the fix.
      final proof = await client
          .from('dispatch_media')
          .select('media_url, mime_type, dispatches!inner(report_id)')
          .eq('dispatches.report_id', widget.reportId);

      // Feedback is one row per report at most — the table has a unique
      // constraint on report_id, so this is the resident's single
      // rating or nothing.
      final fb = await client
          .from('feedback')
          .select('rating, comment, submitted_at')
          .eq('report_id', widget.reportId)
          .maybeSingle();

      // `id` is selected so _withAuthorLabels() below can match each row
      // back to its byline. `ascending: true` is not the default here --
      // postgrest-dart's own default is DESCENDING (newest first), which
      // this screen's timeline was silently rendering in for as long as
      // this call left it unstated: newest-to-oldest, upside down from
      // what a "timeline" and this widget's own top-to-bottom rail
      // drawing both assume. Caught 30 Aug 2026 off a live screenshot
      // where "Report submitted" (always first, built separately from
      // the report's own created_at) was followed by the newest real
      // entry, then older ones, ending on the OLDEST real entry at the
      // very bottom -- exactly backwards. Explicit from here on so this
      // can't silently regress if a future edit reorders the call.
      final logs = await client
          .from('status_logs')
          .select('id, old_status, new_status, remark, created_at')
          .eq('report_id', widget.reportId)
          .order('created_at', ascending: true);

      if (!mounted) return;
      setState(() {
        _report = r;
        _photos = [
          for (final m in media)
            (
              url: m['media_url'] as String,
              isVideo: isVideoMime(m['mime_type'] as String?),
            ),
        ];
        _proof = [
          for (final m in proof)
            (
              url: m['media_url'] as String,
              isVideo: isVideoMime(m['mime_type'] as String?),
            ),
        ];
        _timeline = List<Map<String, dynamic>>.from(logs);
        _feedback = fb;
      });
      await _loadTimelineAuthors();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.reportViewLoadError);
    }
  }

  /// Tags every row already in _timeline with an 'author_label' key --
  /// "TANOD <NAME>" or "SYSTEM" -- via 0049's my_status_log_authors RPC,
  /// scoped to this one report. _TimelineRow reads entry['author_label']
  /// directly, and _ReportCard's own resolution-note lookup (its
  /// _resolution() method) picks the same key off whichever entry it
  /// finds -- one RPC call backs both the full timeline's bylines and
  /// the card body's, since the resolution note IS one timeline entry's
  /// remark. Its own try/catch, same as reports_screen.dart's list
  /// version: failing to resolve a byline is never a reason to blank the
  /// timeline the rest of _load() just populated.
  Future<void> _loadTimelineAuthors() async {
    try {
      final rows = await Supabase.instance.client.rpc(
          'my_status_log_authors',
          params: {'p_report_id': widget.reportId});
      if (!mounted) return;
      final labels = <String, String>{};
      for (final row in rows as List) {
        final id = row['status_log_id'] as String?;
        if (id == null) continue;
        final isSystem = row['is_system'] as bool? ?? false;
        final name = (row['author_name'] as String?)?.trim();
        if (isSystem) {
          labels[id] = 'SYSTEM';
        } else if (name != null && name.isNotEmpty) {
          labels[id] = 'TANOD ${name.toUpperCase()}';
        }
      }
      if (labels.isEmpty) return;
      setState(() {
        _timeline = [
          for (final entry in _timeline)
            if (labels.containsKey(entry['id']))
              {...entry, 'author_label': labels[entry['id']]}
            else
              entry,
        ];
      });
    } catch (_) {
      // Rows still show with no byline.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.bg,
        surfaceTintColor: context.colors.bg,
        elevation: 0,
        foregroundColor: context.colors.navy,
        title: Text(s.reportViewTitle,
            style: t.labelLarge?.copyWith(fontSize: 18)),
        actions: [
          if (_report != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: s.reportViewShare,
              onPressed: _share,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: context.colors.navy,
          child: _body(s),
        ),
      ),
    );
  }

  Widget _body(Strings s) {
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.hint)),
      ]);
    }
    if (_report == null) {
      return Center(child: CircularProgressIndicator(color: context.colors.navy));
    }

    final r = _report!;
    final status = ReportStatus.parse(r['status'] as String?);
    final category = ComplaintCategory.parse(r['category'] as String?);
    final lat = (r['latitude'] as num?)?.toDouble();
    final lng = (r['longitude'] as num?)?.toDouble();

    return ListView(
      padding: const EdgeInsets.fromLTRB(44, 8, 44, 32),
      children: [
        _ReportCard(
          trackingId: r['tracking_id'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          category: category,
          description: r['description'] as String? ?? '',
          status: status,
          createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
          isAnonymous: r['is_anonymous'] == true,
          latitude: lat,
          longitude: lng,
          photos: _photos,
          onViewPhoto: (i) => _openPhoto(_photos, i),
          // Merged into the card itself -- the reference mockup runs the
          // timeline on inside the same card, straight under the date
          // band, rather than as a separate section below the fold the
          // way this screen used to. Full remark text and time-of-day
          // stay (unlike the compact copy this reference-driven card
          // shows on the list) -- this is the one screen a resident
          // actually reads history on, so trimming it here would lose
          // real information for the sake of matching a mockup that was
          // only ever drawn as a list-row preview.
          timeline: _timeline,
          // Absorbed into the card too (29 Aug 2026) -- the status note
          // and the feedback box used to float below as their own
          // separately bordered pieces (the line under the card that
          // used to be "the only real difference between Rose's six
          // frames"); the user's own call after seeing them looking
          // disconnected from the card on the emulator. Both still only
          // render the way they always did -- the status note's own
          // switch on `status`, the feedback box's own switch on whether
          // `_feedback` has landed yet -- just laid out as trailing
          // sections of _ReportCard now instead of separate widgets in
          // this ListView.
          hasProof: _proof.isNotEmpty,
          reopenedCount: (r['reopened_count'] as num?)?.toInt() ?? 0,
          onViewProof: () => _openPhoto(_proof, 0),
          feedback: _feedback,
          onRate: _openFeedback,
        ),
      ],
    );
  }

  Future<void> _openFeedback() async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => _FeedbackSheet(reportId: widget.reportId),
    );
    if (saved == true) await _load();
  }

  // Hands the tracking id off through the OS share sheet — SMS, Messenger,
  // copy — rather than the resident retyping a 13-character code by hand
  // to a neighbour or a barangay staffer. Never includes the resident's
  // own name; is_anonymous already controls who the barangay tells, and
  // this only ever repeats what's already on this screen (id, subject,
  // status) — nothing that could re-identify an anonymous filer to
  // whoever the share lands with.
  Future<void> _share() async {
    final r = _report;
    if (r == null) return;
    final s = context.s;
    final trackingId = r['tracking_id'] as String? ?? '';
    final subject = r['subject'] as String? ?? '';
    final status = ReportStatus.parse(r['status'] as String?);
    final text = s.reportViewShareText(
      trackingId,
      subject,
      s.reportStatusLabel(status.wire),
    );
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.reportViewShareFailed)),
      );
    }
  }

  void _openPhoto(List<({String url, bool isVideo})> items, int index) {
    if (items.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PhotoViewer(items: items, initial: index),
    ));
  }
}

// ---------- pieces -------------------------------------------

// Card layout below now follows the reference mockup's structure verbatim
// (meta line + corner pill, title, body, tinted date band, timeline all
// in one card) rather than Rose's six-frame design -- the user's own call
// (29 Aug 2026): "figma is a reference ngl", this screen should read like
// the mockup. What stays app-specific rather than mockup-verbatim: the
// navy/orange/Poppins palette (kept, not the mockup's blue/Jakarta Sans,
// so this screen doesn't clash with every other screen around it), and
// the map + photo carousel (the mockup never had to render either since
// it was static, but a resident checking their own filed report needs to
// see the pin and their evidence, so both stay, slotted in after the
// description).
class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.trackingId,
    required this.subject,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.isAnonymous,
    required this.latitude,
    required this.longitude,
    required this.photos,
    required this.onViewPhoto,
    this.timeline = const [],
    required this.hasProof,
    required this.reopenedCount,
    required this.onViewProof,
    required this.feedback,
    required this.onRate,
  });

  final String trackingId;
  final String subject;
  final ComplaintCategory category;
  final String description;
  final ReportStatus status;
  final DateTime? createdAt;
  final bool isAnonymous;
  final double? latitude;
  final double? longitude;
  final List<({String url, bool isVideo})> photos;
  final ValueChanged<int> onViewPhoto;

  /// This report's status_logs rows, oldest first. Same shape and same
  /// source as reports_screen.dart's hero timeline, just never trimmed --
  /// see the call site for why this screen keeps the full remark/time.
  final List<Map<String, dynamic>> timeline;

  /// The status note and feedback box's own inputs, unchanged from when
  /// they were separate widgets below the card -- just threaded through
  /// so build() can render them as trailing sections of this card
  /// instead (29 Aug 2026).
  final bool hasProof;
  final int reopenedCount;
  final VoidCallback onViewProof;
  final Map<String, dynamic>? feedback;
  final VoidCallback onRate;

  /// What actually happened, in the tanod's own words -- not the
  /// resident's original complaint text. 29 Aug 2026: the mockup's own
  /// card body isn't a static description at all, it's a live status
  /// narrative ("Maintenance team replaced the faulty bulb. Streetlight
  /// is now operational."). submit_field_report() (0002) already writes
  /// that exact free-text note into the 'resolved' transition's
  /// status_logs.remark -- the same `timeline` this card already has,
  /// no new query and no RLS change, since a resident could always read
  /// their own status_logs (0001). Only defined for reports that have
  /// actually been resolved (checked on `status` directly, the same
  /// resolved/closed/archived set the status pill's green covers --
  /// deliberately not `isFinished`, which excludes archived for an
  /// unrelated reason, whether a reopen is still offered). Searching
  /// `timeline.reversed` for the most recent 'resolved' row rather than
  /// just the last row matters for a reopened-then-resolved-again
  /// report: it finds the CURRENT resolution, not a stale one from
  /// before a reopen. note is null (falls back to the original
  /// description) when the report was never resolved, or was resolved
  /// with no field text to show (an edge case, not the common path).
  ///
  /// note and author come from the SAME timeline entry, in one pass --
  /// author is just entry['author_label'], the byline
  /// ReportViewScreen's _loadTimelineAuthors() already tagged every
  /// timeline row with via 0049's my_status_log_authors RPC. No separate
  /// lookup: the resolution note IS one timeline entry's remark, so its
  /// byline is that same entry's byline. A null author is normal (the
  /// lookup hasn't landed yet, or found nothing to say) -- the note
  /// still renders either way, just without one.
  ({String? note, String? author}) _resolution() {
    const finished = {
      ReportStatus.resolved,
      ReportStatus.closed,
      ReportStatus.archived,
    };
    if (!finished.contains(status)) return (note: null, author: null);
    for (final entry in timeline.reversed) {
      if (entry['new_status'] == 'resolved') {
        final remark = (entry['remark'] as String?)?.trim();
        if (remark == null || remark.isEmpty) return (note: null, author: null);
        return (note: remark, author: entry['author_label'] as String?);
      }
    }
    return (note: null, author: null);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final resolution = _resolution();
    final resolutionNote = resolution.note;
    final resolutionAuthor = resolution.author;
    final bodyText = resolutionNote ?? s.reportsCardDescription(description);
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      // Light card, not the navy fill this card used before this round --
      // the user's own call, straying from Rose's frames on purpose for
      // this screen. `field` is this app's existing "lighter than the
      // page" surface token (already used by _FeedbackCard below), so
      // this reuses an established light-card convention rather than
      // inventing a new one; `navy` on it reads as dark accent-coloured
      // text/border, same as it always has, just no longer the fill.
      //
      // 1:1 pass (29 Aug 2026): radius, padding, shadow and the section
      // split below now match the mockup's .report-detail-card exactly
      // (10px radius, transparent border, two-layer soft shadow, and a
      // padded "top" block / full-bleed tinted "bottom" band / padded
      // timeline block, instead of one uniform outer padding) -- only
      // the font-family and the established navy/orange/muted/field/bg
      // colour roles stay put, per the user's own framing of the ask.
      decoration: BoxDecoration(
        color: context.colors.field,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // rdc-top: header, body, and the app's own map/photo additions
          // (the mockup has no equivalent for those two, so their own
          // sizing is untouched) -- separated from the date band below
          // by `divider`, the literal mapping for the mockup's
          // var(--border), not an ad-hoc navy alpha.
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: context.colors.divider),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ID · category, small and muted, directly above the
                          // title -- same top line reports_screen.dart's card
                          // uses, so a resident sees the identical pattern
                          // whether they're skimming the list or reading one
                          // report in full.
                          Text(
                            '$trackingId · ${category.label}',
                            style: TextStyle(fontSize: 11, color: context.colors.muted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subject,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              height: 1.1,
                              color: context.colors.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    _StatusPill(status: status),
                  ],
                ),
                if (isAnonymous) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_off_outlined,
                          size: 13, color: context.colors.muted),
                      const SizedBox(width: 3),
                      Text(s.reportViewAnonymous,
                          style: TextStyle(fontSize: 11, color: context.colors.muted)),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                // Full text, no ellipsis -- unlike the list card's 3-line clip,
                // this is the one screen a resident reads their own complaint
                // (or, once resolved, its resolution note -- see
                // _resolution() above) back on in full.
                Text.rich(
                  TextSpan(
                    children: [
                      if (resolutionNote != null && resolutionAuthor != null)
                        TextSpan(
                          text: '$resolutionAuthor: ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: context.colors.navy,
                          ),
                        ),
                      TextSpan(text: bodyText),
                    ],
                  ),
                  style: TextStyle(fontSize: 12, height: 1.4, color: context.colors.muted),
                ),

                if (latitude != null && longitude != null) ...[
                  const SizedBox(height: 14),
                  _MiniMap(point: LatLng(latitude!, longitude!)),
                ],

                // 29 Aug 2026: the map got bigger and the evidence photos
                // moved off a strip of small 200x134 thumbnails and onto
                // one big swipeable frame close to the map's own size --
                // neither had a mockup layout to be 1:1 against (see the
                // Round 7 write-up), this is the user's own direct call
                // after seeing both cramped side by side on the emulator.
                if (photos.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _MediaCarousel(photos: photos, onViewPhoto: onViewPhoto),
                ],
              ],
            ),
          ),

          // rdc-bottom: a full-bleed tinted strip, not a nested rounded
          // chip -- the mockup runs this the full width of the card.
          // 1:1 pass (29 Aug 2026): the 🕐 emoji glyph is gone, replaced
          // by a proper Icons widget (this app's own established icon
          // pack -- Material Icons, already used everywhere else on this
          // screen, not a new dependency), and the mockup's
          // "📍 <place>" line is back, fed by a best-effort
          // reverse-geocode lookup rather than a stored address column --
          // see location_lookup.dart's header for why.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: context.colors.bg,
            child: Row(
              children: [
                if (latitude != null && longitude != null)
                  _LocationLabel(latitude: latitude!, longitude: longitude!),
                if (createdAt != null) ...[
                  Icon(Icons.access_time_rounded,
                      size: 12, color: context.colors.muted),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(s, createdAt!),
                    style: TextStyle(fontSize: 11, color: context.colors.muted),
                  ),
                ],
              ],
            ),
          ),

          if (createdAt != null || timeline.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
              child: _Timeline(
                entries: timeline,
                submittedAt: createdAt,
                upcomingWire: status.isOngoing
                    ? (status == ReportStatus.pendingReview ||
                            status == ReportStatus.validated
                        ? 'assigned'
                        : 'resolved')
                    : null,
              ),
            ),

          // Status note -- "Your report has been resolved.", the one
          // line that differs between Rose's six frames -- used to float
          // below the card as its own bordered bubble; now just another
          // divided section, same top-border pattern the rdc-top/
          // rdc-bottom split above already uses.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.colors.divider)),
            ),
            child: _StatusNote(
              status: status,
              hasProof: hasProof,
              reopenedCount: reopenedCount,
              onViewProof: onViewProof,
            ),
          ),

          // Feedback closes the loop the resident started. RLS allows
          // the insert only on a resolved or closed report, so this
          // only ever shows on the states the database would accept.
          // Also absorbed into the card (29 Aug 2026), same reasoning
          // as the status note above.
          if (status.isFinished)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: context.colors.divider)),
              ),
              child: _FeedbackCard(feedback: feedback, onRate: onRate),
            ),
        ],
      ),
    );
  }

  static String _formatDate(Strings s, DateTime utc) {
    final d = utc.toLocal();
    return '${s.monthFull(d.month)} ${d.day}, ${d.year}';
  }
}

/// The mockup's "📍 <place>" footer meta item, resolved from the
/// report's coordinates via location_lookup.dart rather than a stored
/// address string -- see that file's header for the full reasoning.
/// Renders nothing (not a coordinate pair, not an error) while loading
/// or when the lookup comes back empty, including its own trailing gap
/// so the date beside it never ends up with a stray double space when
/// there's nothing to show. Same widget as reports_screen.dart's own
/// copy -- duplicated, not shared, per this app's established
/// convention for screen-specific widgets.
class _LocationLabel extends StatefulWidget {
  const _LocationLabel({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;

  @override
  State<_LocationLabel> createState() => _LocationLabelState();
}

class _LocationLabelState extends State<_LocationLabel> {
  late Future<String?> _future =
      ReverseGeocode.lookup(widget.latitude, widget.longitude);

  @override
  void didUpdateWidget(covariant _LocationLabel old) {
    super.didUpdateWidget(old);
    if (old.latitude != widget.latitude || old.longitude != widget.longitude) {
      _future = ReverseGeocode.lookup(widget.latitude, widget.longitude);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        final name = snap.data;
        if (name == null || name.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined,
                  size: 12, color: context.colors.muted),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: context.colors.muted),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The rounded corner badge the reference mockup puts status in, rather
/// than this screen's old inline coloured text folded into the title.
/// Same shape as reports_screen.dart's card, but its own tint logic --
/// ReportStatus.labelColour returns this app's bg colour for the normal
/// case, tuned for text sitting on a navy card; on this light card that
/// would read as invisible near-white text, which is why this file
/// never called it for the pill.
///
/// COLOUR PER STATUS (29 Aug 2026). The mockup's own .status-pill isn't
/// one accent colour -- it's three (warning-orange/pending,
/// primary-blue/progress, success-green/resolved), each carrying real
/// meaning at a glance. Matched here with the app's own palette rather
/// than importing the mockup's blue: pending reuses the app's one
/// existing accent orange, in-progress uses navy (the app's primary
/// ink, already read as "the app is doing something" everywhere else),
/// and completed gets a new green -- context.colors has no success
/// token, so this is the one new colour this pass introduces, matched
/// to the mockup's own --success (#16A34A). Cancelled keeps its
/// existing red, now the theme's own `hint` token instead of a
/// one-off literal -- same colour role (the small red warnings
/// elsewhere in the app), one fewer hard-coded hex in this file.
/// Rejected gets `muted`, not folded into any of the above: this
/// class's own labelColour doc already says cancelled "reads
/// differently from a rejection" but the code never actually gave
/// rejected a distinct colour until now -- it silently fell into the
/// same bucket as in-progress. `switch` on the enum member (not the
/// three-value `label` bucket already collapses to) so a status that's
/// merely `isFinished` doesn't accidentally miss `archived`, which
/// belongs to the same Completed bucket but isn't `isFinished` (see
/// that getter's own comment).
///
/// Deliberately still local to this file's `_StatusPill`, not folded
/// into `ReportStatus.labelColour` -- that extension is also read by
/// map_screen.dart's pin colouring (`labelColour(context) ==
/// context.colors.bg` as its "not cancelled" check), and widening its
/// contract to five colours would silently break that comparison for
/// every status but exactly one. Out of scope for a card-styling pass;
/// flagged rather than touched.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final tint = switch (status) {
      ReportStatus.cancelled => context.colors.hint,
      ReportStatus.rejected => context.colors.muted,
      ReportStatus.resolved ||
      ReportStatus.closed ||
      ReportStatus.archived =>
        const Color(0xFF16A34A),
      ReportStatus.pendingReview || ReportStatus.validated =>
        const Color(0xFFFF9800),
      _ => context.colors.navy, // assigned / inProgress / offlineInvestigation
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        context.s.reportStatusLabel(status.wire),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 10,
          color: tint,
        ),
      ),
    );
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
        // Bumped 189 -> 240 (29 Aug 2026) -- the user's own call after
        // seeing it live on the emulator next to the evidence photos
        // below, which read as cramped at the old size.
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.navy.withValues(alpha: 0.12)),
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
                child: Icon(Icons.location_on,
                    size: 36, color: context.colors.navy),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The evidence photos/videos a resident attached, shown one at a time
/// large and swipeable -- not as a strip of small 200x134 thumbnails --
/// so this reads with the same visual weight as the map above it rather
/// than as an afterthought squeezed underneath it. A small dot rail
/// beneath the frame is the only affordance for "there's more than one";
/// tapping the frame still opens the full-screen _PhotoViewer, same as
/// the old thumbnail strip did.
class _MediaCarousel extends StatefulWidget {
  const _MediaCarousel({required this.photos, required this.onViewPhoto});

  final List<({String url, bool isVideo})> photos;
  final ValueChanged<int> onViewPhoto;

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            height: 220,
            width: double.infinity,
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.photos.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final photo = widget.photos[i];
                return GestureDetector(
                  onTap: () => widget.onViewPhoto(i),
                  child: photo.isVideo
                      ? Container(
                          color: context.colors.navy.withValues(alpha: 0.08),
                          child: Center(
                            child: Icon(Icons.play_circle_fill,
                                size: 48, color: context.colors.navy),
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: photo.url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, __) => Container(
                            color: context.colors.navy.withValues(alpha: 0.08),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: context.colors.navy, strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: context.colors.navy.withValues(alpha: 0.08),
                            child: Icon(Icons.broken_image_outlined,
                                color: context.colors.navy),
                          ),
                        ),
                );
              },
            ),
          ),
        ),
        if (widget.photos.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.photos.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page
                        ? context.colors.navy
                        : context.colors.divider,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// The one line that differs between Rose's six frames. Used to be its
/// own right-margined, bordered chat bubble floating below the card;
/// absorbed into the card itself as of 29 Aug 2026 (see the card's own
/// build() for the section that now wraps this), so the bubble's own
/// border/fill/radius/margin are gone -- just the text and its actions.
/// Centered rather than right-aligned as of the same round's follow-up
/// feedback -- this reads as the card's own closing line now that it
/// lives inside the card, not a message bubble handed across a chat.
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
    final s = context.s;
    final (text, action) = switch (status) {
      ReportStatus.pendingReview || ReportStatus.validated => (
          s.reportViewReviewing,
          null,
        ),
      ReportStatus.assigned ||
      ReportStatus.inProgress ||
      ReportStatus.offlineInvestigation =>
        (s.reportViewAssigned, null),
      ReportStatus.resolved || ReportStatus.closed || ReportStatus.archived =>
        hasProof
            ? (s.reportViewResolvedWithProof, s.reportViewViewPhoto)
            : (s.reportViewResolvedNoProof, null),
      ReportStatus.rejected => (
          s.reportViewRejected,
          null,
        ),
      ReportStatus.cancelled => (
          s.reportViewCancelled,
          null,
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text.rich(
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
            if (action != null) TextSpan(text: s.reportViewForTheProof),
          ]),
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 12, height: 1.4, color: context.colors.navy),
        ),
        if (action != null)
          TextButton(
            onPressed: onViewProof,
            child: Text(s.reportViewViewPhoto),
          ),
        if (reopenedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              reopenedCount == 1
                  ? s.reportViewReopenedOnce
                  : s.reportViewReopenedTimes(reopenedCount),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: context.colors.muted),
            ),
          ),
      ],
    );
  }
}

/// From status_logs, plus two synthetic rows neither table has to offer:
/// a first "Report submitted" node built from the report's own
/// created_at (submission itself is never a logged transition, so
/// without this the timeline's first real row would be whatever
/// happened to transition it first), and, only while the report is
/// still moving, a last "not yet reached" node for the next stage --
/// see report_view_screen's card build() for how upcomingWire is
/// computed (the same three status buckets reportStatusLabel already
/// collapses into, not a guess at specifics). The Track Complaint
/// Status use case calls for "a linear progress timeline showing
/// tracking updates" and "formal remarks appended by responding
/// personnel or administrators" -- the remarks stay on the real rows.
class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.entries,
    required this.submittedAt,
    this.upcomingWire,
  });

  final List<Map<String, dynamic>> entries;
  final DateTime? submittedAt;
  final String? upcomingWire;

  @override
  Widget build(BuildContext context) {
    final hasUpcoming = upcomingWire != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (submittedAt != null)
          _SubmittedStepRow(
            when: submittedAt!,
            hasMore: entries.isNotEmpty || hasUpcoming,
          ),
        for (var i = 0; i < entries.length; i++)
          _TimelineRow(
            entry: entries[i],
            isCurrent: i == entries.length - 1 && hasUpcoming,
            isFinalNode: i == entries.length - 1 && !hasUpcoming,
          ),
        if (upcomingWire != null) _UpcomingStepRow(wire: upcomingWire!),
      ],
    );
  }
}

/// The dot-and-line shell every timeline row shares, so the submitted /
/// real / upcoming rows all line up in the same 24px-wide rail
/// regardless of which one draws the dot.
class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.dot,
    required this.hasLineBelow,
    required this.bottomPadding,
    this.lineColor,
    required this.child,
  });

  final Widget dot;
  final bool hasLineBelow;
  final double bottomPadding;

  /// Mockup nuance from the raw markup, not just the CSS rules: only the
  /// line below a fully-`done` dot gets the accent colour -- the line
  /// below the `active`/current dot stays neutral, since what follows
  /// is unknown/future. Callers pass `navy` after a done row and
  /// `divider` after the current row; unset falls back to `divider`.
  final Color? lineColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                dot,
                if (hasLineBelow)
                  Expanded(
                    child: VerticalDivider(
                      color: lineColor ?? context.colors.divider,
                      thickness: 2,
                      width: 10,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomPadding),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmittedStepRow extends StatelessWidget {
  const _SubmittedStepRow({required this.when, required this.hasMore});
  final DateTime when;
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _TimelineRail(
      hasLineBelow: hasMore,
      bottomPadding: hasMore ? 20 : 0,
      // Always a "done" node -- the line below it (if any) gets the
      // accent colour, same as the mockup's .tl-line.done.
      lineColor: context.colors.navy,
      dot: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(color: context.colors.navy, shape: BoxShape.circle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.reportViewSubmittedStep,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 2),
          Text(_formatWhen(s, when),
              style: TextStyle(fontSize: 11, color: context.colors.muted)),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.isCurrent,
    required this.isFinalNode,
  });

  final Map<String, dynamic> entry;

  /// This is the report's status right now -- the report is still
  /// moving and an upcoming row follows. Gets the app's one accent
  /// colour and a soft ring so "you are here" actually reads as current
  /// rather than just another line in a flat list.
  final bool isCurrent;

  /// This is the last row drawn, full stop -- no line beneath it. True
  /// for the true last entry on a finished/rejected/cancelled report
  /// (where isCurrent is always false: nothing is "still moving"); false
  /// whenever an upcoming row follows, current or not.
  final bool isFinalNode;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final status = ReportStatus.parse(entry['new_status'] as String?);
    final when = DateTime.tryParse(entry['created_at'] as String? ?? '');
    final remark = entry['remark'] as String?;
    // "TANOD <NAME>" / "SYSTEM" -- see ReportViewScreen's
    // _loadTimelineAuthors(). Null while the lookup is still in flight,
    // or for a synthetic row (submitted/upcoming) that never has one --
    // those don't build a _TimelineRow at all, so this is only ever
    // null here because the real lookup hasn't landed or had nothing to
    // add, never because a row is somehow author-less by nature.
    final author = entry['author_label'] as String?;

    return _TimelineRail(
      hasLineBelow: !isFinalNode,
      bottomPadding: isFinalNode ? 0 : 20,
      // A done real entry (not the current one) leads into another done
      // or current row -- accent line. The current row's own line leads
      // to the not-yet-reached upcoming row -- neutral, per the mockup.
      lineColor: isCurrent ? context.colors.divider : context.colors.navy,
      dot: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: isCurrent ? const Color(0xFFFF9800) : context.colors.navy,
          shape: BoxShape.circle,
          boxShadow: isCurrent
              ? const [
                  BoxShadow(color: Color(0x55FF9800), blurRadius: 0, spreadRadius: 3),
                ]
              : null,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.reportStatusLabel(status.wire),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: context.colors.navy,
            ),
          ),
          if (when != null) ...[
            const SizedBox(height: 2),
            Text(_formatWhen(s, when),
                style: TextStyle(fontSize: 11, color: context.colors.muted)),
          ],
          if (remark != null && remark.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  children: [
                    if (author != null)
                      TextSpan(
                        text: '$author: ',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    TextSpan(text: remark),
                  ],
                ),
                style: TextStyle(fontSize: 12, height: 1.3, color: context.colors.navy),
              ),
            ),
        ],
      ),
    );
  }
}

/// The greyed, not-yet-happened last row -- see the card's upcomingWire
/// computation for why this is safe to show without inventing data: the
/// label is one of the three buckets reportStatusLabel already collapses
/// every real status into, never a guess at a specific next action.
class _UpcomingStepRow extends StatelessWidget {
  const _UpcomingStepRow({required this.wire});
  final String wire;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return _TimelineRail(
      hasLineBelow: false,
      bottomPadding: 0,
      dot: Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(top: 2),
        decoration: BoxDecoration(
          color: context.colors.field,
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.divider, width: 2.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.reportStatusLabel(wire),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: context.colors.muted,
            ),
          ),
          const SizedBox(height: 2),
          Text(s.reportViewUpcomingStep,
              style: TextStyle(fontSize: 11, color: context.colors.muted)),
        ],
      ),
    );
  }
}

String _formatWhen(Strings s, DateTime utc) {
  final d = utc.toLocal();
  final h24 = d.hour;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 < 12 ? 'AM' : 'PM';
  final mm = d.minute.toString().padLeft(2, '0');
  return '${s.monthAbbr(d.month)} ${d.day}, ${d.year} \u2022 $h12:$mm $ampm';
}

/// Figma 2613:709 — full-screen photo with pinch to zoom. A video page
/// embeds the shared player instead of an InteractiveViewer, since
/// pinch-to-zoom on a playing video is not a thing anyone wants.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.items, required this.initial});

  final List<({String url, bool isVideo})> items;
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
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item.isVideo) {
            return InlineVideoPlayer(url: item.url);
          }
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: CachedNetworkImage(
                imageUrl: item.url,
                fit: BoxFit.contain,
                placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
                errorWidget: (_, __, ___) => Center(
                  child: Text(context.s.reportViewCouldNotLoadPhoto,
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}


// ---------- feedback -----------------------------------------

/// Shown under a resolved or closed report. Either an invitation to
/// rate, or the rating already given — feedback cannot be edited,
/// because the table takes one row per report and the barangay is
/// reading these as a record of how a case landed at the time. Used to
/// be its own separately bordered box below the card; absorbed into the
/// card itself as of 29 Aug 2026 (see the card's own build() for the
/// section that now wraps this), so the box's own border/fill/radius
/// are gone -- just the content, sized to match the rest of the card's
/// now-14px titles and 12px body text rather than its old standalone
/// 16px/13px. Centered as of the same round's follow-up feedback --
/// reads as the card's closing summary now, not a left-aligned body
/// section, matching _StatusNote's own centering right above it.
class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback, required this.onRate});

  final Map<String, dynamic>? feedback;
  final VoidCallback onRate;

  @override
  Widget build(BuildContext context) {
    final given = feedback;
    final s = context.s;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          given == null ? s.reportViewHowDidWeDo : s.reportViewYourFeedback,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: context.colors.navy,
          ),
        ),
        const SizedBox(height: 6),

        if (given == null) ...[
          Text(
            s.reportViewFeedbackPrompt,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: context.colors.muted),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onRate,
              child: Text(s.reportViewGiveFeedback),
            ),
          ),
        ] else ...[
          _Stars(rating: (given['rating'] as num?)?.toInt() ?? 0),
          if ((given['comment'] as String?)?.trim().isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(
              given['comment'] as String,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, height: 1.4, color: context.colors.muted),
            ),
          ],
        ],
      ],
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 26});

  final int rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: const Color(0xFFFF9800),
          ),
      ],
    );
  }
}

class _FeedbackSheet extends StatefulWidget {
  const _FeedbackSheet({required this.reportId});

  final String reportId;

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      setState(() => _error = context.s.reportViewRatingRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final client = Supabase.instance.client;
      final comment = _comment.text.trim();
      await client.from('feedback').insert({
        'report_id': widget.reportId,
        'resident_id': client.auth.currentUser!.id,
        'rating': _rating,
        'comment': comment.isEmpty ? null : comment,
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      final s = context.s;
      setState(() {
        _saving = false;
        // The unique constraint on report_id, and the RLS check that
        // only lets a resolved or closed report through, are the two
        // ways this legitimately fails.
        _error = m.contains('duplicate') || m.contains('unique')
            ? s.reportViewFeedbackDuplicate
            : m.contains('policy') || m.contains('row-level')
                ? s.reportViewFeedbackNotFinished
                : s.reportViewFeedbackFailed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.s.reportViewFeedbackFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final s = context.s;

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.reportViewHowDidWeDo,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 16),

          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => setState(() {
                              _rating = i;
                              _error = null;
                            }),
                    iconSize: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFFF9800),
                    ),
                    tooltip: '$i',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          TextField(
            controller: _comment,
            enabled: !_saving,
            maxLines: 4,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: s.reportViewCommentHint,
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!,
                style: TextStyle(color: context.colors.hint, fontSize: 12)),
          ],
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: context.colors.bg),
                    )
                  : Text(s.reportViewSendFeedback),
            ),
          ),
        ],
      ),
    );
  }
}
