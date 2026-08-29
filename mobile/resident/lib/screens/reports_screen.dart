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
// One thing that is NOT built to match Figma 2780:3806/2923:258: a
// full-screen "Ticket Reopened" confirmation. Showing that would be a
// lie — request_reopen() only files a request; the report's status does
// not change until an admin calls the admin-only reopen_report(). The
// toast ("Your request has been sent to the barangay") says what is
// actually true and stays that way on purpose.
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../location_lookup.dart';
import '../models/complaint_category.dart';
import '../theme.dart';
import '../widgets/resident_nav_bar.dart';

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
  /// to put next to the mockup's "📍 <place>" footer line (see
  /// location_lookup.dart's header for the full reasoning), so these
  /// feed a best-effort reverse-geocode lookup instead of a stored
  /// string. Null for a report with no pinned location.
  final double? latitude;
  final double? longitude;

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

  // Hero card (29 Aug 2026 — aesthetics pass, resident's own reference
  // mockup). The first ongoing report in the CURRENTLY VISIBLE (i.e.
  // filtered) list renders as an expanded card with its status_logs
  // timeline embedded right there — a resident checking on the one
  // complaint they actually care about shouldn't have to tap in just to
  // see whether anything moved. Every other card stays the plain
  // summary it always was. Basing this on _visible rather than
  // _reports means it needs no special-casing per filter: under
  // "Resolved", _visible never contains an isOngoing report, so no
  // hero shows there, automatically, correctly.
  String? _heroTimelineFor;
  List<Map<String, dynamic>> _heroTimeline = const [];

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
    _load();
  }

  @override
  void dispose() {
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
    try {
      // reports_resident_read already limits this to the caller's own
      // reports, but filtering here too keeps the query honest about
      // what it means rather than relying on the policy for correctness.
      final rows = await client
          .from('reports')
          .select('id, tracking_id, subject, description, status, category, '
              'created_at, closed_at, latitude, longitude')
          .eq('resident_id', uid)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _reports = [
            for (final r in rows) ReportSummary.fromRow(r),
          ]);
      await _syncHeroTimeline();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = context.s.reportsLoadError);
    }
  }

  List<ReportSummary> get _visible {
    final all = _reports ?? const <ReportSummary>[];
    final wires = _filter.wires;
    if (wires == null) return all;
    return all.where((r) => wires.contains(r.status.wire)).toList();
  }

  ReportSummary? get _hero {
    for (final r in _visible) {
      if (r.status.isOngoing) return r;
    }
    return null;
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
    _syncHeroTimeline();
  }

  /// Keeps _heroTimeline matched to whichever report _hero currently
  /// points at. Always re-fetches when a hero exists, even if it's the
  /// SAME report as last time — that's the one case that matters most:
  /// a live reload just landed because this exact report's status
  /// changed, and the whole point is showing that change without the
  /// resident tapping in. The id check only decides whether to blank
  /// the card first, so a hero swap (filter change, or the previous
  /// hero finishing) never flashes the wrong report's timeline while
  /// the new fetch is still in flight.
  Future<void> _syncHeroTimeline() async {
    final hero = _hero;
    if (hero == null) {
      if (_heroTimelineFor != null) {
        setState(() {
          _heroTimelineFor = null;
          _heroTimeline = const [];
        });
      }
      return;
    }
    if (hero.id != _heroTimelineFor) {
      setState(() {
        _heroTimelineFor = hero.id;
        _heroTimeline = const [];
      });
    }
    try {
      final logs = await Supabase.instance.client
          .from('status_logs')
          .select('old_status, new_status, remark, created_at')
          .eq('report_id', hero.id)
          .order('created_at');
      // The hero could have changed again while this was in flight
      // (another live reload, or the resident switching filters) --
      // never let a slow response overwrite a newer one.
      if (!mounted || _hero?.id != hero.id) return;
      setState(() => _heroTimeline = List<Map<String, dynamic>>.from(logs));
    } catch (_) {
      // The card still shows fine without it -- title, status,
      // description and meta all come from the report row already in
      // hand, same as before this existed.
    }
  }

  // ---------- actions ----------------------------------------

  Future<void> _cancel(ReportSummary r) async {
    // Figma 2864:332 — the same navy pill dialog as everywhere else in
    // the app, not a plain Material AlertDialog. This used to be one;
    // fixed during the Figma parity pass (27 Aug 2026).
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
          .rpc('cancel_report', params: {'p_report': r.id});
      if (!mounted) return;
      // Figma 2864:461 — a follow-up modal, not a snackbar.
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
      _toast(_friendly(e.message));
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
    final result = await showModalBottomSheet<_ReopenResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
      _toast(context.s.reportsRequestSent);
      _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _toast(_friendly(e.message));
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
    if (m.contains('only the resident')) {
      return s.reportsErrorOwnReportsOnly;
    }
    if (m.contains('say why')) {
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

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = context.s;

    return Scaffold(
      bottomNavigationBar: const ResidentNavBar(current: ResidentTab.reports),
      body: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 46),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              Text(s.reportsViewTitle,
                  style: t.labelLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 10),
              _FilterDropdown(
                value: _filter,
                counts: _filterCounts,
                onChanged: _setFilter,
              ),
              const SizedBox(height: 16),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: context.colors.navy,
                  child: _body(t, s),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(TextTheme t, Strings s) {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.hint)),
        ],
      );
    }

    if (_reports == null) {
      return Center(child: CircularProgressIndicator(color: context.colors.navy));
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.description_outlined,
              size: 48, color: context.colors.navy.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            _filter == ReportFilter.all
                ? s.reportsEmptyAll
                : s.reportsEmptyFiltered(
                    s.reportFilterLabel(_filter.name).toLowerCase()),
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.muted),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: visible.length,
      separatorBuilder: (_, __) => const SizedBox(height: 13),
      itemBuilder: (_, i) {
        final r = visible[i];
        final isHero = _hero?.id == r.id;
        return _ReportCard(
          report: r,
          isHero: isHero,
          timeline: isHero ? _heroTimeline : const [],
          onView: () => Navigator.of(context)
              .pushNamed('/report', arguments: r.id)
              .then((_) => _load()),
          onCancel: r.status.canCancel ? () => _cancel(r) : null,
          onReopen:
              r.status.canRequestReopen ? () => _requestReopen(r) : null,
        );
      },
    );
  }
}

// ---------- pieces -------------------------------------------

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

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<ReportFilter>(
      initialValue: value,
      isExpanded: true,
      items: [
        for (final f in ReportFilter.values)
          DropdownMenuItem(
            value: f,
            child: Text(
                '${context.s.reportFilterLabel(f.name)} (${counts[f] ?? 0})'),
          ),
      ],
      onChanged: (f) {
        if (f != null) onChanged(f);
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.onView,
    this.isHero = false,
    this.timeline = const [],
    this.onCancel,
    this.onReopen,
  });

  final ReportSummary report;
  final VoidCallback onView;

  /// The one ongoing report ReportsScreen picked out of the currently
  /// visible list — see its own header comment. Everything below just
  /// renders whatever it's handed; picking the hero is the parent's job.
  final bool isHero;

  /// This report's status_logs rows, oldest first — same shape
  /// report_view_screen.dart's timeline reads. Only ever non-empty when
  /// isHero is true; a non-hero card ignores it entirely.
  final List<Map<String, dynamic>> timeline;

  final VoidCallback? onCancel;
  final VoidCallback? onReopen;

  static const _orange = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        // Light card, not navy -- transferred over from
        // report_view_screen.dart's own switch (30 Aug 2026), so the list
        // and the detail screen read as the same design rather than one
        // navy and one light. `field` is this app's existing "lighter
        // than the page" surface token; navy on it reads as dark accent
        // text, same role it always had, just no longer the fill.
        //
        // 1:1 pass (29 Aug 2026): radius, padding, shadow and the
        // section split below now match the mockup's .report-detail-card
        // exactly, the same restructuring report_view_screen.dart's own
        // card just got -- only the font-family and the established
        // colour roles stay put.
        decoration: BoxDecoration(
          color: context.colors.field,
          // The hero still gets an orange edge -- the app's one accent
          // colour, not a third status colour -- so it reads as "this is
          // the one being tracked" without inventing a new palette entry.
          border: Border.all(
            color: isHero ? _orange : Colors.transparent,
            width: isHero ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 3, offset: Offset(0, 1)),
            BoxShadow(color: Color(0x0F000000), blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // rdc-top: header row + body, separated from the date band
            // below by `divider`, the literal mapping for the mockup's
            // var(--border).
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: context.colors.divider),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ID · category, small and muted — the reference
                        // mockup's card puts this directly above the title,
                        // not folded into it the way this card used to. The
                        // pill sitting beside this whole column (not just the
                        // title) is what keeps it lined up with this top line
                        // rather than floating centred on the card.
                        Text(
                          '${report.trackingId} · ${report.category.label}',
                          style: TextStyle(fontSize: 11, color: context.colors.muted),
                        ),
                        const SizedBox(height: 2),
                        if (isHero) ...[
                          Text(
                            s.reportsTrackingLabel,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                              letterSpacing: .5,
                              color: _orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                        Text(
                          report.subject,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.1,
                            color: context.colors.navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.reportsCardDescription(report.description),
                          maxLines: isHero ? 4 : 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12, height: 1.4, color: context.colors.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _StatusPill(status: report.status),
                      const SizedBox(height: 4),
                      _CardMenu(
                        onView: onView,
                        onCancel: onCancel,
                        onReopen: onReopen,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // rdc-bottom: a full-bleed tinted strip, not a nested rounded
            // chip -- the mockup runs this the full width of the card.
            // 1:1 pass (29 Aug 2026): the 🕐 emoji glyph is gone, replaced
            // by a proper Icons widget (this app's own established icon
            // pack -- Material Icons, already used everywhere else in
            // this file and report_view_screen.dart, not a new
            // dependency), and the mockup's "📍 <place>" line is back,
            // fed by a best-effort reverse-geocode lookup rather than a
            // stored address column -- see location_lookup.dart's header
            // for why. The pin itself is still on the map in the full
            // report view either way.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: context.colors.bg,
              child: Row(
                children: [
                  if (report.latitude != null && report.longitude != null)
                    _LocationLabel(
                      latitude: report.latitude!,
                      longitude: report.longitude!,
                    ),
                  Icon(Icons.access_time_rounded,
                      size: 12, color: context.colors.muted),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(s, report.createdAt),
                    style: TextStyle(fontSize: 11, color: context.colors.muted),
                  ),
                ],
              ),
            ),

            if (isHero)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                child: _MiniTimeline(
                  entries: timeline,
                  submittedAt: report.createdAt,
                  // Hero is, by _hero's own definition, always an
                  // isOngoing report -- so there's always a next
                  // bucket to name here, same computation
                  // report_view_screen.dart's card does.
                  upcomingWire:
                      report.status == ReportStatus.pendingReview ||
                              report.status == ReportStatus.validated
                          ? 'assigned'
                          : 'resolved',
                ),
              ),
          ],
        ),
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
/// there's nothing to show.
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
                constraints: const BoxConstraints(maxWidth: 110),
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

/// The rounded corner badge the reference mockup put status in, rather
/// than this screen's old inline coloured text. Own tint logic, not
/// ReportStatus.labelColour -- that extension returns this app's bg
/// colour, tuned for text sitting on the navy card this used to be; on
/// this now-light card that would read as invisible near-white text.
/// Same one exception as labelColour still keeps (red for cancelled),
/// just re-derived for a light background -- see
/// report_view_screen.dart's own copy of this same fix.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final danger = status == ReportStatus.cancelled;
    final tint = danger ? const Color(0xFFFF4949) : context.colors.navy;
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

/// The dot-and-line timeline embedded in the hero card — the same
/// story report_view_screen.dart's own _Timeline tells, sized to match
/// it exactly rather than a separate condensed variant (the mockup
/// doesn't depict a compact version, so as of the 1:1 pass this one no
/// longer invents its own smaller dots/text), now including that same
/// screen's two synthetic rows: a "Report submitted" first node built
/// from the report's own createdAt (never a logged status_logs
/// transition on its own) and a greyed "not yet reached" last node
/// naming the next status bucket, since _hero is by definition always
/// an isOngoing report. Deliberately a separate small copy rather than
/// a shared widget: see _ActionDialog's own comment further down in
/// this file for why this app duplicates rather than shares
/// screen-specific widgets.
class _MiniTimeline extends StatelessWidget {
  const _MiniTimeline({
    required this.entries,
    required this.submittedAt,
    required this.upcomingWire,
  });

  final List<Map<String, dynamic>> entries;
  final DateTime submittedAt;
  final String upcomingWire;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MiniTimelineRow.submitted(when: submittedAt, hasMore: true),
        for (var i = 0; i < entries.length; i++)
          _MiniTimelineRow.entry(
            entry: entries[i],
            hasMore: true,
            // The upcoming row always follows a hero's entries (a hero
            // is by definition isOngoing), so only the true last real
            // entry is "current" -- earlier ones are already-settled
            // past steps even though hasMore is true for all of them.
            isCurrent: i == entries.length - 1,
          ),
        _MiniTimelineRow.upcoming(wire: upcomingWire),
      ],
    );
  }
}

class _MiniTimelineRow extends StatelessWidget {
  const _MiniTimelineRow.entry({
    required Map<String, dynamic> entry,
    required this.hasMore,
    required this.isCurrent,
  })  : _kind = _RowKind.entry,
        _entry = entry,
        _when = null,
        _wire = null;

  const _MiniTimelineRow.submitted({required DateTime when, required this.hasMore})
      : _kind = _RowKind.submitted,
        _entry = null,
        _when = when,
        _wire = null,
        isCurrent = false;

  const _MiniTimelineRow.upcoming({required String wire})
      : _kind = _RowKind.upcoming,
        _entry = null,
        _when = null,
        _wire = wire,
        hasMore = false,
        isCurrent = false;

  final _RowKind _kind;
  final Map<String, dynamic>? _entry;
  final DateTime? _when;
  final String? _wire;

  /// Whether a connecting line runs down to another row beneath this
  /// one -- true for "submitted" and for every real entry (the upcoming
  /// row, when present, always follows), false only for "upcoming"
  /// itself.
  final bool hasMore;

  /// The orange ring -- explicitly passed by _MiniTimeline rather than
  /// derived from hasMore, since every real entry here has hasMore true
  /// (the upcoming row always follows a hero, which is always
  /// isOngoing) yet only the true last real entry should ring.
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final isUpcoming = _kind == _RowKind.upcoming;
    final isSubmitted = _kind == _RowKind.submitted;
    final status = isUpcoming || isSubmitted
        ? null
        : ReportStatus.parse(_entry!['new_status'] as String?);
    final when = isSubmitted
        ? _when
        : isUpcoming
            ? null
            : DateTime.tryParse(_entry!['created_at'] as String? ?? '');

    // Mockup nuance from the raw markup, not just the CSS rules: only
    // the line below a fully-`done` dot gets the accent colour -- the
    // line below the `active`/current dot stays neutral, since what
    // follows is unknown/future. Submitted is always done; only a real
    // entry can be current.
    final lineColor =
        !isUpcoming && isCurrent ? context.colors.divider : context.colors.navy;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 14,
                  height: 14,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    // The reference distinguishes done (green) from the
                    // current step (blue, ringed) from what hasn't
                    // happened yet. Reinterpreted with this app's own
                    // navy/orange accents: submitted + past entries sit
                    // in plain navy (settled, already true), the current
                    // step gets the app's one accent colour and a soft
                    // ring, and the synthetic upcoming row is a hollow
                    // outline -- nothing has happened there yet.
                    color: isUpcoming
                        ? context.colors.field
                        : (isCurrent ? const Color(0xFFFF9800) : context.colors.navy),
                    shape: BoxShape.circle,
                    border: isUpcoming
                        ? Border.all(color: context.colors.divider, width: 2.5)
                        : null,
                    boxShadow: isCurrent
                        ? const [
                            BoxShadow(
                              color: Color(0x55FF9800),
                              blurRadius: 0,
                              spreadRadius: 3,
                            ),
                          ]
                        : null,
                  ),
                ),
                if (hasMore)
                  Expanded(
                    child: VerticalDivider(
                      color: lineColor,
                      thickness: 2,
                      width: 10,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: hasMore ? 20 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSubmitted
                        ? s.reportViewSubmittedStep
                        : isUpcoming
                            ? s.reportStatusLabel(_wire!)
                            : s.reportStatusLabel(status!.wire),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isUpcoming ? context.colors.muted : context.colors.navy,
                    ),
                  ),
                  if (when != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _formatWhen(s, when),
                      style: TextStyle(fontSize: 11, color: context.colors.muted),
                    ),
                  ] else if (isUpcoming) ...[
                    const SizedBox(height: 2),
                    Text(s.reportViewUpcomingStep,
                        style: TextStyle(fontSize: 11, color: context.colors.muted)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Same format report_view_screen.dart's own private _formatWhen uses --
/// duplicated rather than shared since each .dart file is its own
/// library and privates are file-scoped (see _ActionDialog's comment
/// further down for the app's general stance on this). The mockup's
/// .tl-sub always shows a full date + time, not the abbreviated
/// month/day this row used before the 1:1 pass.
String _formatWhen(Strings s, DateTime utc) {
  final d = utc.toLocal();
  final h24 = d.hour;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  final ampm = h24 < 12 ? 'AM' : 'PM';
  final mm = d.minute.toString().padLeft(2, '0');
  return '${s.monthAbbr(d.month)} ${d.day}, ${d.year} • $h12:$mm $ampm';
}

enum _RowKind { submitted, entry, upcoming }

/// The three-dot menu. Actions the backend would refuse are absent
/// rather than present and failing — a menu that offers Cancel on a
/// dispatched report teaches the resident the app is unreliable.
class _CardMenu extends StatelessWidget {
  const _CardMenu({required this.onView, this.onCancel, this.onReopen});

  final VoidCallback onView;
  final VoidCallback? onCancel;
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, color: context.colors.bg, size: 20),
      color: const Color(0xFFFF9800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      onSelected: (v) {
        switch (v) {
          case 'view':
            onView();
          case 'cancel':
            onCancel?.call();
          case 'reopen':
            onReopen?.call();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'view',
          height: 36,
          child: Row(children: [
            Icon(Icons.visibility_outlined, size: 16, color: context.colors.bg),
            const SizedBox(width: 8),
            Text(s.reportsMenuView,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: context.colors.bg)),
          ]),
        ),
        if (onCancel != null)
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
        if (onReopen != null)
          PopupMenuItem(
            value: 'reopen',
            height: 36,
            child: Row(children: [
              Icon(Icons.refresh, size: 16, color: context.colors.bg),
              const SizedBox(width: 8),
              Text(s.reportsMenuReopen,
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: context.colors.bg)),
            ]),
          ),
      ],
    );
  }
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

  Future<void> _addPhoto() async {
    final granted = await PermissionGate.ensure(
      context,
      permission: AppPermission.photos,
      title: context.s.reportsPhotoAccessTitle,
      rationale: context.s.reportsPhotoAccessBody,
    );
    if (!granted || !mounted) return;
    setState(() => _banner = null);
    try {
      final f = await widget.uploader.pick();
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

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + inset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),

            // The navy header card carrying the ticket being reopened.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: context.colors.navy,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.reportsReopenHeader(r.trackingId,
                        s.reportStatusLabel(r.status.wire), r.subject),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.25,
                      color: context.colors.bg,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Figma 2780:3594 — the outcome being asked about, so the
            // resident can see it before disputing it. Only shown when
            // there is something to show: an older closed report from
            // before status_logs remarks were consistently recorded may
            // have neither.
            if (r.closedAt != null || widget.closingRemark != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.colors.field,
                    border: Border.all(color: context.colors.navy),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.closingRemark != null) ...[
                        Text(
                          s.reportsOriginalClosingRemarks,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: context.colors.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.closingRemark!,
                          style: TextStyle(
                              fontSize: 12, height: 1.35, color: context.colors.navy),
                        ),
                      ],
                      if (r.closedAt != null) ...[
                        if (widget.closingRemark != null)
                          const SizedBox(height: 8),
                        Text(
                          s.reportsDateClosed(_formatDate(s, r.closedAt!)),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: context.colors.navy,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

            // Reopening does not happen here — the barangay decides,
            // because it restarts the SLA clock. Saying so up front is
            // the difference between a wait and a broken button.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.colors.field,
                border: Border.all(color: context.colors.navy),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                s.reportsReopenNote,
                style: TextStyle(fontSize: 12, height: 1.35,
                    color: context.colors.navy),
              ),
            ),
            const SizedBox(height: 16),

            Text(s.reportsReasonOfReopen,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: context.colors.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              hint: Text(s.reportsSelectAReason),
              items: [
                for (final v in _reopenReasons)
                  DropdownMenuItem(
                      value: v, child: Text(s.reportsReopenReasonLabel(v))),
              ],
              onChanged: (v) => setState(() {
                _reason = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _concern,
              maxLines: 4,
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: s.reportsConcernHint,
              ),
              onChanged: (_) => setState(() => _error = null),
            ),

            const SizedBox(height: 14),

            Text(s.reportsOptional,
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: context.colors.navy)),
            const SizedBox(height: 6),
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
            const SizedBox(height: 14),

            // Figma 2780:3594's checkbox, same wording pattern as the
            // Submit Report acknowledgement (report_details_screen.dart)
            // rather than the Sign Up agreement — this is about the
            // reopen request being accurate, not about a Terms page.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _acknowledged,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() {
                              _acknowledged = v ?? false;
                              _error = null;
                            }),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    s.reportsAckReopen,
                    style: TextStyle(
                        fontSize: 12, color: context.colors.navy, height: 1.3),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: TextStyle(color: context.colors.hint, fontSize: 12)),
            ],
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(s.reportsDialogBack),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
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
    return InkWell(
      onTap: enabled ? onAdd : null,
      borderRadius: BorderRadius.circular(25),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: context.colors.field,
          borderRadius: BorderRadius.circular(25),
        ),
        child: CustomPaint(
          painter: _ReopenDashedBorder(color: context.colors.navy),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_box_outlined, color: context.colors.navy, size: 22),
              const SizedBox(height: 6),
              Text(context.s.reportsAttachMedia,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: context.colors.navy,
                  )),
              Text(context.s.reportsMaxPhotoSize,
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: context.colors.navy,
                  )),
            ],
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
