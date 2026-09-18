import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:chatcore/chat-core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/account_path_manager.dart';
import 'package:ox_common/push/push_notification_manager.dart';
import 'package:ox_common/scheme/scheme_helper.dart';
import 'package:ox_common/utils/chat_prompt_tone.dart';
import 'package:ox_common/utils/error_utils.dart';
import 'package:ox_common/utils/font_size_notifier.dart';
import 'package:ox_common/utils/storage_key_tool.dart';
import 'package:ox_common/utils/user_config_tool.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/ox_userinfo_manager.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/ox_common.dart';
import 'package:ox_common/utils/nip46_status_notifier.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_chat_project/multi_route_utils.dart';
import 'package:ox_theme/ox_theme.dart';

import 'app_initializer.dart';

const MethodChannel navigatorChannel = const MethodChannel('NativeNavigator');

void main() async {
  runZonedGuarded(() async {
    await AppInitializer.shared.initialize();
    runApp(
      MainApp(window.defaultRouteName),
    );
  }, (error, stackTrace) async {
    try {
      bool openDevLog = UserConfigTool.getSetting(
          StorageSettingKey.KEY_OPEN_DEV_LOG.name,
          defaultValue: false);
      if (openDevLog) {
        ErrorUtils.logErrorToFile(
            error.toString() + '\n' + stackTrace.toString());
      }
      print(error);
      print(stackTrace);
    } catch (e, stack) {
      if (kDebugMode) {
        print(e);
        print(stack);
      }
    }
  });
}

class MainApp extends StatefulWidget {
  final String routeName;

  MainApp(this.routeName,);

  @override
  State<StatefulWidget> createState() {
    return MainState();
  }
}

class MainState extends State<MainApp>
    with WidgetsBindingObserver, OXUserInfoObserver {
  late StreamSubscription wsSwitchStateListener;
  StreamSubscription? cacheTimeEventListener;
  int lastUserInteractionTime = 0;
  Timer? timer;

  List<OXErrorInfo> initializeErrors = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Localized.addLocaleChangedCallback(onLocaleChange);
    OXUserInfoManager.sharedInstance.addObserver(this);
    if (LoginManager.instance.isLoginCircle) {
      notNetworInitWow();
    }
    timer = Timer.periodic(Duration(seconds: 5), (Timer t) {
      printMemoryUsage();
    });
    showErrorDialogIfNeeded();

    if (!Adapt.isInitialized) {
      Adapt.init();
    }
    nip46ConnectStatusInit();

    ThemeManager.addOnThemeChangedCallback(() => setState(() {}));
    
    // Handle Universal Links on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SchemeHelper.tryHandlerForOpenAppScheme();
    });
  }

  void showErrorDialogIfNeeded() async {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await Future.delayed(Duration(seconds: 5));
    final entries = [...AppInitializer.shared.initializeErrors];
    for (var entry in entries) {
      showDialog(
        context: OXNavigator.navigatorKey.currentContext!,
        builder: (context) {
          return AlertDialog(
            title: Text(entry.error.toString()),
            content: SingleChildScrollView(child: Text(entry.stack.toString())),
            actions: <Widget>[
              TextButton(
                child: Text(Localized.text('ox_common.ok')),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  void notNetworInitWow() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setBool('isGuestLogin', false);
  }

  @override
  void didChangePlatformBrightness() {
    final style = themeManager.themeStyle;
    if (style != ThemeStyle.system) return;

    ThemeManager.changeTheme(ThemeStyle.system);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!Adapt.isInitialized) {
      Adapt.init();
      setState(() {});
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    timer = null;
    super.dispose();
    OXUserInfoManager.sharedInstance.removeObserver(this);
    WidgetsBinding.instance.removeObserver(this);
    wsSwitchStateListener.cancel();
    AccountPathManager.clearAllTempFolders();
  }

  onLocaleChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CLApp(
      key: UniqueKey(),
      navigatorKey: OXNavigator.navigatorKey,
      navigatorObservers: [OXNavigator.routeObserver],
      themeMode: ThemeManager.themeMode,
      themeData: CLThemeData.fromSeed(null),
      home: WillPopScope(
        child: MultiRouteUtils.widgetForRoute(
          // If routeName is a URL scheme, use default route instead
          widget.routeName.startsWith('xchat://') || widget.routeName.startsWith('https://') 
              ? '/' 
              : widget.routeName,
          context
        ),
        onWillPop: () async {
          if (Platform.isAndroid) {
            OXCommon.backToDesktop();
          }
          return Future.value(false);
        },
      ),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        CupertinoLocalizationsDelegate()
      ],
      supportedLocales: Localized.supportedLocales(),
      locale: Localized.getCurrentLanguage().asLocale,
      builder: (BuildContext context, Widget? child) {
        return OXLoading.init()(
          context,
          ValueListenableBuilder<double>(
            valueListenable: textScaleFactorNotifier,
            builder: (context, scaleFactor, child) {
              return Directionality(
                textDirection: Localized.getTextDirectionForLang(),
                child: MediaQuery(
                  ///Text size does not change with system Settings
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scaleFactor)),
                  child: child!,
                ),
              );
            },
            child: child,
          ),
        );
      },
    );
  }

  @override
  void didLoginSuccess(UserDBISAR? userInfo) {}

  @override
  void didLogout() {}

  @override
  void didSwitchUser(UserDBISAR? userInfo) {}

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    LogUtil.log(key: 'didChangeAppLifecycleState', content: state.toString());
    switch (state) {
      case AppLifecycleState.resumed:
        PromptToneManager.sharedInstance.isAppPaused = false;
        // Ahead of the circle check, because an invite link is the one thing
        // that can put someone into a circle: gating it on already being in
        // one meant tapping an invite did nothing at all for exactly the
        // people it is meant for. Still gated on having an account, since the
        // native side clears the pending URL as it hands it over — reading it
        // while signed out would discard the invite rather than defer it.
        if (LoginManager.instance.currentState.account != null) {
          SchemeHelper.tryHandlerForOpenAppScheme();
        }
        if (!LoginManager.instance.isLoginCircle) return;
        keepHeartBeat();
        CLUserPushNotificationManager.instance.updatePushTokenIfNeeded();
        // For handling notification permission being granted
        CLUserPushNotificationManager.instance.checkAndUpdatePermissionStatus();
        break;
      case AppLifecycleState.paused:
        PromptToneManager.sharedInstance.isAppPaused = true;
        if (!LoginManager.instance.isLoginCircle) return;
        lastUserInteractionTime = DateTime.now().millisecondsSinceEpoch;
        break;
      default:
        break;
    }
  }

  Future<void> keepHeartBeat() async {
    if (!LoginManager.instance.isLoginCircle) return;

    await ThreadPoolManager.sharedInstance.initialize();
    Connect.sharedInstance.checkAndReconnectIfNeeded();
    Account.sharedInstance.startHeartBeat();
  }

  void printMemoryUsage() {
    final memoryUsage = ProcessInfo.currentRss;
    // print('Current RSS memory usage: ${memoryUsage / (1024 * 1024)} MB');
    // print('Max RSS memory usage: ${ProcessInfo.maxRss / (1024 * 1024)} MB');
  }

  void nip46ConnectStatusInit() {
    Future.delayed(const Duration(seconds: 3), () {
      Account.sharedInstance.nip46connectionStatusCallback =
          (status) => _nip46connectionStatusCallback(status);
    });
  }

  void _nip46connectionStatusCallback(NIP46ConnectionStatus status) {
    UserDBISAR? user = Account.sharedInstance.me;
    if (user == null) return;
    NIP46StatusNotifier.sharedInstance.notify(status, user);
  }
}