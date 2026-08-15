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

  bool get canRequestReopen =>
      this == ReportStatus.resolved || this == ReportStatus.closed;

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
  completed('Completed', ['resolved', 'closed', 'archived']),
  rejected('Rejected', ['rejected']),
  cancelled('Cancelled', ['cancelled']);

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
  });

  final String id;
  final String trackingId;
  final String subject;
  final String description;
  final ReportStatus status;
  final DateTime createdAt;

  factory ReportSummary.fromRow(Map<String, dynamic> r) => ReportSummary(
        id: r['id'] as String,
        trackingId: r['tracking_id'] as String? ?? '',
        subject: r['subject'] as String? ?? '',
        description: r['description'] as String? ?? '',
        status: ReportStatus.parse(r['status'] as String?),
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      );
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.auth});

  final AuthService auth;

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
          .select('id, tracking_id, subject, description, status, created_at')
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Tokens.bg,
        title: const Text('Cancel this report?'),
        content: Text(
          'You are about to withdraw ${r.trackingId} — ${r.subject}. '
          'The barangay will stop working on it. This cannot be undone.',
          style: const TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Tokens.hint),
            child: const Text('Cancel report'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await Supabase.instance.client
          .rpc('cancel_report', params: {'p_report': r.id});
      if (!mounted) return;
      _toast('Report ${r.trackingId} has been cancelled.');
      _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _toast(_friendly(e.message));
    }
  }

  Future<void> _requestReopen(ReportSummary r) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReasonDialog(
        title: 'Reopen ${r.trackingId}?',
        prompt: 'Tell the barangay why this should be looked at again.',
      ),
    );
    if (reason == null || reason.trim().isEmpty) return;

    try {
      await Supabase.instance.client.rpc(
        'request_reopen',
        params: {'p_report': r.id, 'p_reason': reason.trim()},
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
