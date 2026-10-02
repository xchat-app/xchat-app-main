// local_push_kit.dart
//
// Minimal, version-pinned local notifications helper for Flutter.
// Compatible with:
//   - flutter_local_notifications: ^19.4.0
//   - timezone: ^0.10.1
//
// Notes for iOS:
// - Foreground presentation uses Darwin defaults (alert/sound/badge shown).
// - If you need custom categories or advanced foreground handling, set the
//   UNUserNotificationCenter delegate in AppDelegate.
//
// Notes for timezone:
// - tz.initializeTimeZones() is called here.
// - If you need the device's real IANA zone (not UTC), call setLocalLocation()
//   with a valid IANA name after initialization (e.g. using a platform plugin).

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz; // timezone: 0.10.1
import 'package:timezone/timezone.dart' as tz;

class LocalPushKit {
  LocalPushKit._();
  static final LocalPushKit instance = LocalPushKit._();

  final FlutterLocalNotificationsPlugin _plugin =
  FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  AndroidNotificationChannel? _defaultAndroidChannel;

  /// Initialize plugin, timezone DB, and create a default Android channel.
  /// Call once during app startup (e.g. before showing notifications).
  Future<void> ensureInitialized({
    String androidDefaultIcon = '@mipmap/ic_launcher',
    String androidChannelId = 'message_channel',
    String androidChannelName = 'Messages',
    String androidChannelDescription = 'General message notifications',
    bool requestIosPermissionsAtInit = false,
    bool requestAndroidPermissionsAtInit = true,
    DidReceiveNotificationResponseCallback? onTap,
    DidReceiveBackgroundNotificationResponseCallback? onBackgroundTap,
  }) async {
    if (_initialized) return;

    // Timezone DB (default variant). tz.local defaults to UTC unless you set it.
    tz.initializeTimeZones();

    const darwin = DarwinInitializationSettings(
      // Set these flags only if you want to ask at init. You can also call
      // requestPermission() later to ask on-demand.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final android = AndroidInitializationSettings(androidDefaultIcon);

    final initSettings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: onTap,
      onDidReceiveBackgroundNotificationResponse: onBackgroundTap,
    );

    // Optionally request permissions up-front.
    if (requestAndroidPermissionsAtInit && Platform.isAndroid) {
      await requestPermission();
    }
    if (requestIosPermissionsAtInit &&
        (Platform.isIOS || Platform.isMacOS)) {
      await requestPermission(alert: true, sound: true, badge: true);
    }

    // Default Android channel for "message" style notifications.
    if (Platform.isAndroid) {
      _defaultAndroidChannel = AndroidNotificationChannel(
        androidChannelId,
        androidChannelName,
        description: androidChannelDescription,
        importance: Importance.high,
      );

      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_defaultAndroidChannel!);
    }

    _initialized = true;
  }

  /// Optional: set tz local location using a valid IANA name (e.g. "Asia/Shanghai").
  /// Call after ensureInitialized() if you need local-time scheduling.
  void setLocalTimeZone(String ianaName) {
    try {
      final loc = tz.getLocation(ianaName);
      tz.setLocalLocation(loc);
    } catch (e) {
      if (kDebugMode) {
        // Fallback remains whatever tz.local currently is.
        // Make sure you pass TZDateTime in the desired zone when scheduling.
        // ignore: avoid_print
        print('LocalPushKit: invalid IANA name "$ianaName": $e');
      }
    }
  }

  /// Request notification permissions on the current platform.
  Future<bool> requestPermission({
    bool alert = true,
    bool sound = true,
    bool badge = true,
    bool critical = false,
  }) async {
    if (Platform.isIOS) {
      final iosImpl = _plugin
          .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await iosImpl?.requestPermissions(
        alert: alert,
        sound: sound,
        badge: badge,
        critical: critical,
      ) ??
          false;
      return granted;
    } else if (Platform.isMacOS) {
      final macImpl = _plugin
          .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin>();
      final granted = await macImpl?.requestPermissions(
        alert: alert,
        sound: sound,
        badge: badge,
        critical: critical,
      ) ??
          false;
      return granted;
    } else if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      // Android 13+ will show a prompt; older versions return "true".
      return await androidImpl?.requestNotificationsPermission() ?? true;
    }
    return true;
  }

  /// Check if system notifications are enabled (best-effort).
  Future<bool> areNotificationsEnabled() async {
    // The cross-platform API doesn't expose a single method; use platform impls.
    if (Platform.isAndroid) {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await androidImpl?.areNotificationsEnabled() ?? true;
    }
    if (Platform.isIOS || Platform.isMacOS) {
      // On Apple platforms you typically check specific settings via platform
      // APIs. Here we assume enabled if plugin can deliver; refine if needed.
      return true;
    }
    return true;
  }

  /// Show an immediate notification.
  Future<void> showInstant({
    required int id,
    required String title,
    required String body,
    String? payload,
    String? androidGroupKey,
    String? iOSThreadId,
    String? channelId,
    String? channelName,
    String? channelDescription,
    bool high = true,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId ?? (_defaultAndroidChannel?.id ?? 'message_channel'),
      channelName ?? (_defaultAndroidChannel?.name ?? 'Messages'),
      channelDescription:
      channelDescription ?? _defaultAndroidChannel?.description,
      importance:
          high ? Importance.high : Importance.defaultImportance,
      priority: high ? Priority.high : Priority.defaultPriority,
      groupKey: androidGroupKey,
      styleInformation: const DefaultStyleInformation(true, true),
      // Mark it sensitive so a lock screen set to hide sensitive content
      // hides the sender and the message.
      visibility: NotificationVisibility.private,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: false,
      threadIdentifier: iOSThreadId,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Show/update an Android group summary notification.
  Future<void> showAndroidGroupedSummary({
    required int id,
    required String groupKey,
    required String summaryTitle,
    required String summaryText,
    String? channelId,
    String? channelName,
    String? channelDescription,
  }) async {
    final inbox = InboxStyleInformation(
      const <String>[],
      contentTitle: summaryTitle,
      summaryText: summaryText,
    );

    final androidDetails = AndroidNotificationDetails(
      channelId ?? (_defaultAndroidChannel?.id ?? 'message_channel'),
      channelName ?? (_defaultAndroidChannel?.name ?? 'Messages'),
      channelDescription:
      channelDescription ?? _defaultAndroidChannel?.description,
      styleInformation: inbox,
      groupKey: groupKey,
      setAsGroupSummary: true,
      importance: Importance.high,
      priority: Priority.high,
    );

    await _plugin.show(
      id,
      summaryTitle,
      summaryText,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Schedule a one-shot notification at a specific TZ date/time.
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    String? payload,
    String? androidGroupKey,
    String? iOSThreadId,
    AndroidScheduleMode androidScheduleMode =
        AndroidScheduleMode.exactAllowWhileIdle,
    DateTimeComponents? matchDateTimeComponents, // set for repeating patterns
  }) async {
    final android = AndroidNotificationDetails(
      _defaultAndroidChannel?.id ?? 'message_channel',
      _defaultAndroidChannel?.name ?? 'Messages',
      channelDescription: _defaultAndroidChannel?.description,
      importance: Importance.high,
      priority: Priority.high,
      groupKey: androidGroupKey,
    );

    final darwin =
    DarwinNotificationDetails(threadIdentifier: iOSThreadId, presentAlert: true, presentSound: true, presentBadge: false);

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduledDate,
      NotificationDetails(android: android, iOS: darwin, macOS: darwin),
      androidScheduleMode: androidScheduleMode,
      payload: payload,
      matchDateTimeComponents: matchDateTimeComponents,
    );
  }

  /// Cancel a single notification.
  Future<void> cancel(int id) => _plugin.cancel(id);

  /// Cancel all notifications.
  Future<void> cancelAll() => _plugin.cancelAll();

  /// Cancel the app's notifications except the ones that belong to a call
  /// (the ringing notification of an incoming call and the ongoing call's,
  /// both posted natively) and the push service's own. Opening the app used
  /// to clear everything, which stopped a call ringing before its page was up.
  Future<void> cancelAllExceptCalls() async {
    if (!Platform.isAndroid) return cancelAll();
    const keep = {'IncomingCallChannel', 'OngoingCallChannel', 'PushNotificationServiceChannel'};
    for (final notification in await _plugin.getActiveNotifications()) {
      final id = notification.id;
      if (id == null || keep.contains(notification.channelId)) continue;
      await _plugin.cancel(id, tag: notification.tag);
    }
  }

  /// Cancel all pending (scheduled) notifications.
  Future<void> cancelAllPending() => _plugin.cancelAllPendingNotifications();

  /// List pending (scheduled) notifications.
  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  /// Get details about whether the app was launched via a notification.
  Future<NotificationAppLaunchDetails?> getLaunchDetails() =>
      _plugin.getNotificationAppLaunchDetails();
}