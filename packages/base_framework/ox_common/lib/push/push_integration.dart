import 'dart:async';
import 'dart:io';

import 'package:chatcore/chat-core.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/ox_common.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';

import 'decision_service.dart';
import 'core/local_notifier.dart';
import 'core/local_push_kit.dart';
import 'core/message_models.dart';
import 'core/policy_config.dart';
import 'core/ports.dart';

/// Wires LocalPushKit + Notifier + DecisionService into app lifecycle and message bus.
class CLPushIntegration with WidgetsBindingObserver {
  static final CLPushIntegration instance = CLPushIntegration._();
  CLPushIntegration._();

  late final Notifier _notifier;
  late final NotificationDecisionService _decision;
  bool _initialized = false;
  
  // Device-level push token storage
  static const String _devicePushTokenKey = 'device_push_token';
  
  /// Get device-level push token from local storage
  Future<String?> get devicePushToken async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_devicePushTokenKey);
  }
  
  /// Set device-level push token to local storage
  Future<void> setDevicePushToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_devicePushTokenKey, token);
  }
  
  /// Check if the given token matches current device push token
  Future<bool> isTokenMatchingDevice(String token) async {
    final deviceToken = await devicePushToken;
    return deviceToken != null && deviceToken == token;
  }
  
  /// Register push token handler - called when iOS native gets push token
  Future<void> registerPushTokenHandler(String token) async {
    await setDevicePushToken(token);
    
    final account = LoginManager.instance.currentState.account;
    if (account != null) {
      await LoginManager.instance.savePushToken(token);
    }

    uploadPushToken(token);
  }

  Future<void> initialize() async {
    if (_initialized) return;

    // 1) Init base kit
    await LocalPushKit.instance.ensureInitialized(
      androidDefaultIcon: '@drawable/ic_notification',
      androidChannelId: 'message_channel',
      androidChannelName: 'Messages',
      androidChannelDescription: 'General message notifications',
    );

    // 2) Notifier based on LocalPushKit
    _notifier = LocalNotifier(
      LocalPushKit.instance,
      'message_channel',
      'Messages',
      'General message notifications',
    );

    // 3) Decision service with port adapters
    _decision = NotificationDecisionService(
      state: _ForegroundStateImpl(),
      perms: _PermissionGatewayImpl(),
      mute: _MuteStoreImpl(),
      unread: _UnreadCounterImpl(),
      dedupe: _DedupeStoreImpl(),
      notifier: _notifier,
      config: const NotificationPolicyConfig(
        coalesceWindow: Duration(seconds: 1),
        previewPolicy: PreviewPolicy.summary,
      ),
    );

    // 4) Hook lifecycle & message bus
    WidgetsBinding.instance.addObserver(this);

    _initialized = true;
  }

  Future<void> initializeForRemotePush() async {
    final notificationPermission = await LocalPushKit.instance.requestPermission();
    if (!notificationPermission) return;

    final accountPushToken = LoginManager.instance.currentState.account?.pushToken;
    final isRotation = (await devicePushToken)?.isNotEmpty ?? false;

    // account push token is null or empty, registe notification
    if (accountPushToken == null || accountPushToken.isEmpty) {
      registeNotification(isRotation);
      return;
    } 
    
    // account push token is not matching device push token, registe notification
    if (!await isTokenMatchingDevice(accountPushToken)) {
      registeNotification(isRotation);
      return;
    }

    CLPushIntegration.instance.uploadPushToken(accountPushToken);
  }

  void registeNotification(bool isRotation) {
    if (Platform.isIOS) {
      OXCommon.registeNotification(isRotation: isRotation);
    } else if (Platform.isAndroid) {
      // TODO: Android implementation
    }
  }

  // Lifecycle
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // cancel any notifications
      _decision.onAppBecameForeground();
    }
  }

  void putReceiveMessage(String title, MessageDBISAR message) {
    final msg = _mapToIncomingMessage(title, message);
    if (msg != null) {
      unawaited(_decision.onMessageArrived(msg));
    }
  }

  // Map MessageDBISAR to IncomingMessage
  IncomingMessage? _mapToIncomingMessage(String title, MessageDBISAR m) {
    try {
      // Determine threadId
      String threadId = '';
      if (m.chatType == 1) {
        // group chat
        threadId = m.groupId;
      } else {
        // private or other: use the other party id
        threadId = m.sender;
      }
      if (threadId.isEmpty) return null;

      final preview = m.content;
      final high = true; // can refine based on kind/type
      final sentAt = DateTime.fromMillisecondsSinceEpoch(
        m.createTime < 1e12 ? m.createTime * 1000 : m.createTime,
      );
      return IncomingMessage(
        id: m.messageId,
        threadId: threadId,
        title: title,
        preview: preview,
        highPriority: high,
        sentAt: sentAt,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> uploadPushToken(String token) async {
    final account = LoginManager.instance.currentState.account;
    if (account?.hasUpload == true) return true;
    if (!LoginManager.instance.isLoginCircle) return false;

    OKEvent okEvent = await NotificationHelper.sharedInstance.updateNotificationDeviceId(token);
    if (okEvent.status && account != null) {
      await LoginManager.instance.saveUploadPushTokenState(true);
    }
    return okEvent.status;
  }
}

// -------- Port Implementations --------

class _ForegroundStateImpl implements ForegroundState {
  @override
  bool isAppInForeground() => false;

  @override
  bool isThreadOpen(String threadId) => false;
}

class _PermissionGatewayImpl implements PermissionGateway {
  @override
  Future<bool> notificationsAllowed() async {
    return LocalPushKit.instance.areNotificationsEnabled();
  }
}

class _MuteStoreImpl implements MuteStore {
  @override
  bool isMuted(String threadId) {
    // Try group first
    final group = Groups.sharedInstance.groups[threadId]?.value ??
        Groups.sharedInstance.myGroups[threadId]?.value;
    if (group != null) {
      return group.mute;
    }
    // Then user mute
    final user = Account.sharedInstance.userCache[threadId]?.value;
    if (user != null) {
      return user.mute ?? false;
    }
    return false;
  }
}

class _UnreadCounterImpl implements UnreadCounter {
  @override
  int unreadCount() {
    int total = 0;
    for (final s in OXChatBinding.sharedInstance.sessionList) {
      total += s.unreadCount;
    }
    return total;
  }
}

class _DedupeStoreImpl implements DedupeStore {
  final Set<String> _seen = <String>{};

  @override
  bool seen(String messageId) => _seen.contains(messageId);

  @override
  void markSeen(Iterable<String> ids) {
    _seen.addAll(ids);
  }
}


