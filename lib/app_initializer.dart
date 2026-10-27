import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ox_chat/ox_chat.dart';
import 'package:ox_chat_ui/ox_chat_ui.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/desktop/window_manager.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_common/network/http_overrides.dart';
import 'package:ox_common/network/tor_network_helper.dart';
import 'package:ox_common/ox_common.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/account_path_manager.dart';
import 'package:ox_common/store_shots/store_shots_flag.dart';
import 'package:ox_common/utils/error_utils.dart';
import 'package:ox_common/utils/font_size_notifier.dart';
import 'package:ox_common/utils/storage_key_tool.dart';
import 'package:ox_common/utils/user_config_tool.dart';
import 'package:ox_cache_manager/ox_cache_manager.dart';
import 'package:ox_home/ox_home.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_login/ox_login.dart';
import 'package:ox_theme/ox_theme.dart';
import 'package:ox_usercenter/ox_usercenter.dart';
import 'package:ox_usercenter/utils/app_config_helper.dart';
import 'package:ox_call/ox_call.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nostr_mls_package/nostr_mls_package.dart';
import 'main.reflectable.dart';
import 'store_shots.dart';

class OXErrorInfo {
  OXErrorInfo(this.error, this.stack);
  Object error;
  StackTrace stack;
}

class AppInitializer {
  static final AppInitializer shared = AppInitializer();
  List<OXErrorInfo> initializeErrors = [];
  
  // Track initialization status
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  OXWindowManager windowManager = OXWindowManager();

  Future initialize() async {
    await _safeHandle(() async {
      try {
        await coreInitializer();
        await Future.wait([
          uiInitializer(),
          businessInitializer(),
        ]);
        await userInitializer();
        if (kDebugMode) {
          getApplicationDocumentsDirectory().then((value) {
            LogUtil.d('[App start] Application Documents Path: $value');
          });
        }
        _isInitialized = true;
      } catch (error, stack) {
        initializeErrors.add(OXErrorInfo(error, stack));
        _isInitialized = false;
      }
    });
  }

  Future coreInitializer() async {
    initializeReflectable();
    await RustLib.init();
    improveOnErrorHandler();
    improveErrorWidget();
  }

  Future businessInitializer() async {
    await Future.wait([
      ThemeManager.init(),
      Localized.init(),
    ]);
    await _setupModules();

    HttpOverrides.global = OXHttpOverrides()
      ..torUsageResolver = () => AppConfigHelper.useTorNetworkNotifier().value;

    AppConfigHelper.preloadAdvancedSettings().then((_) {
      if (AppConfigHelper.useTorNetworkNotifier().value) {
        TorNetworkHelper.initialize();
      }
    });

    ThemeManager.addOnThemeChangedCallback(onThemeStyleChange);
  }

  /// User-level initialization including auto login
  Future userInitializer() async {
    // Play screenshots: a made-up local account instead (lib/store_shots.dart).
    if (kStoreShots) return StoreShots.start();
    await _tryAutoLogin();
    _cleanupTempFolders();
  }

  /// Try auto login using LoginManager
  Future<void> _tryAutoLogin() async {
    try {
      await LoginManager.instance.autoLogin();
    } catch (e) {
      debugPrint('Auto login failed: $e');
      // Continue to app, which will show login page if needed
    }
  }

  Future uiInitializer() async {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.initWindow();
    PlatformStyle.initialized();
    double fontSize = await OXCacheManager.defaultOXCacheManager.getForeverData(
      StorageKeyTool.APP_FONT_SIZE,
      defaultValue: 1.0,
    );
    textScaleFactorNotifier.value = fontSize;
  }

  onThemeStyleChange() async {
    print("******  changeTheme int ${ThemeManager.getCurrentThemeStyle().name}");
  }

  Future<void> _setupModules() async {
    await Future.wait([
      OXCommon().setup(),
      OXLoginModuleService().setup(),
      OXUserCenter().setup(),
      OXChat().setup(),
      OXChatUI().setup(),
      OxChatHome().setup(),
      OXCall().setup(),
    ]);
  }

  Future _safeHandle(Function fn) async {
    try {
      await fn();
    } catch (e, stack) {
      if (kDebugMode) {
        print(e);
        print(stack);
        rethrow;
      }
    }
  }

  void improveOnErrorHandler() {
    FlutterError.onError = (FlutterErrorDetails details) async {
      bool openDevLog = UserConfigTool.getSetting(StorageSettingKey.KEY_OPEN_DEV_LOG.name,
          defaultValue: false);
      if (openDevLog || kDebugMode) {
        FlutterError.presentError(details);
        ErrorUtils.logErrorToFile(details.toString() + '\n' + details.stack.toString());
      }
    };
  }

  void improveErrorWidget() {
    final originErrorWidgetBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        return ConstrainedBox(
          constraints: BoxConstraints.loose(Size.square(300)),
          child: originErrorWidgetBuilder(details),
        );
      } else {
        return SizedBox();
      }
    };
  }

  /// Clean up temp folders on app startup
  Future<void> _cleanupTempFolders() async {
    try {
      final deletedCount = await AccountPathManager.clearAllTempFolders();
      LogUtil.d('Cleaned up $deletedCount temp files on app startup');
    } catch (e) {
      LogUtil.e('Error cleaning up temp folders on app startup: $e');
    }
  }
}