import 'package:chatcore/chat-core.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_module_service/ox_module_service.dart';

enum _CallServerChoice { cancel, addServer, getPrivateCircle }

/// A call needs a TURN server wherever two phones cannot connect directly. A
/// Private Circle has ours; a free circle needs its own, added under Call
/// Server. When a call is tried in a free circle without one, this says so
/// and offers both ways; someone who already has a Private Circle is only
/// offered the server.
Future<void> showCallNeedsServer(BuildContext context, {required bool isVideo}) async {
  final circles = LoginManager.instance.currentState.account?.circles ?? [];
  final hasPrivateCircle = circles.any((circle) => CircleApi.isPaidRelay(circle.relayUrl));
  final choice = await CLAlertDialog.show<_CallServerChoice>(
    context: context,
    title: Localized.text(isVideo ? 'ox_chat.video_call' : 'ox_chat.voice_call'),
    content: Localized.text('ox_chat.call_private_circle_only'),
    actions: [
      CLAlertAction<_CallServerChoice>(
        label: Localized.text('ox_common.cancel'),
        value: _CallServerChoice.cancel,
      ),
      CLAlertAction<_CallServerChoice>(
        label: Localized.text('ox_chat.call_add_server'),
        value: _CallServerChoice.addServer,
        isDefaultAction: hasPrivateCircle,
      ),
      if (!hasPrivateCircle)
        CLAlertAction<_CallServerChoice>(
          label: Localized.text('ox_login.private_cloud'),
          value: _CallServerChoice.getPrivateCircle,
          isDefaultAction: true,
        ),
    ],
  );
  if (!context.mounted) return;
  switch (choice) {
    case _CallServerChoice.addServer:
      OXModuleService.pushPage(context, 'ox_usercenter', 'CallServerPage', null);
    case _CallServerChoice.getPrivateCircle:
      OXModuleService.pushPage(context, 'ox_login', 'PrivateCloudOverviewPage', null);
    case _CallServerChoice.cancel:
    case null:
      break;
  }
}
