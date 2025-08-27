
import 'package:flutter/widgets.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_usercenter/page/settings/single_setting_page.dart';

class NicknameSettingsPage extends StatelessWidget {
  const NicknameSettingsPage({
    super.key,
    this.previousPageTitle,
  });

  final String? previousPageTitle;

  @override
  Widget build(BuildContext context) {
    return SingleSettingPage(
      previousPageTitle: previousPageTitle,
      title: 'Nickname',
      initialValue: Account.sharedInstance.me?.name ?? '',
      saveAction: buttonHandler,
    );
  }

  void buttonHandler(BuildContext context, String value) async {
    final circleType = LoginManager.instance.currentCircle?.type;
    switch (circleType) {
      case CircleType.relay:
        updateRelayNickname(context, value);
        break;
      case CircleType.bitchat:
        updateBitchatNickname(context, value);
        break;
      default:
        assert(false, 'Error Circle Type');
    }
  }

  void updateRelayNickname(BuildContext context, String value) async {
    final user = Account.sharedInstance.me;

    if (user == null) {
      CommonToast.instance.show(context, 'Current user info is null.');
      return;
    }

    final newNickname = value;
    if (newNickname.isEmpty) {
      CommonToast.instance.show(context, Localized.text('ox_usercenter.enter_username_tips'));
      return;
    }
    if (Account.sharedInstance.me?.name == newNickname) {
      OXNavigator.pop(context);
      return;
    }

    user.name = newNickname;

    OXLoading.show();
    final newUser = await Account.sharedInstance.updateProfile(user);
    await OXLoading.dismiss();
    if (newUser == null) {
      CommonToast.instance.show(context, 'Update Nickname Failed.');
    } else {
      LoginUserNotifier.instance.name$.value = newNickname;
      OXNavigator.pop(context);
    }
  }


  void updateBitchatNickname(BuildContext context, String value) async {
    final newNickname = value;
    if (newNickname.isEmpty) {
      CommonToast.instance.show(context, Localized.text('ox_usercenter.enter_username_tips'));
      return;
    }

    final currentName = LoginUserNotifier.instance.name$.value;
    if (currentName == newNickname) {
      OXNavigator.pop(context);
      return;
    }

    await BitchatService().updateNickname(newNickname: newNickname);
    LoginUserNotifier.instance.updateNickname(newNickname);
    OXNavigator.pop(context);
  }
}