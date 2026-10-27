// Store screenshot mode: walks the real screens for tool/store_shots/capture.sh.
//
// Only reachable from AppInitializer behind kStoreShots; a normal build drops
// it. The data comes from ox_common's store_shots_seed.dart.

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ox_call/ox_call.dart';
import 'package:ox_chat/page/session/chat_message_page.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/store_shots/store_shots_seed.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_login/page/profile_setup_page.dart';
import 'package:ox_usercenter/page/settings/circle_detail_page.dart';

class StoreShots {
  StoreShots._();

  /// In place of auto login: waits for capture.sh to push the content, plants
  /// it, then shows each screen in turn once the app is up.
  static Future<void> start() async {
    try {
      final content = await StoreShotsFiles.readContent();
      final seed = await StoreShotsSeed.plant(content);
      _walk(content, seed);
    } catch (e, stack) {
      debugPrint('[StoreShots] could not start: $e\n$stack');
    }
  }

  static Future<void> _walk(StoreShotsContent content, StoreShotsSeed seed) async {
    try {
      await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
      // The launch page fades into the home page over a second.
      await _settle(4000);

      // The family circle's chat list.
      await StoreShotsFiles.ready('circle');

      // The family group.
      ChatMessagePage.open(context: null, communityItem: seed.groupSession);
      await _settle(2500);
      await StoreShotsFiles.ready('chat');
      _pop();

      // Ringing, as an incoming call shows before it is answered. The session
      // is not CallManager's, so nothing is signalled to anyone.
      final myPubkey = LoginManager.instance.currentPubkey;
      final callerPubkey = seed.pubkeys[content.call]!;
      OXNavigator.pushPage(
        null,
        (_) => CallPage(
          session: CallSession(
            sessionId: 'store-shots',
            privateGroupId: '',
            localPubkey: myPubkey,
            remotePubkey: callerPubkey,
            participantPubkeys: [myPubkey, callerPubkey],
            callType: CallType.audio,
            direction: CallDirection.incoming,
            state: CallState.ringing,
            startTime: DateTime.now().millisecondsSinceEpoch,
          ),
        ),
        type: OXPushPageType.present,
        fullscreenDialog: true,
      );
      await _settle(2500);
      // The call page has no app bar to set the status bar, so it keeps the
      // light theme's dark icons, unreadable on its dark background.
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
      await _settle(300);
      await StoreShotsFiles.ready('call');
      _pop();

      // Sign-up's name step, filled in.
      OXNavigator.pushPage(null, (_) => ProfileSetupPage(initialFirstName: content.me));
      await _settle(2000);
      await StoreShotsFiles.ready('signup');
      _pop();

      // The paid circle's settings with its "…" menu open on "Delete Circle",
      // the same sheet the page's menu button shows.
      final circle = LoginManager.instance.currentCircle!;
      OXNavigator.pushPage(null, (_) => CircleDetailPage(circle: circle));
      await _settle(2000);
      final context = OXNavigator.rootContext;
      if (!context.mounted) return;
      CLPicker.show<int>(
        context: context,
        items: [
          CLPickerItem(
            label: Localized.text('ox_usercenter.delete_circle'),
            value: 0,
            isDestructive: true,
          ),
        ],
      );
      await _settle(1500);
      await StoreShotsFiles.ready('server');

      await StoreShotsFiles.done();
    } catch (e, stack) {
      debugPrint('[StoreShots] walk failed: $e\n$stack');
    }
  }

  static Future<void> _settle(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
    await WidgetsBinding.instance.endOfFrame;
  }

  static void _pop() {
    OXNavigator.navigatorKey.currentState?.pop();
  }
}
