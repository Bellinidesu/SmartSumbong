// SmartSumbong — push notifications (Firebase Cloud Messaging).
//
// Closes the gap found during QA: notifications_screen only ever showed
// what was already true when the resident/tanod happened to reopen the
// app. Nothing told them anything while it was backgrounded or closed —
// there was no push system at all (README listed it as "planned"). This
// file is the client half of that: it registers this device against the
// signed-in user, shows a system notification while the app is open
// (Android does not do this for you in the foreground — only in the
// background/killed states), and routes a tap back to the right report.
//
// The server half — actually turning a new `notifications` row into a
// call to FCM — is supabase/functions/send-dispatch-push, triggered by a
// Database Webhook on insert. Both halves have to exist for a phone to
// ever show a banner; this file alone does not.
//
// WHAT THIS FILE DOES NOT DO: create the Firebase project, or wire
// google-services.json / firebase_options.dart into either app's Android
// build. That is `flutterfire configure`, run once per app — it needs a
// Firebase login only the barangay's own Google account can give it. See
// the deploy notes delivered alongside this file.

import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Must be a top-level function (or static): FCM invokes this in its own
/// background isolate for a data message that arrives while the app is
/// backgrounded or fully killed. The functions this app actually sends
/// are plain FCM "notification" messages, which Android displays by
/// itself in that state without any app code running at all — this
/// handler exists only so the isolate is registered for the future, and
/// deliberately does nothing today.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class PushNotifications {
  PushNotifications._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'smartsumbong_default',
    'SmartSumbong notifications',
    description: 'Status changes and dispatch updates for your reports.',
    importance: Importance.high,
  );

  static bool _initialized = false;

  /// Call once, after Firebase.initializeApp(). [onOpenReport] is how each
  /// app decides what "open this notification" means — the resident app
  /// has a `/report` route that takes a report id; the tanod app does
  /// not have an equivalent single-ticket route yet, so it can point
  /// this at `/notifications` instead. Kept as a callback here rather
  /// than a hardcoded route name so this shared package does not have to
  /// know either app's navigation.
  static Future<void> init({
    required void Function(String reportId) onOpenReport,
  }) async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final reportId = response.payload;
        if (reportId != null && reportId.isNotEmpty) {
          onOpenReport(reportId);
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Android 13+ requires this explicit runtime grant or nothing above
    // ever shows, foreground or otherwise.
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // Foreground display. This is the ONE state Android does not handle
    // for a plain FCM notification message — everywhere else (background,
    // killed) the system tray shows it without any of this code running.
    //
    // The id is derived from report_id, not the notification's own
    // hashCode (title+body), so a second status push for the SAME
    // report replaces the first in the tray instead of stacking next to
    // it — matching what send-dispatch-push now does server-side via
    // android.notification.tag for the background/killed path this
    // listener never sees. A notification with no report_id
    // (verification) keeps the old per-message id, since there is
    // nothing to collapse it against.
    FirebaseMessaging.onMessage.listen((message) {
      final n = message.notification;
      if (n == null) return;
      final reportId = message.data['report_id'] as String?;
      final notifId = (reportId != null && reportId.isNotEmpty)
          ? reportId.hashCode
          : n.hashCode;
      _local.show(
        id: notifId,
        title: n.title,
        body: n.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.high,
            priority: Priority.high,
            // A remark can run long; the collapsed one-line preview
            // Android shows by default cuts it off mid-sentence.
            styleInformation: BigTextStyleInformation(n.body ?? ''),
          ),
        ),
        payload: reportId,
      );
    });

    // Tapped from the system tray while the app was backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final reportId = message.data['report_id'] as String?;
      if (reportId != null && reportId.isNotEmpty) onOpenReport(reportId);
    });

    // Tapped from a fully killed state — the app's very first frame.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    final initialReport = initial?.data['report_id'] as String?;
    if (initialReport != null && initialReport.isNotEmpty) {
      onOpenReport(initialReport);
    }

    // Keep the backend's copy current across token rotations (FCM
    // rotates tokens periodically and after certain app/OS events).
    FirebaseMessaging.instance.onTokenRefresh.listen(_registerRaw);
  }

  /// Call after a successful sign-in, and it is harmless to call again on
  /// every cold start with an existing session — register_device_token
  /// upserts on (user_id, fcm_token).
  static Future<void> registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _registerRaw(token);
    } catch (_) {
      // Best-effort. A resident with no signal at the moment of sign-in
      // simply does not get push until the next successful call — nothing
      // else in the app depends on this succeeding.
    }
  }

  static Future<void> _registerRaw(String token) async {
    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
      });
    } catch (_) {}
  }

  /// Call at sign-out, so a stale token for a logged-out account does not
  /// keep receiving that account's notifications on a shared or reused
  /// device.
  static Future<void> unregisterToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await Supabase.instance.client
            .rpc('unregister_device_token', params: {'p_token': token});
      }
    } catch (_) {}
  }
}
