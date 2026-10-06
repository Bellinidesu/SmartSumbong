// SmartSumbong — Assigned Dispatch.
//
// Figma: REPORTS - TANOD, both states.
//
// An accordion rather than a list that pushes a detail screen. Each row
// opens in place to show who filed it, what they said, and three links
// out — map, media, instructions — with a green Submit an update at the
// bottom.
//
// This is deliberately not where a ticket is accepted. Home carries
// Incoming Dispatch with View Details, and accept and reroute live
// there; by the time a ticket appears here the tanod has taken it and
// the only thing left is to report back. Splitting it that way means
// neither screen offers an action that would fail — accept_dispatch()
// only moves a row in `assigned`, and submit_field_report() only one in
// `accepted`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:smartsumbong_core/smartsumbong_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../tanod_strings.dart';
import '../../d/d_theme.dart';
import '../../d/d_ui.dart';
import '../widgets/tanod_nav_bar.dart';
import 'dispatch_order.dart';
import 'tickets_screen.dart';

class TanodReportsScreen extends StatefulWidget {
  const TanodReportsScreen({super.key});

  @override
  State<TanodReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<TanodReportsScreen> {
  List<_Assigned>? _rows;
  String? _error;

  // Live updates (8 Sep 2026 — mirrors resident's reports_screen.dart
  // and this app's own tanod_home_screen.dart). Before this, an update
  // elsewhere (the tanod resolves the same ticket from another device,
  // an admin reroutes it) sat unseen here until a manual pull.
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

  /// One channel per tanod, opened once the first successful [_load]
  /// confirms who they are — never re-opened by a later, live-triggered
  /// [_load], since [_liveChannel] is already set by then.
  void _subscribeLive(String uid) {
    if (_liveChannel != null) return;
    _liveChannel = Supabase.instance.client
        .channel('tanod-reports-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'dispatches',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'tanod_id',
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
    // The last copy, at once (branch B).
    if (_rows == null) {
      final saved = await JsonCache.read('assigned');
      if (saved is List && mounted && _rows == null) {
        setState(() => _rows = [
              for (final r in saved)
                _Assigned.fromRow(Map<String, dynamic>.from(r as Map)),
            ]);
      }
    }
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

      _subscribeLive(uid);

      final rows = await client
          .from('dispatches')
          .select('id, report_id, state, accept_due_at, assigned_at, '
              'admin_instructions, '
              'reports(tracking_id, subject, description, due_at, '
              'is_anonymous, latitude, longitude)')
          .eq('tanod_id', uid)
          .eq('state', 'accepted')
          .order('assigned_at', ascending: false);

      unawaited(JsonCache.write('assigned', rows));
      if (!mounted) return;
      setState(() {
        _rows = [
          for (final r in rows) _Assigned.fromRow(r),
        ];
        _error = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = context.ts.reportsLoadError(e.message));
    } catch (_) {
      if (!mounted) return;
      // No signal, but the saved list is showing: keep it.
      if (_rows != null) return;
      setState(() => _error = context.ts.reportsLoadOffline);
    }
  }

  // Branch D: the preview's Assigned reports — a heading and a lead line,
  // then one card per accepted dispatch: what, the ticket, the target
  // date (red once it has passed), the three quick looks (map, media,
  // the admin's directions) and Open dispatch.
  @override
  Widget build(BuildContext context) {
    final s = context.ts;
    return DPage(
      bottomBar: const TanodNavBar(current: TanodTab.reports),
      child: RefreshIndicator(
        onRefresh: _load,
        color: context.d.accent,
        child: _body(context, s),
      ),
    );
  }

  Widget _body(BuildContext context, TanodStrings s) {
    final d = context.d;
    final head = <Widget>[
      DHeading(s.reportsTitle,
          lead: context.tr('Dispatches given to you. Open one to see the details, the map and the admin’s directions.',
              'Mga dispatch na ibinigay sa iyo. Buksan ang isa para makita ang detalye, mapa at tagubilin.')),
      const SizedBox(height: 16),
    ];
    final rows = _rows;
    if (_error != null) {
      return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
        ...head,
        DSheet(
          borderColor: DColors.red.withValues(alpha: .5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(_error!, style: DType.body(d.dark ? const Color(0xFFFF8A8A) : DColors.red, size: 13, w: FontWeight.w700)),
            const SizedBox(height: 10),
            DButton(s.reportsTryAgain, small: true, kind: DButtonKind.accent, onTap: _load),
          ]),
        ),
      ]);
    }
    if (rows == null) {
      return ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
        ...head,
        const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        ...head,
        if (rows.isEmpty)
          DSheet(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
            child: Column(children: [
              Icon(Icons.assignment_turned_in_outlined, size: 40, color: d.muted),
              const SizedBox(height: 10),
              Text(s.reportsEmptyTitle, textAlign: TextAlign.center, style: DType.h3(d.ink)),
              const SizedBox(height: 4),
              Text(s.reportsEmptyBody, textAlign: TextAlign.center, style: DType.body(d.muted, size: 13)),
            ]),
          )
        else
          for (final r in rows) ...[
            _AssignedCard(row: r, onUpdated: _load),
            const SizedBox(height: 12),
          ],
      ],
    );
  }
}

class _Assigned {
  _Assigned({
    required this.dispatchId,
    required this.reportId,
    required this.trackingId,
    required this.subject,
    required this.description,
    required this.dueAt,
    required this.assignedAt,
    required this.isAnonymous,
    required this.instructions,
    required this.lat,
    required this.lon,
  });

  final String dispatchId;
  final String reportId;
  final String trackingId;
  final String subject;
  final String description;
  final DateTime? dueAt;
  /// When the barangay sent it: the time on its instructions bubble.
  final DateTime? assignedAt;
  final bool isAnonymous;
  final String? instructions;
  final double? lat;
  final double? lon;

  factory _Assigned.fromRow(Map<String, dynamic> d) {
    final r = (d['reports'] ?? const {}) as Map<String, dynamic>;
    return _Assigned(
      dispatchId: d['id'] as String,
      reportId: d['report_id'] as String,
      trackingId: r['tracking_id'] as String? ?? '',
      subject: r['subject'] as String? ?? '',
      description: r['description'] as String? ?? '',
      dueAt: DateTime.tryParse(r['due_at'] as String? ?? ''),
      assignedAt: DateTime.tryParse(d['assigned_at'] as String? ?? ''),
      isAnonymous: r['is_anonymous'] == true,
      instructions: d['admin_instructions'] as String?,
      lat: (r['latitude'] as num?)?.toDouble(),
      lon: (r['longitude'] as num?)?.toDouble(),
    );
  }

  Ticket toTicket() => Ticket(
        dispatchId: dispatchId,
        reportId: reportId,
        state: DispatchState.accepted,
        trackingId: trackingId,
        subject: subject,
        description: description,
        acceptDueAt: null,
        dueAt: dueAt,
        assignedAt: assignedAt,
        instructions: instructions,
      );
}

class _AssignedCard extends StatelessWidget {
  const _AssignedCard({required this.row, required this.onUpdated});

  final _Assigned row;
  final Future<void> Function() onUpdated;

  @override
  Widget build(BuildContext context) {
    final d = context.d;
    final s = context.ts;
    final overdue = row.dueAt != null && row.dueAt!.isBefore(DateTime.now());
    final red = d.dark ? const Color(0xFFFF8A8A) : DColors.red;
    Widget look(IconData icon, String tip, DispatchTarget t) => Tooltip(
          message: tip,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _open(context, target: t),
            child: DWell(icon, size: 40),
          ),
        );
    return Container(
      decoration: BoxDecoration(
        color: d.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: d.line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: d.dark ? .25 : .05), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 5, color: overdue ? red : DColors.orange),
          Expanded(
            child: InkWell(
              onTap: () => _open(context),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(row.subject, style: DType.h3(d.ink).copyWith(fontSize: 17)),
                  const SizedBox(height: 2),
                  Text(row.trackingId, style: DType.mono(d.link, size: 12.5)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.event_outlined, size: 15, color: overdue ? red : d.muted),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        '${s.reportsDeadlineLabel}${_date(context, row.dueAt)}${overdue ? ' · ${s.ticketOverdue}' : ''}',
                        style: DType.body(overdue ? red : d.muted, size: 12.5, w: overdue ? FontWeight.w800 : FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('“${row.description}”', maxLines: 2, overflow: TextOverflow.ellipsis, style: DType.body(d.ink2, size: 13)),
                  const SizedBox(height: 12),
                  Row(children: [
                    look(Icons.map_outlined, s.reportsViewMap, DispatchTarget.map),
                    const SizedBox(width: 6),
                    look(Icons.photo_library_outlined, s.reportsViewMedia, DispatchTarget.media),
                    const SizedBox(width: 6),
                    look(Icons.assignment_outlined, s.reportsViewInstructions, DispatchTarget.instructions),
                    const Spacer(),
                    DButton(s.windowOpen, small: true, onTap: () => _open(context)),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  /// The quick looks open the dispatch card on that pane; Open dispatch
  /// passes no target, so an accepted ticket goes on to the job page.
  Future<void> _open(BuildContext context, {DispatchTarget target = DispatchTarget.order}) async {
    if (await showDispatchOrder(context, row.toTicket(), target: target)) {
      await onUpdated();
    }
  }

  static String _date(BuildContext context, DateTime? d) {
    if (d == null) return context.ts.reportsDeadlineNotSet;
    final l = d.toLocal();
    return '${context.ts.monthFull(l.month)} ${l.day}, ${l.year}';
  }
}
