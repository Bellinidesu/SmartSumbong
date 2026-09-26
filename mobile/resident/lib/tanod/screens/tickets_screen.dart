// SmartSumbong — the dispatch model.
//
// Ticket and DispatchState only. The list screen that used to live here
// is gone: REPORTS - TANOD is an accordion, built in
// reports_screen.dart, and two lists over the same rows would mean two
// places to fix when the query changes.
//
// Two clocks matter and they are not the same thing:
//
//   accept_due_at  — how long the tanod has to respond at all. Elapsing
//                    expires the dispatch and alerts the admin (0006).
//   due_at         — the report's own SLA, from the category's
//                    resolution_hours. Elapsing is a breach on the
//                    barangay, not on this tanod.

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

// The screen that used to live here is gone. REPORTS - TANOD is an
// accordion, built in reports_screen.dart, and keeping a second list of
// the same rows would mean two places to fix when the query changes.
// Ticket and DispatchState stay because Home and the ticket detail both
// read them.
