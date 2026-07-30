import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/push/push_message_handler.dart';
import '../../core/utils/logger.dart';

/// Background/terminated messages.
///
/// Deliberately EMPTY and dependency-free: every MyWeli push carries a
/// `notification` block, so Android/iOS render it themselves when we're not in
/// the foreground — no Dart work is needed. The handler must still be
/// registered (FCM requires one to spin up the background isolate), and it
/// must never touch the service locator: that isolate has no DI, no providers,
/// no router.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) async {}

/// The only place that talks to `firebase_messaging` +
/// `flutter_local_notifications`. It owns the plumbing; every decision
/// ("where does this tap go?") belongs to [PushMessageHandler], which is
/// Firebase-free and unit-tested.
///
/// NO TEST MAY IMPORT THIS FILE — it reaches `FirebaseMessaging.instance`,
/// which needs a native Firebase app.
///
/// Design: docs/design/push-notifications-app.md.
class FcmMessageBridge {
  FcmMessageBridge(this._handler, {FlutterLocalNotificationsPlugin? local})
      : _local = local ?? FlutterLocalNotificationsPlugin();

  final PushMessageHandler _handler;
  final FlutterLocalNotificationsPlugin _local;

  /// Wires the four ways a push can reach the user. Best-effort: a failure
  /// here degrades push, it never breaks the app.
  Future<void> init() async {
    try {
      FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);

      await _initLocalNotifications();

      // FOREGROUND. Android shows nothing for a `notification` payload while
      // the app is in front, so we draw it ourselves in the same channel the
      // backend stamps. iOS can present it natively instead.
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } else {
        FirebaseMessaging.onMessage.listen(_showForeground);
      }

      // BACKGROUND tap (the app was alive behind the notification).
      FirebaseMessaging.onMessageOpenedApp.listen(
        (m) => _handler.handleData(m.data),
      );

      // COLD-START tap (the notification LAUNCHED the app). The session isn't
      // restored yet — the handler buffers this and replays it on auth.
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) await _handler.handleData(initial.data);
    } catch (e, s) {
      AppLogger.error('Push: bridge init failed', error: e, stackTrace: s);
    }
  }

  Future<void> _initLocalNotifications() async {
    await _local.initialize(
      settings: const InitializationSettings(
        // The status-bar icon (a flat white glyph — Android masks it).
        android: AndroidInitializationSettings('ic_stat_myweli'),
        // firebase_messaging owns the permission prompt; never double-ask.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onLocalTap,
    );

    // The channel the BACKEND stamps on every message
    // (FcmV1PushProvider.androidChannelId). Creating it here is what gives it
    // a name and a high importance in the OS settings — without it, Android
    // files our notifications under an unnamed default channel.
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            kPushChannelId,
            kPushChannelName,
            description: kPushChannelDescription,
            importance: Importance.high,
          ),
        );
  }

  /// Draw a foreground push, carrying its data so a tap routes identically to
  /// a background tap.
  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    try {
      await _local.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            kPushChannelId,
            kPushChannelName,
            channelDescription: kPushChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: 'ic_stat_myweli',
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (e, s) {
      AppLogger.error('Push: foreground display failed',
          error: e, stackTrace: s);
    }
  }

  void _onLocalTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _handler.handleData(data);
    } catch (e, s) {
      AppLogger.error('Push: bad local payload', error: e, stackTrace: s);
    }
  }
}
