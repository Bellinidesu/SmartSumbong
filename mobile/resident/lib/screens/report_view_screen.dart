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
// ROUND 16 (30 Aug 2026) — BACK TO ROSE'S SIX FRAMES, NOT THE REFERENCE
// MOCKUP. Rounds 1-15 progressively rebuilt this card to match a
// separate reference HTML mockup (light card, a "TRACKING-ID · Category"
// meta line, a corner status pill, the timeline embedded in the card,
// the tanod's resolution note replacing the card body). The barangay
// supervisor's feedback on seeing it live: keep every functional
// upgrade, but the LAYOUT should follow Rose's actual approved frames,
// not the mockup. Checked against zoomed crops of the six real frames
// (screenshots the user supplied directly — the Figma MCP connector had
// hit its own plan-level rate limit that session), which settled several
// things definitively:
//
//   - The card is navy fill (this app's own accent), not a light
//     `field` card. Reverts Round 4/5's flip.
//   - The title is ONE inline bold line — "(# <id> - <Status>) <subject>"
//     — no separate meta line, no corner pill. Only Cancelled gets a
//     distinct colour (red); every other status stays plain white. This
//     is the ORIGINAL pre-Round-2 title format and ReportStatus's own
//     pre-Round-11 labelColour rule, both reinstated rather than reinvented.
//   - The card BODY is always the resident's OWN original description —
//     never the tanod's resolution note. All six frames confirm this,
//     including the two Completed ones (their body is still the
//     resident's original complaint text, unchanged by resolution).
//   - There is no multi-row timeline anywhere in these frames. Instead,
//     a single small note bubble floats below-right of the card — only
//     for In Progress / Rejected / Completed, never for Under Review or
//     Cancelled — carrying whatever the tanod/system last logged.
//   - A "•••" menu on the card offers Cancel (View/Reopen dropped for
//     this screen — see _ReportCard's own header for why).
//
// WHAT SURVIVES FROM THE HYBRID PASS, ON PURPOSE. The user was explicit:
// every functional/data upgrade stays, it just moves to fit Rose's
// actual layout instead of the mockup's.
//   - The real tanod/system resolution text + "TANOD <NAME>:" / "SYSTEM:"
//     byline (Rounds 12-15) — now the note bubble's own content instead
//     of the card body, via the same _loadTimelineAuthors()/
//     my_status_log_authors() plumbing, unchanged.
//   - The chronological-order fix (Round 15) — `_load()`'s
//     `ascending: true` stays; the bubble just reads timeline.last
//     instead of walking every row.
//   - The reverse-geocoded "📍 <place>" line and the bigger map/photo
//     carousel (Rounds 7-8) — real, user-requested improvements with no
//     connection to the mockup's structure, so they're untouched here
//     even though Rose's own example frames don't show them at this
//     size (her sample reports just have modest map+photo, not a
//     deliberate size cue to shrink back to).
//
// The "•••" menu's View/Cancel styling (orange popup, same icons) is
// identical to what reports_screen.dart's own _CardMenu already draws —
// that screen's card apparently never drifted as far from Rose's frames
// as this one did (its header already cited Figma 2869:156 and the
// exact same cancel-flow node IDs throughout). reports_screen.dart's own
// card likely needs this same navy/inline-title treatment, but that is
// a separate frame ("REPORTS", not "VIEW REPORTS - <STATUS>") the user
// has not sent screenshots of yet — left untouched this round rather
// than guessed at.
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
import 'package:latlong2/latlong.dart' hide Path;
import 'package:share_plus/share_plus.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/flood_watch.dart';
import '../d/d_ui.dart';
import '../models/complaint_category.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/brgy_map.dart';
import '../widgets/figma_ui.dart';
import 'add_details_screen.dart';
import 'report_messages_screen.dart';
import 'reports_screen.dart' show ReportStatus;

class ReportViewScreen extends StatefulWidget {
  const ReportViewScreen({super.key, required this.reportId, this.uploader});

  final String reportId;

  /// For attaching a photo when answering a request for more details.
  final MediaUploader? uploader;

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  /// Once the coloured header has scrolled away, the status bar gets the
  /// page colour behind it, so the clock never sits on top of the text.
  final _pastHero = ValueNotifier<bool>(false);
  Map<String, dynamic>? _report;
  List<({String url, bool isVideo})> _photos = const [];
  List<({String url, bool isVideo})> _proof = const [];
  List<Map<String, dynamic>> _timeline = const [];
  Map<String, dynamic>? _feedback;

  /// An open request for more details from the tanod (0065), if any.
  Map<String, dynamic>? _detailRequest;
  String? _error;

  /// Round 17 (30 Aug 2026): the full row-by-row timeline is back, per
  /// direct feedback that the barangay actually liked it even though
  /// none of Rose's six frames draw it. Collapsed by default so the
  /// screen still reads like those frames at a glance (note bubble only)
  /// -- expanding is one tap on the centered toggle below the bubble.
  bool _timelineExpanded = false;
  bool _mediaOpen = false;
  List<({String url, String kind})> _evidence = const [];
  String? _official;
  String? _officialNote;
  bool _reasonsOpen = false;
  bool _busyAct = false;

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
    _pastHero.dispose();
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

  String get _cacheKey => 'report_${widget.reportId}';

  /// Fills the screen from one report's rows — the network's or the
  /// saved copy's, the same either way.
  void _apply(
    Map<String, dynamic> r,
    List<Map<String, dynamic>> media,
    List<Map<String, dynamic>> proof,
    Map<String, dynamic>? fb,
    List<Map<String, dynamic>> newestFirst,
  ) {
    final logs = <Map<String, dynamic>>[];
    for (final e in newestFirst.reversed) {
      final prev = logs.isEmpty ? null : logs.last;
      if (prev != null &&
          prev['new_status'] == e['new_status'] &&
          prev['old_status'] == e['old_status'] &&
          (prev['remark'] ?? '') == (e['remark'] ?? '')) {
        continue;
      }
      logs.add(e);
    }

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
  }

  /// The last copy of this report, shown at once while the network
  /// catches up. False if there was none.
  Future<bool> _showSaved() async {
    final c = await JsonCache.read(_cacheKey);
    if (c is! Map || c['report'] == null || !mounted) return false;
    List<Map<String, dynamic>> rows(Object? v) => [
          for (final e in (v as List? ?? const []))
            Map<String, dynamic>.from(e as Map),
        ];
    _apply(
      Map<String, dynamic>.from(c['report'] as Map),
      rows(c['media']),
      rows(c['proof']),
      c['feedback'] == null
          ? null
          : Map<String, dynamic>.from(c['feedback'] as Map),
      rows(c['logs']),
    );
    return true;
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    setState(() => _error = null);
    final hadSaved = _report == null && await _showSaved();

    try {
      // No `category` column here (30 Aug 2026) -- Rose's six frames
      // never show it; that meta line was a reference-mockup addition
      // this round undoes. See _ReportCard's own header.
      // All five at once (branch B): they are independent, and on mobile
      // data each round trip one after another was most of the wait.
      final reportQ = client
          .from('reports')
          .select('id, tracking_id, subject, description, status, '
              'latitude, longitude, location_label, is_anonymous, created_at, '
              'resolved_at, closed_at, reopened_count, due_at, '
              'referred_to, referral_note, followed_up_at, category')
          .eq('id', widget.reportId)
          .maybeSingle();

      final mediaQ = client
          .from('report_media')
          .select('media_url, mime_type')
          .eq('report_id', widget.reportId);

      // Proof of resolution, readable by the resident since 0024. A
      // resident told their complaint was fixed should be able to see
      // the fix.
      final proofQ = client
          .from('dispatch_media')
          .select('media_url, mime_type, dispatches!inner(report_id)')
          .eq('dispatches.report_id', widget.reportId);

      // Feedback is one row per report at most — the table has a unique
      // constraint on report_id, so this is the resident's single
      // rating or nothing.
      final fbQ = client
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
      // Newest first, then flipped: the API returns at most 1000 rows, and
      // a report that waited long for a unit collects a dispatch-retry row
      // every two minutes — oldest-first, those crowded the resolution
      // itself out of the response. Consecutive identical rows (the same
      // retry, again) are then shown once.
      final logsQ = client
          .from('status_logs')
          .select('id, old_status, new_status, remark, created_at')
          .eq('report_id', widget.reportId)
          .order('created_at', ascending: false)
          .limit(300);

      final got = await Future.wait<Object?>(
        [reportQ, mediaQ, proofQ, fbQ, logsQ],
        eagerError: true,
      );
      final r = got[0] as Map<String, dynamic>?;
      if (r == null) {
        if (mounted) setState(() => _error = context.s.reportViewNotFound);
        return;
      }
      final media = got[1] as List<Map<String, dynamic>>;
      final proof = got[2] as List<Map<String, dynamic>>;
      final fb = got[3] as Map<String, dynamic>?;
      final newestFirst = got[4] as List<Map<String, dynamic>>;
      // Kept for the next open (and for no signal): the raw rows, as the
      // API gave them.
      unawaited(JsonCache.write(_cacheKey, {
        'report': r,
        'media': media,
        'proof': proof,
        'feedback': fb,
        'logs': newestFirst,
      }));
      if (!mounted) return;
      _apply(r, media, proof, fb, newestFirst);
      // Separate, so the report still shows if this fails; alongside the
      // timeline bylines rather than after them.
      Future<void> detail() async {
        try {
          final q = await client
              .from('detail_requests')
              .select('id, message')
              .eq('report_id', widget.reportId)
              .isFilter('responded_at', null)
              .maybeSingle();
          if (mounted) setState(() => _detailRequest = q);
        } catch (_) {}
      }

      // 0079: the barangay's own photos and the official the case was
      // handed to. Separate and optional, so an older database (or a
      // failure here) never blanks the report.
      Future<void> barangay() async {
        try {
          final ev = await client
              .from('report_evidence')
              .select('kind, media_url, mime_type')
              .eq('report_id', widget.reportId)
              .order('created_at');
          if (mounted) {
            setState(() => _evidence = [
                  for (final m in ev) (url: m['media_url'] as String, kind: m['kind'] as String? ?? 'update'),
                ]);
          }
        } catch (_) {}
        try {
          final o = await client
              .from('reports')
              .select('higher_official, higher_official_note')
              .eq('id', widget.reportId)
              .maybeSingle();
          if (mounted && o != null) {
            setState(() {
              _official = o['higher_official'] as String?;
              _officialNote = o['higher_official_note'] as String?;
            });
          }
        } catch (_) {}
      }

      await Future.wait([detail(), _loadTimelineAuthors(), barangay()]);
    } catch (_) {
      if (!mounted) return;
      // No signal, but the saved copy is on screen: keep it (the offline
      // strip says why) rather than replacing it with an error.
      if (hadSaved || _report != null) return;
      setState(() => _error = context.s.reportViewLoadError);
    }
  }

  /// Tags every row already in _timeline with an 'author_label' key --
  /// `"TANOD <NAME>"` or "SYSTEM" -- via 0049's my_status_log_authors RPC,
  /// scoped to this one report. _StatusNoteBubble reads
  /// `timeline.last['author_label']` directly (30 Aug 2026 -- see that
  /// widget's own header for why it's the last entry, not every entry,
  /// now that there's no more per-row timeline to walk). Its own
  /// try/catch, same as reports_screen.dart's list version: failing to
  /// resolve a byline is never a reason to blank the timeline the rest
  /// of _load() just populated -- the bubble just shows the bare remark.
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
          labels[id] = 'TANOD ${casualName(name).toUpperCase()}';
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

  // Branch D (go list: the individual report page): the case's category
  // colour across the top with the contour lines, back and share on it;
  // under it the status pill, the subject, the ticket and date, the
  // detail rows, the resident's words, the map and photos; then the
  // case desk, the latest note, the timeline and the rating as before.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final r = _report;
    final cat = ComplaintCategory.parse(r?['category'] as String?);
    final col = categoryColour(cat);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: d.bg,
      body: Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.depth == 0) _pastHero.value = n.metrics.pixels > 170 - 8;
            return false;
          },
          child: RefreshIndicator(
        onRefresh: _load,
        color: d.accent,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: DHero(
              colour: r == null ? d.card2 : col,
              height: 170 + MediaQuery.paddingOf(context).top,
              children: [
                Positioned(left: 12, top: MediaQuery.paddingOf(context).top + 10, child: DHeroButton(icon: Icons.chevron_left_rounded, onTap: () => Navigator.of(context).maybePop())),
                if (r != null) Positioned(right: 12, top: MediaQuery.paddingOf(context).top + 10, child: DHeroButton(icon: Icons.ios_share_rounded, onTap: _share)),
                if (r != null) Positioned(left: 12, bottom: 10, child: DHeroChip(cat.label)),
              ],
            ),
          ),
          SliverToBoxAdapter(child: _body(s)),
        ]),
      ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top,
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _pastHero,
              builder: (context, on, _) => AnimatedOpacity(
                opacity: on ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: ColoredBox(color: d.bg),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body(Strings s) {
    final d = context.d;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
        child: Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 14, w: FontWeight.w700)),
      );
    }
    if (_report == null) {
      return Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: d.accent)));
    }

    final r = _report!;
    final status = ReportStatus.parse(r['status'] as String?);
    final lat = (r['latitude'] as num?)?.toDouble();
    final lng = (r['longitude'] as num?)?.toDouble();

    // Whether a note bubble shows at all, and what it says, both live in
    // _StatusNoteBubble. Neither Under Review nor Cancelled gets a bubble.
    final showsNote = status != ReportStatus.pendingReview && status != ReportStatus.validated && status != ReportStatus.cancelled;
    // The note is the entry that explains the current status, not simply
    // the newest row: a completed report's resolution note, a rejected
    // one's denial. Newer system rows can follow those (dispatch retries,
    // the old SLA sweep) and used to replace the tanod's note here.
    final wanted = switch (status) {
      ReportStatus.resolved || ReportStatus.closed || ReportStatus.archived => const {'resolved', 'closed', 'archived'},
      ReportStatus.rejected => const {'rejected'},
      _ => null,
    };
    Map<String, dynamic>? latestEntry = _timeline.isNotEmpty ? _timeline.last : null;
    if (wanted != null) {
      Map<String, dynamic>? bare;
      latestEntry = null;
      for (final e in _timeline.reversed) {
        final remark = ((e['remark'] as String?) ?? '').trim();
        if (!wanted.contains(e['new_status']) || remark.startsWith('SLA breach')) continue;
        if (remark.isNotEmpty) {
          latestEntry = e;
          break;
        }
        bare ??= e;
      }
      latestEntry ??= bare;
    }

    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    final col0 = categoryColour(ComplaintCategory.parse(r['category'] as String?));
    final referred = (r['referred_to'] as String?)?.isNotEmpty ?? false;
    final (Color stCol, String stLabel) = referred && status.isOngoing
        ? (const Color(0xFF8B5CF6), context.tr('Escalated', 'In-escalate'))
        : (_statusColour(status), s.reportStatusLabel(status.wire));

    final due = DateTime.tryParse(r['due_at'] as String? ?? '')?.toLocal();
    final overdue = status.isOngoing && due != null && due.isBefore(DateTime.now()) && !referred;
    String dueText(DateTime t) {
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      return '${s.monthFull(t.month)} ${t.day}, ${t.year}, $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
    }

    final followedAt = DateTime.tryParse(r['followed_up_at'] as String? ?? '');
    final followedToday = followedAt != null && DateTime.now().difference(followedAt).inHours < 24;
    final finished = status.isFinished;
    final remark = (latestEntry?['remark'] as String?)?.trim();
    final author = latestEntry?['author_label'] as String?;
    final hasRemark = remark != null && remark.isNotEmpty;
    final remarkText = hasRemark ? (author != null ? '$author: $remark' : remark) : null;
    final reopened = (r['reopened_count'] as num?)?.toInt() ?? 0;
    final askingDetails = _detailRequest != null && widget.uploader != null;
    const amber = Color(0xFFF59E0B);
    const green = Color(0xFF1F8A45);

    // One tinted note per situation, the way the preview draws them: a
    // dot, a bold title, the words under it.
    final notes = <Widget>[];
    if (overdue) {
      notes.add(_RNote(
        colour: const Color(0xFFE5383B),
        title: s.caseOverdue,
        body: s.caseOverdueBody(dueText(due)),
        action: followedToday ? null : (s.followUpButton, () => _followUp(r)),
        foot: followedToday ? s.followUpToday : null,
      ));
    }
    if (askingDetails) {
      notes.add(_RNote(colour: amber, title: s.reportViewDetailsNeeded, body: '“${_detailRequest!['message'] as String? ?? ''}”'));
    } else if (referred && status.isOngoing) {
      notes.add(_RNote(
        colour: const Color(0xFF8B5CF6),
        title: context.tr('Escalated to the ${r['referred_to']}', 'In-escalate sa ${r['referred_to']}'),
        body: (r['referral_note'] as String?)?.isNotEmpty == true ? r['referral_note'] as String : s.caseReferredBody,
      ));
    } else if (status == ReportStatus.rejected) {
      notes.add(_RNote(colour: const Color(0xFFC62828), title: context.tr('Not accepted', 'Hindi tinanggap'), body: remarkText ?? s.reportViewRejected));
    } else if (status == ReportStatus.cancelled) {
      notes.add(_RNote(
        colour: const Color(0xFF9AA1AB),
        title: context.tr('Cancelled', 'Kinansela'),
        body: context.tr('You cancelled this report. A cancelled case can’t be opened again.', 'Kinansela mo ang ulat na ito.'),
      ));
    } else if (finished) {
      notes.add(_RNote(
        colour: green,
        title: context.tr('Resolved', 'Naayos na'),
        body: remarkText ?? (_proof.isNotEmpty || _evidence.any((e) => e.kind == 'resolution') ? s.reportViewResolvedWithProof : s.reportViewResolvedNoProof),
        action: _proof.isNotEmpty
            ? (s.reportViewViewPhoto, () => _openPhoto(_proof, 0))
            : _evidence.any((e) => e.kind == 'resolution')
                ? (s.reportViewViewPhoto, () => _openPhoto([for (final e in _evidence) if (e.kind == 'resolution') (url: e.url, isVideo: false)], 0))
                : null,
        foot: reopened > 0 ? (reopened == 1 ? s.reportViewReopenedOnce : s.reportViewReopenedTimes(reopened)) : null,
      ));
    } else if (showsNote) {
      final fallback = status == ReportStatus.assigned || status == ReportStatus.inProgress || status == ReportStatus.offlineInvestigation ? s.reportViewAssigned : null;
      final text = remarkText ?? fallback;
      if (text != null) notes.add(_RNote(colour: stCol, title: stLabel, body: text));
    }

    final barangayPhotos = [for (final e in _evidence) (url: e.url, isVideo: false)];
    final hasMedia = (lat != null && lng != null) || _photos.isNotEmpty || barangayPhotos.isNotEmpty;
    final cancelled = status == ReportStatus.cancelled;
    Widget ask() => DButton(
          context.tr('Ask the barangay', 'Magtanong sa barangay'),
          kind: DButtonKind.line,
          icon: Icons.chat_bubble_outline_rounded,
          expand: true,
          onTap: () => ReportMessagesScreen.open(
            context,
            ReportMessagesScreen(
              reportId: widget.reportId,
              trackingId: r['tracking_id'] as String? ?? '',
              subject: r['subject'] as String? ?? '',
              category: ComplaintCategory.parse(r['category'] as String?),
              canWrite: status != ReportStatus.cancelled && status != ReportStatus.archived,
            ),
          ),
        );

    final actions = <Widget>[];
    if (finished) {
      if (_feedback == null) {
        actions.add(_RateCard(reportId: widget.reportId, onSaved: _load));
      } else {
        actions.add(Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: d.line)),
          child: _FeedbackCard(feedback: _feedback, onRate: _openFeedback),
        ));
      }
      actions.add(ask());
      if (status.canRequestReopen) {
        actions.add(DButton(context.tr('Reopen this report', 'Buksan muli ang ulat'), kind: DButtonKind.line, expand: true, onTap: () => setState(() => _reasonsOpen = !_reasonsOpen)));
        if (_reasonsOpen) {
          actions.add(_ReasonPanel(
            title: context.tr('Why are you reopening it?', 'Bakit mo ito binubuksan muli?'),
            options: [
              context.tr('The problem came back', 'Bumalik ang problema'),
              context.tr('The proof photo doesn’t match', 'Hindi tugma ang litrato'),
              context.tr('Other', 'Iba pa'),
            ],
            busy: _busyAct,
            onBack: () => setState(() => _reasonsOpen = false),
            onConfirm: (why) => _sendRequest('request_reopen', why, '${r['tracking_id']} — ${context.tr('your reopen request was sent.', 'naipadala ang iyong hiling na buksan muli.')}'),
          ));
        }
      }
    } else if (status == ReportStatus.rejected) {
      actions.add(ask());
      if (status.canRequestAppeal) {
        actions.add(DButton(context.tr('Appeal this decision', 'Umapela'), kind: DButtonKind.line, expand: true, onTap: () => setState(() => _reasonsOpen = !_reasonsOpen)));
        if (_reasonsOpen) {
          actions.add(_ReasonPanel(
            title: context.tr('Why are you appealing?', 'Bakit ka umaapela?'),
            options: [
              context.tr('I think the decision was a mistake', 'Sa tingin ko ay mali ang desisyon'),
              context.tr('I have more information', 'May dagdag akong impormasyon'),
              context.tr('Other', 'Iba pa'),
            ],
            busy: _busyAct,
            onBack: () => setState(() => _reasonsOpen = false),
            onConfirm: (why) => _sendRequest('request_appeal', why, '${r['tracking_id']} — ${context.tr('your appeal was sent.', 'naipadala ang iyong apela.')}'),
          ));
        }
      }
    } else if (!cancelled) {
      if (askingDetails) {
        actions.add(DButton(
          s.reportsMenuAddDetails,
          expand: true,
          onTap: () async {
            final sent = await AddDetailsScreen.open(
              context,
              AddDetailsScreen(
                requestId: _detailRequest!['id'] as String,
                trackingId: r['tracking_id'] as String? ?? '',
                subject: r['subject'] as String? ?? '',
                statusLabel: context.s.reportStatusLabel(status.wire),
                createdAt: createdAt,
                question: _detailRequest!['message'] as String? ?? '',
                uploader: widget.uploader!,
              ),
            );
            if (sent && mounted) _load();
          },
        ));
      }
      actions.add(ask());
      if (status.canCancel && !referred) {
        actions.add(DButton(context.tr('Cancel this report', 'Kanselahin ang ulat'), kind: DButtonKind.danger, expand: true, onTap: () => _cancel(r)));
      }
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 16, 18, 32 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(r['subject'] as String? ?? '', style: DType.body(d.ink, size: 19, w: FontWeight.w800).copyWith(height: 1.25)),
        const SizedBox(height: 10),
        Text.rich(TextSpan(children: [
          TextSpan(text: r['tracking_id'] as String? ?? '', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w700, fontSize: 13, color: d.link)),
          TextSpan(text: ' · ', style: DType.body(d.muted, size: 13)),
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: BoxDecoration(shape: BoxShape.circle, color: stCol))),
          TextSpan(text: stLabel, style: DType.body(d.ink, size: 13, w: FontWeight.w700)),
        ])),
        const SizedBox(height: 10),
        Column(children: [
          if (lat != null && lng != null)
            DRow(icon: Icons.place_outlined, title: (r['location_label'] as String?)?.isNotEmpty == true ? r['location_label'] as String : 'Barangay 183', sub: 'Barangay 183, Zone 20, Villamor, Pasay City'),
          if (createdAt != null) DRow(icon: Icons.calendar_today_outlined, title: s.reportsSubmittedOn(_fmtDate(s, createdAt))),
          DRow(
            icon: Icons.shield_outlined,
            title: _hasTanod(status) ? context.tr('A tanod is assigned', 'May naka-assign na tanod') : context.tr('No tanod assigned yet', 'Wala pang tanod'),
            sub: _hasTanod(status) ? context.tr('Assigned to your report', 'Naka-assign sa iyong report') : context.tr('The barangay is reviewing it', 'Sinusuri ng barangay'),
          ),
          if (_official != null)
            DRow(
              icon: Icons.account_balance_outlined,
              title: context.tr('Handled by $_official', 'Hawak ni $_official'),
              sub: (_officialNote?.isNotEmpty ?? false) ? _officialNote : context.tr('Handed up by the barangay', 'Ipinasa ng barangay'),
            ),
          if (lat != null && lng != null) _FloodRow(lat: lat, lng: lng),
          if (status.isOngoing && due != null && !overdue && !referred) DRow(icon: Icons.schedule_rounded, title: s.caseExpectedTitle, sub: dueText(due)),
          if (r['is_anonymous'] == true) DRow(icon: Icons.visibility_off_outlined, title: s.reportViewAnonymous),
        ]),
        const SizedBox(height: 10),
        Text(r['description'] as String? ?? '', style: DType.body(d.ink2, size: 14, w: FontWeight.w400).copyWith(height: 1.5)),
        for (final n in notes) ...[const SizedBox(height: 10), n],
        const SizedBox(height: 10),
        DStepList(
          labels: _short(status, referred)
              ? [context.tr('Filed', 'Naisampa'), referred && status.isOngoing ? context.tr('Escalated to the ${r['referred_to']}', 'In-escalate sa ${r['referred_to']}') : stLabel]
              : [context.tr('Filed', 'Naisampa'), context.tr('Validated', 'Napatunayan'), context.tr('Tanod dispatched', 'Na-dispatch ang tanod'), context.tr('Resolved', 'Nalutas')],
          on: _short(status, referred)
              ? 2
              : switch (status) {
                  ReportStatus.pendingReview => 1,
                  ReportStatus.validated => 2,
                  ReportStatus.assigned || ReportStatus.inProgress || ReportStatus.offlineInvestigation => 3,
                  _ => 4,
                },
          colour: col0,
          subs: createdAt == null ? const {} : {0: _fmtDate(s, createdAt)},
        ),
        // The map and the photos, folded away: the preview's page has
        // neither, so they open from here rather than push the page down.
        if (hasMedia) ...[
          const SizedBox(height: 14),
          _Drop(
            icon: Icons.photo_library_outlined,
            title: context.tr('Location & photos', 'Lokasyon at mga larawan'),
            open: _mediaOpen,
            onTap: () => setState(() => _mediaOpen = !_mediaOpen),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (lat != null && lng != null) _MiniMap(point: LatLng(lat, lng)),
              if (lat != null && lng != null && _photos.isNotEmpty) const SizedBox(height: 12),
              if (_photos.isNotEmpty) _MediaCarousel(photos: _photos, onViewPhoto: (i) => _openPhoto(_photos, i)),
              if (barangayPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(context.tr("The barangay's photos", 'Mga larawan ng barangay'), style: DType.body(d.muted, size: 12, w: FontWeight.w800)),
                const SizedBox(height: 6),
                _MediaCarousel(photos: barangayPhotos, onViewPhoto: (i) => _openPhoto(barangayPhotos, i)),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 10),
        _Drop(
          icon: Icons.timeline_rounded,
          title: _timelineExpanded ? s.reportViewHideTimeline : s.reportViewShowTimeline,
          open: _timelineExpanded,
          onTap: () => setState(() => _timelineExpanded = !_timelineExpanded),
          child: _Timeline(
            entries: _timeline,
            submittedAt: createdAt,
            upcomingWire: status.isOngoing
                ? (status == ReportStatus.pendingReview || status == ReportStatus.validated ? 'assigned' : 'resolved')
                : null,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (var i = 0; i < actions.length; i++) ...[if (i > 0) const SizedBox(height: 8), actions[i]],
        ],
      ]),
    );
  }

  /// Reopen or appeal: a request to the barangay, never a decision — the
  /// report keeps its status until an administrator acts on it.
  Future<void> _sendRequest(String fn, String reason, String done) async {
    final s = context.s;
    setState(() => _busyAct = true);
    try {
      await Supabase.instance.client.rpc(fn, params: {'p_report': widget.reportId, 'p_reason': reason});
      if (!mounted) return;
      setState(() => _reasonsOpen = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.reportsErrorGeneric)));
    } finally {
      if (mounted) setState(() => _busyAct = false);
    }
  }

  static bool _hasTanod(ReportStatus s) =>
      s == ReportStatus.assigned || s == ReportStatus.inProgress || s == ReportStatus.offlineInvestigation || s == ReportStatus.resolved || s == ReportStatus.closed || s == ReportStatus.archived;

  static bool _short(ReportStatus s, bool referred) => s == ReportStatus.rejected || s == ReportStatus.cancelled || (referred && s.isOngoing);

  static Color _statusColour(ReportStatus s) => switch (s) {
        ReportStatus.pendingReview || ReportStatus.validated => const Color(0xFFF59E0B),
        ReportStatus.assigned || ReportStatus.inProgress || ReportStatus.offlineInvestigation => const Color(0xFF356CF9),
        ReportStatus.resolved || ReportStatus.closed || ReportStatus.archived => const Color(0xFF1F8A45),
        ReportStatus.rejected => const Color(0xFFC62828),
        ReportStatus.cancelled => const Color(0xFF9AA1AB),
      };

  /// The resident's "up" on an overdue complaint (0072): an optional
  /// line for the barangay, then follow_up_report(). Once a day.
  Future<void> _followUp(Map<String, dynamic> r) async {
    final s = context.s;
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.colors.bg,
        title: Text(s.followUpTitle,
            style: TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w800,
                color: ctx.colors.navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.followUpBody,
                style: TextStyle(
                    fontFamily: 'Urbanist', fontSize: 13.5, color: ctx.colors.navy)),
            const SizedBox(height: 12),
            TextField(
              controller: note,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: s.followUpHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.followUpCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.followUpSend),
          ),
        ],
      ),
    );
    final message = note.text.trim();
    note.dispose();
    if (go != true || !mounted) return;
    try {
      await Supabase.instance.client.rpc('follow_up_report', params: {
        'p_report': widget.reportId,
        'p_message': message.isEmpty ? null : message,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.followUpSent)));
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message.contains('already followed up')
              ? s.followUpToday
              : s.followUpFailed)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(s.followUpFailed)));
      }
    }
  }

  // Figma 2864:332/2864:461 -- the same flow reports_screen.dart's own
  // _cancel() already uses (same RPC, same confirm-then-confirmed pill
  // dialogs); duplicated rather than shared per this app's established
  // convention for screen-specific widgets (see _ActionDialog below).
  Future<void> _cancel(Map<String, dynamic> r) async {
    final s = context.s;
    final confirmed = await showDialog<bool>(
      barrierColor: context.colors.bg.withValues(alpha: 0.7),
      context: context,
      builder: (_) => _ActionDialog(
        title: s.reportsCancelConfirmTitle,
        body: s.reportsCancelConfirmBody,
        secondaryLabel: s.reportsDialogBack,
        onSecondary: () => Navigator.of(context).pop(false),
        primaryLabel: s.reportsConfirm,
        onPrimary: () => Navigator.of(context).pop(true),
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .rpc('cancel_report', params: {'p_report': widget.reportId});
      if (!mounted) return;
      await showDialog<void>(
        barrierColor: context.colors.bg.withValues(alpha: 0.7),
        context: context,
        barrierDismissible: false,
        builder: (_) => _ActionDialog(
          title: s.reportsCancelledTitle,
          primaryLabel: s.reportsDialogBack,
          onPrimary: () => Navigator.of(context).pop(),
        ),
      );
      if (!mounted) return;
      _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(m.contains('already started working')
              ? s.reportsErrorAlreadyStarted
              : s.reportsErrorGeneric),
          backgroundColor: context.colors.navy,
        ));
    } catch (_) {
      // No connection — same as reports_screen.dart's _cancel.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(s.reportsErrorGeneric),
          backgroundColor: context.colors.navy,
        ));
    }
  }

  Future<void> _openFeedback() async {
    final saved = await showFigmaDialog<bool>(
      context,
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

// Round 17 (30 Aug 2026): the top status field from Round 16 (_StatusBadge)
// is gone -- direct feedback that it had no job on this single-report
// screen and was just taking up space. Removed rather than left unused.

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

  /// Only the line below a fully-`done` dot gets the accent colour --
  /// the line below the current dot stays neutral, since what follows
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
              fontFamily: 'Urbanist',
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
  /// moving and an upcoming row follows.
  final bool isCurrent;

  /// This is the last row drawn, full stop -- no line beneath it.
  final bool isFinalNode;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final status = ReportStatus.parse(entry['new_status'] as String?);
    final when = DateTime.tryParse(entry['created_at'] as String? ?? '');
    final remark = entry['remark'] as String?;
    // "TANOD <NAME>" / "SYSTEM" -- see ReportViewScreen's
    // _loadTimelineAuthors(). Null while the lookup is still in flight,
    // or for a synthetic row (submitted/upcoming), which never has one.
    final author = entry['author_label'] as String?;

    return _TimelineRail(
      hasLineBelow: !isFinalNode,
      bottomPadding: isFinalNode ? 0 : 20,
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
              fontFamily: 'Urbanist',
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

/// The greyed, not-yet-happened last row.
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
              fontFamily: 'Urbanist',
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
  return '${s.monthAbbr(d.month)} ${d.day}, ${d.year} • $h12:$mm $ampm';
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
        // The frame's 1px #F3F3F3 edge; the height stays the 240 asked
        // for on 29 Aug rather than the frame's 189.
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFF3F3F3)),
          borderRadius: BorderRadius.circular(25),
        ),
        // A picture of the place, not a map to explore: no gestures,
        // the pin drawn over the centre with its tip on the report.
        child: Stack(
          children: [
            BrgyMap(
              initialCenter: point,
              interactive: false,
              cornerRadius: 25,
              // The report card behind it (see _ReportCard).
              cornerColour: context.isDark
                  ? context.colors.field
                  : const Color(0xFF00308F),
            ),
            // Navy on the light map, the pale ink on the night one.
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_on,
                    size: 36, color: context.colors.navy),
              ),
            ),
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
                          // Card width, not the 1920 upload.
                          imageUrl: cloudinarySized(photo.url, width: 1080),
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          placeholder: (_, _) => Container(
                            color: context.colors.navy.withValues(alpha: 0.08),
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: context.colors.navy, strokeWidth: 2),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
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

/// The navy pill dialog from Figma 2864:332/2864:461 (Confirm Cancel /
/// Report Cancelled) -- byte-for-byte the same shape as
/// reports_screen.dart's own _ActionDialog, duplicated rather than
/// shared per this app's established convention: every screen that
/// needs this look defines its own copy, since there is no shared
/// dialog widget for it in smartsumbong_core.
class _ActionDialog extends StatelessWidget {
  const _ActionDialog({
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
    this.body,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String title;
  final String? body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  static const _orange = Color(0xFFFF9800);

  // Figma REPORTS - CONFIRM CANCEL / REPORT CANCELLED (2864:332/461):
  // a 300x200 navy card, radius 50, 2px #252525 edge; the title orange
  // at 24/700, the body 16/500, and 106x40 pills 13 apart with the
  // frame's shadow. A lone button is drawn as the frame's navy Back pill.
  @override
  Widget build(BuildContext context) {
    final single = secondaryLabel == null;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        width: 300,
        constraints: const BoxConstraints(minHeight: 200),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        decoration: BoxDecoration(
          color: context.colors.navy,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: const Color(0xFF252525), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 24,
                height: 21 / 24,
                color: _orange,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 22),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 15 / 16,
                  color: context.colors.bg,
                ),
              ),
            ],
            SizedBox(height: body != null ? 23 : 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!single) ...[
                  _DialogPill(
                    label: secondaryLabel!,
                    onTap: onSecondary!,
                    filled: false,
                  ),
                  const SizedBox(width: 13),
                ],
                _DialogPill(
                    label: primaryLabel, onTap: onPrimary, filled: !single),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogPill extends StatelessWidget {
  const _DialogPill({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(50),
    );
    const size = Size(106, 40);
    const text = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 16,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 3.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: filled
          ? FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: context.colors.bg,
                foregroundColor: context.colors.navy,
                fixedSize: size,
                minimumSize: size,
                elevation: 0,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.colors.bg,
                backgroundColor: context.colors.navy,
                side: BorderSide(color: context.colors.bg),
                fixedSize: size,
                minimumSize: size,
                padding: EdgeInsets.zero,
                shape: shape,
                textStyle: text,
              ),
              child: Text(label),
            ),
    );
  }
}

/// Figma 2613:709 — full-screen photo with pinch to zoom. A video page
/// embeds the shared player instead of an InteractiveViewer, since
/// pinch-to-zoom on a playing video is not a thing anyone wants.
/// Full-screen photo/video viewer. No frame of its own: black, as any
/// photo viewer is, with the design's round light close button and a
/// "2 / 3" count when there is more than one.
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.items, required this.initial});

  final List<({String url, bool isVideo})> items;
  final int initial;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final item = items[i];
              if (item.isVideo) {
                return SafeArea(child: InlineVideoPlayer(url: item.url));
              }
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedNetworkImage(
                    imageUrl: item.url,
                    fit: BoxFit.contain,
                    placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(color: Colors.white)),
                    errorWidget: (context, url, error) => Center(
                      child: Text(context.s.reportViewCouldNotLoadPhoto,
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ),
                ),
              );
            },
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Material(
                    color: const Color(0xFFF3F3F3),
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close,
                          color: Color(0xFF00308F), size: 22),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                    ),
                  ),
                  const Spacer(),
                  if (items.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Text(
                        '${_index + 1} / ${items.length}',
                        style: const TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Colors.white,
                        ),
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
            fontFamily: 'Urbanist',
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
          FigmaPill(
            onPressed: onRate,
            child: Text(s.reportViewGiveFeedback),
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
  const _Stars({required this.rating});

  final int rating;
  final double size = 26;

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

  // Figma EMERGENCY - FEEDBACK's popup: a 352-wide #F3F3F3 card with a
  // 2px navy edge, radius 50; the 28/800 title, five 38px orange stars 10
  // apart, "Please provide your feedback" 14/700 over a 128-tall #FBFBFB
  // box (radius 25) with its 0/300 count, and the 180x50 navy Submit.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 352,
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: c.navy, width: 2),
          boxShadow: kFigmaShadow,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 52, 34, 44),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.reportViewFeedbackTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  height: 25 / 28,
                  color: c.navy,
                ),
              ),
              const SizedBox(height: 28),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    Semantics(
                      button: true,
                      selected: i <= _rating,
                      label: s.reportViewRateStars(i),
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: _saving
                            ? null
                            : () => setState(() {
                                  _rating = i;
                                  _error = null;
                                }),
                        radius: 26,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                            i <= _rating
                                ? Icons.star_rounded
                                : Icons.star_outline_rounded,
                            size: 44,
                            color: kFigmaOrange,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),

              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 2),
                  child: Text(
                    s.reportViewProvideFeedback,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 22 / 14,
                      color: c.navy,
                    ),
                  ),
                ),
              ),
              // The count sits inside the box's corner, as the frame has it.
              Stack(
                children: [
                  TextField(
                    controller: _comment,
                    enabled: !_saving,
                    minLines: 5,
                    maxLines: 5,
                    maxLength: 300,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: c.navy,
                    ),
                    decoration: InputDecoration(
                      hintText: s.reportViewCommentHint,
                      hintStyle: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: c.navy,
                      ),
                      counterText: '',
                      contentPadding: const EdgeInsets.fromLTRB(17, 12, 17, 22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(color: c.navy),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(color: c.navy),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide(color: c.navy, width: 2),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 8,
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _comment,
                      builder: (context, v, _) => Text(
                        '${v.text.characters.length}/300',
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w300,
                          fontSize: 10,
                          color: c.navy,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.hint, fontSize: 12)),
              ],
              const SizedBox(height: 30),

              FigmaPill(
                width: 180,
                height: 50,
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: c.bg),
                      )
                    : Text(s.reportViewSendFeedback),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------- Branch D report page pieces ----------

/// The preview's `.rnote`: a tinted card, a dot, a bold title and the
/// words under it; optionally one underlined action and a small foot line.
class _RNote extends StatelessWidget {
  const _RNote({required this.colour, required this.title, required this.body, this.action, this.foot});

  final Color colour;
  final String title;
  final String body;
  final (String, VoidCallback)? action;
  final String? foot;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(colour.withValues(alpha: .10), d.card),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colour.withValues(alpha: .35)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 4), decoration: BoxDecoration(shape: BoxShape.circle, color: colour)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: DType.body(d.ink, size: 13, w: FontWeight.w800).copyWith(height: 1.35)),
            Text(body, style: DType.body(d.ink2, size: 12.5).copyWith(height: 1.45)),
            if (action != null)
              GestureDetector(
                onTap: action!.$2,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(action!.$1, style: DType.body(d.link, size: 12.5, w: FontWeight.w800).copyWith(decoration: TextDecoration.underline)),
                ),
              ),
            if (foot != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(foot!, style: DType.body(d.muted, size: 11.5))),
          ]),
        ),
      ]),
    );
  }
}

/// A folded section: a bordered row with a chevron that opens its content.
class _Drop extends StatelessWidget {
  const _Drop({required this.icon, required this.title, required this.open, required this.onTap, required this.child});

  final IconData icon;
  final String title;
  final bool open;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(14), border: Border.all(color: d.line)),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 20, color: d.link),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: DType.body(d.ink, size: 13.5, w: FontWeight.w700))),
              Icon(open ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: d.muted),
            ]),
          ),
        ),
        if (open) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child),
      ]),
    );
  }
}

/// The Project NOAH flood row: the level at the report's pin.
class _FloodRow extends StatefulWidget {
  const _FloodRow({required this.lat, required this.lng});

  final double lat;
  final double lng;

  @override
  State<_FloodRow> createState() => _FloodRowState();
}

class _FloodRowState extends State<_FloodRow> {
  late final Future<int> _level = FloodHazard.levelAt(widget.lat, widget.lng);

  @override
  Widget build(BuildContext context) => FutureBuilder<int>(
        future: _level,
        builder: (_, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          final title = switch (snap.data!) {
            3 => context.tr('High flood hazard', 'Mataas na panganib sa baha'),
            2 => context.tr('Medium flood hazard', 'Katamtamang panganib sa baha'),
            1 => context.tr('Low flood hazard', 'Mababang panganib sa baha'),
            _ => context.tr('Outside the flood zones', 'Labas sa mga flood zone'),
          };
          return DRow(icon: Icons.waves_rounded, title: title, sub: 'Project NOAH 100-year flood map');
        },
      );
}

/// "How did we do?": stars, a few words, Send feedback — the same insert
/// the old sheet made, now on the page.
class _RateCard extends StatefulWidget {
  const _RateCard({required this.reportId, required this.onSaved});

  final String reportId;
  final Future<void> Function() onSaved;

  @override
  State<_RateCard> createState() => _RateCardState();
}

class _RateCardState extends State<_RateCard> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _saving = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = context.s;
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.reportViewRatingRequired)));
      return;
    }
    setState(() => _saving = true);
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
      await widget.onSaved();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      final m = e.message.toLowerCase();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(m.contains('duplicate') || m.contains('unique')
              ? s.reportViewFeedbackDuplicate
              : m.contains('policy') || m.contains('row-level')
                  ? s.reportViewFeedbackNotFinished
                  : s.reportViewFeedbackFailed)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.reportViewFeedbackFailed)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: d.line)),
      child: Column(children: [
        Text(context.s.reportViewHowDidWeDo, style: DType.body(d.dark ? Colors.white : DColors.brandNavy, size: 16, w: FontWeight.w800)),
        const SizedBox(height: 8),
        Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 1; i <= 5; i++)
            GestureDetector(
              onTap: () => setState(() => _rating = i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.star_rounded, size: 34, color: i <= _rating ? const Color(0xFFFF9800) : d.line),
              ),
            ),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _comment,
          minLines: 2,
          maxLines: 4,
          maxLength: 500,
          style: DType.body(d.ink, size: 13.5),
          decoration: InputDecoration(
            counterText: '',
            hintText: context.tr('Tell us more (optional)', 'Sabihin pa (opsyonal)'),
            hintStyle: DType.body(d.muted, size: 13.5),
            filled: true,
            fillColor: d.card2,
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
          ),
        ),
        const SizedBox(height: 10),
        DButton(context.tr('Send feedback', 'Ipadala'), busy: _saving, onTap: _saving ? null : _send),
      ]),
    );
  }
}

/// The reopen / appeal reasons: a few choices, Other with a line of its
/// own, then Back and Confirm.
class _ReasonPanel extends StatefulWidget {
  const _ReasonPanel({required this.title, required this.options, required this.busy, required this.onBack, required this.onConfirm});

  final String title;
  final List<String> options;
  final bool busy;
  final VoidCallback onBack;
  final void Function(String reason) onConfirm;

  @override
  State<_ReasonPanel> createState() => _ReasonPanelState();
}

class _ReasonPanelState extends State<_ReasonPanel> {
  int _pick = 0;
  final _other = TextEditingController();

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final last = _pick == widget.options.length - 1;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: d.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: d.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.title, style: DType.body(d.ink, size: 13.5, w: FontWeight.w800)),
        const SizedBox(height: 6),
        for (var i = 0; i < widget.options.length; i++)
          InkWell(
            onTap: () => setState(() => _pick = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Icon(_pick == i ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 20, color: _pick == i ? d.link : d.muted),
                const SizedBox(width: 10),
                Expanded(child: Text(widget.options[i], style: DType.body(d.ink, size: 13.5))),
              ]),
            ),
          ),
        if (last)
          TextField(
            controller: _other,
            maxLength: 300,
            style: DType.body(d.ink, size: 13.5),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              counterText: '',
              hintText: context.tr('Tell us why', 'Sabihin kung bakit'),
              hintStyle: DType.body(d.muted, size: 13.5),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: d.line)),
            ),
          ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DButton(context.tr('Back', 'Bumalik'), small: true, kind: DButtonKind.ghost, expand: true, onTap: widget.onBack)),
          const SizedBox(width: 10),
          Expanded(
            child: DButton(
              context.tr('Confirm', 'Kumpirmahin'),
              small: true,
              expand: true,
              busy: widget.busy,
              onTap: widget.busy || (last && _other.text.trim().isEmpty)
                  ? null
                  : () => widget.onConfirm(last ? _other.text.trim() : widget.options[_pick]),
            ),
          ),
        ]),
      ]),
    );
  }
}

String _fmtDate(Strings s, DateTime utc) {
  final d = utc.toLocal();
  return '${s.monthFull(d.month)} ${d.day}, ${d.year}';
}
