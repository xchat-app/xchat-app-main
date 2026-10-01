import 'package:chatcore/chat-core.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:flutter/material.dart';
import 'package:ox_chat/widget/common_chat_widget.dart';
import 'package:ox_chat_ui/ox_chat_ui.dart';
import 'package:ox_chat/utils/general_handler/chat_general_handler.dart';
import 'package:ox_common/business_interface/ox_chat/utils.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_localizable/ox_localizable.dart';
import '../../utils/block_helper.dart';

class ChatGroupMessagePage extends StatefulWidget {
  final ChatGeneralHandler handler;

  const ChatGroupMessagePage({
    super.key,
    required this.handler,
  });

  @override
  State<ChatGroupMessagePage> createState() => _ChatGroupMessagePageState();
}

class _ChatGroupMessagePageState extends State<ChatGroupMessagePage> {
  late ValueNotifier<GroupDBISAR> group$;
  ChatGeneralHandler get handler => widget.handler;
  ChatSessionModelISAR get session => handler.session;
  String get groupId => group$.value.privateGroupId;

  @override
  void initState() {
    super.initState();
    prepareData();
  }

  void prepareData() {
    final groupId = session.groupId;
    if (groupId == null) return;
    group$ = Groups.sharedInstance.getPrivateGroupNotifier(groupId);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: group$,
      builder: (context, group, child) {
        String showName = group.name;
        UserDBISAR? otherUser;
        final isSingleChat = session.isSingleChat == true;
        
        // Check if this is a self chat first
        if (session.isSelfChat) {
          showName = Localized.text('ox_chat.file_transfer_assistant');
        } else if (isSingleChat) {
          otherUser = Account.sharedInstance.userCache[group.otherPubkey]?.value;
          showName = otherUser?.getUserShowName() ?? '';
        }

        final bottomHintParam = getHintParam(group);
        return CommonChatWidget(
          handler: handler,
          title: showName,
          bottomHintParam: bottomHintParam,
          showUserNames: !isSingleChat,
        );
      },
    );
  }

  ChatHintParam? getHintParam(GroupDBISAR group) {
    final myPubkey = handler.author.id;
    if (group.members?.contains(myPubkey) != true) {
      return ChatHintParam(
        Localized.text('ox_chat_ui.not_in_group'),
        (){}
      );
    } else if (!Groups.sharedInstance.checkInMyGroupList(groupId)) {
      // To the person invited, a one-to-one chat is not a group to join.
      final isPrivateChat = session.isSingleChat || group.isDirectMessage;
      return ChatHintParam(
        Localized.text(isPrivateChat ? 'ox_chat_ui.private_chat_accept' : 'ox_chat_ui.group_join'),
        onJoinGroupTap,
      );
    } else if (session.isSingleChat) {
      final otherPubkey = handler.otherUser?.pubKey;
      if (otherPubkey != null) {
        final otherUser = Account.sharedInstance.userCache[otherPubkey]?.value;
        if (otherUser != null) {
          final isBlocked = BlockHelper.isUserBlocked(otherUser.pubKey);
          if (isBlocked) {
            return ChatHintParam(
              Localized.text('ox_chat.user_blocked_hint'),
              () => unblockOnTap(otherUser),
            );
          }
        }
      }
    }

    return null;
  }

  Future onJoinGroupTap() async {
    await OXLoading.show();
    final OKEvent okEvent = await Groups.sharedInstance
        .joinGroup(groupId, '${handler.author.firstName} join the group');
    await OXLoading.dismiss();
    if (okEvent.status) {
      OXChatBinding.sharedInstance.groupsUpdatedCallBack();
    } else {
      CommonToast.instance.show(context, okEvent.message);
    }
  }

  Future unblockOnTap(UserDBISAR user) async {
    final isSuccess = await BlockHelper.unblockUser(context, user);
    if (isSuccess) setState(() {});
  }
}
