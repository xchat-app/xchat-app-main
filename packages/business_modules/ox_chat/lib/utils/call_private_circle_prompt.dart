import 'package:chatcore/chat-core.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_module_service/ox_module_service.dart';

/// Calls are a Private Circle feature. In a free circle the call buttons stay
/// where they are, and tapping one says so and offers the way to get a
/// Private Circle; someone who already has one is only told.
Future<void> showCallsNeedPrivateCircle(BuildContext context, {required bool isVideo}) async {
  final circles = LoginManager.instance.currentState.account?.circles ?? [];
  final hasPrivateCircle = circles.any((circle) => CircleApi.isPaidRelay(circle.relayUrl));
  final getOne = await CLAlertDialog.show<bool>(
    context: context,
    title: Localized.text(isVideo ? 'ox_chat.video_call' : 'ox_chat.voice_call'),
    content: Localized.text('ox_chat.call_private_circle_only'),
    actions: hasPrivateCircle
        ? [CLAlertAction.ok()]
        : [
            CLAlertAction.cancel(),
            CLAlertAction<bool>(
              label: Localized.text('ox_login.private_cloud'),
              value: true,
              isDefaultAction: true,
            ),
          ],
  );
  if (getOne == true && !hasPrivateCircle && context.mounted) {
    OXModuleService.pushPage(context, 'ox_login', 'PrivateCloudOverviewPage', null);
  }
}
