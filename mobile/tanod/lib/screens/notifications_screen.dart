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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../i18n.dart';
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

  // Live while open (8 Sep 2026 — mirrors resident's notifications_
  // screen.dart / this app's own tanod_home_screen.dart). A channel on
  // this tanod's own notifications rows reloads the list through the
  // same _load() pull-to-refresh already used, so a freshly-arrived row
  // gets marked read the moment it arrives instead of only on the next
  // manual open or pull.
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
        .channel('tanod-notifications-$uid')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'notifications',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
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
    if (uid == null) return;

    _subscribeLive(uid);

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
      setState(() => _error = context.s.notificationsLoadError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: context.colors.bg,
        surfaceTintColor: context.colors.bg,
        elevation: 0,
        foregroundColor: context.colors.navy,
        title: Text(context.s.notificationsTitle,
            style: t.labelLarge?.copyWith(fontSize: 18)),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          color: context.colors.navy,
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        Text(_error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.hint)),
      ]);
    }

    if (_items == null) {
      return Center(
          child: CircularProgressIndicator(color: context.colors.navy));
    }

    if (_items!.isEmpty) {
      final s = context.s;
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 44),
        children: [
          const SizedBox(height: 120),
          Icon(Icons.notifications_off_outlined,
              size: 56, color: context.colors.navy.withValues(alpha: 0.35)),
          const SizedBox(height: 20),
          Text(
            s.notificationsEmptyTitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: context.colors.navy,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.notificationsEmptyBody,
            textAlign: TextAlign.center,
            style:
                TextStyle(fontSize: 13, height: 1.35, color: context.colors.muted),
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
        color: unread ? context.colors.navy : context.colors.field,
        border: Border.all(color: context.colors.navy),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(item.icon,
              size: 20,
              color: unread ? context.colors.bg : context.colors.navy),
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
                    color: unread ? context.colors.bg : context.colors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _ago(context, item.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: unread
                        ? context.colors.bg.withValues(alpha: 0.75)
                        : context.colors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _ago(BuildContext context, DateTime utc) {
    final s = context.s;
    final d = DateTime.now().difference(utc.toLocal());
    if (d.inMinutes < 1) return s.notificationsJustNow;
    if (d.inMinutes < 60) return s.notificationsMinutesAgo(d.inMinutes);
    if (d.inHours < 24) {
      return d.inHours == 1
          ? s.notificationsAnHourAgo
          : s.notificationsHoursAgo(d.inHours);
    }
    if (d.inDays == 1) return s.notificationsYesterday;
    if (d.inDays < 7) return s.notificationsDaysAgo(d.inDays);

    final l = utc.toLocal();
    return '${s.monthAbbr(l.month)} ${l.day}, ${l.year}';
  }
}
