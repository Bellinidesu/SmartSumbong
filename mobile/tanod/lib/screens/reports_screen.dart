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
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
import '../theme.dart';
import '../widgets/figma_ui.dart';
import '../widgets/tanod_nav_bar.dart';
import 'dispatch_order.dart';
import 'tickets_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  List<_Assigned>? _rows;
  String? _error;
  String? _openId;

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

      if (!mounted) return;
      setState(() {
        _rows = [
          for (final r in rows) _Assigned.fromRow(r as Map<String, dynamic>),
        ];
        _error = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() => _error = context.s.reportsLoadError(e.message));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.s.reportsLoadOffline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Scaffold(
      bottomNavigationBar: const TanodNavBar(current: TanodTab.reports),
      body: Stack(
        children: [
          const FigmaTexture(),
          // Figma REPORTS - TANOD: the title 28/800 centred at y=55, a
          // 311-wide 1px rule at 103, the first card at 121.
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                SizedBox(height: figmaTop(context, 55)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: FigmaTitle(s.reportsTitle),
                ),
                Container(
                  width: 311,
                  height: 1,
                  margin: const EdgeInsets.only(top: 4),
                  color: context.colors.navy,
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    color: context.colors.navy,
                    child: _body(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = context.s;
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        children: [
          const SizedBox(height: 60),
          Text(_error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.hint, fontSize: 12)),
          const SizedBox(height: 14),
          Center(
            child: FilledButton(
                onPressed: _load, child: Text(s.reportsTryAgain)),
          ),
        ],
      );
    }

    final rows = _rows;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (rows.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        children: [
          const SizedBox(height: 70),
          Icon(Icons.assignment_outlined, size: 44, color: context.colors.muted),
          const SizedBox(height: 12),
          Text(
            s.reportsEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Urbanist',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.reportsEmptyBody,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: context.colors.muted),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(30, 0, 30, 24),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 11),
      itemBuilder: (_, i) => _AssignedCard(
        row: rows[i],
        open: _openId == rows[i].dispatchId,
        onToggle: () => setState(() =>
            _openId = _openId == rows[i].dispatchId ? null : rows[i].dispatchId),
        onUpdated: _load,
      ),
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
      isAnonymous: r['is_anonymous'] == true,
      instructions: d['admin_instructions'] as String?,
      lat: (r['latitude'] as num?)?.toDouble(),
      lon: (r['longitude'] as num?)?.toDouble(),
    );
  }

  /// The frame prints "User: Anonymous". It stays Anonymous for every
  /// row, and not because every complaint is anonymous — users_self_read
  /// is `id = auth.uid() or is_admin()`, so a tanod cannot read the
  /// filer's row at all. Printing a name here would need that policy
  /// loosened, which is the barangay's decision rather than a display
  /// one. Until then the honest label is the one that is true.
  String get filer => 'Anonymous';

  Ticket toTicket() => Ticket(
        dispatchId: dispatchId,
        reportId: reportId,
        state: DispatchState.accepted,
        trackingId: trackingId,
        subject: subject,
        description: description,
        acceptDueAt: null,
        dueAt: dueAt,
        assignedAt: null,
        instructions: instructions,
      );
}

class _AssignedCard extends StatelessWidget {
  const _AssignedCard({
    required this.row,
    required this.open,
    required this.onToggle,
    required this.onUpdated,
  });

  final _Assigned row;
  final bool open;
  final VoidCallback onToggle;
  final Future<void> Function() onUpdated;

  static const _green = Color(0xFF058F00);

  // Figma "Group 333/335": 352 wide, #F3F3F3, 1px ink edge, radius 20; the
  // heading 14/600 at 30 in and 22 down, "Deadline:" in red, the 13x7
  // chevron 26 from the right. Open, the body is 14/500 at 35 in, then
  // the three links (22px icons, 14/700) and the 162x30 green pill.
  @override
  Widget build(BuildContext context) {
    final ink = context.colors.navy;
    final body = TextStyle(
      fontFamily: 'Urbanist',
      fontWeight: FontWeight.w500,
      fontSize: 14,
      height: 15 / 14,
      color: ink,
    );
    return Container(
      decoration: BoxDecoration(
        color: context.colors.bg,
        border: Border.all(color: ink),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(30, 22, 24, 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: body.copyWith(fontWeight: FontWeight.w600),
                        children: [
                          TextSpan(text: '${row.trackingId} - ${row.subject}\n'),
                          TextSpan(
                            text: context.s.reportsDeadlineLabel,
                            style: const TextStyle(color: kFigmaRed),
                          ),
                          TextSpan(
                            text: _date(context, row.dueAt),
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: kFigmaRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    open
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: ink,
                  ),
                ],
              ),
            ),
          ),

          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(35, 0, 28, 17),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(
                      label: context.s.reportsUserLabel,
                      value: context.s.reportsFilerAnonymous),
                  const SizedBox(height: 15),
                  _Line(
                    label: context.s.reportsDescriptionLabel,
                    value: '\u201C${row.description}\u201D',
                  ),
                  const SizedBox(height: 14),
                  _LinkRow(
                    icon: Icons.location_on_outlined,
                    label: context.s.reportsViewMap,
                    onTap: () => _open(context, target: DispatchTarget.map),
                  ),
                  _LinkRow(
                    icon: Icons.photo_camera_outlined,
                    label: context.s.reportsViewMedia,
                    onTap: () => _open(context, target: DispatchTarget.media),
                  ),
                  _LinkRow(
                    icon: Icons.my_location_rounded,
                    label: context.s.reportsViewInstructions,
                    onTap: () =>
                        _open(context, target: DispatchTarget.instructions),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(50)),
                        boxShadow: kFigmaShadow,
                      ),
                      child: FilledButton(
                        onPressed: () => _open(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: const Color(0xFFF3F3F3),
                          minimumSize: const Size(162, 30),
                          maximumSize: const Size(260, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFF3F3F3)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Urbanist',
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(context.s.reportsSubmitUpdate,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// All four openers land on the same dispatch card — the map, the
  /// evidence and the instructions are already on it, so a fresh modal
  /// for each would be more taps to see less. What changed 9 Sep 2026
  /// (CAPSTONE G12 feedback: the three view links all landed on the
  /// submit-update form) is that each link now says which pane it wants
  /// rather than leaving it to the ticket's default. "Submit an update"
  /// still passes no target, so it opens on the update pane — the ticket
  /// is already accepted, and the order pane's Accept/Reroute would
  /// raise on a row in that state.
  Future<void> _open(
    BuildContext context, {
    DispatchTarget target = DispatchTarget.order,
  }) async {
    if (await showDispatchOrder(context, row.toTicket(), target: target)) {
      await onUpdated();
    }
  }

  static String _date(BuildContext context, DateTime? d) {
    if (d == null) return context.s.reportsDeadlineNotSet;
    final l = d.toLocal();
    return '${context.s.monthFull(l.month)} ${l.day}, ${l.year}';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(
          style: TextStyle(
            fontFamily: 'Urbanist',
            fontWeight: FontWeight.w500,
            fontSize: 14,
            height: 15 / 14,
            color: context.colors.navy,
          ),
          children: [
            TextSpan(
                text: label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      );
}

/// The frame's link row: a 22px icon, the label 14/700 underlined 32 to
/// its right; rows 46 apart.
class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 22, color: ink),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Urbanist',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: ink,
                  decoration: TextDecoration.underline,
                  decorationColor: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
