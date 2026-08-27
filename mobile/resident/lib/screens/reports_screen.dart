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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

  /// Cancelled is drawn in red in the design — it is the one outcome the
  /// resident caused, and it reads differently from a rejection.
  Color get labelColour =>
      this == ReportStatus.cancelled ? const Color(0xFFFF4949) : Tokens.bg;
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
    required this.createdAt,
    this.closedAt,
  });

  final String id;
  final String trackingId;
  final String subject;
  final String description;
  final ReportStatus status;
  final DateTime createdAt;

  /// Null until the report is resolved or closed. Shown, with the closing
  /// remark from status_logs, on the Reopen sheet (Figma 2780:3594) so the
  /// resident can see what they are asking to reopen.
  final DateTime? closedAt;

  factory ReportSummary.fromRow(Map<String, dynamic> r) => ReportSummary(
        id: r['id'] as String,
        trackingId: r['tracking_id'] as String? ?? '',
        subject: r['subject'] as String? ?? '',
        description: r['description'] as String? ?? '',
        status: ReportStatus.parse(r['status'] as String?),
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
        closedAt: DateTime.tryParse(r['closed_at'] as String? ?? ''),
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

  @override
  void initState() {
    super.initState();
    _load();
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

    setState(() => _error = null);
    try {
      // reports_resident_read already limits this to the caller's own
      // reports, but filtering here too keeps the query honest about
      // what it means rather than relying on the policy for correctness.
      final rows = await client
          .from('reports')
          .select(
              'id, tracking_id, subject, description, status, created_at, closed_at')
          .eq('resident_id', uid)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() => _reports = [
            for (final r in rows) ReportSummary.fromRow(r),
          ]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your reports. Pull to retry.');
    }
  }

  List<ReportSummary> get _visible {
    final all = _reports ?? const <ReportSummary>[];
    final wires = _filter.wires;
    if (wires == null) return all;
    return all.where((r) => wires.contains(r.status.wire)).toList();
  }

  // ---------- actions ----------------------------------------

  Future<void> _cancel(ReportSummary r) async {
    // Figma 2864:332 — the same navy pill dialog as everywhere else in
    // the app, not a plain Material AlertDialog. This used to be one;
    // fixed during the Figma parity pass (27 Aug 2026).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ActionDialog(
        title: 'Confirm to cancel?',
        body: 'Once you cancel, the case can’t be opened again.',
        secondaryLabel: 'Back',
        onSecondary: () => Navigator.of(context).pop(false),
        primaryLabel: 'Confirm',
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
          title: 'Report has been cancelled.',
          primaryLabel: 'Back',
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
      _toast('Your request has been sent to the barangay.');
      _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _toast(_friendly(e.message));
    }
  }

  String _friendly(String raw) {
    final m = raw.toLowerCase();
    if (m.contains('already started working')) {
      return 'The barangay has already started on this report, so it can '
          'no longer be cancelled.';
    }
    if (m.contains('only a finished report')) {
      return 'Only a completed report can be reopened.';
    }
    if (m.contains('only the resident')) {
      return 'You can only do this to your own reports.';
    }
    if (m.contains('say why')) {
      return 'Please give a reason.';
    }
    return 'That did not work. Please try again.';
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Tokens.navy,
      ));
  }

  // ---------- build ------------------------------------------

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

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
              Text('View your Reports',
                  style: t.labelLarge?.copyWith(fontSize: 18)),
              const SizedBox(height: 10),
              _FilterBox(
                value: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: Tokens.navy,
                  child: _body(t),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(TextTheme t) {
    if (_error != null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.hint)),
        ],
      );
    }

    if (_reports == null) {
      return const Center(child: CircularProgressIndicator(color: Tokens.navy));
    }

    final visible = _visible;
    if (visible.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 100),
          Icon(Icons.description_outlined,
              size: 48, color: Tokens.navy.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            _filter == ReportFilter.all
                ? 'You have not filed any reports yet.'
                : 'No ${_filter.label.toLowerCase()} reports.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Tokens.muted),
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
        return _ReportCard(
          report: r,
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

class _FilterBox extends StatelessWidget {
  const _FilterBox({required this.value, required this.onChanged});

  final ReportFilter value;
  final ValueChanged<ReportFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.field,
        border: Border.all(color: Tokens.navy),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ReportFilter>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(20),
          dropdownColor: Tokens.field,
          icon: const Icon(Icons.expand_more, color: Tokens.navy, size: 20),
          style: const TextStyle(fontSize: 14, color: Tokens.navy),
          items: [
            for (final f in ReportFilter.values)
              DropdownMenuItem(value: f, child: Text(f.label)),
          ],
          onChanged: (f) => f == null ? null : onChanged(f),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.report,
    required this.onView,
    this.onCancel,
    this.onReopen,
  });

  final ReportSummary report;
  final VoidCallback onView;
  final VoidCallback? onCancel;
  final VoidCallback? onReopen;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onView,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 15, 10, 10),
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: '('),
                        TextSpan(
                          text: '${report.trackingId} - '
                              '${report.status.label}',
                          style: TextStyle(color: report.status.labelColour),
                        ),
                        const TextSpan(text: ') '),
                        TextSpan(text: report.subject),
                      ],
                    ),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      height: 1.1,
                      color: Tokens.bg,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Submitted on ${_formatDate(report.createdAt)}',
                    style: const TextStyle(fontSize: 12, color: Tokens.bg),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '\u201C${report.description}\u201D',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, height: 1.25, color: Tokens.bg),
                  ),
                ],
              ),
            ),
            _CardMenu(
              onView: onView,
              onCancel: onCancel,
              onReopen: onReopen,
            ),
          ],
        ),
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
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_horiz, color: Tokens.bg, size: 20),
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
        const PopupMenuItem(
          value: 'view',
          height: 36,
          child: Row(children: [
            Icon(Icons.visibility_outlined, size: 16, color: Tokens.bg),
            SizedBox(width: 8),
            Text('View',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Tokens.bg)),
          ]),
        ),
        if (onCancel != null)
          const PopupMenuItem(
            value: 'cancel',
            height: 36,
            child: Row(children: [
              Icon(Icons.cancel_outlined, size: 16, color: Tokens.bg),
              SizedBox(width: 8),
              Text('Cancel',
                  style: TextStyle(fontSize: 12, color: Tokens.bg)),
            ]),
          ),
        if (onReopen != null)
          const PopupMenuItem(
            value: 'reopen',
            height: 36,
            child: Row(children: [
              Icon(Icons.refresh, size: 16, color: Tokens.bg),
              SizedBox(width: 8),
              Text('Reopen',
                  style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Tokens.bg)),
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
      backgroundColor: Tokens.navy,
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
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Tokens.bg,
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
              backgroundColor: Tokens.bg,
              foregroundColor: Tokens.navy,
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
              foregroundColor: Tokens.bg,
              side: const BorderSide(color: Tokens.bg),
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
      backgroundColor: Tokens.bg,
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
              fillColor: Tokens.field,
              hintText: 'Your reason',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Tokens.navy),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Send request'),
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
      title: 'Photo access',
      rationale: 'SmartSumbong needs access to your photos to attach '
          'evidence to this reopen request.',
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
      setState(() => _error = 'Please choose a reason.');
      return;
    }
    if (_concern.text.trim().isEmpty) {
      setState(() => _error = 'Please describe your concern.');
      return;
    }
    if (!_acknowledged) {
      setState(() =>
          _error = 'Please confirm the information above is accurate.');
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
                color: Tokens.navy,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reopen:\n(${r.trackingId} - ${r.status.label}) '
                    '${r.subject}',
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      height: 1.25,
                      color: Tokens.bg,
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
                    color: Tokens.field,
                    border: Border.all(color: Tokens.navy),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.closingRemark != null) ...[
                        const Text(
                          'Original Closing Remarks',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Tokens.navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.closingRemark!,
                          style: const TextStyle(
                              fontSize: 12, height: 1.35, color: Tokens.navy),
                        ),
                      ],
                      if (r.closedAt != null) ...[
                        if (widget.closingRemark != null)
                          const SizedBox(height: 8),
                        Text(
                          'Date Closed: ${_formatDate(r.closedAt!)}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Tokens.navy,
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
                color: Tokens.field,
                border: Border.all(color: Tokens.navy),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Note: Reopening asks the barangay to look at this case '
                'again. If this is a new problem rather than the same '
                'one, please file a new report instead.',
                style: TextStyle(fontSize: 12, height: 1.35,
                    color: Tokens.navy),
              ),
            ),
            const SizedBox(height: 16),

            const Text('Reason of Reopen',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Tokens.navy)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              initialValue: _reason,
              isExpanded: true,
              hint: const Text('Select a Reason'),
              items: [
                for (final v in _reopenReasons)
                  DropdownMenuItem(value: v, child: Text(v)),
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
              decoration: const InputDecoration(
                hintText: 'Enter your concern here.',
              ),
              onChanged: (_) => setState(() => _error = null),
            ),

            const SizedBox(height: 14),

            const Text('(Optional)',
                style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Tokens.navy)),
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
                  style: const TextStyle(color: Tokens.hint, fontSize: 12)),
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
                const Expanded(
                  child: Text(
                    'I acknowledge that the information I am submitting is, '
                    'to the best of my knowledge, accurate and complete.',
                    style: TextStyle(
                        fontSize: 12, color: Tokens.navy, height: 1.3),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!,
                  style: const TextStyle(color: Tokens.hint, fontSize: 12)),
            ],
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Tokens.bg),
                          )
                        : const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime utc) {
    final d = utc.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
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
          color: Tokens.field,
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
            const Expanded(
              child: Text(
                'A photo is attached to this request.',
                style: TextStyle(fontSize: 12, color: Tokens.navy),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.cancel, color: Tokens.navy),
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
          color: Tokens.field,
          borderRadius: BorderRadius.circular(25),
        ),
        child: CustomPaint(
          painter: _ReopenDashedBorder(),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_box_outlined, color: Tokens.navy, size: 22),
              SizedBox(height: 6),
              Text('Attach Media',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Tokens.navy,
                  )),
              Text('(Max: 10 MB)',
                  style: TextStyle(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: Tokens.navy,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReopenDashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Tokens.navy
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
