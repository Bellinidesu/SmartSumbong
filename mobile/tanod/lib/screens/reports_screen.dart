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

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import '../widgets/tanod_nav_bar.dart';
import 'ticket_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

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
      setState(() => _error = 'Could not load your dispatches. '
          '(${e.message})');
    } catch (_) {
      if (!mounted) return;
      setState(() =>
          _error = 'Could not load your dispatches. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      bottomNavigationBar: const TanodNavBar(current: TanodTab.reports),
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.55,
              child: Image.asset(
                'assets/images/texture.png',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 14),
                Text('Assigned Dispatch',
                    style: t.headlineLarge?.copyWith(fontSize: 20)),
                Container(
                  width: 150,
                  height: 2,
                  margin: const EdgeInsets.only(top: 6),
                  color: Tokens.navy,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    color: Tokens.navy,
                    child: _body(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        children: [
          const SizedBox(height: 60),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.hint, fontSize: 12)),
          const SizedBox(height: 14),
          Center(
            child: FilledButton(
                onPressed: _load, child: const Text('Try again')),
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
        children: const [
          SizedBox(height: 70),
          Icon(Icons.assignment_outlined, size: 44, color: Tokens.muted),
          SizedBox(height: 12),
          Text(
            'Nothing assigned to you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: Tokens.navy,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Tickets appear here once you accept them from Home.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: Tokens.muted),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
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

  static const _red = Color(0xFFFF4949);
  static const _green = Color(0xFF1FA84E);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Tokens.bg,
        border: Border.all(color: Tokens.navy, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row.trackingId} - ${row.subject}',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            color: Tokens.navy,
                          ),
                        ),
                        const SizedBox(height: 2),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 10),
                            children: [
                              const TextSpan(
                                text: 'Deadline: ',
                                style: TextStyle(
                                    color: _red,
                                    fontWeight: FontWeight.w700),
                              ),
                              TextSpan(
                                text: _date(row.dueAt),
                                style: const TextStyle(color: Tokens.navy),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(open ? Icons.expand_less : Icons.expand_more,
                      color: Tokens.navy),
                ],
              ),
            ),
          ),

          if (open) ...[
            const Divider(height: 1, color: Tokens.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line(label: 'User: ', value: row.filer),
                  const SizedBox(height: 6),
                  _Line(
                    label: 'Description: ',
                    value: '\u201C${row.description}\u201D',
                  ),
                  const SizedBox(height: 12),

                  _LinkRow(
                    icon: Icons.place_outlined,
                    label: 'View Map',
                    onTap: () => _open(context),
                  ),
                  _LinkRow(
                    icon: Icons.image_outlined,
                    label: 'View Attached Media',
                    onTap: () => _open(context),
                  ),
                  _LinkRow(
                    icon: Icons.info_outline,
                    label: 'View Instructions',
                    onTap: () => _open(context),
                  ),
                  const SizedBox(height: 10),

                  Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      height: 30,
                      child: FilledButton(
                        onPressed: () => _open(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Submit an update'),
                            SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 14),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// All four openers land on the ticket screen. The map, the evidence
  /// and the instructions are already on it, and three separate modals
  /// showing one thing each would be more taps to see less.
  Future<void> _open(BuildContext context) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TicketScreen(ticket: row.toTicket())),
    );
    if (changed == true) await onUpdated();
  }

  static String _date(DateTime? d) {
    if (d == null) return 'not set';
    const m = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final l = d.toLocal();
    return '${m[l.month - 1]} ${l.day}, ${l.year}';
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 11, height: 1.4, color: Tokens.navy),
          children: [
            TextSpan(
                text: label,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: value),
          ],
        ),
      );
}

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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Tokens.navy),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11.5,
                color: Tokens.navy,
                decoration: TextDecoration.underline,
                decorationColor: Tokens.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
