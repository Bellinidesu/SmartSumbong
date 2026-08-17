// SmartSumbong — Notifications (tanod).
//
// Figma: NOTIFICATION (2260:1781), NO NOTIFICATION (2452:386).
//
// Everything the system tells a resident lands here: status changes on
// their complaints, SLA warnings, and the approval message when the
// barangay verifies their account. The Home bell counts the unread ones.
//
// Marked read on open rather than per row. A resident who opened the
// screen has seen them, and asking them to tap each one to clear a badge
// is a chore that teaches them to ignore the badge.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as String,
        kind: r['kind'] as String? ?? '',
        message: r['message'] as String? ?? '',
        isRead: r['is_read'] == true,
        createdAt:
            DateTime.tryParse(r['created_at'] as String? ?? '') ?? DateTime.now(),
      );

  /// The three kinds in notification_kind read differently to a
  /// resident: a status change is news, an SLA warning is the barangay
  /// telling on itself, and a dispatch note is somebody on their way.
  IconData get icon => switch (kind) {
        'sla_warning' => Icons.schedule,
        'dispatch' => Icons.directions_walk,
        _ => Icons.notifications_none_rounded,
      };
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final client = Supabase.instance.client;
    final uid = client.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _error = null);
    try {
      final rows = await client
          .from('notifications')
          .select('id, kind, message, is_read, created_at')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() => _items = [
            for (final r in rows) AppNotification.fromRow(r),
          ]);

      // Clear the badge. Failing here is not worth telling the resident
      // about — the notifications are on screen either way.
      final unread = [
        for (final n in _items!) if (!n.isRead) n.id,
      ];
      if (unread.isNotEmpty) {
        try {
          await client
              .from('notifications')
              .update({'is_read': true}).inFilter('id', unread);
        } catch (_) {}
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not load your notifications.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        surfaceTintColor: Tokens.bg,
        elevation: 0,
        foregroundColor: Tokens.navy,
        title: Text('Notifications',
            style: t.labelLarge?.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: Tokens.navy,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Text(_error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Tokens.hint)),
      ]);
    }

    if (_items == null) {
      return const Center(child: CircularProgressIndicator(color: Tokens.navy));
    }

    if (_items!.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.notifications_off_outlined,
              size: 56, color: Tokens.navy.withValues(alpha: 0.35)),
          const SizedBox(height: 20),
          const Text(
            'No notifications yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: Tokens.navy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'When the barangay updates one of your reports, you will '
            'see it here.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.35, color: Tokens.muted),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(30, 16, 30, 32),
      itemCount: _items!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _NotificationCard(item: _items![i]),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    // Unread stays visually distinct for this one viewing, even though
    // the row has just been marked read — otherwise opening the screen
    // erases the very distinction the resident came to see.
    final unread = !item.isRead;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: unread ? Tokens.navy : Tokens.field,
        border: Border.all(color: Tokens.navy),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon,
              size: 20, color: unread ? Tokens.bg : Tokens.navy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: unread ? Tokens.bg : Tokens.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _ago(item.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: unread
                        ? Tokens.bg.withValues(alpha: 0.75)
                        : Tokens.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(DateTime utc) {
    final d = DateTime.now().difference(utc.toLocal());
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
    if (d.inHours < 24) {
      return d.inHours == 1 ? 'An hour ago' : '${d.inHours} hours ago';
    }
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';

    final l = utc.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }
}
