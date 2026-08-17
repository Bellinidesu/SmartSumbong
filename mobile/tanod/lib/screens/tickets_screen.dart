// SmartSumbong — assigned tickets.
//
// "View Assigned Complaints And SLA deadlines" in the tanod use case.
//
// Two clocks run here and they are not the same thing, which is the
// whole reason this screen is not a plain list:
//
//   accept_due_at  — how long the tanod has to respond at all. Elapsing
//                    expires the dispatch and alerts the admin (0006).
//   due_at         — the report's own SLA, set from the category's
//                    resolution_hours. Elapsing is a breach on the
//                    barangay, not on this tanod.
//
// An assigned ticket is counting against the first; an accepted one
// against the second. Showing one number without saying which it is
// would be worse than showing none.
//
// Live rows only. Rerouted, expired and resolved dispatches are history
// and belong in an activity log, not a work queue.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';
import 'ticket_screen.dart';

enum DispatchState {
  assigned('assigned'),
  accepted('accepted'),
  rerouted('rerouted'),
  resolved('resolved'),
  expired('expired');

  const DispatchState(this.wire);

  final String wire;

  static DispatchState parse(String? w) => DispatchState.values.firstWhere(
        (s) => s.wire == w,
        orElse: () => DispatchState.assigned,
      );
}

class Ticket {
  Ticket({
    required this.dispatchId,
    required this.reportId,
    required this.state,
    required this.trackingId,
    required this.subject,
    required this.description,
    required this.acceptDueAt,
    required this.dueAt,
    required this.assignedAt,
    required this.instructions,
  });

  final String dispatchId;
  final String reportId;
  final DispatchState state;
  final String trackingId;
  final String subject;
  final String description;
  final DateTime? acceptDueAt;
  final DateTime? dueAt;
  final DateTime? assignedAt;
  final String? instructions;

  /// The clock that applies right now.
  DateTime? get deadline =>
      state == DispatchState.assigned ? acceptDueAt : dueAt;

  bool get awaitingResponse => state == DispatchState.assigned;

  factory Ticket.fromRow(Map<String, dynamic> d) {
    final r = (d['reports'] ?? const {}) as Map<String, dynamic>;
    return Ticket(
      dispatchId: d['id'] as String,
      reportId: d['report_id'] as String,
      state: DispatchState.parse(d['state'] as String?),
      trackingId: r['tracking_id'] as String? ?? '',
      subject: r['subject'] as String? ?? '',
      description: r['description'] as String? ?? '',
      acceptDueAt: DateTime.tryParse(d['accept_due_at'] as String? ?? ''),
      dueAt: DateTime.tryParse(r['due_at'] as String? ?? ''),
      assignedAt: DateTime.tryParse(d['assigned_at'] as String? ?? ''),
      instructions: d['admin_instructions'] as String?,
    );
  }
}

class TicketsScreen extends StatefulWidget {
  const TicketsScreen({super.key});

  @override
  State<TicketsScreen> createState() => _TicketsScreenState();
}

class _TicketsScreenState extends State<TicketsScreen> {
  List<Ticket>? _tickets;
  String? _error;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    // The countdowns have to move on their own. Once a minute is enough
    // and costs nothing; a per-second timer would redraw the list 60
    // times for a number that changes once.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser!.id;

      // dispatches_read already limits this to tanod_id = auth.uid(),
      // but the filter is stated anyway: relying on RLS alone to scope a
      // query means a policy change silently changes what this screen
      // shows.
      final rows = await client
          .from('dispatches')
          .select('id, report_id, state, accept_due_at, assigned_at, '
              'admin_instructions, '
              'reports(tracking_id, subject, description, due_at)')
          .eq('tanod_id', uid)
          .inFilter('state', ['assigned', 'accepted'])
          .order('assigned_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _tickets = [
          for (final r in rows) Ticket.fromRow(r as Map<String, dynamic>),
        ];
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your tickets.');
    }
  }

  Future<void> _open(Ticket t) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TicketScreen(ticket: t)),
    );
    if (changed == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final tickets = _tickets;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text('My Tickets',
                style: t.headlineLarge?.copyWith(fontSize: 26)),
            const SizedBox(height: 16),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: _body(t, tickets),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(TextTheme t, List<Ticket>? tickets) {
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        children: [
          const SizedBox(height: 80),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Tokens.hint)),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              onPressed: _load,
              child: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    if (tickets == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (tickets.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        children: [
          const SizedBox(height: 90),
          const Icon(Icons.inbox_outlined,
              size: 46, color: Tokens.muted),
          const SizedBox(height: 12),
          const Text(
            'No tickets right now.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Set yourself On Duty and share your location to be sent '
            'nearby complaints.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.4, color: Tokens.muted),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      itemCount: tickets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => _TicketCard(
        ticket: tickets[i],
        onTap: () => _open(tickets[i]),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.ticket, required this.onTap});

  final Ticket ticket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final waiting = ticket.awaitingResponse;

    return Material(
      color: Tokens.navy,
      borderRadius: BorderRadius.circular(25),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '(${ticket.trackingId}) ${ticket.subject}',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.25,
                        color: Tokens.bg,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _StatePill(waiting: waiting),
                ],
              ),
              const SizedBox(height: 8),

              Text(
                ticket.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, height: 1.35, color: Tokens.bg),
              ),
              const SizedBox(height: 12),

              _Countdown(
                deadline: ticket.deadline,
                waiting: waiting,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  const _StatePill({required this.waiting});

  final bool waiting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: waiting ? Tokens.orange : Tokens.bg,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Text(
        waiting ? 'New' : 'Accepted',
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: Tokens.navy,
        ),
      ),
    );
  }
}

/// Names the clock as well as reading it. "Respond within 12 min" and
/// "Resolve within 12 min" are different obligations and a tanod
/// deciding what to do next needs to know which one is running.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.deadline, required this.waiting});

  final DateTime? deadline;
  final bool waiting;

  @override
  Widget build(BuildContext context) {
    final d = deadline;
    if (d == null) {
      return Text(
        waiting ? 'Waiting for your response' : 'No deadline set',
        style: const TextStyle(fontSize: 11, color: Tokens.bg),
      );
    }

    final left = d.difference(DateTime.now());
    final overdue = left.isNegative;
    final label = waiting ? 'Respond' : 'Resolve';

    final text = overdue
        ? (waiting
            ? 'Response window closed'
            : 'Overdue by ${_short(left.abs())}')
        : '$label within ${_short(left)}';

    return Row(
      children: [
        Icon(
          overdue ? Icons.warning_amber_rounded : Icons.schedule,
          size: 15,
          color: overdue ? Tokens.orange : Tokens.bg,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: overdue ? FontWeight.w700 : FontWeight.w400,
              color: overdue ? Tokens.orange : Tokens.bg,
            ),
          ),
        ),
      ],
    );
  }

  static String _short(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) {
      final m = d.inMinutes % 60;
      return m == 0 ? '${d.inHours} hr' : '${d.inHours} hr ${m} min';
    }
    return '${d.inDays} d';
  }
}
