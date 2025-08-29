import 'package:flutter/material.dart';
import 'package:ox_common/push/core/local_push_kit.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:chatcore/chat-core.dart';

import 'push_integration.dart';

class CLPushNotificationManager {
  static final CLPushNotificationManager instance = CLPushNotificationManager._internal();
  CLPushNotificationManager._internal();

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
    await _syncToNotificationHelper();

    if (!_isConfigurationInitialized(circle)) {
      await _initializeDefaultConfiguration(circle);
    }

    await checkAndUpdatePermissionStatus();
  }

  Future<void> setAllowSendNotification(bool value) async {
    if (_allowSendNotificationNotifier.value == value) return;

    final currentState = LoginManager.instance.currentState;
    final circle = currentState.currentCircle;
    if (circle == null) return;

    await circle.updateAllowSendNotification(value);

    _allowSendNotificationNotifier.value = value;
    
    await _syncToNotificationHelper();
  }

  Future<bool> setAllowReceiveNotification(bool value) async {
    if (_allowReceiveNotificationNotifier.value == value) return true;

    final currentState = LoginManager.instance.currentState;
    final circle = currentState.currentCircle;
    if (circle == null) return false;

    if (value) {
      // Check push permission
      final hasPermission = await _checkNativePushPermission();
      if (!hasPermission) {
        _showPermissionDialog().then((shouldGoToSettings) {
          if (shouldGoToSettings) {
            openAppSettings();
          }
        });
        return true;
      }
      
      final success = await _uploadPushToken();
      if (!success) {
        return false;
      }
    }
    else{
      await LoginManager.instance.saveUploadPushTokenState(false);
    }

    await circle.updateAllowReceiveNotification(value);

    _allowReceiveNotificationNotifier.value = value;
    
    await _syncToNotificationHelper();

    return true;
  }

  Future<void> checkAndUpdatePermissionStatus() async {
    if (!_allowReceiveNotificationNotifier.value) return;

    final hasPermission = await _checkNativePushPermission();
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

  Future<void> _initializeDefaultConfiguration(Circle circle) async {
    final hasPermission = await _checkNativePushPermission();
    await setAllowSendNotification(hasPermission);
    await setAllowReceiveNotification(hasPermission).then((isSuccess) {
      if (!isSuccess) setAllowReceiveNotification(false);
    });
  }

  Future<bool> _checkNativePushPermission() async {
    return LocalPushKit.instance.requestPermission();
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

  Future<bool> _uploadPushToken() async {
    final currentState = LoginManager.instance.currentState;
    final account = currentState.account;
    final pushToken = account?.pushToken;
    if (account == null) return false;
    if (pushToken == null || pushToken.isEmpty) return false;
    if (account.hasUpload == true) return true;

    return CLPushIntegration.instance.uploadPushToken(pushToken)
        .timeout(Duration(seconds: 3), onTimeout: () => false);
  }
  
  Future<void> _syncToNotificationHelper() async {
    try {
      final notificationHelper = NotificationHelper.sharedInstance;
      await notificationHelper.setAllowSendNotification(_allowSendNotificationNotifier.value);
      await notificationHelper.setAllowReceiveNotification(_allowReceiveNotificationNotifier.value);
    } catch (e) {
      debugPrint('Failed to sync to NotificationHelper: $e');
    }
  }

  void dispose() {
    _allowSendNotificationNotifier.dispose();
    _allowReceiveNotificationNotifier.dispose();
  }
}
