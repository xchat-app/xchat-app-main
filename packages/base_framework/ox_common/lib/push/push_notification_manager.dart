import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ox_common/push/core/local_push_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/log_util.dart';

import 'push_integration.dart';

class CLUserPushNotificationManager implements PushPermissionChecker {
  static final CLUserPushNotificationManager instance = CLUserPushNotificationManager._internal();
  static const MethodChannel _authChannel = MethodChannel('com.oxchat.global/perferences');
  Timer? _authCheckTimer;
  
  CLUserPushNotificationManager._internal() {
    NotificationHelper.sharedInstance.permissionChecker = this;
    _setupAuthHandler();
    _startAuthCheckTimer();
  }

  void _setupAuthHandler() {
    // Listen for AUTH requests from Android push service
    _authChannel.setMethodCallHandler((call) async {
      if (call.method == 'requestAuthJson') {
        final challenge = call.arguments['challenge'] as String?;
        final relay = call.arguments['relay'] as String?;
        
        if (challenge != null && relay != null) {
          try {
            final authJson = await NotificationHelper.generateAuthJson(challenge, relay);
            if (authJson.isNotEmpty) {
              // Send authJson back to Android service
              await _authChannel.invokeMethod('sendAuthResponse', {
                'authJson': authJson,
              });
            }
          } catch (e) {
            print('Error generating authJson: $e');
          }
        }
      }
      return null;
    });
  }

  final ValueNotifier<bool> _allowSendNotificationNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _allowReceiveNotificationNotifier = ValueNotifier<bool>(false);

  ValueNotifier<bool> get allowSendNotificationNotifier => _allowSendNotificationNotifier;
  ValueNotifier<bool> get allowReceiveNotificationNotifier => _allowReceiveNotificationNotifier;

  bool get allowSendNotification => _allowSendNotificationNotifier.value;
  bool get allowReceiveNotification => _allowReceiveNotificationNotifier.value;

  Future<void> initialize() async {
    final currentState = LoginManager.instance.currentState;
    final circle = currentState.currentCircle;

    if (circle == null) return;

    await _loadConfiguration(circle);

    final token = await updatePushTokenIfNeeded();

    if (!_isConfigurationInitialized(circle)) {
      final hasPermission = await LocalPushKit.instance.requestPermission();
      _initializeDefaultConfiguration(hasPermission, token);
      return;
    }

    await checkAndUpdatePermissionStatus();
    
    // Check for pending AUTH challenges from Android push service
    if (Platform.isAndroid) {
      _checkPendingAuth();
      await _ensureAndroidPushServiceStarted();
    }
  }

  Future<void> _ensureAndroidPushServiceStarted() async {
    if (!Platform.isAndroid || !allowReceiveNotification) return;

    final currentState = LoginManager.instance.currentState;
    final account = currentState.account;
    if (account == null || account.pubkey.isEmpty) return;

    final serverRelay = NotificationHelper.sharedInstance.serverRelay;
    if (serverRelay.isEmpty) return;

    try {
      final event = await NotificationHelper.sharedInstance
          .updateNotificationDeviceId(account.pubkey);
      if (!event.status) {
      LogUtil.e('ensurePushService update device failed: ${event.message}');
        return;
      }

      // Get private key from Account
      final privkey = Account.sharedInstance.currentPrivkey;
      if (privkey.isEmpty) {
        LogUtil.e('ensurePushService: Private key not available');
        return;
      }

      const MethodChannel channel = MethodChannel('com.oxchat.global/perferences');
      await channel.invokeMethod('startPushNotificationService', {
        'serverRelay': serverRelay,
        'pubkey': account.pubkey,
        'privkey': privkey,
      });
    } catch (e) {
      LogUtil.e('ensurePushService failed to start service: $e');
    }
  }

  // Start timer to periodically check for pending AUTH challenges
  void _startAuthCheckTimer() {
    if (Platform.isAndroid) {
      _authCheckTimer?.cancel();
      _authCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        _checkPendingAuth();
      });
    }
  }

  // Check for pending AUTH challenges and process them
  Future<void> _checkPendingAuth() async {
    try {
      final result = await _authChannel.invokeMethod('getPendingAuthChallenge');
      if (result != null && result is Map) {
        final challenge = result['challenge'] as String?;
        final relay = result['relay'] as String?;
        
        if (challenge != null && relay != null && challenge.isNotEmpty) {
          try {
            final authJson = await NotificationHelper.generateAuthJson(challenge, relay);
            if (authJson.isNotEmpty) {
              await _authChannel.invokeMethod('sendAuthResponse', {
                'authJson': authJson,
              });
              // Clear the pending challenge
              await _authChannel.invokeMethod('clearPendingAuthChallenge');
            }
          } catch (e) {
            print('Error generating authJson: $e');
          }
        }
      }
    } catch (e) {
      // No pending challenge or error
    }
  }

  Future<String?> updatePushTokenIfNeeded() async {
    // For Android, skip getting pushToken
    if (Platform.isAndroid) {
      return null;
    }

    final account = LoginManager.instance.currentState.account;
    if (account == null) return null;
    return CLPushIntegration.instance
        .registerNotification()
        .then((token) {
      if (token.isEmpty) return null;
      if (account.pubkey != LoginManager.instance.currentState.account?.pubkey) return null;

      LoginManager.instance.savePushToken(token);
      if (allowReceiveNotification) {
        NotificationHelper.sharedInstance.updateNotificationDeviceId(token);
      }
      return token;
    });
  }

  Future<void> setAllowSendNotification(bool value) async {
    if (_allowSendNotificationNotifier.value == value) return;

    final currentState = LoginManager.instance.currentState;
    final circle = currentState.currentCircle;
    if (circle == null) return;

    circle.updateAllowSendNotification(value);

    _allowSendNotificationNotifier.value = value;
  }

  // Return error message
  Future<String?> setAllowReceiveNotification(bool value, [String? pushToken, bool? hasPermission]) async {
    if (_allowReceiveNotificationNotifier.value == value) return null;

    final currentState = LoginManager.instance.currentState;
    final circle = currentState.currentCircle;
    if (circle == null) return Localized.text('ox_common.logged_circle_not_found');

    if (value) {
      // Check push permission
      hasPermission ??= await LocalPushKit.instance.requestPermission();
      if (!hasPermission) {
        _showPermissionDialog().then((shouldGoToSettings) {
          if (shouldGoToSettings) {
            openAppSettings();
          }
        });
        return null;
      }

      // For Android, use pubkey as deviceId and register on server before starting service
      if (Platform.isAndroid) {
        final account = currentState.account;
        if (account == null || account.pubkey.isEmpty) {
          return Localized.text('ox_common.account_not_found');
        }

        final serverRelay = NotificationHelper.sharedInstance.serverRelay;
        if (serverRelay.isEmpty) {
          return 'Server relay not configured';
        }

        try {
          final event = await NotificationHelper.sharedInstance
              .updateNotificationDeviceId(account.pubkey);
          if (!event.status) {
            return event.message;
          }

          // Get private key from Account
          final privkey = Account.sharedInstance.currentPrivkey;
          if (privkey.isEmpty) {
            return 'Private key not available';
          }

          const MethodChannel channel = MethodChannel('com.oxchat.global/perferences');
          await channel.invokeMethod('startPushNotificationService', {
            'serverRelay': serverRelay,
            'pubkey': account.pubkey,
            'privkey': privkey,
          });
        } catch (e) {
          return 'Failed to start push service: $e';
        }
      } else {
        // For iOS, use the original flow with pushToken
        pushToken ??= currentState.account?.pushToken;
        if (pushToken == null || pushToken.isEmpty) {
          // Try to register pushToken again
          pushToken = await CLPushIntegration.instance
              .registerNotification()
              .timeout(Duration(seconds: 15), onTimeout: () => '')
              .then((token) {
            if (token.isEmpty) return '';
            LoginManager.instance.savePushToken(token);
            return token;
          });
          if (pushToken == null || pushToken.isEmpty) {
            return Localized.text('ox_common.push_token_is_null');
          }
        }

        final event = await NotificationHelper.sharedInstance.updateNotificationDeviceId(pushToken);
        if (!event.status) {
          return event.message;
        }
      }
    } else {
      // Stop push service for Android
      if (Platform.isAndroid) {
        try {
          const MethodChannel channel = MethodChannel('com.oxchat.global/perferences');
          await channel.invokeMethod('stopPushNotificationService');
        } catch (e) {
          // Ignore errors when stopping service
        }

        final event = await NotificationHelper.sharedInstance.removeNotification();
        if (!event.status) {
          return event.message;
        }
      } else {
        final event = await NotificationHelper.sharedInstance.removeNotification();
        if (!event.status) {
          return event.message;
        }
      }
    }

    circle.updateAllowReceiveNotification(value);

    _allowReceiveNotificationNotifier.value = value;

    return null;
  }

  Future<void> checkAndUpdatePermissionStatus() async {
    if (!allowReceiveNotification) return;

    final hasPermission = await LocalPushKit.instance.requestPermission();
    if (!hasPermission) {
      await setAllowReceiveNotification(false);
    }
  }

  Future<void> _loadConfiguration(Circle circle) async {
    _allowSendNotificationNotifier.value = circle.allowSendNotification;
    _allowReceiveNotificationNotifier.value = circle.allowReceiveNotification;
  }

  bool _isConfigurationInitialized(Circle circle) {
    return circle.isNotificationSettingsInitialized;
  }

  Future<void> _initializeDefaultConfiguration(bool hasPermission, String? token) async {
    await setAllowSendNotification(true);
    await setAllowReceiveNotification(hasPermission, token, hasPermission).then((err) {
      if (err != null) setAllowReceiveNotification(false);
    });
  }

  Future<bool> _showPermissionDialog() async {
    final context = OXNavigator.navigatorKey.currentContext;
    if (context == null) return false;

    final result = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_common.tips'),
      content: Localized.text('ox_common.push_permission_required_hint'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.str_go_to_settings'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    );
    
    return result ?? false;
  }

  @override
  Future<bool> canReceiveNotification() async => allowReceiveNotification;

  @override
  Future<bool> canSendNotification() async => allowSendNotification;
}
