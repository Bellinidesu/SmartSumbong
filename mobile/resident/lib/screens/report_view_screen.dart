// SmartSumbong — View a report (the case screen).
//
// 19 Nov 2026 (Ace: "case page now"): rebuilt 1:1 from the approved design canvas, following the portal's case card. A thin
// header; the status said once (the portal's solid pill and one sentence); the portal's segmented track only while the report is
// moving; each concern with its own status when there are several; the one note that matters; evidence you can open; the details
// folded; the full timeline on its own page; feedback. The one main action is pinned at the bottom, the rest sit behind More.
// The parts are in case/case_ui.dart and case/case_screens.dart; this file reads the report's rows and chooses what to say.
//
// LIVE WHILE OPEN (29 Aug 2026): a channel filtered to this report (reports) and its log rows (status_logs) reloads the whole screen
// through the same _load() the pull-to-refresh uses — one fetch path, not two that could drift apart.
//
// Reads only what the app already read (reports, report_media, dispatch_media, report_evidence, report_concerns, status_logs,
// detail_requests, feedback, the byline function); writes only through the same calls (cancel_report, request_reopen,
// request_appeal, follow_up_report, the feedback insert). Nothing new on the server.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:share_plus/share_plus.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../models/barangay_profile.dart';
import '../models/complaint_catalogue.dart';
import '../models/complaint_category.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import 'add_details_screen.dart';
import 'case/case_screens.dart';
import 'case/case_ui.dart';
import 'report_messages_screen.dart';
import 'reports_screen.dart' show ReportStatus, reportStatusColour;

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

  List<({String url, String kind, DateTime? at})> _evidence = const [];
  // 0130: each concern in this report, open or resolved on its own (panel ask 3b).
  List<Map<String, dynamic>> _concerns = const [];
  // 0140: "Was it fixed?", while the barangay's question is open and unanswered.
  Map<String, dynamic>? _fixCheck;
  // 0140: why this report is where it is, in words (English and Filipino), for an open report.
  Map<String, dynamic>? _whyOrder;
  String? _official;
  String? _officialNote;
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
        // the two reads run together (17 Nov 2026: one wait, as the portal does)
        await Future.wait([() async {
        try {
          final ev = await client
              .from('report_evidence')
              .select('kind, media_url, mime_type, created_at')
              .eq('report_id', widget.reportId)
              .order('created_at', ascending: true);
          if (mounted) {
            setState(() => _evidence = [
                  for (final m in ev) (url: m['media_url'] as String, kind: m['kind'] as String? ?? 'update', at: DateTime.tryParse(m['created_at'] as String? ?? '')),
                ]);
          }
        } catch (_) {}
        }(), () async {
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
        }()]);
      }

      // Panel ask 3b (7 Sep 2026): the resident sees each concern's own status. Separate and
      // optional, like the rest: an older database or a failure never blanks the report.
      Future<void> concerns() async {
        try {
          final rows = await client
              .from('report_concerns')
              .select('category, option_id, filed_category_en, filed_category_fil, filed_option_en, filed_option_fil, note, status, resolved_at, remark')
              .eq('report_id', widget.reportId)
              .order('created_at', ascending: true);
          if (mounted) setState(() => _concerns = List<Map<String, dynamic>>.from(rows));
        } catch (_) {}
      }

      // 0140: the barangay's "Was it fixed?" and SMART's "why this order". Separate and optional, so an older
      // database (or a failure here) never blanks the report.
      Future<void> fixCheck() async {
        try {
          final c = await client
              .from('resolution_checks')
              .select('id, asked_at')
              .eq('report_id', widget.reportId)
              .isFilter('answered_at', null)
              .maybeSingle();
          final asked = DateTime.tryParse(c?['asked_at'] as String? ?? '');
          final open = asked != null && asked.isAfter(DateTime.now().subtract(const Duration(days: 14)));
          if (mounted) setState(() => _fixCheck = open ? c : null);
        } catch (_) {}
      }

      Future<void> whyOrder() async {
        try {
          if (!ReportStatus.parse(r['status'] as String?).isOngoing) return;
          final j = await client.rpc('smart_why_order', params: {'p_report': widget.reportId});
          if (mounted && j is Map) setState(() => _whyOrder = Map<String, dynamic>.from(j));
        } catch (_) {}
      }

      await Future.wait([detail(), _loadTimelineAuthors(), barangay(), concerns(), fixCheck(), whyOrder()]);
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
      // 0099: the note as a resident should read it (no tanod names,
      // distances or system jargon).
      final remarks = <String, String?>{};
      for (final row in rows as List) {
        final id = row['status_log_id'] as String?;
        if (id == null) continue;
        if ((row as Map).containsKey('resident_remark')) remarks[id] = row['resident_remark'] as String?;
        final label = bylineFor(row);
        if (label != null) labels[id] = label;
      }
      if (labels.isEmpty && remarks.isEmpty) return;
      setState(() {
        _timeline = [
          for (final entry in _timeline)
            {
              ...entry,
              if (labels.containsKey(entry['id'])) 'author_label': labels[entry['id']],
              if (remarks.containsKey(entry['id'])) 'remark': remarks[entry['id']],
            },
        ];
      });
    } catch (_) {
      // Rows still show with no byline.
    }
  }


  // ---------- the screen -------------------------------------------------------------------------------------------------
  //
  // 19 Nov 2026 (Ace: "case page now"): built 1:1 from the approved canvas. A thin header (the category, back, share); the status
  // said once (the portal's solid pill and one sentence); the portal's track only while the report is moving; the concerns each
  // with their own status when there are several; the one note that matters; evidence you can open; the details folded; the full
  // timeline on its own page; feedback. The one main action is pinned at the bottom and the rest sit behind More.

  @override
  Widget build(BuildContext context) {
    final t = CaseTokens.of(context);
    final r = _report;
    final cat = ComplaintCategory.parse(r?['category'] as String?);
    final top = MediaQuery.paddingOf(context).top;
    final v = r == null ? null : _view(context, r);
    final headerHeight = CaseHeader.heightFor(top);
    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(children: [
        Column(children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth == 0) _pastHero.value = n.metrics.pixels > headerHeight - 8;
                return false;
              },
              child: RefreshIndicator(
                onRefresh: _load,
                color: context.d.accent,
                child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                  SliverToBoxAdapter(
                    child: CaseHeader(
                      colour: r == null ? DStatusPill.grey : categoryColour(cat),
                      glyph: r == null ? null : categoryGlyph(cat),
                      onBack: () => Navigator.of(context).maybePop(),
                      onShare: r == null ? null : _share,
                    ),
                  ),
                  SliverToBoxAdapter(child: _body(context, t, v)),
                ]),
              ),
            ),
          ),
          if (v != null) v.bar,
        ]),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top,
          child: IgnorePointer(
            child: ValueListenableBuilder<bool>(
              valueListenable: _pastHero,
              builder: (context, on, _) => AnimatedOpacity(opacity: on ? 1 : 0, duration: const Duration(milliseconds: 150), child: ColoredBox(color: t.bg)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _body(BuildContext context, CaseTokens t, _CaseView? v) {
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 56, 24, 24),
        child: Column(children: [
          Text(_error!, textAlign: TextAlign.center, style: caseInter(t.dangerInk, 14, FontWeight.w700, 20)),
          const SizedBox(height: 16),
          SizedBox(width: 200, child: CaseButton(label: context.tr('Try again', 'Subukan muli'), icon: Icons.refresh_rounded, kind: CaseButtonKind.ghost, small: true, onTap: _load)),
        ]),
      );
    }
    if (v == null) {
      return Padding(padding: const EdgeInsets.only(top: 60), child: Center(child: CircularProgressIndicator(color: context.d.accent)));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var i = 0; i < v.blocks.length; i++) ...[if (i > 0) const SizedBox(height: 12), v.blocks[i]],
      ]),
    );
  }

  /// The words of a report's state and the blocks that say it, from the report's rows.
  _CaseView _view(BuildContext context, Map<String, dynamic> r) {
    final s = context.s;
    final t = CaseTokens.of(context);
    final fil = AppLocaleScope.of(context) == AppLocale.fil;
    final status = ReportStatus.parse(r['status'] as String?);
    final cat = ComplaintCategory.parse(r['category'] as String?);
    final lat = (r['latitude'] as num?)?.toDouble();
    final lng = (r['longitude'] as num?)?.toDouble();
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    final referred = (r['referred_to'] as String?)?.isNotEmpty ?? false;
    final ongoing = status.isOngoing;
    final finished = status == ReportStatus.resolved || status == ReportStatus.closed || status == ReportStatus.archived;
    final cancelled = status == ReportStatus.cancelled;
    final rejected = status == ReportStatus.rejected;
    final reopened = (r['reopened_count'] as num?)?.toInt() ?? 0;
    final description = (r['description'] as String?)?.trim() ?? '';
    final ticket = r['tracking_id'] as String? ?? '';
    final subject = r['subject'] as String? ?? '';
    final askingDetails = _detailRequest != null && widget.uploader != null && ongoing;
    final multi = _concerns.length > 1;
    final resolvedConcerns = _concerns.where((c) => c['status'] == 'resolved').length;

    // What the resident asked and the barangay has not yet decided (reopen after a resolution, appeal after a rejection).
    final reopenReason = _pendingRequest(status, const {'resolved', 'closed'}, 'Resident requested reopening');
    final appealReason = _pendingRequest(status, const {'rejected'}, 'Resident appealed the rejection', alt: 'Appeal requested');
    final pendingChat = reopenReason != null || appealReason != null;

    // The entry that explains the status: a resolution's note, a rejection's reason, else the newest.
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
    final remark = (latestEntry?['remark'] as String?)?.trim();
    final author = latestEntry?['author_label'] as String?;
    final hasRemark = remark != null && remark.isNotEmpty;
    final remarkText = hasRemark ? (_byline(author) != null ? '${_byline(author)}: $remark' : remark) : null;

    // ---- the pill and the one sentence
    final Color pillColour;
    final String pillLabel;
    final String answer;
    if (reopenReason != null) {
      pillColour = DStatusPill.violet;
      pillLabel = context.tr('Reopen requested', 'Hiniling na buksan muli');
      answer = context.tr('You asked the barangay to reopen this report.', 'Hiniling mo sa barangay na buksan muli ang ulat na ito.');
    } else if (appealReason != null) {
      pillColour = DStatusPill.violet;
      pillLabel = context.tr('Appeal requested', 'Hiniling ang apela');
      answer = context.tr('You asked the barangay to look at this again.', 'Hiniling mo sa barangay na muling tingnan ito.');
    } else {
      pillColour = reportStatusColour(status);
      pillLabel = s.reportStatusLabel(status.wire);
      if (finished) {
        answer = context.tr('Your report is resolved.', 'Nalutas na ang ulat mo.');
      } else if (rejected) {
        answer = context.tr('The barangay could not accept this report.', 'Hindi natanggap ng barangay ang ulat na ito.');
      } else if (cancelled) {
        answer = context.tr('You cancelled this report.', 'Kinansela mo ang ulat na ito.');
      } else if (status == ReportStatus.pendingReview || status == ReportStatus.validated) {
        answer = context.tr('The barangay is reviewing your report.', 'Sinusuri ng barangay ang iyong ulat.');
      } else {
        final base = context.tr('A tanod is on it.', 'May tanod na umaasikaso.');
        answer = multi && resolvedConcerns > 0
            ? '$base ${context.tr('$resolvedConcerns of ${_concerns.length} concerns is resolved.', '$resolvedConcerns sa ${_concerns.length} na concern ang nalutas na.')}'
            : base;
      }
    }
    final violetInk = t.dark ? const Color(0xFFCDBDFF) : DStatusPill.violet;
    final extraLine = referred && ongoing
        ? context.tr('Escalated to the ${r['referred_to']}', 'In-escalate sa ${r['referred_to']}')
        : (reopened > 0 && reopenReason == null ? (reopened == 1 ? s.reportViewReopenedOnce : s.reportViewReopenedTimes(reopened)) : null);

    // ---- overdue, and what the barangay asked for
    final due = DateTime.tryParse(r['due_at'] as String? ?? '')?.toLocal();
    final overdue = ongoing && due != null && due.isBefore(DateTime.now()) && !referred;
    String dueText(DateTime d) {
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '${s.monthFull(d.month)} ${d.day}, ${d.year}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
    }

    final followedAt = DateTime.tryParse(r['followed_up_at'] as String? ?? '');
    final followedToday = followedAt != null && DateTime.now().difference(followedAt).inHours < 24;

    // ---- the evidence
    final mine = <CaseMedia>[
      for (final p in _photos)
        CaseMedia(url: p.url, isVideo: p.isVideo, at: createdAt, title: context.tr('What you sent', 'Ipinadala mo'), text: description.isEmpty ? null : '“$description”'),
    ];
    final finishedAt = _entryTime(latestEntry);
    final barangay = <CaseMedia>[];
    final seen = <String>{};
    for (final p in _proof) {
      if (seen.add(p.url)) {
        barangay.add(CaseMedia(url: p.url, isVideo: p.isVideo, fromBarangay: true, at: finishedAt, title: context.tr('Proof of resolution', 'Patunay ng paglutas'), text: finished ? remarkText : null));
      }
    }
    for (final e in _evidence) {
      if (seen.add(e.url)) {
        final proof = e.kind == 'resolution';
        barangay.add(CaseMedia(
          url: e.url,
          fromBarangay: true,
          at: e.at ?? finishedAt,
          title: proof ? context.tr('Proof of resolution', 'Patunay ng paglutas') : context.tr('An update from the barangay', 'Update mula sa barangay'),
          text: proof ? remarkText : null,
        ));
      }
    }
    final all = [...mine, ...barangay];
    void openViewer(int i) => CaseViewer.open(context, all, i);

    // ---- the blocks, in the canvas' order
    final blocks = <Widget>[];
    blocks.add(CaseTitleBlock(
      title: multi ? context.tr(cat.label, cat.labelFil) : subject,
      ticket: ticket,
      pillLabel: pillLabel,
      pillColour: pillColour,
      filed: createdAt == null ? '' : context.tr('Filed ${s.monthAbbr(createdAt.toLocal().month)} ${createdAt.toLocal().day}', 'Naisampa ${s.monthAbbr(createdAt.toLocal().month)} ${createdAt.toLocal().day}'),
      answer: answer,
      extraLine: extraLine,
      extraColour: referred && ongoing ? violetInk : null,
    ));

    final showFix = _fixCheck != null && status == ReportStatus.resolved && reopenReason == null;
    if (showFix) blocks.add(_FixCheckCard(reportId: widget.reportId, onDone: _load));

    // the portal's track, only while the report is moving
    if (ongoing) blocks.add(Container(padding: const EdgeInsets.all(14), decoration: caseCardBox(t), child: CaseTrack(done: caseStepsDone(status.wire))));

    if (multi) {
      blocks.add(CaseConcernsCard(concerns: _concernRows(context, status, fil), dot: categoryColour(cat)));
    }

    // the one note that matters
    if (overdue) {
      blocks.add(CaseNote(
        tone: DStatusPill.denied,
        title: s.caseOverdue,
        body: s.caseOverdueBody(dueText(due)),
        action: followedToday ? null : (s.followUpButton, () => _followUp(r)),
        foot: followedToday ? s.followUpToday : null,
      ));
    }
    if (reopenReason != null) {
      blocks.add(CaseNote(
        tone: DStatusPill.violet,
        title: context.tr('Your reason', 'Dahilan mo'),
        body: '“${_sentence(reopenReason)}” ${context.tr('The barangay will look at it. You can chat with them here.', 'Titingnan ito ng barangay. Puwede kayong mag-chat dito.')}',
      ));
    } else if (appealReason != null) {
      blocks.add(CaseNote(
        tone: DStatusPill.violet,
        title: context.tr('Your reason', 'Dahilan mo'),
        body: '“${_sentence(appealReason)}” ${context.tr('The barangay will look at it. You can chat with them here.', 'Titingnan ito ng barangay. Puwede kayong mag-chat dito.')}',
      ));
    } else if (askingDetails) {
      blocks.add(CaseNote(tone: DStatusPill.pending, title: context.tr('The barangay needs more details', 'Kailangan ng barangay ng karagdagang detalye'), body: '“${_detailRequest!['message'] as String? ?? ''}”'));
    } else if (referred && ongoing) {
      final note = (r['referral_note'] as String?)?.isNotEmpty == true ? r['referral_note'] as String : s.caseReferredBody;
      blocks.add(CaseNote(tone: DStatusPill.violet, title: context.tr('Escalated to the ${r['referred_to']}', 'In-escalate sa ${r['referred_to']}'), body: note));
    } else if (rejected) {
      blocks.add(CaseNote(tone: DStatusPill.denied, title: context.tr('The barangay’s reason', 'Dahilan ng barangay'), body: remarkText ?? s.reportViewRejected));
    } else if (cancelled) {
      blocks.add(CaseNote(tone: DStatusPill.grey, body: context.tr('A cancelled case can’t be opened again.', 'Hindi na mabubuksan muli ang kinanselang ulat.')));
    } else if (ongoing && status != ReportStatus.pendingReview && status != ReportStatus.validated) {
      // the hand-off already has its own "Handled by" row below; the same words in a note above it read twice
      final handOff = _official != null && (remark ?? '').startsWith('Handed to');
      final update = handOff ? null : (_latestUpdate(context, latestEntry, remarkText) ?? (context.tr('Latest update', 'Pinakabagong update'), s.reportViewAssigned));
      if (update != null) blocks.add(CaseNote(tone: DStatusPill.progress, title: update.$1, body: update.$2));
    }

    // the completed report's big Resolved card
    final showResolved = finished && reopenReason == null;
    final proofItems = [for (var i = 0; i < barangay.length; i++) if (barangay[i].fromBarangay) i];
    final proofIndex = proofItems.isEmpty ? null : mine.length + proofItems.first;
    if (showResolved) {
      blocks.add(CaseResolvedCard(
        words: hasRemark ? remark : (barangay.isNotEmpty ? s.reportViewResolvedWithProof : s.reportViewResolvedNoProof),
        byTanod: (author ?? '').startsWith('TANOD'),
        proof: proofIndex == null ? null : barangay[proofIndex - mine.length],
        onOpenProof: proofIndex == null ? null : () => openViewer(proofIndex),
        steps: _steps(context, createdAt),
      ));
    }

    // where it is: a small map and the address (two fingers move the map; one finger scrolls the page)
    if (lat != null && lng != null) {
      blocks.add(CaseWhereCard(
        point: LatLng(lat, lng),
        colour: categoryColour(cat),
        glyph: cat.icon,
        address: _address(r),
        sub: '${BarangayProfile.name}, ${BarangayProfile.place}',
      ));
    }

    // evidence: with the Resolved card, the proof is already big, so the card keeps your photos and any further proof
    final barangayForCard = showResolved && barangay.isNotEmpty ? barangay.sublist(1) : barangay;
    final addTile = askingDetails ? _addDetails : null;
    if (mine.isNotEmpty || barangayForCard.isNotEmpty || addTile != null) {
      blocks.add(CaseEvidenceCard(
        mine: mine,
        barangay: barangayForCard,
        barangayBase: mine.length + (showResolved && barangay.isNotEmpty ? 1 : 0),
        onOpen: openViewer,
        onAdd: addTile,
      ));
    }

    // the details, folded
    final rows = <CaseDetailRow>[
      if (createdAt != null) CaseDetailRow(Icons.calendar_today_outlined, s.reportsSubmittedOn(_fmtDate(s, createdAt)), context.tr('Filed in the app', 'Isinampa sa app')),
      CaseDetailRow(
        Icons.shield_outlined,
        _hasTanod(status) ? (finished ? context.tr('A tanod handled it', 'Tanod ang umasikaso') : context.tr('A tanod is assigned', 'May naka-assign na tanod')) : context.tr('No tanod assigned yet', 'Wala pang tanod'),
        _hasTanod(status) ? context.tr('Assigned to your report', 'Naka-assign sa iyong report') : context.tr('The barangay is reviewing it', 'Sinusuri ng barangay'),
      ),
      if (_official != null)
        CaseDetailRow(Icons.account_balance_outlined, context.tr('Handled by $_official', 'Hawak ni $_official'), (_officialNote?.isNotEmpty ?? false) ? _officialNote : context.tr('Handed up by the barangay', 'Ipinasa ng barangay')),
      if (ongoing && due != null && !overdue && !referred) CaseDetailRow(Icons.schedule_rounded, s.caseExpectedTitle, dueText(due)),
      if (r['is_anonymous'] == true) CaseDetailRow(Icons.visibility_off_outlined, s.reportViewAnonymous),
    ];
    blocks.add(CaseDetailsCard(
      quote: description,
      rows: rows,
      foldLabel: finished ? context.tr('Your words, and who handled it', 'Ang sinabi mo, at sino ang humawak') : context.tr('Your words, and who is handling it', 'Ang sinabi mo, at sino ang humahawak'),
      extra: [
        if (_whyOrder != null && ongoing)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DEngineCard(
              label: context.tr('WHY THIS ORDER', 'BAKIT GANITO ANG PAGKAKASUNOD'),
              child: Text(context.tr(_whyOrder!['en'] as String? ?? '', _whyOrder!['fil'] as String? ?? ''), style: DType.body(DEngineCard.body, size: 13.5).copyWith(height: 1.45)),
            ),
          ),
      ],
    ));

    blocks.add(CaseFold(
      icon: Icons.calendar_today_outlined,
      label: context.tr('Full timeline', 'Buong timeline'),
      onTap: () => CaseTimelineScreen.open(
        context,
        CaseTimelineScreen(ticket: ticket, category: context.tr(cat.label, cat.labelFil), events: _events(context, r, status, mine, barangay, multi, answer, latestEntry, remarkText, fil)),
      ),
    ));

    // feedback, once the barangay has finished (or while a reopen waits)
    if (finished && status != ReportStatus.archived) {
      if (_feedback == null) {
        blocks.add(_RateCard(reportId: widget.reportId, onSaved: _load));
      } else {
        blocks.add(CaseFeedbackCard(rating: (_feedback!['rating'] as num?)?.toInt() ?? 0, comment: _feedback!['comment'] as String?));
      }
    }

    // ---- the pinned bar: the one main action, the rest behind More
    final canWrite = status != ReportStatus.cancelled && status != ReportStatus.archived;
    void ask() => ReportMessagesScreen.open(
          context,
          ReportMessagesScreen(
            reportId: widget.reportId,
            trackingId: ticket,
            subject: subject,
            category: cat,
            canWrite: canWrite,
            status: (pillLabel, pillColour),
            request: pendingChat
                ? (
                    title: reopenReason != null ? context.tr('You asked to reopen this report', 'Humiling kang buksan muli ang ulat na ito') : context.tr('You appealed this decision', 'Umapela ka sa desisyong ito'),
                    reason: reopenReason ?? appealReason,
                    at: _requestTime(),
                  )
                : null,
          ),
        );
    final askItem = CaseMoreItem(Icons.chat_bubble_outline_rounded, context.tr('Ask the barangay', 'Magtanong sa barangay'), ask);
    final more = <CaseMoreItem>[];
    String label;
    IconData? icon;
    CaseButtonKind kind = CaseButtonKind.primary;
    VoidCallback? onTap;
    if (pendingChat) {
      label = context.tr('Open the chat', 'Buksan ang chat');
      icon = Icons.chat_bubble_outline_rounded;
      onTap = ask;
    } else if (rejected) {
      label = context.tr('Appeal this decision', 'Umapela');
      icon = null;
      kind = CaseButtonKind.appeal;
      onTap = status.canRequestAppeal ? _appeal : null;
      more.add(askItem);
    } else if (cancelled || status == ReportStatus.archived) {
      label = context.tr('Ask the barangay', 'Magtanong sa barangay');
      icon = Icons.chat_bubble_outline_rounded;
      kind = CaseButtonKind.ghost;
      onTap = ask;
    } else if (finished) {
      label = context.tr('Ask the barangay', 'Magtanong sa barangay');
      icon = Icons.chat_bubble_outline_rounded;
      onTap = ask;
      if (status.canRequestReopen) more.add(CaseMoreItem(Icons.refresh_rounded, context.tr('Reopen this report', 'Buksan muli ang ulat'), _reopen));
    } else if (askingDetails) {
      label = s.reportsMenuAddDetails;
      icon = Icons.add_rounded;
      onTap = _addDetails;
      more.add(askItem);
      if (status.canCancel && !referred) more.add(CaseMoreItem(Icons.close_rounded, context.tr('Cancel this report', 'Kanselahin ang ulat'), () => _cancel(r), danger: true));
    } else {
      label = context.tr('Ask the barangay', 'Magtanong sa barangay');
      icon = Icons.chat_bubble_outline_rounded;
      onTap = ask;
      if (status.canCancel && !referred) more.add(CaseMoreItem(Icons.close_rounded, context.tr('Cancel this report', 'Kanselahin ang ulat'), () => _cancel(r), danger: true));
    }
    final bar = CaseActionBar(
      label: label,
      icon: icon,
      kind: kind,
      onTap: onTap,
      busy: _busyAct,
      onMore: more.isEmpty ? null : () => showCaseMore(context, more),
    );
    return _CaseView(blocks: blocks, bar: bar);
  }

  // ---------- reading the report's rows -----------------------------------------------------------------------------------

  /// The reason of a request the resident made and the barangay has not yet decided, or null. A reopen or an appeal leaves the
  /// status as it is and writes one line in the history; a later change of status means the barangay has decided.
  String? _pendingRequest(ReportStatus status, Set<String> statuses, String prefix, {String? alt}) {
    if (!statuses.contains(status.wire)) return null;
    for (var i = _timeline.length - 1; i >= 0; i--) {
      final e = _timeline[i];
      final remark = ((e['remark'] as String?) ?? '').trim();
      for (final p in [prefix, ?alt]) {
        if (remark.startsWith(p)) {
          final at = remark.indexOf(':');
          final why = at < 0 ? '' : remark.substring(at + 1).trim();
          return why.isEmpty ? '…' : why;
        }
      }
      if (e['old_status'] != e['new_status']) return null;
    }
    return null;
  }

  DateTime? _requestTime() {
    for (var i = _timeline.length - 1; i >= 0; i--) {
      final remark = ((_timeline[i]['remark'] as String?) ?? '');
      if (remark.startsWith('Resident requested reopening') || remark.startsWith('Resident appealed') || remark.startsWith('Appeal requested')) {
        return DateTime.tryParse(_timeline[i]['created_at'] as String? ?? '');
      }
    }
    return null;
  }

  static String _sentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return RegExp(r'[.!?…]$').hasMatch(t) ? t : '$t.';
  }

  static DateTime? _entryTime(Map<String, dynamic>? e) => e == null ? null : DateTime.tryParse(e['created_at'] as String? ?? '');

  String _address(Map<String, dynamic> r) => (r['location_label'] as String?)?.isNotEmpty == true ? r['location_label'] as String : BarangayProfile.name;

  /// "TANOD KIM" as "Tanod Kim", "BARANGAY" as "Barangay"; the system has no name to show.
  static String? _byline(String? raw) {
    if (raw == null || raw == 'SYSTEM') return null;
    return raw.toLowerCase().split(' ').where((w) => w.isNotEmpty).map((w) => '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  /// The latest update: a concern resolved since the last note, else the newest line of the history.
  (String, String)? _latestUpdate(BuildContext context, Map<String, dynamic>? entry, String? remarkText) {
    final fil = AppLocaleScope.of(context) == AppLocale.fil;
    DateTime? entryAt = _entryTime(entry);
    Map<String, dynamic>? newest;
    DateTime? newestAt;
    for (final c in _concerns) {
      final at = DateTime.tryParse(c['resolved_at'] as String? ?? '');
      if (c['status'] == 'resolved' && at != null && (newestAt == null || at.isAfter(newestAt))) {
        newest = c;
        newestAt = at;
      }
    }
    if (_concerns.length > 1 && newest != null && (entryAt == null || newestAt!.isAfter(entryAt))) {
      final remark = (newest['remark'] as String?)?.trim() ?? '';
      return (context.tr('${concernOptionName(newest, filipino: fil)} resolved', '${concernOptionName(newest, filipino: fil)} ay nalutas'), remark.isEmpty ? context.tr('Resolved.', 'Nalutas na.') : remark);
    }
    if (remarkText == null) return null;
    return (context.tr('Latest update', 'Pinakabagong update'), remarkText);
  }

  /// Each concern with its own state. The database knows open and resolved; an open concern is Being handled once a tanod is on the report.
  List<CaseConcern> _concernRows(BuildContext context, ReportStatus status, bool fil) {
    final s = context.s;
    final handled = status == ReportStatus.assigned || status == ReportStatus.inProgress || status == ReportStatus.offlineInvestigation;
    return [
      for (final c in _concerns)
        () {
          final resolved = c['status'] == 'resolved';
          final at = DateTime.tryParse(c['resolved_at'] as String? ?? '')?.toLocal();
          final remark = (c['remark'] as String?)?.trim() ?? '';
          final note = (c['note'] as String?)?.trim() ?? '';
          final state = resolved ? CaseConcernState.resolved : (handled ? CaseConcernState.handled : CaseConcernState.open);
          final sub = switch (state) {
            CaseConcernState.resolved => [
                at == null ? context.tr('Resolved', 'Nalutas') : context.tr('Resolved ${s.monthAbbr(at.month)} ${at.day}', 'Nalutas noong ${s.monthAbbr(at.month)} ${at.day}'),
                if (remark.isNotEmpty) remark,
              ].join(' · '),
            CaseConcernState.handled => [context.tr('A tanod is handling it', 'May tanod na umaasikaso'), if (note.isNotEmpty) note].join(' · '),
            CaseConcernState.open => [context.tr('Waiting its turn', 'Naghihintay ng turn'), if (note.isNotEmpty) note].join(' · '),
          };
          return CaseConcern(name: concernOptionName(c, filipino: fil), sub: sub, state: state, filedAs: concernFiledAs(c, filipino: fil));
        }(),
    ];
  }

  static String _clock(DateTime d) {
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    return '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "How it was handled": the steps the report went through, with their times, from its history.
  List<CaseStep> _steps(BuildContext context, DateTime? createdAt) {
    final s = context.s;
    String day(DateTime d) => '${s.monthAbbr(d.toLocal().month)} ${d.toLocal().day}';
    final out = <CaseStep>[];
    DateTime? prev;
    void add(String title, DateTime? at) {
      if (at == null) return;
      final same = prev != null && prev!.toLocal().year == at.toLocal().year && prev!.toLocal().month == at.toLocal().month && prev!.toLocal().day == at.toLocal().day;
      out.add(CaseStep(title, same ? _clock(at) : '${day(at)} · ${_clock(at)}'));
      prev = at;
    }

    add(context.tr('Filed', 'Naisampa'), createdAt);
    final seen = <String>{'filed'};
    for (final e in _timeline) {
      final to = e['new_status'] as String?;
      if (e['old_status'] == to) continue;
      final (key, title) = switch (to) {
        'validated' => ('validated', context.tr('Validated', 'Napatunayan')),
        'assigned' || 'in_progress' || 'offline_investigation' => ('dispatched', context.tr('Tanod dispatched', 'Na-dispatch ang tanod')),
        'resolved' || 'closed' => ('resolved', context.tr('Resolved', 'Nalutas')),
        _ => ('', ''),
      };
      if (key.isEmpty || !seen.add(key)) continue;
      add(title, DateTime.tryParse(e['created_at'] as String? ?? ''));
    }
    return out;
  }

  /// The full timeline, oldest to newest then flipped: the report's history, each concern that was resolved, the evidence at the step it belongs to.
  List<CaseEvent> _events(BuildContext context, Map<String, dynamic> r, ReportStatus status, List<CaseMedia> mine, List<CaseMedia> barangay, bool multi, String answer,
      Map<String, dynamic>? latestEntry, String? remarkText, bool fil) {
    final s = context.s;
    String when(DateTime d) {
      final l = d.toLocal();
      final yr = l.year == DateTime.now().year ? '' : ', ${l.year}';
      return '${s.monthAbbr(l.month)} ${l.day}$yr, ${_clock(l)}';
    }

    final ongoing = status.isOngoing;
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    final items = <(DateTime, CaseEvent)>[];
    if (createdAt != null) {
      items.add((
        createdAt,
        CaseEvent(
          title: context.tr('Filed', 'Naisampa'),
          time: when(createdAt),
          body: multi ? context.tr('You filed this report with ${_concerns.length} concerns.', 'Isinampa mo ang ulat na ito na may ${_concerns.length} na concern.') : context.tr('You filed this report.', 'Isinampa mo ang ulat na ito.'),
          thumbs: mine,
          thumbLabel: mine.isEmpty ? null : context.tr('Your photos', 'Mga larawan mo'),
        ),
      ));
    }
    var proofPlaced = false;
    // concerns that were resolved (several concerns only)
    final concernEvents = <(DateTime, Map<String, dynamic>)>[];
    if (multi) {
      for (final c in _concerns) {
        final at = DateTime.tryParse(c['resolved_at'] as String? ?? '');
        if (c['status'] == 'resolved' && at != null) concernEvents.add((at, c));
      }
      concernEvents.sort((a, b) => a.$1.compareTo(b.$1));
    }
    final lastConcern = concernEvents.isEmpty ? null : concernEvents.last.$2;
    for (final ce in concernEvents) {
      final remark = (ce.$2['remark'] as String?)?.trim() ?? '';
      final carriesProof = !proofPlaced && ongoing && identical(ce.$2, lastConcern) && barangay.isNotEmpty;
      if (carriesProof) proofPlaced = true;
      items.add((
        ce.$1,
        CaseEvent(
          title: context.tr('${concernOptionName(ce.$2, filipino: fil)} resolved', '${concernOptionName(ce.$2, filipino: fil)} ay nalutas'),
          time: when(ce.$1),
          body: remark.isEmpty ? null : remark,
          thumbs: carriesProof ? barangay : const [],
          thumbLabel: carriesProof ? context.tr('Proof from the barangay', 'Patunay mula sa barangay') : null,
        ),
      ));
    }
    for (final e in _timeline) {
      final at = DateTime.tryParse(e['created_at'] as String? ?? '');
      if (at == null) continue;
      final from = e['old_status'] as String?;
      final to = e['new_status'] as String?;
      final remark = ((e['remark'] as String?) ?? '').trim();
      final by = _byline(e['author_label'] as String?);
      final said = remark.isEmpty ? null : (by == null ? remark : '$by: $remark');
      if (from == null && to == 'pending_review') continue; // the Filed event is the report's own
      String? title;
      String? body = said;
      var proof = false;
      var col = CaseTokens.doneFill;
      var ic = Icons.check_rounded;
      if (from != to) {
        switch (to) {
          case 'validated':
            title = context.tr('Validated', 'Napatunayan');
            body = context.tr('The barangay confirmed your report.', 'Kinumpirma ng barangay ang iyong ulat.');
          case 'assigned':
            title = context.tr('Tanod dispatched', 'Na-dispatch ang tanod');
            body = context.tr('A tanod was assigned to your report.', 'May tanod na naka-assign sa iyong ulat.');
            col = DStatusPill.progress;
          case 'in_progress' || 'offline_investigation':
            title = context.tr('A tanod is on it', 'May tanod na umaasikaso');
            col = DStatusPill.progress;
          case 'resolved' || 'closed':
            title = to == 'closed' ? context.tr('Closed', 'Isinara') : context.tr('Resolved', 'Nalutas');
            proof = !proofPlaced && barangay.isNotEmpty;
            if (proof) proofPlaced = true;
          case 'rejected':
            title = context.tr('Rejected', 'Tinanggihan');
            col = DStatusPill.denied;
            ic = Icons.close_rounded;
          case 'cancelled':
            title = context.tr('Cancelled', 'Kinansela');
            col = DStatusPill.grey;
            ic = Icons.close_rounded;
          case 'pending_review':
            title = context.tr('Reopened', 'Binuksan muli');
            col = DStatusPill.violet;
            ic = Icons.refresh_rounded;
        }
      } else if (remark.startsWith('Resident requested reopening')) {
        title = context.tr('You asked to reopen this report', 'Humiling kang buksan muli ang ulat na ito');
        col = DStatusPill.violet;
        ic = Icons.refresh_rounded;
        body = context.tr('Reason: ${_sentence(remark.substring(remark.indexOf(':') + 1).trim())}', 'Dahilan: ${_sentence(remark.substring(remark.indexOf(':') + 1).trim())}');
      } else if (remark.startsWith('Resident appealed') || remark.startsWith('Appeal requested')) {
        title = context.tr('You appealed this decision', 'Umapela ka sa desisyong ito');
        col = DStatusPill.violet;
        ic = Icons.refresh_rounded;
      } else if (remark.startsWith('More details requested')) {
        title = context.tr('The barangay asked for details', 'Humingi ng detalye ang barangay');
        col = DStatusPill.pending;
        ic = Icons.priority_high_rounded;
        body = remark.substring(remark.indexOf(':') + 1).trim();
      } else if (remark.startsWith('Resident sent more details')) {
        title = context.tr('You sent more details', 'Nagpadala ka ng karagdagang detalye');
      } else if (remark.startsWith('Escalated to') || remark.startsWith('Referred to')) {
        title = context.tr('Escalated', 'In-escalate');
        col = DStatusPill.violet;
      }
      if (title == null) continue;
      items.add((
        at,
        CaseEvent(
          title: title,
          time: when(at),
          body: body,
          thumbs: proof ? barangay : const [],
          thumbLabel: proof ? context.tr('Proof from the barangay', 'Patunay mula sa barangay') : null,
          colour: col,
          icon: ic,
        ),
      ));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    final out = [for (final i in items.reversed) i.$2];
    if (ongoing) {
      final open = _concerns.where((c) => c['status'] != 'resolved').toList();
      final lines = [for (final c in _concernRows(context, status, fil)) if (c.state != CaseConcernState.resolved) '${c.name}: ${c.sub.split(' · ').first}'];
      out.insert(
        0,
        CaseEvent(
          title: context.tr('Now', 'Ngayon'),
          time: multi ? context.tr('${open.length} of ${_concerns.length} concerns are still open', '${open.length} sa ${_concerns.length} na concern ang bukas pa') : answer,
          body: multi ? lines.join('. ') : (status == ReportStatus.pendingReview || status == ReportStatus.validated ? null : remarkText),
          now: true,
        ),
      );
    }
    return out;
  }

  // ---------- doing things ----------------------------------------------------------------------------------------------

  Future<void> _addDetails() async {
    final r = _report;
    final q = _detailRequest;
    if (r == null || q == null || widget.uploader == null) return;
    final status = ReportStatus.parse(r['status'] as String?);
    final sent = await AddDetailsScreen.open(
      context,
      AddDetailsScreen(
        requestId: q['id'] as String,
        trackingId: r['tracking_id'] as String? ?? '',
        subject: r['subject'] as String? ?? '',
        statusLabel: context.s.reportStatusLabel(status.wire),
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? ''),
        question: q['message'] as String? ?? '',
        uploader: widget.uploader!,
      ),
    );
    if (sent && mounted) _load();
  }

  /// Reopen: pick the reason, then one request to the barangay (the report keeps its status until an administrator decides).
  Future<void> _reopen() async {
    final r = _report;
    if (r == null) return;
    final why = await showCaseReasonSheet(
      context,
      title: context.tr('Why are you reopening it?', 'Bakit mo ito binubuksan muli?'),
      hint: context.tr('The barangay sees your reason in the chat, and you can talk there.', 'Nakikita ng barangay ang dahilan mo sa chat, at puwede kayong mag-usap doon.'),
      reasons: [
        context.tr('The problem came back', 'Bumalik ang problema'),
        context.tr('The proof photo doesn’t match', 'Hindi tugma ang litrato'),
        context.tr('Other', 'Iba pa'),
      ],
      confirmLabel: context.tr('Reopen this report', 'Buksan muli ang ulat'),
      confirmIcon: Icons.refresh_rounded,
    );
    if (why == null || !mounted) return;
    await _sendRequest('request_reopen', why, '${r['tracking_id']} — ${context.tr('your reopen request was sent.', 'naipadala ang iyong hiling na buksan muli.')}');
  }

  Future<void> _appeal() async {
    final r = _report;
    if (r == null) return;
    final why = await showCaseReasonSheet(
      context,
      title: context.tr('Why are you appealing?', 'Bakit ka umaapela?'),
      hint: context.tr('The barangay sees your reason in the chat, and you can talk there.', 'Nakikita ng barangay ang dahilan mo sa chat, at puwede kayong mag-usap doon.'),
      reasons: [
        context.tr('I think the decision was a mistake', 'Sa tingin ko ay mali ang desisyon'),
        context.tr('I have more information', 'May dagdag akong impormasyon'),
        context.tr('Other', 'Iba pa'),
      ],
      confirmLabel: context.tr('Send my appeal', 'Ipadala ang apela'),
      confirmIcon: Icons.gavel_outlined,
      confirmKind: CaseButtonKind.appeal,
    );
    if (why == null || !mounted) return;
    await _sendRequest('request_appeal', why, '${r['tracking_id']} — ${context.tr('your appeal was sent.', 'naipadala ang iyong apela.')}');
  }

  /// Reopen or appeal: a request to the barangay, never a decision.
  Future<void> _sendRequest(String fn, String reason, String done) async {
    final s = context.s;
    setState(() => _busyAct = true);
    try {
      await Supabase.instance.client.rpc(fn, params: {'p_report': widget.reportId, 'p_reason': reason});
      if (!mounted) return;
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

  /// The resident's "up" on an overdue complaint (0072): an optional
  /// line for the barangay, then follow_up_report(). Once a day.
  Future<void> _followUp(Map<String, dynamic> r) async {
    final s = context.s;
    final note = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => PDialog(
        backgroundColor: ctx.colors.bg,
        title: Text(s.followUpTitle,
            style: TextStyle(
                fontFamily: 'Inter Tight',
                fontWeight: FontWeight.w800,
                color: ctx.colors.navy)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.followUpBody,
                style: TextStyle(
                    fontFamily: 'Inter', fontSize: 13.5, color: ctx.colors.navy)),
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
}

/// What the screen says for one report: the blocks in order, and the pinned bar.
class _CaseView {
  const _CaseView({required this.blocks, required this.bar});

  final List<Widget> blocks;
  final Widget bar;
}

// ---------- pieces that stay ---------------------------------

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
                fontFamily: 'Inter Tight',
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
                  fontFamily: 'Inter',
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
      fontFamily: 'Inter',
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

/// 0140: "Naayos na ba? / Was it fixed?", asked of the resident when the barangay resolves their report. One
/// answer, within 14 days. "No" opens a line for what is still wrong and tells the barangay, who then reopen the
/// report or write back.
class _FixCheckCard extends StatefulWidget {
  const _FixCheckCard({required this.reportId, required this.onDone});

  final String reportId;
  final VoidCallback onDone;

  @override
  State<_FixCheckCard> createState() => _FixCheckCardState();
}

class _FixCheckCardState extends State<_FixCheckCard> {
  final _note = TextEditingController();
  bool _no = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send(bool fixed) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note = _note.text.trim();
      await Supabase.instance.client.rpc('confirm_fix', params: {
        'p_report': widget.reportId,
        'p_fixed': fixed,
        'p_note': fixed || note.isEmpty ? null : note,
      });
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.tr('Could not send that. Please try again.', 'Hindi naipadala. Subukan muli.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DEngineCard(
      label: context.tr('WAS IT FIXED?', 'NAAYOS NA BA?'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          context.tr('The barangay marked this report resolved. Tell us if the problem is really gone.',
              'Minarkahan ng barangay na naresolba ang report na ito. Sabihin sa amin kung wala na talaga ang problema.'),
          style: DType.body(DEngineCard.title, size: 14, w: FontWeight.w600).copyWith(height: 1.4),
        ),
        const SizedBox(height: 12),
        if (!_no)
          Row(children: [
            Expanded(child: DButton(context.tr('Yes, fixed', 'Oo, naayos na'), expand: true, busy: _busy, onTap: _busy ? null : () => _send(true))),
            const SizedBox(width: 10),
            Expanded(child: DButton(context.tr('Not yet', 'Hindi pa'), kind: DButtonKind.white, expand: true, onTap: _busy ? null : () => setState(() => _no = true))),
          ])
        else ...[
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 3,
            minLines: 2,
            enabled: !_busy,
            style: DType.body(const Color(0xFF141B34), size: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              counterStyle: DType.body(DEngineCard.body, size: 11),
              hintText: context.tr('What is still wrong? (optional)', 'Ano ang problema pa? (opsyonal)'),
              hintStyle: DType.body(const Color(0xFF6B6B6B), size: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 8),
          DButton(context.tr('Send to the barangay', 'Ipadala sa barangay'), expand: true, busy: _busy, onTap: _busy ? null : () => _send(false)),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: DType.body(const Color(0xFFFF8A8A), size: 12.5, w: FontWeight.w700)),
        ],
      ]),
    );
  }
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
      decoration: d.cardBox(16),
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
            fillColor: d.field,   // was card2, the navy of the role cards: dark ink on dark navy could not be read (Rose, 16 Nov 2026)
            contentPadding: const EdgeInsets.all(10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: d.line)),
          ),
        ),
        const SizedBox(height: 10),
        DButton(context.tr('Send feedback', 'Ipadala'), expand: true, busy: _saving, onTap: _saving ? null : _send),
      ]),
    );
  }
}


String _fmtDate(Strings s, DateTime utc) {
  final d = utc.toLocal();
  return '${s.monthFull(d.month)} ${d.day}, ${d.year}';
}

/// Who wrote a timeline entry, as the resident reads it: "BARANGAY" for
/// anything an administrator did (residents see the barangay as one body,
/// as in the chat), `"TANOD <NAME>"` for a tanod, "SYSTEM" for the system.
String? bylineFor(Map row) {
  if (row['is_system'] as bool? ?? false) return 'SYSTEM';
  final role = row['author_role'] as String?;
  final name = (row['author_name'] as String?)?.trim();
  if (role == 'admin' || name == 'Barangay') return 'BARANGAY';
  if (name == null || name.isEmpty) return null;
  return 'TANOD ${casualName(name).toUpperCase()}';
}

/// A concern's name today: its category and, when it has one, its option (0163), from the barangay's list as the phone last read it.
String concernTitle(Map<String, dynamic> c, {required bool filipino}) {
  final cat = ComplaintCategory.parse(c['category'] as String?);
  final id = (c['option_id'] as num?)?.toInt();
  final opt = id == null ? null : cat.options.where((o) => o.id == id).firstOrNull;
  final catName = filipino ? cat.labelFil : cat.label;
  final optName = opt != null
      ? (filipino ? opt.fil : opt.en)
      : ((filipino ? c['filed_option_fil'] : c['filed_option_en']) as String?);
  return optName == null || optName.isEmpty ? catName : '$catName: $optName';
}

/// "Filed as ..." when the category or the option was renamed or switched off after this concern was raised (0163); null when not.
String? concernFiledAs(Map<String, dynamic> c, {required bool filipino}) {
  final wire = c['category'] as String?;
  final filedCat = (c['filed_category_en'] as String?) ?? '';
  final filedOpt = (c['filed_option_en'] as String?) ?? '';
  final offered = ComplaintCatalogue.current.where((x) => x.wire == wire).firstOrNull;
  final id = (c['option_id'] as num?)?.toInt();
  final opt = offered == null || id == null ? null : offered.options.where((o) => o.id == id).firstOrNull;
  final off = offered == null || (filedOpt.isNotEmpty && opt == null);
  final renamed = (offered != null && filedCat.isNotEmpty && filedCat != offered.label) || (opt != null && filedOpt.isNotEmpty && filedOpt != opt.en);
  if (!off && !renamed) return null;
  final was = [
    filipino ? ((c['filed_category_fil'] as String?) ?? filedCat) : filedCat,
    if (filedOpt.isNotEmpty) filipino ? ((c['filed_option_fil'] as String?) ?? filedOpt) : filedOpt,
  ].where((x) => x.isNotEmpty).join(': ');
  if (was.isEmpty) return null;
  return filipino
      ? 'Isinampa bilang "$was" (${off ? 'hindi na inaalok' : 'pinalitan ang pangalan mula noon'})'
      : 'Filed as "$was" (${off ? 'no longer offered' : 'renamed since'})';
}

/// A concern's name inside its own report: the option alone ("Illegal Parking"), since the report's title already says the category
/// (one category per report, 0176). The category's name stands in when the concern has no option.
String concernOptionName(Map<String, dynamic> c, {required bool filipino}) {
  final cat = ComplaintCategory.parse(c['category'] as String?);
  final id = (c['option_id'] as num?)?.toInt();
  final opt = id == null ? null : cat.options.where((o) => o.id == id).firstOrNull;
  final name = opt != null ? (filipino ? opt.fil : opt.en) : ((filipino ? c['filed_option_fil'] : c['filed_option_en']) as String?);
  return name == null || name.isEmpty ? (filipino ? cat.labelFil : cat.label) : name;
}
