// SmartSumbong — View your Reports.
//
// Figma node 2869:156, with the cancel flow from 2864:332 / 2864:461 and
// the reopen reason screen from 2780:3762.
//
// TWO ACTIONS THE DESIGN GIVES THE RESIDENT.
//
// Cancel is theirs, and 0023 allows it from pending_review and validated
// only — once a tanod is dispatched somebody is walking to a location,
// and a complaint that evaporates underneath them is worse than one left
// open. The menu hides the option rather than showing it and failing.
//
// Reopen is the design's, but reopen_report() in 0002 is admin-only and
// should stay that way: reopening restarts the SLA clock, re-notifies
// staff and increments a counter the Report Summary reads. So the button
// and the reason screen are Rose's verbatim, and what they do is raise a
// request through request_reopen(). The success copy is the one visible
// difference, and it is honest — the barangay decides.
//
// The "Ticket Reopened" confirmation (Figma TICKET REOPENED) is built as
// the frame lays it out, but says what is true: request_reopen() only
// files a request, and the report's status does not change until an
// admin calls the admin-only reopen_report(). So the page reads "your
// reopen request was sent", not "was reopened" (_RequestSentPage). The
// same page confirms an appeal.
//
// The reason screen (2780:3594) picked up three things it was missing
// during the Figma parity pass (27 Aug 2026): the Original Closing
// Remarks / Date Closed context (status_logs_read already lets a
// resident read their own trail, so this is a read, not a schema
// change), the accuracy checkbox, and the optional Attach Media tile —
// request_reopen() now takes p_media the same shape as file_report()'s
// (migration 0037) and writes it into report_media same as any other
// report evidence, so the 35 MB combined cap and the URL-pinning check
// both still apply to it.
//
// A THIRD ACTION, ADDED 10 SEP 2026, NOT IN ANY FIGMA FRAME: Appeal.
// Rose's feedback list asked for a way to dispute a rejected complaint —
// the one outcome that previously had no resident-facing recourse at
// all (Cancel never applied to it, and Reopen is gated to isFinished,
// which rejected deliberately is not). Built as the rejected path's own
// Cancel/Reopen pair rather than folding it into Reopen: request_appeal()
// and appeal_report() (0057) are new, but they follow request_reopen()/
// reopen_report()'s exact split, so the same "request, not a decision"
// honesty applies — see _requestAppeal's own comment. The sheet
// (_AppealSheet, bottom of this file) is a deliberate near-duplicate of
// _ReopenSheet for the same reason report_view_screen.dart gives for NOT
// collapsing its six status frames into fewer than they need: the copy
// differs throughout, so sharing the widget would just be an if/else
// wearing a trenchcoat.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../d/d_categories.dart';
import '../d/d_theme.dart';
import '../d/d_ui.dart';
import '../i18n.dart';
import '../location_lookup.dart';
import '../models/complaint_category.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import '../outbox.dart';
import '../widgets/resident_nav_bar.dart';
import 'add_details_screen.dart';

/// Mirrors `public.report_status` in 0001, plus `cancelled` from 0023.
enum ReportStatus {
  pendingReview('pending_review', 'Under Review'),
  validated('validated', 'Under Review'),
  assigned('assigned', 'In Progress'),
  inProgress('in_progress', 'In Progress'),
  offlineInvestigation('offline_investigation', 'In Progress'),
  resolved('resolved', 'Completed'),
  closed('closed', 'Completed'),
  archived('archived', 'Completed'),
  rejected('rejected', 'Rejected'),
  cancelled('cancelled', 'Cancelled');

  const ReportStatus(this.wire, this.label);
  final String wire;

  /// What the resident sees. Several internal states collapse into one
  /// label: a resident does not need to know the difference between
  /// assigned and offline_investigation, only that someone is on it.
  final String label;

  static ReportStatus parse(String? w) => ReportStatus.values.firstWhere(
        (s) => s.wire == w,
        orElse: () => ReportStatus.pendingReview,
      );

  bool get canCancel =>
      this == ReportStatus.pendingReview || this == ReportStatus.validated;

  /// The complaint has run its course. Mirrors the RLS condition on
  /// feedback_insert, which is the only place a resident is allowed to
  /// rate a case.
  bool get isFinished =>
      this == ReportStatus.resolved || this == ReportStatus.closed;

  bool get canRequestReopen => isFinished;

  /// The rejected path's own version of canRequestReopen — added 10 Sep
  /// 2026 alongside request_appeal() (0057). A denial is not "finished"
  /// in the sense isFinished means (nobody did any work), so it gets its
  /// own gate rather than being folded into that one.
  bool get canRequestAppeal => this == ReportStatus.rejected;

  /// Still moving — not resolved/closed/archived, not rejected, not
  /// cancelled. Exactly the states worth a resident watching in real
  /// time; see the hero-card comment on ReportsScreen for what reads
  /// this. Spelled out explicitly rather than as "not isFinished" so a
  /// future status the enum doesn't list yet fails safe (excluded, not
  /// silently swept in).
  bool get isOngoing =>
      this == ReportStatus.pendingReview ||
      this == ReportStatus.validated ||
      this == ReportStatus.assigned ||
      this == ReportStatus.inProgress ||
      this == ReportStatus.offlineInvestigation;

  /// Cancelled is drawn in red in the design — it is the one outcome the
  /// resident caused, and it reads differently from a rejection. Takes a
  /// [BuildContext] (rather than being a plain getter) because the
  /// non-cancelled colour is the theme's `bg` — dark mode's whole point
  /// is that value differs by brightness, and an enum has no context of
  /// its own to read that from.
  Color labelColour(BuildContext context) =>
      this == ReportStatus.cancelled
          ? const Color(0xFFFF4949)
          : context.colors.bg;
}

/// The filter above the list. Groups map to several wire values.
enum ReportFilter {
  all('All', null),
  underReview('Under Review', ['pending_review', 'validated']),
  inProgress('In Progress',
      ['assigned', 'in_progress', 'offline_investigation']),
  rejected('Rejected', ['rejected']),
  cancelled('Cancelled', ['cancelled']),
  completed('Completed', ['resolved', 'closed', 'archived']);

  const ReportFilter(this.label, this.wires);
  final String label;
  final List<String>? wires;
}

class ReportSummary {
  ReportSummary({
    required this.id,
    required this.trackingId,
    required this.subject,
    required this.description,
    required this.status,
    required this.category,
    required this.createdAt,
    this.closedAt,
    this.latitude,
    this.longitude,
    this.locationLabel,
  });

  final String id;
  final String trackingId;
  final String subject;
  final String description;
  final ReportStatus status;

  /// Added 29 Aug 2026, aesthetics pass — the reference mockup's card
  /// shows "TRACKING-ID · Category" above the title; this screen never
  /// selected category before, only status.
  final ComplaintCategory category;

  final DateTime createdAt;

  /// Null until the report is resolved or closed. Shown, with the closing
  /// remark from status_logs, on the Reopen sheet (Figma 2780:3594) so the
  /// resident can see what they are asking to reopen.
  final DateTime? closedAt;

  /// Added 29 Aug 2026, 1:1 pass — 0001 has no free-text address column
  /// to put next to the mockup's `"📍 <place>"` footer line (see
  /// location_lookup.dart's header for the full reasoning), so these
  /// feed a best-effort reverse-geocode lookup instead of a stored
  /// string. Null for a report with no pinned location.
  final double? latitude;
  final double? longitude;

  /// The street saved with the complaint (0068), when there is one.
  final String? locationLabel;

  factory ReportSummary.fromRow(Map<String, dynamic> r) => ReportSummary(
        id: r['id'] as String,
        trackingId: r['tracking_id'] as String? ?? '',
        subject: r['subject'] as String? ?? '',
        description: r['description'] as String? ?? '',
        status: ReportStatus.parse(r['status'] as String?),
        category: ComplaintCategory.parse(r['category'] as String?),
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        closedAt: DateTime.tryParse(r['closed_at'] as String? ?? ''),
        latitude: (r['latitude'] as num?)?.toDouble(),
        longitude: (r['longitude'] as num?)?.toDouble(),
        locationLabel: r['location_label'] as String?,
      );
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.auth, required this.uploader});

  final AuthService auth;

  /// Only needed for the Reopen sheet's optional evidence photo (0037) —
  /// every other action on this screen is text-only.
  final MediaUploader uploader;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportFilter _filter = ReportFilter.all;
  List<ReportSummary>? _reports;
  String? _error;

  // The 29 Aug "hero" card (an expanded status_logs timeline on the first
  // ongoing report) came from the reference mockup the barangay
  // supervisor later set aside for Rose's frames (see
  // report_view_screen.dart's ROUND 16 header). Removed 23 Sep 2026 with
  // Ace's go-ahead when this list moved to Figma REPORTS (2869:156):
  // the latest update stays one tap away in View Report's note bubble.

  /// report_id -> the tanod's own resolution note, for every finished
  /// report in the CURRENT list. Added 29 Aug 2026 to close the gap the
  /// resident spotted: report_view_screen.dart's card already swaps in
  /// this text once a report is resolved (see that file's
  /// _resolutionNote() and its header comment for where the text comes
  /// from -- submit_field_report, 0002, writes it straight into
  /// status_logs.remark, already resident-readable, no schema/RLS
  /// change), but this screen's list cards kept showing the resident's
  /// own original description even after resolution, because they never
  /// fetched a timeline at all.
  ///
  /// Deliberately ONE query for the whole visible list rather than a
  /// per-report pattern: a resident's Completed filter can hold
  /// dozens of cards, and firing one status_logs query per card would be
  /// the N+1 this comment exists to avoid. See _loadResolutionNotes().
  Map<String, String> _resolutionNotes = const {};

  /// report_id -> `"TANOD <NAME>"` or "SYSTEM", the byline for the entry
  /// in _resolutionNotes. Added 29 Aug 2026, same round: a remark with
  /// no byline reads like an anonymous status line even though it's
  /// someone's own account of what they did. status_logs.remark never
  /// carries a name (0002 never wrote one, and status_logs is immutable
  /// -- 0015 -- so it never will for reports already resolved), so this
  /// comes from 0049's my_resolution_authors RPC instead: a narrow,
  /// read-only function that resolves status_logs.changed_by to a name
  /// ONLY for the caller's own resolved reports, rather than widening
  /// RLS on public.users the way 0047's header explicitly rejected doing
  /// for the auto-dispatch case. Absent (no key) means the byline isn't
  /// known yet or the lookup found nothing to say -- the card just shows
  /// the bare remark, same as before this existed.
  Map<String, String> _resolutionAuthors = const {};

  // Live updates (29 Aug 2026 — see home_screen.dart's header for the
  // same reasoning, and 0046 for the notifications side of it). reports
  // has been in the realtime publication since 0004 for the admin map,
  // so this list riding along costs nothing new at the database level —
  // only the one extra open channel, while this screen is on screen.
  RealtimeChannel? _liveChannel;
  Timer? _liveDebounce;

  @override
  void initState() {
    super.initState();
    Outbox.instance.addListener(_onOutbox);
    _load();
  }

  @override
  void dispose() {
    Outbox.instance.removeListener(_onOutbox);
    _liveDebounce?.cancel();
    if (_liveChannel != null) {
      Supabase.instance.client.removeChannel(_liveChannel!);
    }
    super.dispose();
  }

  void _subscribeLive(String uid) {
    if (_liveChannel != null) return;
    _liveChannel = Supabase.instance.client
        .channel('resident-reports-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'reports',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'resident_id',
          value: uid,
        ),
        callback: (_) => _scheduleLiveReload(),
      )
      ..subscribe();
  }

  void _scheduleLiveReload() {
    _liveDebounce?.cancel();
    _liveDebounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) _load();
    });
  }

  // Reports queued with no signal (lib/outbox.dart). When one goes
  // through, it becomes a real report here, so the list reloads.
  int _queued = Outbox.instance.items.length;

  void _onOutbox() {
    final n = Outbox.instance.items.length;
    final sentOne = n < _queued;
    _queued = n;
    if (!mounted) return;
    setState(() {});
    if (sentOne) _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
      return;
    }

    _subscribeLive(uid);

    setState(() => _error = null);
    // The last copy of the list, at once (branch B); the network refresh
    // replaces it a moment later.
    if (_reports == null) {
      final saved = await JsonCache.read('reports');
      if (saved is List && mounted && _reports == null) {
        setState(() => _reports = [
              for (final r in saved)
                ReportSummary.fromRow(Map<String, dynamic>.from(r as Map)),
            ]);
      }
    }
    try {
      // reports_resident_read already limits this to the caller's own
      // reports, but filtering here too keeps the query honest about
      // what it means rather than relying on the policy for correctness.
      final rows = await client
          .from('reports')
          .select('id, tracking_id, subject, description, status, category, '
              'created_at, closed_at, latitude, longitude, location_label')
          .eq('resident_id', uid)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      unawaited(JsonCache.write('reports', rows));
      if (!mounted) return;
      setState(() => _reports = [
            for (final r in rows) ReportSummary.fromRow(r),
          ]);
      // The notes and the details requests don't depend on each other.
      await Future.wait([_loadResolutionNotes(), _loadDetailRequests()]);
    } catch (e) {
      if (!mounted) return;
      // No signal but the saved list is showing: keep it.
      if (_reports != null) return;
      setState(() => _error = context.s.reportsLoadError);
    }
  }

  /// Open requests for more details (0065), by report id — one query
  /// for the whole list, like _resolutionNotes. A report with one gets
  /// "Add details" in its menu.
  Map<String, ({String id, String message})> _detailRequests = const {};

  Future<void> _loadDetailRequests() async {
    try {
      final rows = await Supabase.instance.client
          .from('detail_requests')
          .select('id, report_id, message')
          .isFilter('responded_at', null);
      if (!mounted) return;
      setState(() => _detailRequests = {
            for (final q in rows)
              q['report_id'] as String: (
                id: q['id'] as String,
                message: q['message'] as String? ?? '',
              ),
          });
    } catch (_) {
      // The list still works; only the menu item is missing.
    }
  }

  Future<void> _addDetails(ReportSummary r) async {
    final q = _detailRequests[r.id];
    if (q == null) return;
    final sent = await AddDetailsScreen.open(
      context,
      AddDetailsScreen(
        requestId: q.id,
        trackingId: r.trackingId,
        subject: r.subject,
        statusLabel: context.s.reportStatusLabel(r.status.wire),
        createdAt: r.createdAt,
        question: q.message,
        uploader: widget.uploader,
      ),
    );
    if (sent && mounted) _load();
  }

  /// Batch fetch for _resolutionNotes -- one status_logs query covering
  /// every finished report in _reports, not one per card. Mirrors
  /// report_view_screen.dart's _resolutionNote() exactly (same finished
  /// set, same 'resolved' wire value, same "most recent wins" rule for a
  /// report that was reopened and resolved again), just done as a batch
  /// group-by instead of one report's timeline scan.
  Future<void> _loadResolutionNotes() async {
    const finished = {
      ReportStatus.resolved,
      ReportStatus.closed,
      ReportStatus.archived,
    };
    final ids = (_reports ?? const <ReportSummary>[])
        .where((r) => finished.contains(r.status))
        .map((r) => r.id)
        .toList();
    if (ids.isEmpty) {
      if (mounted &&
          (_resolutionNotes.isNotEmpty || _resolutionAuthors.isNotEmpty)) {
        setState(() {
          _resolutionNotes = const {};
          _resolutionAuthors = const {};
        });
      }
      return;
    }
    try {
      // Newest first, so the first row seen per report_id below is the
      // latest 'resolved' entry -- the same entry a reopened-then-
      // resolved-again report's timeline would surface last.
      final rows = await Supabase.instance.client
          .from('status_logs')
          .select('report_id, remark, created_at')
          .inFilter('report_id', ids)
          .eq('new_status', 'resolved')
          .order('created_at', ascending: false);
      if (!mounted) return;
      final notes = <String, String>{};
      for (final row in rows) {
        final id = row['report_id'] as String?;
        if (id == null || notes.containsKey(id)) continue;
        final remark = (row['remark'] as String?)?.trim();
        if (remark != null && remark.isNotEmpty) notes[id] = remark;
      }
      setState(() => _resolutionNotes = notes);
    } catch (_) {
      // Cards still show fine without it -- falls back to the resident's
      // own description, same as before this existed.
    }
    await _loadResolutionAuthors(ids);
  }

  /// Who wrote each note in _resolutionNotes -- `"TANOD <NAME>"` or
  /// "SYSTEM" -- via 0049's my_resolution_authors RPC. Kept as its own
  /// try/catch, separate from the remark fetch above: a byline the app
  /// can't resolve is a reason to show the remark bare, never a reason
  /// to hide the remark itself.
  Future<void> _loadResolutionAuthors(List<String> ids) async {
    try {
      final rows = await Supabase.instance.client
          .rpc('my_resolution_authors', params: {'p_report_ids': ids});
      if (!mounted) return;
      final authors = <String, String>{};
      for (final row in rows as List) {
        final id = row['report_id'] as String?;
        if (id == null) continue;
        final isSystem = row['is_system'] as bool? ?? false;
        final name = (row['author_name'] as String?)?.trim();
        if (isSystem) {
          authors[id] = 'SYSTEM';
        } else if (name != null && name.isNotEmpty) {
          authors[id] = 'TANOD ${casualName(name).toUpperCase()}';
        }
      }
      setState(() => _resolutionAuthors = authors);
    } catch (_) {
      // The note still shows with no byline -- see the field's own doc
      // comment.
    }
  }

  List<ReportSummary> get _visible {
    final all = _reports ?? const <ReportSummary>[];
    final wires = _filter.wires;
    if (wires == null) return all;
    return all.where((r) => wires.contains(r.status.wire)).toList();
  }

  Map<ReportFilter, int> get _filterCounts {
    final all = _reports ?? const <ReportSummary>[];
    return {
      for (final f in ReportFilter.values)
        f: f.wires == null
            ? all.length
            : all.where((r) => f.wires!.contains(r.status.wire)).length,
    };
  }

  void _setFilter(ReportFilter f) {
    setState(() => _filter = f);
  }

  // ---------- actions ----------------------------------------

  Future<void> _cancel(ReportSummary r) async {
    // Figma 2864:332 — the same navy pill dialog as everywhere else in
    // the app, not a plain Material AlertDialog. This used to be one;
    // fixed during the Figma parity pass (27 Aug 2026).
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
          .rpc('cancel_report', params: {'p_report': r.id});
      if (!mounted) return;
      // Figma 2864:461 — a follow-up modal, not a snackbar.
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
      _toast(_friendly(e.message));
    } catch (_) {
      // No connection: without this the tap just did nothing, and the
      // reason typed into the sheet was gone with no word why.
      if (!mounted) return;
      _toast(context.s.reportsErrorGeneric);
    }
  }

  Future<void> _requestReopen(ReportSummary r) async {
    // Figma 2780:3594 shows the original closing remark and date closed
    // above the reopen form — the resident is being asked "reopen this
    // specific outcome?" and that context is what makes the question
    // answerable. status_logs_read (0003) already lets a resident read
    // their own report's trail, so this costs one query, not a schema
    // change.
    String? closingRemark;
    try {
      final log = await Supabase.instance.client
          .from('status_logs')
          .select('remark')
          .eq('report_id', r.id)
          .inFilter('new_status', ['resolved', 'closed'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      closingRemark = (log?['remark'] as String?)?.trim();
      if (closingRemark != null && closingRemark.isEmpty) closingRemark = null;
    } catch (_) {
      // The sheet still works without it; the resident just sees less
      // context than the design shows.
    }

    if (!mounted) return;
    // A full page on the app background, as Figma draws it — the sheet
    // used to be transparent over the list, which the navy cards behind
    // it made unreadable.
    final result = await showModalBottomSheet<_ReopenResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(),
      constraints: const BoxConstraints.expand(),
      builder: (_) => _ReopenSheet(
        report: r,
        closingRemark: closingRemark,
        uploader: widget.uploader,
      ),
    );
    if (result == null || result.reason.trim().isEmpty) return;

    try {
      await Supabase.instance.client.rpc(
        'request_reopen',
        params: {
          'p_report': r.id,
          'p_reason': result.reason.trim(),
          if (result.media != null) 'p_media': [result.media!.toJson()],
        },
      );
      if (!mounted) return;
      // Honest about what happened: the request is with the barangay,
      // the report has not changed state.
      _load();
      await _RequestSentPage.show(context, r, appeal: false);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _toast(_friendly(e.message));
    } catch (_) {
      // No connection: without this the tap just did nothing, and the
      // reason typed into the sheet was gone with no word why.
      if (!mounted) return;
      _toast(context.s.reportsErrorGeneric);
    }
  }

  /// The appeal counterpart to [_requestReopen] — same shape end to end
  /// (fetch context, show a sheet, raise a request, be honest that
  /// nothing has changed yet), for a rejected complaint instead of a
  /// finished one. request_appeal() (0057) only files the request;
  /// appeal_report() (admin-only) is what actually reinstates the case.
  Future<void> _requestAppeal(ReportSummary r) async {
    // Same reasoning as _requestReopen's closing-remark fetch: the
    // resident is being asked "dispute this specific denial?", so the
    // denial reason and when it happened are shown above the form.
    String? denialRemark;
    DateTime? deniedAt;
    try {
      final log = await Supabase.instance.client
          .from('status_logs')
          .select('remark, created_at')
          .eq('report_id', r.id)
          .eq('new_status', 'rejected')
          // Before 0062 the SLA sweep kept logging "SLA breach" rows on
          // rejected reports, newer than the rejection itself; those are
          // not the denial.
          .or('remark.is.null,remark.not.like."SLA breach*"')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      denialRemark = (log?['remark'] as String?)?.trim();
      if (denialRemark != null && denialRemark.isEmpty) denialRemark = null;
      deniedAt = DateTime.tryParse(log?['created_at'] as String? ?? '');
    } catch (_) {
      // The sheet still works without it; the resident just sees less
      // context than the design shows for Reopen.
    }

    if (!mounted) return;
    // A full page on the app background, as Figma draws it — the sheet
    // used to be transparent over the list, which the navy cards behind
    // it made unreadable.
    final result = await showModalBottomSheet<_AppealResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(),
      constraints: const BoxConstraints.expand(),
      builder: (_) => _AppealSheet(
        report: r,
        denialRemark: denialRemark,
        deniedAt: deniedAt,
        uploader: widget.uploader,
      ),
    );
    if (result == null || result.reason.trim().isEmpty) return;

    try {
      await Supabase.instance.client.rpc(
        'request_appeal',
        params: {
          'p_report': r.id,
          'p_reason': result.reason.trim(),
          if (result.media != null) 'p_media': [result.media!.toJson()],
        },
      );
      if (!mounted) return;
      // Same honesty as _requestReopen — the request is with the
      // barangay, the report has not changed state.
      _load();
      await _RequestSentPage.show(context, r, appeal: true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _toast(_friendly(e.message));
    } catch (_) {
      // No connection: without this the tap just did nothing, and the
      // reason typed into the sheet was gone with no word why.
      if (!mounted) return;
      _toast(context.s.reportsErrorGeneric);
    }
  }

  String _friendly(String raw) {
    final m = raw.toLowerCase();
    final s = context.s;
    if (m.contains('already started working')) {
      return s.reportsErrorAlreadyStarted;
    }
    if (m.contains('only a finished report')) {
      return s.reportsErrorOnlyCompletedReopen;
    }
    if (m.contains('only a rejected complaint')) {
      return s.reportsErrorOnlyRejectedAppeal;
    }
    if (m.contains('only the resident')) {
      return s.reportsErrorOwnReportsOnly;
    }
    if (m.contains('say why') || m.contains('explain why')) {
      return s.reportsErrorGiveReason;
    }
    return s.reportsErrorGeneric;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: context.colors.navy,
      ));
  }

  // ---------- build ------------------------------------------

  // Branch D: Your reports in the preview's look — the heading, the
  // filter, anything still waiting to send, then each report as a white
  // card with its category colour down the side, a status pill, the
  // subject, ticket, date and street, and the resident's words (or the
  // tanod's resolution note once it is done). The menu keeps every
  // action: view, cancel, reopen, appeal, add details.
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;
    final d = context.d;
    return DPage(
      bottomBar: const ResidentNavBar(current: ResidentTab.reports),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 18),
          Text(s.reportsViewTitle, style: DType.h1(d.accent).copyWith(fontSize: 28)),
          const SizedBox(height: 10),
          _FilterDropdown(value: _filter, counts: _filterCounts, onChanged: _setFilter),
          const SizedBox(height: 14),
          // Waiting to send: at most a couple on screen, the rest a
          // scroll away inside the same box.
          if (Outbox.instance.items.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: SingleChildScrollView(
                child: Column(children: [
                  for (final q in Outbox.instance.items) ...[_QueuedCard(item: q), const SizedBox(height: 12)],
                ]),
              ),
            ),
          Expanded(
            child: RefreshIndicator(onRefresh: _load, color: d.accent, child: _body(t, s)),
          ),
        ]),
      ),
    );
  }

  Widget _body(TextTheme t, Strings s) {
    final d = context.d;
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 60),
        Text(_error!, textAlign: TextAlign.center, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 14, w: FontWeight.w700)),
      ]);
    }
    if (_reports == null) {
      return Center(child: CircularProgressIndicator(color: d.accent));
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 70),
        Icon(Icons.description_outlined, size: 46, color: d.muted),
        const SizedBox(height: 12),
        Text(
          _filter == ReportFilter.all ? s.reportsEmptyAll : s.reportsEmptyFiltered(s.reportFilterLabel(_filter.name).toLowerCase()),
          textAlign: TextAlign.center,
          style: DType.body(d.muted, size: 14),
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final r = visible[i];
        return _ReportCard(
          report: r,
          resolutionNote: _resolutionNotes[r.id],
          resolutionAuthor: _resolutionAuthors[r.id],
          onView: () => Navigator.of(context).pushNamed('/report', arguments: r.id).then((_) => _load()),
          onCancel: r.status.canCancel ? () => _cancel(r) : null,
          onReopen: r.status.canRequestReopen ? () => _requestReopen(r) : null,
          onAppeal: r.status.canRequestAppeal ? () => _requestAppeal(r) : null,
          onAddDetails: _detailRequests.containsKey(r.id) ? () => _addDetails(r) : null,
        );
      },
    );
  }
}

// ---------- pieces -------------------------------------------

/// A report kept on the phone until there is signal (lib/outbox.dart):
/// the report card's shape, outlined rather than filled, so it reads as
/// "not filed yet"; Send now and Discard under it.
class _QueuedCard extends StatelessWidget {
  const _QueuedCard({required this.item});

  final OutboxItem item;

  Future<void> _discard(BuildContext context) async {
    final s = context.s;
    final yes = await showFigmaDialog<bool>(
      context,
      builder: (d) => FigmaDialog(
        title: s.outboxDiscardTitle,
        body: s.outboxDiscardBody,
        secondaryLabel: s.settingsCancel,
        onSecondary: () => Navigator.of(d).pop(false),
        primaryLabel: s.outboxDiscard,
        onPrimary: () => Navigator.of(d).pop(true),
        destructive: true,
      ),
    );
    if (yes == true) await Outbox.instance.discard(item.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final c = context.colors;
    final refused = item.error != null;
    final accent = refused ? kFigmaRed : kFigmaOrange;
    Widget pill(String label, VoidCallback onTap, {bool filled = false}) =>
        SizedBox(
          height: 30,
          child: FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: filled ? c.navy : c.field,
              foregroundColor: filled ? c.bg : c.navy,
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              elevation: 0,
              side: BorderSide(color: c.navy),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              textStyle: const TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            child: Text(label),
          ),
        );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 12),
      decoration: BoxDecoration(
        color: c.field,
        border: Border.all(color: accent, width: 1.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(refused ? Icons.error_outline : Icons.cloud_upload_outlined,
                  size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                s.outboxWaitingTitle,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            item.subject,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              height: 1.2,
              color: c.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            refused ? s.outboxRefused(item.error!) : s.outboxWaitingBody,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w500,
              fontSize: 12,
              height: 1.3,
              color: refused ? kFigmaRed : c.muted,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              pill(s.outboxSendNow,
                  () => refused
                      ? Outbox.instance.retry(item.id)
                      : Outbox.instance.flush(),
                  filled: true),
              pill(s.outboxDiscard, () => _discard(context)),
            ],
          ),
        ],
      ),
    );
  }
}

/// The dropdown filter Figma specifies, restored (30 Aug 2026) after a
/// brief chip-row detour during the reference-mockup aesthetics pass --
/// the user's own call, keeping this one control as the original design
/// even while the cards and timeline it filters kept the mockup's
/// structure. No prior copy of the original dropdown survived to restore
/// verbatim (fully replaced, not commented out, and this repo has no git
/// history in this environment), so this is rebuilt from the app's own
/// standard themed field -- a plain DropdownButtonFormField picks up
/// theme.dart's InputDecorationTheme automatically (pill-radius border,
/// navy outline, field fill), the exact same styling every other
/// dropdown/text field in the app already uses (see the reopen sheet's
/// own reason dropdown further down this file), rather than a bespoke
/// look invented for just this one screen. The live per-filter counts
/// stay in each item's label -- a genuine improvement the mockup work
/// surfaced, not something the user asked to give back, just no longer
/// tied to a row of buttons.
class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.value,
    required this.counts,
    required this.onChanged,
  });

  final ReportFilter value;
  final Map<ReportFilter, int> counts;
  final ValueChanged<ReportFilter> onChanged;

  // Figma's "Reports" dropdown: a 47-tall #FBFBFB box, 1px navy, radius
  // 20, 15 padding, Inter 14/400, a navy chevron, y5 / blur 5 shadow at
  // 30%. The open list keeps the same box colour and radius.
  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: context.colors.navy),
    );
    final itemStyle = TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 14,
      color: context.colors.navy,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x4D121212),
            blurRadius: 3.5,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: DropdownButtonFormField<ReportFilter>(
        initialValue: value,
        isExpanded: true,
        style: itemStyle,
        dropdownColor: context.colors.field,
        borderRadius: BorderRadius.circular(20),
        icon: Icon(Icons.keyboard_arrow_down_rounded,
            color: context.colors.navy, size: 20),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: context.colors.field,
          contentPadding: const EdgeInsets.fromLTRB(15, 15, 12, 15),
          border: border,
          enabledBorder: border,
          focusedBorder: border,
        ),
        items: [
          for (final f in ReportFilter.values)
            DropdownMenuItem(
              value: f,
              child: Text(
                  '${context.s.reportFilterLabel(f.name)} (${counts[f] ?? 0})',
                  style: itemStyle),
            ),
        ],
        onChanged: (f) {
          if (f != null) onChanged(f);
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.onView,
    this.resolutionNote,
    this.resolutionAuthor,
    this.onCancel,
    this.onReopen,
    this.onAppeal,
    this.onAddDetails,
  });

  final ReportSummary report;
  final VoidCallback onView;

  /// The tanod's own resolution note, when this report is finished and
  /// one exists (batch-fetched for the whole visible list).
  final String? resolutionNote;

  /// `"TANOD <NAME>"` or "SYSTEM" — who wrote [resolutionNote] (0049).
  final String? resolutionAuthor;

  final VoidCallback? onCancel;
  final VoidCallback? onReopen;
  final VoidCallback? onAppeal;
  final VoidCallback? onAddDetails;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final d = context.d;
    final col = categoryColour(report.category);
    final st = reportStatusColour(report.status);
    return Material(
      color: d.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: onAddDetails != null ? DColors.orange : d.line, width: onAddDetails != null ? 1.6 : 1)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: col),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: st.withValues(alpha: .14), borderRadius: BorderRadius.circular(99)),
                      child: Text(s.reportStatusLabel(report.status.wire),
                          style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, color: d.dark ? Color.lerp(st, Colors.white, .35) : st)),
                    ),
                    if (onAddDetails != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                        decoration: BoxDecoration(color: DColors.orange.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)),
                        child: Text(context.tr('Details needed', 'Kailangan ng detalye'),
                            style: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFFB26A00))),
                      ),
                    ],
                    const Spacer(),
                    _CardMenu(onView: onView, onCancel: onCancel, onReopen: onReopen, onAppeal: onAppeal, onAddDetails: onAddDetails),
                  ]),
                  const SizedBox(height: 6),
                  Text(report.subject, style: DType.h3(d.ink).copyWith(fontSize: 17)),
                  const SizedBox(height: 2),
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(report.trackingId, style: DType.mono(d.link, size: 12.5)),
                    Text(_formatDate(s, report.createdAt), style: DType.body(d.muted, size: 12.5)),
                    if (report.latitude != null && report.longitude != null)
                      _LocationLabel(latitude: report.latitude!, longitude: report.longitude!, stored: report.locationLabel, color: d.muted),
                  ]),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Text.rich(
                      TextSpan(children: [
                        if (resolutionNote != null && resolutionAuthor != null)
                          TextSpan(text: '$resolutionAuthor: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                        TextSpan(text: resolutionNote ?? s.reportsCardDescription(report.description)),
                      ]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: DType.body(d.ink2, size: 13),
                    ),
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  static String _formatDate(Strings s, DateTime utc) {
    final d = utc.toLocal();
    return '${s.monthFull(d.month)} ${d.day}, ${d.year}';
  }
}

/// The preview's status colours.
Color reportStatusColour(ReportStatus s) => switch (s) {
      ReportStatus.pendingReview || ReportStatus.validated => const Color(0xFFF59E0B),
      ReportStatus.assigned || ReportStatus.inProgress || ReportStatus.offlineInvestigation => const Color(0xFF356CF9),
      ReportStatus.resolved || ReportStatus.closed || ReportStatus.archived => const Color(0xFF1F8A45),
      ReportStatus.rejected => const Color(0xFFC62828),
      ReportStatus.cancelled => const Color(0xFF9AA1AB),
    };

/// The mockup's `"📍 <place>"` footer meta item, resolved from the
/// report's coordinates via location_lookup.dart rather than a stored
/// address string -- see that file's header for the full reasoning.
/// Renders nothing (not a coordinate pair, not an error) while loading
/// or when the lookup comes back empty, including its own trailing gap
/// so the date beside it never ends up with a stray double space when
/// there's nothing to show.
class _LocationLabel extends StatefulWidget {
  const _LocationLabel({
    required this.latitude,
    required this.longitude,
    this.stored,
    this.color,
  });
  final double latitude;
  final double longitude;
  final String? stored;

  /// Defaults to the theme's muted grey.
  final Color? color;

  @override
  State<_LocationLabel> createState() => _LocationLabelState();
}

class _LocationLabelState extends State<_LocationLabel> {
  late Future<String?> _future = _resolve();

  /// The street saved with the complaint (0068) when there is one; the
  /// live lookup only for complaints filed before it existed.
  Future<String?> _resolve() {
    final saved = widget.stored;
    if (saved != null && saved.isNotEmpty) return Future.value(saved);
    return ReverseGeocode.lookup(widget.latitude, widget.longitude);
  }

  @override
  void didUpdateWidget(covariant _LocationLabel old) {
    super.didUpdateWidget(old);
    if (old.latitude != widget.latitude || old.longitude != widget.longitude ||
        old.stored != widget.stored) {
      _future = _resolve();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snap) {
        final name = snap.data;
        if (name == null || name.isEmpty) return const SizedBox.shrink();
        final colour = widget.color ?? context.colors.muted;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, size: 12, color: colour),
            const SizedBox(width: 3),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: colour),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The three-dot menu. Actions the backend would refuse are absent
/// rather than present and failing — a menu that offers Cancel on a
/// dispatched report teaches the resident the app is unreliable.
class _CardMenu extends StatelessWidget {
  const _CardMenu({
    required this.onView,
    this.onCancel,
    this.onReopen,
    this.onAppeal,
    this.onAddDetails,
  });

  final VoidCallback onView;
  final VoidCallback? onCancel;
  final VoidCallback? onReopen;
  final VoidCallback? onAppeal;

  /// Present only while the tanod is waiting on more details (0065).
  final VoidCallback? onAddDetails;

  static const _orange = Color(0xFFFF9800);
  static const _ink = Color(0xFFF3F3F3);

  // Figma: three 4x4 orange dots (2 apart) at the card's top right, and
  // an 83-wide orange pop-over (radius 10) of 12px rows — icon, label —
  // split by 1px #F3F3F3 lines. View and Reopen are 700, Cancel 500, as
  // drawn. Appeal (10 Sep, in no frame) takes Reopen's style.
  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final rows = <({String value, String label, Widget icon, bool bold})>[
      (
        value: 'view',
        label: s.reportsMenuView,
        icon: Image.asset('assets/images/menu-view.png', width: 13, height: 8),
        bold: true,
      ),
      if (onCancel != null)
        (
          value: 'cancel',
          label: s.reportsMenuCancel,
          icon: Image.asset('assets/images/menu-cancel.png',
              width: 10, height: 10),
          bold: false,
        ),
      if (onReopen != null)
        (
          value: 'reopen',
          label: s.reportsMenuReopen,
          icon: Image.asset('assets/images/menu-reopen.png',
              width: 13, height: 13),
          bold: true,
        ),
      if (onAppeal != null)
        (
          value: 'appeal',
          label: s.reportsMenuAppeal,
          icon: const Icon(Icons.gavel_outlined, size: 12, color: _ink),
          bold: true,
        ),
      if (onAddDetails != null)
        (
          value: 'details',
          label: s.reportsMenuAddDetails,
          icon: const Icon(Icons.add_comment_outlined, size: 12, color: _ink),
          bold: true,
        ),
    ];
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      color: _orange,
      elevation: 2,
      menuPadding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 83, maxWidth: 160),
      offset: const Offset(-20, 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) {
        switch (v) {
          case 'view':
            onView();
          case 'cancel':
            onCancel?.call();
          case 'reopen':
            onReopen?.call();
          case 'appeal':
            onAppeal?.call();
          case 'details':
            onAddDetails?.call();
        }
      },
      itemBuilder: (_) => [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const PopupMenuDivider(height: 1, thickness: 1, color: _ink),
          PopupMenuItem<String>(
            value: rows[i].value,
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(
              children: [
                SizedBox(width: 13, child: Center(child: rows[i].icon)),
                const SizedBox(width: 8),
                Text(
                  rows[i].label,
                  style: TextStyle(
                    fontFamily: 'Urbanist',
                    fontWeight: rows[i].bold ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 12,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      // The dots are drawn at the frame's size inside a finger-sized
      // target.
      child: const SizedBox(
        width: 32,
        height: 24,
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _Dot(),
                SizedBox(width: 2),
                _Dot(),
                SizedBox(width: 2),
                _Dot(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 4,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _CardMenu._orange,
            shape: BoxShape.circle,
          ),
        ),
      );
}

/// The navy pill dialog from REPORTS - CONFIRM CANCEL and
/// REPORTS - REPORT CANCELLED. Same shape as edit_profile_screen.dart's
/// _ProfileDialog — orange title, optional white body, one or two pills
/// — duplicated here rather than shared because every screen in this
/// app that needs this look defines its own copy; there is no shared
/// dialog widget in smartsumbong_core for it.
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

/// Figma 2780:3762 — Reason of Reopen.
class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.prompt});

  final String title;
  final String prompt;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.bg,
      title: Text(widget.title, style: const TextStyle(fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.prompt,
              style: const TextStyle(fontSize: 13, height: 1.3)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            maxLines: 4,
            maxLength: 300,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              filled: true,
              fillColor: context.colors.field,
              hintText: context.s.reportsReasonDialogHint,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: context.colors.navy),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.s.reportsDialogBack),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(context.s.reportsReasonDialogSend),
        ),
      ],
    );
  }
}


// ---------- reopen -------------------------------------------

/// The sheet from REPORTS - REOPEN.
///
/// The reason is a menu rather than free text because the barangay
/// reads these to decide, and a fixed vocabulary is easier to weigh
/// than a paragraph. The concern box carries the detail.
///
/// The frame also offers an optional photo. There is nowhere to put
/// one: request_reopen(uuid, text) takes text and writes it to
/// status_logs, and no media row is keyed to a reopen request. It is
/// left out rather than shown and discarded.
///
/// Reasons are developer-invented and belong on the list of values the
/// barangay still has to confirm, alongside the SLA windows.
const _reopenReasons = <String>[
  'The problem came back',
  'The problem was not fixed',
  'The proof does not match my report',
  'Other',
];

/// What the sheet hands back to [_ReportsScreenState._requestReopen] —
/// the reason text plus, if the resident attached one, the already-
/// uploaded photo. Uploading happens inside the sheet (same as every
/// other photo picker in this app) so a failed upload is a banner here,
/// not a half-finished RPC call in the parent.
class _ReopenResult {
  const _ReopenResult({required this.reason, this.media});
  final String reason;
  final UploadedMedia? media;
}

class _ReopenSheet extends StatefulWidget {
  const _ReopenSheet({
    required this.report,
    required this.uploader,
    this.closingRemark,
  });

  final ReportSummary report;
  final MediaUploader uploader;

  /// The remark left on the status_logs row that resolved or closed this
  /// report, if there is one. Figma 2780:3594 pairs this with Date Closed
  /// so the resident can see the outcome they are asking to reopen.
  final String? closingRemark;

  @override
  State<_ReopenSheet> createState() => _ReopenSheetState();
}

class _ReopenSheetState extends State<_ReopenSheet> {
  final _concern = TextEditingController();
  String? _reason;
  bool _acknowledged = false;
  String? _error;
  String? _banner;
  bool _busy = false;

  /// Figma 2780:3594's "(Optional) Attach Media" — one photo, matching
  /// request_reopen()'s p_media (0037), which takes a single-item array
  /// the same shape as file_report()'s.
  File? _photo;

  @override
  void dispose() {
    _concern.dispose();
    super.dispose();
  }

  /// Gallery-only until 9 Sep 2026 — same gap as the other photo pickers
  /// in this app, fixed the same day (see report_details_screen.dart's
  /// _chooseSource for why offering the camera here is safe).
  Future<ImageSource?> _chooseSource(BuildContext context) =>
      showFigmaSourceSheet(
        context,
        takeLabel: context.s.reportsTakePhoto,
        galleryLabel: context.s.reportsChooseFromGallery,
      );


  Future<void> _addPhoto() async {
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;
    final s = context.s;
    final granted = await PermissionGate.ensure(
      context,
      permission:
          source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.reportsCameraAccessTitle
          : s.reportsPhotoAccessTitle,
      rationale: source == ImageSource.camera
          ? s.reportsCameraAccessRationale
          : s.reportsPhotoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pick(source: source);
      if (f == null) return;
      setState(() => _photo = f);
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  void _removePhoto() => setState(() => _photo = null);

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = context.s.reportsReasonRequired);
      return;
    }
    if (_concern.text.trim().isEmpty) {
      setState(() => _error = context.s.reportsConcernRequired);
      return;
    }
    if (!_acknowledged) {
      setState(() => _error = context.s.reportsAckRequired);
      return;
    }

    UploadedMedia? media;
    if (_photo != null) {
      setState(() {
        _busy = true;
        _banner = null;
      });
      try {
        media = await widget.uploader
            .upload(_photo!, kind: MediaKind.reportPhoto);
      } on MediaUploadException catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _banner = e.message;
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(_ReopenResult(
      reason: '$_reason. ${_concern.text.trim()}',
      media: media,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final s = context.s;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final navy = context.colors.navy;
    final label = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 14,
      height: 21.84 / 14,
      color: navy,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: navy),
    );
    final inter = TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 14,
      color: navy,
    );
    // The first "Label: " of a note is bold in the frame.
    TextSpan boldLead(String text) {
      final i = text.indexOf(':');
      if (i < 0) return TextSpan(text: text);
      return TextSpan(children: [
        TextSpan(
            text: text.substring(0, i + 1),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: text.substring(i + 1)),
      ]);
    }

    // Figma REPORTS - REOPEN (2780:3594): a full page on #F3F3F3 — the
    // navy header card holding the ticket and the outcome being asked
    // about, the red note, the reason dropdown, the concern box, the
    // optional photo, the acknowledgement and the Back/Submit pair.
    return Padding(
      padding: EdgeInsets.fromLTRB(41, 0, 41, 24 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Navy card, radius 20: the header at 28/800 on 30, then the
            // closing remarks and date inside it at 12/500 on 15. The
            // remarks only show when there is something to show: an
            // older report from before remarks were consistently logged
            // may have neither.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 18, 16),
              decoration: BoxDecoration(
                color: navy,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.reportsReopenHeader(r.trackingId,
                        s.reportStatusLabel(r.status.wire), r.subject),
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      height: 30 / 28,
                      color: context.colors.bg,
                    ),
                  ),
                  if (widget.closingRemark != null || r.closedAt != null) ...[
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(children: [
                        if (widget.closingRemark != null) ...[
                          TextSpan(
                            text: '${s.reportsOriginalClosingRemarks}: ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: widget.closingRemark!),
                        ],
                        if (r.closedAt != null) ...[
                          if (widget.closingRemark != null)
                            const TextSpan(text: '\n'),
                          boldLead(s.reportsDateClosed(_formatDate(s, r.closedAt!))),
                        ],
                      ]),
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        height: 15 / 12,
                        color: context.colors.bg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Reopening does not happen here — the barangay decides, because it restarts the SLA clock. Saying so up front is the difference between a wait and a broken button.
            Text.rich(
              boldLead(s.reportsReopenNote),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 15 / 12,
                color: Color(0xFFFF4949),
              ),
            ),
            const SizedBox(height: 16),

            Text(s.reportsReasonOfReopen, style: label),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              style: inter,
              dropdownColor: context.colors.field,
              borderRadius: BorderRadius.circular(20),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: navy, size: 20),
              hint: Text(s.reportsSelectAReason, style: inter),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: context.colors.field,
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder,
              ),
              items: [
                for (final v in _reopenReasons)
                  DropdownMenuItem(
                      value: v,
                      child: Text(s.reportsReopenReasonLabel(v), style: inter)),
              ],
              onChanged: (v) => setState(() {
                _reason = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 30),

            // The frame's 128-tall box, radius 25, 12/400 hint.
            TextField(
              controller: _concern,
              minLines: 6,
              maxLines: 6,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 12, height: 18.72 / 12, color: navy),
              decoration: InputDecoration(
                hintText: s.reportsConcernHint,
                hintStyle: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  fontStyle: FontStyle.normal,
                  color: navy,
                ),
                contentPadding: const EdgeInsets.fromLTRB(17, 11, 17, 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: navy),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: navy),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: navy, width: 2),
                ),
                counterStyle: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w300,
                  fontSize: 10,
                  color: navy,
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),

            const SizedBox(height: 8),

            Text(s.reportsOptional, style: label),
            _ReopenPhotoTile(
              photo: _photo,
              enabled: !_busy,
              onAdd: _addPhoto,
              onRemove: _removePhoto,
            ),

            if (_banner != null) ...[
              const SizedBox(height: 10),
              Text(_banner!,
                  style: TextStyle(color: context.colors.hint, fontSize: 12)),
            ],
            const SizedBox(height: 23),

            // The frame's 12x12 box with the text 15 in; a 24x24 area
            // takes the tap so the small box is not harder to hit.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Text(
                    s.reportsAckReopen,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 18.72 / 12,
                      color: navy,
                    ),
                  ),
                ),
                Positioned(
                  left: -6,
                  top: 0,
                  width: 24,
                  height: 24,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _acknowledged = !_acknowledged;
                              _error = null;
                            }),
                    child: Center(
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: IgnorePointer(
                          child: FittedBox(
                            child: Checkbox(
                              value: _acknowledged,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                        _acknowledged = v ?? false;
                                        _error = null;
                                      }),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(color: navy, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: TextStyle(color: context.colors.hint, fontSize: 12)),
            ],
            const SizedBox(height: 20),

            // The frame's 150x45 pills, 20 apart.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SheetPill(
                  shadow: 0.30,
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: navy,
                      backgroundColor: context.colors.field,
                      fixedSize: const Size(150, 45),
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: navy),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50)),
                      textStyle: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    child: Text(s.reportsDialogBack),
                  ),
                ),
                const SizedBox(width: 20),
                _SheetPill(
                  shadow: 0.50,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      fixedSize: const Size(150, 45),
                      minimumSize: const Size(150, 45),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      side: BorderSide(color: context.colors.bg),
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.colors.bg),
                          )
                        : Text(s.reportsSubmit),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(Strings s, DateTime utc) {
    final d = utc.toLocal();
    return '${s.monthAbbr(d.month)} ${d.day}, ${d.year}';
  }
}

/// Figma 2780:3594's single "Attach Media" tile — same dashed-border
/// language as report_details_screen.dart's photo/video attach tiles,
/// reduced to the one optional photo request_reopen() (0037) accepts.
class _ReopenPhotoTile extends StatelessWidget {
  const _ReopenPhotoTile({
    required this.photo,
    required this.enabled,
    required this.onAdd,
    required this.onRemove,
  });

  final File? photo;
  final bool enabled;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    if (photo != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.colors.field,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child:
                  Image.file(photo!, width: 40, height: 40, fit: BoxFit.cover),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.s.reportsPhotoAttachedNote,
                style: TextStyle(fontSize: 12, color: context.colors.navy),
              ),
            ),
            IconButton(
              icon: Icon(Icons.cancel, color: context.colors.navy),
              onPressed: enabled ? onRemove : null,
            ),
          ],
        ),
      );
    }
    // The frame's 174x128 tile (same as the report form's): the frame's
    // own 20x20 icon 8 left of the two lines, centred.
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: enabled ? onAdd : null,
        borderRadius: BorderRadius.circular(25),
        child: Container(
          width: 174,
          height: 128,
          decoration: BoxDecoration(
            color: context.colors.field,
            borderRadius: BorderRadius.circular(25),
          ),
          child: CustomPaint(
            painter: _ReopenDashedBorder(color: context.colors.navy),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/icon-attach.png',
                    width: 20, height: 20, color: context.colors.navy),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.s.reportsAttachMedia,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 14 / 12,
                          color: context.colors.navy,
                        )),
                    Text(context.s.reportsMaxPhotoSize,
                        style: TextStyle(
                          fontFamily: 'Urbanist',
                          fontWeight: FontWeight.w400,
                          fontSize: 10,
                          height: 1,
                          fontStyle: FontStyle.italic,
                          color: context.colors.navy,
                        )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReopenDashedBorder extends CustomPainter {
  // No BuildContext of its own -- see _DashedBorder in
  // report_details_screen.dart for the same pattern and why.
  const _ReopenDashedBorder({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(25),
    );
    final path = Path()..addRRect(rrect);

    const dash = 6.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, (d + dash).clamp(0, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReopenDashedBorder oldDelegate) =>
      oldDelegate.color != color;
}

// ---------- appeal (10 Sep 2026, request_appeal 0057) ---------
//
// The rejected path's own Reopen sheet. Structured as a near-duplicate
// of _ReopenSheet just above rather than a shared parametrised widget —
// same call this file already makes for _ActionDialog/_ReasonDialog
// versus a one-off dialog: the two forms read a different context
// (denial reason + date denied, not closing remark + date closed) and
// carry different copy throughout, so a shared widget would just be an
// if/else in disguise. _ReopenPhotoTile and _ReopenDashedBorder ARE
// reused as-is, though — those two are already copy-free (a generic
// "Attach Media" tile), so duplicating them would be copying for its
// own sake.

/// Developer-invented, same status as _reopenReasons — on the list of
/// values the barangay still has to confirm.
const _appealReasons = <String>[
  'The rejection reason is incorrect',
  'I have more evidence to support this',
  'This should not have been denied',
  'Other',
];

/// What the sheet hands back to [_ReportsScreenState._requestAppeal] —
/// mirrors _ReopenResult exactly.
class _AppealResult {
  const _AppealResult({required this.reason, this.media});
  final String reason;
  final UploadedMedia? media;
}

class _AppealSheet extends StatefulWidget {
  const _AppealSheet({
    required this.report,
    required this.uploader,
    this.denialRemark,
    this.deniedAt,
  });

  final ReportSummary report;
  final MediaUploader uploader;

  /// The remark left on the status_logs row that rejected this report,
  /// if there is one — the outcome being disputed, shown the same way
  /// _ReopenSheet shows the closing remark it is asking to reopen.
  final String? denialRemark;

  /// When that rejection happened. Read from status_logs.created_at by
  /// the caller rather than a stored column — reports has no
  /// rejected_at, only resolved_at/closed_at (see ReportSummary).
  final DateTime? deniedAt;

  @override
  State<_AppealSheet> createState() => _AppealSheetState();
}

class _AppealSheetState extends State<_AppealSheet> {
  final _concern = TextEditingController();
  String? _reason;
  bool _acknowledged = false;
  String? _error;
  String? _banner;
  bool _busy = false;

  /// One optional photo, matching request_appeal()'s p_media (0057),
  /// the same shape request_reopen() already takes.
  File? _photo;

  @override
  void dispose() {
    _concern.dispose();
    super.dispose();
  }

  Future<ImageSource?> _chooseSource(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: context.colors.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading:
                  Icon(Icons.photo_camera_outlined, color: context.colors.navy),
              title: Text(context.s.reportsTakePhoto),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading:
                  Icon(Icons.photo_library_outlined, color: context.colors.navy),
              title: Text(context.s.reportsChooseFromGallery),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addPhoto() async {
    final source = await _chooseSource(context);
    if (source == null || !mounted) return;
    final s = context.s;
    final granted = await PermissionGate.ensure(
      context,
      permission:
          source == ImageSource.camera ? AppPermission.camera : AppPermission.photos,
      title: source == ImageSource.camera
          ? s.reportsCameraAccessTitle
          : s.reportsPhotoAccessTitle,
      rationale: source == ImageSource.camera
          ? s.reportsAppealCameraAccessRationale
          : s.reportsAppealPhotoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pick(source: source);
      if (f == null) return;
      setState(() => _photo = f);
    } on MediaUploadException catch (e) {
      setState(() => _banner = e.message);
    }
  }

  void _removePhoto() => setState(() => _photo = null);

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _error = context.s.reportsReasonRequired);
      return;
    }
    if (_concern.text.trim().isEmpty) {
      setState(() => _error = context.s.reportsConcernRequired);
      return;
    }
    if (!_acknowledged) {
      setState(() => _error = context.s.reportsAckRequired);
      return;
    }

    UploadedMedia? media;
    if (_photo != null) {
      setState(() {
        _busy = true;
        _banner = null;
      });
      try {
        media = await widget.uploader
            .upload(_photo!, kind: MediaKind.reportPhoto);
      } on MediaUploadException catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _banner = e.message;
        });
        return;
      }
    }

    if (!mounted) return;
    Navigator.of(context).pop(_AppealResult(
      reason: '$_reason. ${_concern.text.trim()}',
      media: media,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.report;
    final s = context.s;
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final navy = context.colors.navy;
    final label = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w700,
      fontSize: 14,
      height: 21.84 / 14,
      color: navy,
    );
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(20),
      borderSide: BorderSide(color: navy),
    );
    final inter = TextStyle(
      fontFamily: 'Inter',
      fontWeight: FontWeight.w400,
      fontSize: 14,
      color: navy,
    );
    // The first "Label: " of a note is bold in the frame.
    TextSpan boldLead(String text) {
      final i = text.indexOf(':');
      if (i < 0) return TextSpan(text: text);
      return TextSpan(children: [
        TextSpan(
            text: text.substring(0, i + 1),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: text.substring(i + 1)),
      ]);
    }

    // Figma REPORTS - REOPEN (2780:3594): a full page on #F3F3F3 — the
    // navy header card holding the ticket and the outcome being asked
    // about, the red note, the reason dropdown, the concern box, the
    // optional photo, the acknowledgement and the Back/Submit pair.
    return Padding(
      padding: EdgeInsets.fromLTRB(41, 0, 41, 24 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),

            // Navy card, radius 20: the header at 28/800 on 30, then the
            // closing remarks and date inside it at 12/500 on 15. The
            // remarks only show when there is something to show: an
            // older report from before remarks were consistently logged
            // may have neither.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 10, 18, 16),
              decoration: BoxDecoration(
                color: navy,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.reportsAppealHeader(r.trackingId,
                        s.reportStatusLabel(r.status.wire), r.subject),
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w800,
                      fontSize: 28,
                      height: 30 / 28,
                      color: context.colors.bg,
                    ),
                  ),
                  if (widget.denialRemark != null || widget.deniedAt != null) ...[
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(children: [
                        if (widget.denialRemark != null) ...[
                          TextSpan(
                            text: '${s.reportsOriginalDenialReason}: ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: widget.denialRemark!),
                        ],
                        if (widget.deniedAt != null) ...[
                          if (widget.denialRemark != null)
                            const TextSpan(text: '\n'),
                          boldLead(s.reportsDateDenied(_formatDate(s, widget.deniedAt!))),
                        ],
                      ]),
                      style: TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        height: 15 / 12,
                        color: context.colors.bg,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Appealing does not happen here — the barangay decides.
            Text.rich(
              boldLead(s.reportsAppealNote),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Urbanist',
                fontWeight: FontWeight.w500,
                fontSize: 12,
                height: 15 / 12,
                color: Color(0xFFFF4949),
              ),
            ),
            const SizedBox(height: 16),

            Text(s.reportsReasonOfAppeal, style: label),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              style: inter,
              dropdownColor: context.colors.field,
              borderRadius: BorderRadius.circular(20),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  color: navy, size: 20),
              hint: Text(s.reportsSelectAReason, style: inter),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: context.colors.field,
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                border: fieldBorder,
                enabledBorder: fieldBorder,
                focusedBorder: fieldBorder,
              ),
              items: [
                for (final v in _appealReasons)
                  DropdownMenuItem(
                      value: v,
                      child: Text(s.reportsAppealReasonLabel(v), style: inter)),
              ],
              onChanged: (v) => setState(() {
                _reason = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 30),

            // The frame's 128-tall box, radius 25, 12/400 hint.
            TextField(
              controller: _concern,
              minLines: 6,
              maxLines: 6,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(fontSize: 12, height: 18.72 / 12, color: navy),
              decoration: InputDecoration(
                hintText: s.reportsConcernHint,
                hintStyle: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  fontStyle: FontStyle.normal,
                  color: navy,
                ),
                contentPadding: const EdgeInsets.fromLTRB(17, 11, 17, 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: navy),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: navy),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(color: navy, width: 2),
                ),
                counterStyle: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w300,
                  fontSize: 10,
                  color: navy,
                ),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),

            const SizedBox(height: 8),

            Text(s.reportsOptional, style: label),
            _ReopenPhotoTile(
              photo: _photo,
              enabled: !_busy,
              onAdd: _addPhoto,
              onRemove: _removePhoto,
            ),

            if (_banner != null) ...[
              const SizedBox(height: 10),
              Text(_banner!,
                  style: TextStyle(color: context.colors.hint, fontSize: 12)),
            ],
            const SizedBox(height: 23),

            // The frame's 12x12 box with the text 15 in; a 24x24 area
            // takes the tap so the small box is not harder to hit.
            Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 15),
                  child: Text(
                    s.reportsAckAppeal,
                    style: TextStyle(
                      fontFamily: 'Urbanist',
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      height: 18.72 / 12,
                      color: navy,
                    ),
                  ),
                ),
                Positioned(
                  left: -6,
                  top: 0,
                  width: 24,
                  height: 24,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _acknowledged = !_acknowledged;
                              _error = null;
                            }),
                    child: Center(
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: IgnorePointer(
                          child: FittedBox(
                            child: Checkbox(
                              value: _acknowledged,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() {
                                        _acknowledged = v ?? false;
                                        _error = null;
                                      }),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(color: navy, width: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: TextStyle(color: context.colors.hint, fontSize: 12)),
            ],
            const SizedBox(height: 20),

            // The frame's 150x45 pills, 20 apart.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SheetPill(
                  shadow: 0.30,
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: navy,
                      backgroundColor: context.colors.field,
                      fixedSize: const Size(150, 45),
                      padding: EdgeInsets.zero,
                      side: BorderSide(color: navy),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50)),
                      textStyle: const TextStyle(
                        fontFamily: 'Urbanist',
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    child: Text(s.reportsDialogBack),
                  ),
                ),
                const SizedBox(width: 20),
                _SheetPill(
                  shadow: 0.50,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      fixedSize: const Size(150, 45),
                      minimumSize: const Size(150, 45),
                      padding: EdgeInsets.zero,
                      elevation: 0,
                      side: BorderSide(color: context.colors.bg),
                    ),
                    child: _busy
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: context.colors.bg),
                          )
                        : Text(s.reportsSubmit),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(Strings s, DateTime utc) {
    final d = utc.toLocal();
    return '${s.monthAbbr(d.month)} ${d.day}, ${d.year}';
  }
}

/// The frame's y5 / blur 5 drop shadow under a 45-tall pill button.
class _SheetPill extends StatelessWidget {
  const _SheetPill({required this.shadow, required this.child});

  final double shadow;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(50),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF121212).withValues(alpha: shadow),
              blurRadius: 3.5,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: child,
      );
}

/// Figma TICKET REOPENED: the 30/800 title centred at 331 — the report's
/// "(# id - status) subject" and what happened — the 16/500 thanks under
/// it, and the 301x44 navy Back to Home 45 below. Worded as a request
/// sent, since that is all request_reopen()/request_appeal() do.
class _RequestSentPage extends StatelessWidget {
  const _RequestSentPage({required this.report, required this.appeal});

  final ReportSummary report;
  final bool appeal;

  static Future<void> show(
    BuildContext context,
    ReportSummary report, {
    required bool appeal,
  }) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => _RequestSentPage(report: report, appeal: appeal),
      ));

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final head = '(# ${report.trackingId} - '
        '${s.reportStatusLabel(report.status.wire)}) ${report.subject}';
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              EdgeInsets.fromLTRB(43, figmaTop(context, 331, min: 40), 43, 24),
          child: Column(
            children: [
              Text(
                appeal
                    ? s.reportsAppealSentTitle(head)
                    : s.reportsReopenSentTitle(head),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  height: 1.0,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                s.reportsRequestSentBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                  height: 20 / 16,
                  color: context.colors.navy,
                ),
              ),
              const SizedBox(height: 48),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 301),
                child: FigmaPill(
                  onPressed: () => Navigator.of(context)
                      .pushNamedAndRemoveUntil('/home', (_) => false),
                  child: Text(s.reportSubmittedBackHome),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// The case's steps for the report page and the map's sheet: Filed,
/// Validated, Tanod dispatched, Resolved — or, for a rejected, cancelled
/// or escalated case, Filed and where it ended. [on] is how many are done.
({List<String> labels, int on}) reportSteps(BuildContext context, ReportStatus status, {String? office}) {
  final referred = office != null && office.isNotEmpty && status.isOngoing;
  if (status == ReportStatus.rejected || status == ReportStatus.cancelled || referred) {
    return (
      labels: [
        context.tr('Filed', 'Naisampa'),
        referred ? context.tr('Escalated to the $office', 'In-escalate sa $office') : context.s.reportStatusLabel(status.wire),
      ],
      on: 2,
    );
  }
  return (
    labels: [
      context.tr('Filed', 'Naisampa'),
      context.tr('Validated', 'Napatunayan'),
      context.tr('Tanod dispatched', 'Na-dispatch ang tanod'),
      context.tr('Resolved', 'Nalutas'),
    ],
    on: switch (status) {
      ReportStatus.pendingReview => 1,
      ReportStatus.validated => 2,
      ReportStatus.assigned || ReportStatus.inProgress || ReportStatus.offlineInvestigation => 3,
      _ => 4,
    },
  );
}
