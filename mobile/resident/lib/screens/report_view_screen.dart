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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:share_plus/share_plus.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../location_lookup.dart';
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

  /// Round 17 (30 Aug 2026): the full row-by-row timeline is back, per
  /// direct feedback that the barangay actually liked it even though
  /// none of Rose's six frames draw it. Collapsed by default so the
  /// screen still reads like those frames at a glance (note bubble only)
  /// -- expanding is one tap on the centered toggle below the bubble.
  bool _timelineExpanded = false;

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
      // No `category` column here (30 Aug 2026) -- Rose's six frames
      // never show it; that meta line was a reference-mockup addition
      // this round undoes. See _ReportCard's own header.
      final r = await client
          .from('reports')
          .select('id, tracking_id, subject, description, status, '
              'latitude, longitude, is_anonymous, created_at, '
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
    final lat = (r['latitude'] as num?)?.toDouble();
    final lng = (r['longitude'] as num?)?.toDouble();

    // Whether a note bubble shows at all, and what it says, both live in
    // _StatusNoteBubble now (30 Aug 2026) -- see that widget's header.
    // Neither Under Review nor Cancelled gets a bubble in Rose's frames.
    final showsNote = status != ReportStatus.pendingReview &&
        status != ReportStatus.validated &&
        status != ReportStatus.cancelled;
    final latestEntry = _timeline.isNotEmpty ? _timeline.last : null;

    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        // Round 17 (30 Aug 2026): the top status field is gone. It has
        // no job on this screen -- there is only ever one report here,
        // nothing for a dropdown-styled control to switch between -- and
        // it was just taking up space above the card for no reason once
        // that was pointed out. See _StatusBadge's own removal note if
        // that class still lingers in git history.
        _ReportCard(
          trackingId: r['tracking_id'] as String? ?? '',
          subject: r['subject'] as String? ?? '',
          description: r['description'] as String? ?? '',
          status: status,
          createdAt: createdAt,
          isAnonymous: r['is_anonymous'] == true,
          latitude: lat,
          longitude: lng,
          photos: _photos,
          onViewPhoto: (i) => _openPhoto(_photos, i),
          onCancel: status.canCancel ? () => _cancel(r) : null,
        ),

        // Round 20 (30 Aug 2026): the timeline toggle now lives INSIDE
        // the note bubble's own box, not just sharing its row -- direct
        // feedback that having the toggle as bare text next to a bordered
        // card read as two different elements, not one uniform control.
        // See _StatusNoteBubble's own header for the box change. Still
        // only makes sense when there IS a bubble to put it in; the
        // states with none (Under Review, Validated, Cancelled) keep the
        // toggle centered on its own row, same as Round 17.
        const SizedBox(height: 10),
        if (showsNote)
          _StatusNoteBubble(
            status: status,
            latestEntry: latestEntry,
            hasProof: _proof.isNotEmpty,
            proofPhotoUrl: _proof.isNotEmpty ? _proof.first.url : null,
            onViewProof: () => _openPhoto(_proof, 0),
            reopenedCount: (r['reopened_count'] as num?)?.toInt() ?? 0,
            toggle: _TimelineToggle(
              expanded: _timelineExpanded,
              label: _timelineExpanded
                  ? s.reportViewHideTimeline
                  : s.reportViewShowTimeline,
              onTap: () =>
                  setState(() => _timelineExpanded = !_timelineExpanded),
            ),
          )
        else
          Center(
            child: _TimelineToggle(
              expanded: _timelineExpanded,
              label: _timelineExpanded
                  ? s.reportViewHideTimeline
                  : s.reportViewShowTimeline,
              onTap: () =>
                  setState(() => _timelineExpanded = !_timelineExpanded),
            ),
          ),
        if (_timelineExpanded) ...[
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            decoration: BoxDecoration(
              color: context.colors.field,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _Timeline(
              entries: _timeline,
              submittedAt: createdAt,
              upcomingWire: status.isOngoing
                  ? (status == ReportStatus.pendingReview ||
                          status == ReportStatus.validated
                      ? 'assigned'
                      : 'resolved')
                  : null,
            ),
          ),
        ],

        // Feedback closes the loop the resident started -- RLS only
        // allows the insert on a resolved or closed report, so this only
        // ever shows on the states the database would accept. Its own
        // light card again (30 Aug 2026), not absorbed into the navy
        // card -- none of Rose's six frames show ratings living inside
        // the report card itself. Gap to the toggle/bubble row above it
        // tightened 10 -> 6 (Round 19) -- direct feedback that ratings
        // should read as sitting right under the note bubble, not
        // floating further down the screen.
        if (status.isFinished) ...[
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.field,
              borderRadius: BorderRadius.circular(16),
            ),
            child: _FeedbackCard(feedback: _feedback, onRate: _openFeedback),
          ),
        ],
      ],
    );
  }

  // Figma 2864:332/2864:461 -- the same flow reports_screen.dart's own
  // _cancel() already uses (same RPC, same confirm-then-confirmed pill
  // dialogs); duplicated rather than shared per this app's established
  // convention for screen-specific widgets (see _ActionDialog below).
  Future<void> _cancel(Map<String, dynamic> r) async {
    final s = context.s;
    final confirmed = await showDialog<bool>(
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
    }
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

// Round 17 (30 Aug 2026): the top status field from Round 16 (_StatusBadge)
// is gone -- direct feedback that it had no job on this single-report
// screen and was just taking up space. Removed rather than left unused.

/// From status_logs, plus two synthetic rows neither table has to offer:
/// a first "Report submitted" node built from the report's own
/// created_at (submission itself is never a logged transition, so
/// without this the timeline's first real row would be whatever
/// happened to transition it first), and, only while the report is
/// still moving, a last "not yet reached" node for the next stage.
/// Brought back this round (Round 17) after Round 16 had cut it in
/// favour of Rose's single-note-bubble frames -- turns out the barangay
/// actually liked having the full history, so it's back, just collapsed
/// behind the centered toggle in _body() rather than always showing.
/// Styled for the light `field` card it now lives in (this toggle
/// section, not the navy report card) -- same colour roles this widget
/// used the first time it existed, before Round 16 ever deleted it.
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
  return '${s.monthAbbr(d.month)} ${d.day}, ${d.year} • $h12:$mm $ampm';
}

/// The "View Full Timeline" / "Hide Timeline" pill, factored out of
/// _body() (Round 18, 30 Aug 2026) so the same control can sit either
/// on the note bubble's own row (left side, bubble on the right -- the
/// layout the user marked up directly on a live screenshot) or centered
/// on its own row for the report states with no bubble at all (Under
/// Review, Validated, Cancelled), where there's no row to share it with.
class _TimelineToggle extends StatelessWidget {
  const _TimelineToggle({
    required this.expanded,
    required this.label,
    required this.onTap,
  });

  final bool expanded;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: context.colors.navy,
              ),
            ),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: context.colors.navy,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rose's six frames (2436:752/2613:773/2461:490/2613:616/2461:382),
/// redrawn 30 Aug 2026 after 15 rounds of drifting toward a separate
/// reference mockup -- see this file's own header for the full context.
///
/// Navy fill, not the light `field` card Round 4/5 introduced. One
/// inline bold title -- "(# <id> - <Status>) <subject>" -- instead of a
/// meta line plus a corner pill; every status stays plain white except
/// Cancelled, which reads in red (ReportStatus's own pre-Round-11
/// labelColour rule, reinstated rather than reinvented). The body is
/// always the resident's OWN description -- all six frames confirm
/// this, including both Completed ones, whose body text is still the
/// original complaint, untouched by resolution. The tanod's real
/// resolution note and its byline still exist; they moved to
/// _StatusNoteBubble below the card instead of replacing this text --
/// that is what Rose's frames actually show a resolution note doing.
///
/// Map + photo carousel stay at Round 8's enlarged size on purpose --
/// a real, explicitly requested improvement with no connection to the
/// reference mockup's structure, so "back to Figma" does not reach it.
///
/// FIXED navy, not `context.colors.navy` (30 Aug 2026 dark-mode fix).
/// `context.colors.navy` is this app's adaptive ink token -- navy in
/// light mode, but a pale near-white (0xFFEAF0FF) in dark mode, by
/// design (theme.dart's own doc: "the field has always meant primary
/// label/border/button ink, not literally the colour navy"). Using it
/// as this card's FILL meant the "navy card" rendered near-white in
/// dark mode, with its light-on-navy text and icons going invisible on
/// top of it. Rose's Figma file has no dark-mode frames at all
/// (theme.dart's header) -- same as this app's brand orange accent,
/// which is kept identical across both modes rather than themed, this
/// card's navy and its light text/icon content are fixed literals here
/// too, deliberately decoupled from `context.colors`.
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
    this.onCancel,
  });

  final String trackingId;
  final String subject;
  final String description;
  final ReportStatus status;
  final DateTime? createdAt;
  final bool isAnonymous;
  final double? latitude;
  final double? longitude;
  final List<({String url, bool isVideo})> photos;
  final ValueChanged<int> onViewPhoto;

  /// Non-null only when [status.canCancel] -- the "•••" menu is hidden
  /// entirely rather than shown offering nothing, same principle
  /// reports_screen.dart's own _CardMenu documents. "View" and "Reopen"
  /// are deliberately not offered here: "View" has no destination (this
  /// screen already IS that view), and Reopen never appeared in either
  /// of the two open-menu frames Rose actually drew -- both narrower
  /// than reports_screen.dart's own menu on purpose, not an oversight.
  final VoidCallback? onCancel;

  static String _formatDate(Strings s, DateTime utc) {
    final d = utc.toLocal();
    return '${s.monthFull(d.month)} ${d.day}, ${d.year}';
  }

  /// The barangay's brand navy, fixed -- same literal as
  /// theme.dart's `AppColors.light.navy`, not re-exposed from there
  /// since that field is meant to be read through `context.colors`
  /// (which is exactly what this card must NOT do -- see this class's
  /// own header).
  static const _cardNavy = Color(0xFF00308F);
  static const _onNavy = Colors.white;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    const onNavy = _onNavy;
    final onNavyMuted = _onNavy.withValues(alpha: 0.72);
    final isCancelled = status == ReportStatus.cancelled;

    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: _cardNavy,
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.25,
                    ),
                    children: [
                      TextSpan(
                        text: '(# $trackingId - '
                            '${s.reportStatusLabel(status.wire)}) ',
                        style: TextStyle(
                            color: isCancelled ? context.colors.hint : onNavy),
                      ),
                      TextSpan(text: subject, style: TextStyle(color: onNavy)),
                    ],
                  ),
                ),
              ),
              if (onCancel != null) ...[
                const SizedBox(width: 6),
                _CardMenu(onCancel: onCancel!),
              ],
            ],
          ),
          if (isAnonymous) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.visibility_off_outlined, size: 13, color: onNavyMuted),
                const SizedBox(width: 3),
                Text(s.reportViewAnonymous,
                    style: TextStyle(fontSize: 11, color: onNavyMuted)),
              ],
            ),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(s.reportsSubmittedOn(_formatDate(s, createdAt!)),
                    style: TextStyle(fontSize: 11, color: onNavyMuted)),
                if (latitude != null && longitude != null)
                  _LocationLabel(
                    latitude: latitude!,
                    longitude: longitude!,
                    color: onNavyMuted,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // Always the resident's own words -- see this class's own
          // header for why this no longer swaps to the resolution note.
          Text(
            s.reportsCardDescription(description),
            style: TextStyle(fontSize: 12, height: 1.4, color: onNavyMuted),
          ),

          if (latitude != null && longitude != null) ...[
            const SizedBox(height: 14),
            _MiniMap(point: LatLng(latitude!, longitude!)),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 14),
            _MediaCarousel(photos: photos, onViewPhoto: onViewPhoto),
          ],
        ],
      ),
    );
  }
}

/// The "•••" menu on the navy card -- same orange popup, same icon,
/// same Cancel copy as reports_screen.dart's own _CardMenu, but only
/// ever offering Cancel here (see _ReportCard.onCancel's own doc for
/// why View/Reopen are out of scope for this screen). Duplicated rather
/// than imported: reports_screen.dart's copy is a private, file-scoped
/// class, and this app's own convention is to duplicate screen-specific
/// widgets rather than share them (see _ActionDialog below).
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return PopupMenuButton<String>(
      // Fixed white, not context.colors.bg -- this icon sits directly on
      // _ReportCard's own fixed navy fill, which (like that card) is no
      // longer theme-adaptive. See _ReportCard's own header for why.
      icon: const Icon(Icons.more_horiz, color: Colors.white, size: 20),
      color: const Color(0xFFFF9800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (_) => onCancel(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'cancel',
          height: 36,
          child: Row(children: [
            Icon(Icons.cancel_outlined, size: 16, color: context.colors.bg),
            const SizedBox(width: 8),
            Text(s.reportsMenuCancel,
                style: TextStyle(fontSize: 12, color: context.colors.bg)),
          ]),
        ),
      ],
    );
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
  const _LocationLabel({
    required this.latitude,
    required this.longitude,
    this.color,
  });
  final double latitude;
  final double longitude;

  /// Defaults to `context.colors.muted`, right for a light card. The
  /// navy card passes its own "muted-on-navy" tone (30 Aug 2026) so this
  /// stays legible instead of near-invisible on a dark fill.
  final Color? color;

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
        final tint = widget.color ?? context.colors.muted;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on_outlined, size: 12, color: tint),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: tint),
                ),
              ),
            ],
          ),
        );
      },
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

/// Rose's own note bubble -- the one element that replaces the old
/// multi-row timeline entirely (30 Aug 2026). None of the six frames
/// show a row-per-status-change history; instead, a single small bubble
/// floats below-right of the card, only for In Progress / Rejected /
/// Completed (never Under Review or Cancelled -- see _body()'s own
/// `showsNote` for that gate), carrying whatever the tanod or the
/// system most recently logged.
///
/// This is where the Round 12-15 upgrades actually live now: the real
/// resolution/status text and its "TANOD <NAME>:" / "SYSTEM:" byline,
/// still sourced from `timeline` (via ReportViewScreen's
/// _loadTimelineAuthors()/my_status_log_authors, unchanged), just read
/// off `timeline.last` -- the most recent entry, already in
/// chronological order thanks to Round 15's ordering fix -- rather than
/// walked row by row. Falls back to the old canned copy only when there
/// is genuinely no remark to show (a status_logs row with an empty
/// remark, an edge case, not the common path); the byline never shows
/// on the fallback since it isn't anyone's real words.
///
/// FULL-WIDTH BOX, TOGGLE INSIDE (Round 20, 30 Aug 2026). Previously this
/// was a right-aligned "chat bubble" capped at 78% of the screen width,
/// with the timeline toggle sitting outside it as bare text to its left
/// -- direct feedback that the two read as separate elements instead of
/// one control: "why not make the hide timeline also in the box... so
/// its uniform all the way." The box is now `width: double.infinity`,
/// no longer right-aligned, and its own `Row` carries the toggle
/// ([toggle], passed in from `_body()` so this widget doesn't need to
/// know about `_timelineExpanded`), a `VerticalDivider` to separate the
/// two zones, then the note text + avatar filling the rest via
/// `Expanded`. `reopenedCount`'s caption and the proof-photo reveal stay
/// outside this box, unchanged -- they're their own elements underneath
/// it, not part of "the box" the user meant.
///
/// The "View Photo" reveal is a StatefulWidget: tapping it opens an
/// orange-framed panel with the proof photo inline, below the box --
/// matching the two Completed frames Rose drew (one collapsed, one
/// expanded), rather than jumping straight to the full-screen viewer
/// the way the old canned button did. Tapping the revealed photo still
/// opens that full-screen viewer, for zoom.
class _StatusNoteBubble extends StatefulWidget {
  const _StatusNoteBubble({
    required this.status,
    required this.latestEntry,
    required this.hasProof,
    required this.proofPhotoUrl,
    required this.onViewProof,
    required this.reopenedCount,
    required this.toggle,
  });

  final ReportStatus status;
  final Map<String, dynamic>? latestEntry;
  final bool hasProof;
  final String? proofPhotoUrl;
  final VoidCallback onViewProof;
  final int reopenedCount;

  /// The timeline show/hide control, built by `_body()` (it owns
  /// `_timelineExpanded`) and rendered inside this box's own Row so the
  /// toggle and the note read as one uniform card, not two.
  final Widget toggle;

  @override
  State<_StatusNoteBubble> createState() => _StatusNoteBubbleState();
}

class _StatusNoteBubbleState extends State<_StatusNoteBubble> {
  bool _photoExpanded = false;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final status = widget.status;
    final isCompleted = status == ReportStatus.resolved ||
        status == ReportStatus.closed ||
        status == ReportStatus.archived;

    final remark = (widget.latestEntry?['remark'] as String?)?.trim();
    final author = widget.latestEntry?['author_label'] as String?;
    final hasRealRemark = remark != null && remark.isNotEmpty;

    final fallback = switch (status) {
      ReportStatus.assigned ||
      ReportStatus.inProgress ||
      ReportStatus.offlineInvestigation =>
        s.reportViewAssigned,
      ReportStatus.rejected => s.reportViewRejected,
      _ => widget.hasProof
          ? s.reportViewResolvedWithProof
          : s.reportViewResolvedNoProof,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: context.colors.field,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: context.colors.navy.withValues(alpha: 0.25)),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                widget.toggle,
                VerticalDivider(
                  color: context.colors.navy.withValues(alpha: 0.2),
                  thickness: 1,
                  width: 18,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text.rich(
                            TextSpan(children: [
                              if (hasRealRemark && author != null)
                                TextSpan(
                                  text: '$author: ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              TextSpan(
                                  text: hasRealRemark ? remark : fallback),
                              if (isCompleted && widget.hasProof) ...[
                                TextSpan(text: ' '),
                                TextSpan(
                                  text: s.reportViewViewPhoto,
                                  style: const TextStyle(
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  recognizer: (TapGestureRecognizer()
                                    ..onTap = () => setState(
                                        () => _photoExpanded = !_photoExpanded)),
                                ),
                                TextSpan(text: s.reportViewForTheProof),
                              ],
                            ]),
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: context.colors.navy),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const _TanodAvatar(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.reopenedCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6, right: 4),
                child: Text(
                  widget.reopenedCount == 1
                      ? s.reportViewReopenedOnce
                      : s.reportViewReopenedTimes(widget.reopenedCount),
                  style: TextStyle(fontSize: 11, color: context.colors.muted),
                ),
              ),
            if (_photoExpanded && widget.proofPhotoUrl != null) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: widget.onViewProof,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.reportViewViewPhoto,
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Colors.white,
                          )),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CachedNetworkImage(
                          imageUrl: widget.proofPhotoUrl!,
                          fit: BoxFit.cover,
                          height: 160,
                          width: double.infinity,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
    );
  }
}

/// A stand-in for Rose's tanod-uniform avatar icon next to the note
/// bubble -- no exported asset for it came through the screenshots, so
/// this approximates with a Material icon in a small circle rather than
/// skip the element entirely. Worth swapping for the real asset if/when
/// it's exported from Figma.
class _TanodAvatar extends StatelessWidget {
  const _TanodAvatar();

  @override
  Widget build(BuildContext context) {
    // Fixed navy/white, not context.colors.navy (30 Aug 2026 dark-mode
    // fix) -- that token flips to near-white at night, which turned this
    // into an invisible white icon on a white circle. See
    // _ReportCard's own header for the same bug, fixed the same way.
    return const CircleAvatar(
      radius: 12,
      backgroundColor: Color(0xFF00308F),
      child: Icon(Icons.shield_outlined, size: 14, color: Colors.white),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.colors.navy,
      insetPadding: const EdgeInsets.symmetric(horizontal: 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: _orange,
              ),
            ),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: context.colors.bg,
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (secondaryLabel != null) ...[
                  _DialogPill(
                    label: secondaryLabel!,
                    onTap: onSecondary!,
                    filled: false,
                  ),
                  const SizedBox(width: 12),
                ],
                _DialogPill(label: primaryLabel, onTap: onPrimary, filled: true),
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
    const size = Size(96, 38);

    return filled
        ? FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.bg,
              foregroundColor: context.colors.navy,
              minimumSize: size,
              padding: EdgeInsets.zero,
              shape: shape,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            child: Text(label),
          )
        : OutlinedButton(
            onPressed: onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.bg,
              side: BorderSide(color: context.colors.bg),
              minimumSize: size,
              padding: EdgeInsets.zero,
              shape: shape,
              textStyle: const TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            child: Text(label),
          );
  }
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
