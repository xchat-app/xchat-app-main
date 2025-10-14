import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_chat/page/session/chat_message_page.dart';
import 'package:ox_chat/utils/chat_session_utils.dart';
import 'package:ox_common/business_interface/ox_chat/utils.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/widget_tool.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_localizable/ox_localizable.dart';

import 'session_list_mixin.dart';
import 'session_view_model.dart';

enum SessionDeleteAction {
  selfChatDelete,
  singleDeleteForMe,
  singleDeleteForAll,
  clearHistory,
  groupDeleteForMe,
  groupDeleteForAll,
}

class SessionListItemWidget extends StatelessWidget {
  const SessionListItemWidget({
    super.key,
    required this.item,
    required this.sessionListController,
    this.showPinnedBackground = false,
  });

  final SessionListViewModel item;
  final SessionListMixin? sessionListController;
  final bool showPinnedBackground;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: item.build$,
      builder: (context, value, _) {
        return CLListTileActions(
          actions: [
            buildPinAction(),
            buildArchiveAction(),
            buildMuteAction(),
            buildDeleteAction(),
          ],
          startActions: [
            buildPinAction(),
          ],
          endActions: [
            buildMuteAction(),
            buildDeleteAction(),
            buildArchiveAction(),
          ],
          child: Builder(builder: (context) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                Slidable.of(context)?.close();

                ChatMessagePage.open(
                  context: context,
                  communityItem: item.sessionModel,
                  unreadMessageCount: item.sessionModel.unreadCount,
                );
              },
              child: _buildItemContent(context),
            );
          }),
        );
      },
    );
  }

  Widget _buildItemContent(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: item.entity$,
      builder: (context, value, _) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.px, vertical: 8.px),
          color: showPinnedBackground && item.isAlwaysTop
              ? ColorToken.surfaceContainer.of(context)
              : null,
          child: Row(
            children: [
              _buildItemIcon(),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 6.px,
                    horizontal: 16.px,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CLText.bodyLarge(
                        item.name,
                        customColor: ColorToken.onSurface.of(context),
                        maxLines: 1,
                      ),
                      _buildItemSubtitle(context),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  CLText.labelSmall(
                    item.updateTime,
                  ).setPadding(EdgeInsets.symmetric(vertical: 4.px)),
                  SizedBox(
                    height: 20.px,
                    child: Center(
                      child: _buildUnreadWidget(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemIcon() {
    return ValueListenableBuilder(
      valueListenable: item.entity$,
      builder: (context, entity, _) {
        return ValueListenableBuilder(
          valueListenable: item.groupMember$,
          builder: (context, groupMember, _) {
            final size = 40.px;
            if (entity is UserDBISAR) {
              return OXUserAvatar(
                user: entity,
                size: size,
                isCircular: true,
              );
            } else {
              return SmartGroupAvatar(
                groupId: item.sessionModel.groupId,
                size: size,
              );
            }
          },
        );
      },
    );
  }

  Widget _buildItemSubtitle(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();

    String subtitle = item.subtitle;
    final draft = item.draft;
    final isMentioned = item.isMentioned;
    if (!isMentioned && draft.isNotEmpty) {
      subtitle = draft;
    }

    return RichText(
      textAlign: TextAlign.left,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          if (isMentioned)
            TextSpan(
              text: '[${Localized.text('ox_chat.session_content_mentioned')}] ',
              style: style.copyWith(color: ColorToken.error.of(context)),
            )
          else if (draft.isNotEmpty)
            TextSpan(
              text: '[${Localized.text('ox_chat.session_content_draft')}] ',
              style: style.copyWith(color: ColorToken.error.of(context)),
            ),
          TextSpan(
            text: subtitle,
            style: style.copyWith(
              color: ColorToken.onSecondaryContainer.of(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadWidget(BuildContext context) {
    if (item.isMute) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 5.px),
        child: Badge(
          smallSize: 10.px,
          backgroundColor: ColorToken.primaryContainer.of(context),
        ),
      );
    }
    if (item.unreadCountText.isNotEmpty) {
      return Badge(
        label: Text(item.unreadCountText),
        backgroundColor: ColorToken.error.of(context),
      );
    }
    return const SizedBox.shrink();
  }


  ItemAction buildMuteAction() {
    bool isMute = item.isMute;
    return ItemAction(
        id: 'mute',
        label: Localized.text(
          isMute ? 'ox_chat.un_mute_item' : 'ox_chat.mute_item',
        ),
        icon: isMute ? CupertinoIcons.volume_up : CupertinoIcons.volume_off,
        onTap: (_) async {
          await ChatSessionUtils.setChatMute(item.sessionModel, !isMute);
          item.rebuild();
          return true;
        }
    );
  }

  ItemAction buildDeleteAction() {
    return ItemAction(
        id: 'delete',
        label: Localized.text('ox_chat.delete'),
        icon: CupertinoIcons.delete_solid,
        destructive: true,
        onTap: (ctx) async {
          await _showDeleteOptions(ctx);
          return true;
        }
    );
  }

  ItemAction buildPinAction() {
    bool isPinned = item.sessionModel.alwaysTop;
    return ItemAction(
        id: 'pin',
        label: Localized.text(
          isPinned ? 'ox_chat.unpin_item' : 'ox_chat.pin_item',
        ),
        icon: isPinned ? CupertinoIcons.pin_slash : CupertinoIcons.pin_fill,
        onTap: (_) async {
          await OXChatBinding.sharedInstance.updateChatSession(
            item.sessionModel.chatId,
            alwaysTop: !isPinned,
          );
          return true;
        }
    );
  }

  ItemAction buildArchiveAction() {
    final isArchived = item.isArchived;
    return ItemAction(
        id: 'archive',
        label: isArchived
            ? Localized.text('ox_chat.unarchive_item')
            : Localized.text('ox_chat.archive_item'),
        icon: CupertinoIcons.archivebox,
        onTap: (_) async {
          await OXChatBinding.sharedInstance.updateChatSession(
            item.sessionModel.chatId,
            isArchived: !isArchived,
          );
          return true;
        }
    );
  }
}


extension _SessionListItemWidgetEx on SessionListItemWidget {
  Future<void> _showDeleteOptions(BuildContext context) async {
    final isSingleChat = item.isSingleChat;
    bool isGroupOwner = false;

    final entity = item.entity$.value;
    if (entity is GroupDBISAR) {
      UserDBISAR? currentUser = Account.sharedInstance.me;
      isGroupOwner = currentUser?.pubKey == entity.owner;
    }

    if (item.sessionModel.isSelfChat) {
      await _showSelfChatDeleteOptions(context);
    } else if (isSingleChat) {
      await _showPrivateChatDeleteOptions(context);
    } else if (isGroupOwner) {
      await _showGroupOwnerDeleteOptions(context);
    } else {
      await _showGroupMemberDeleteOptions(context);
    }
  }

  bool _isInGroup(SessionListViewModel item) {
    final groupId = item.sessionModel.groupId;
    return groupId != null &&
        groupId.isNotEmpty &&
        Groups.sharedInstance.checkInMyGroupList(groupId);
  }

  Future<void> _showSelfChatDeleteOptions(BuildContext context) async {
    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      items: [
        CLPickerItem(
          label: Localized.text('ox_chat.clear_history'),
          value: SessionDeleteAction.clearHistory,
        ),
        CLPickerItem(
          label: Localized.text('ox_chat.delete'),
          value: SessionDeleteAction.selfChatDelete,
          isDestructive: true,
        ),
      ],
    );

    if (result != null) {
      await _handleSessionDeleteAction(result);
    }
  }

  Future<void> _showPrivateChatDeleteOptions(BuildContext context) async {
    final entity = item.entity$.value;
    String otherUserName = '';

    if (entity is UserDBISAR) {
      otherUserName = entity.getUserShowName();
    }

    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      title: Localized.text('ox_chat.delete_private_chat_title')
          .replaceAll(r'${userName}', otherUserName),
      items: [
        CLPickerItem(
          label: Localized.text('ox_chat.delete_just_for_me'),
          value: SessionDeleteAction.singleDeleteForMe,
          isDestructive: true,
        ),
        CLPickerItem(
          label: Localized.text('ox_chat.delete_for_me_and_user')
              .replaceAll(r'${userName}', otherUserName),
          value: SessionDeleteAction.singleDeleteForAll,
          isDestructive: true,
        ),
      ],
    );

    if (result != null) {
      await _handleSessionDeleteAction(result);
    }
  }

  Future<void> _showGroupOwnerDeleteOptions(BuildContext context) async {
    String chatName = item.name;
    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      title: Localized.text('ox_chat.leave_and_delete_group_title')
          .replaceAll(r'${chatName}', chatName),
      items: [
        CLPickerItem(
          label: Localized.text('ox_chat.clear_history'),
          value: SessionDeleteAction.clearHistory,
        ),
        if (_isInGroup(item))
          CLPickerItem(
            label: Localized.text('ox_chat.delete_for_all_members'),
            value: SessionDeleteAction.groupDeleteForAll,
            isDestructive: true,
          ),
      ],
    );

    if (result != null) {
      await _handleSessionDeleteAction(result);
    }
  }

  Future<void> _showGroupMemberDeleteOptions(BuildContext context) async {
    String chatName = item.name;
    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      title: Localized.text('ox_chat.leave_group_title')
          .replaceAll(r'${chatName}', chatName),
      items: [
        CLPickerItem(
          label: Localized.text('ox_chat.clear_history'),
          value: SessionDeleteAction.clearHistory,
        ),
        CLPickerItem(
          label: Localized.text('ox_chat.delete_group_item'),
          value: SessionDeleteAction.groupDeleteForMe,
          isDestructive: true,
        ),
      ],
    );

    if (result != null) {
      await _handleSessionDeleteAction(result);
    }
  }

  Future<void> _handleSessionDeleteAction(SessionDeleteAction action) async {
    switch (action) {
      case SessionDeleteAction.selfChatDelete:
        if (!await _confirmDeleteSelfChat()) return;
        break;
      case SessionDeleteAction.singleDeleteForMe:
        if (!await _confirmDeleteForMe()) return;
        break;
      case SessionDeleteAction.singleDeleteForAll:
        if (!await _confirmDeleteForAll()) return;
        break;
      case SessionDeleteAction.clearHistory:
        if (!await _confirmClearHistory()) return;
        break;
      case SessionDeleteAction.groupDeleteForMe:
        if (!await _confirmLeaveGroup()) return;
        break;
      case SessionDeleteAction.groupDeleteForAll:
        if (!await _confirmDeleteGroupForAll()) return;
        break;
    }
    _deleteWithAction(item: item, action: action);
  }

  Future<bool> _confirmDeleteSelfChat() async {
    final bool? confirmed = await CLAlertDialog.show(
      content: Localized.text('ox_chat.delete_self_chat_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.delete'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );
    return confirmed == true;
  }

  Future<bool> _confirmDeleteForMe() async {
    final bool? confirmed = await CLAlertDialog.show(
      content: Localized.text('ox_chat.delete_for_me_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.delete'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );
    return confirmed == true;
  }

  Future<bool> _confirmDeleteForAll() async {
    final entity = item.entity$.value;
    String otherUserName = '';

    if (entity is UserDBISAR) {
      otherUserName = entity.getUserShowName();
    }

    final bool? confirmed = await CLAlertDialog.show(
      content: Localized.text('ox_chat.delete_for_all_content')
          .replaceAll(r'${userName}', otherUserName),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.delete_all'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );
    return confirmed == true;
  }

  Future<bool> _confirmClearHistory() async {
    final bool? confirmed = await CLAlertDialog.show(
      content: Localized.text('ox_chat.clear_history_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.clear_history'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );
    return confirmed == true;
  }

  Future<bool> _confirmLeaveGroup() async {
    final bool? confirmed = await CLAlertDialog.show(
      content: Localized.text('ox_chat.leave_group_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.delete'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );
    return confirmed == true;
  }

  Future<bool> _confirmDeleteGroupForAll() async {
    final bool? confirmed = await CLAlertDialog.show(
      content: Localized.text('ox_chat.delete_group_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.delete_all'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );
    return confirmed == true;
  }

  Future<bool> _deleteWithAction({
    required SessionListViewModel item,
    required SessionDeleteAction action,
  }) async {
    final controller = sessionListController;
    if (controller == null) return false;

    final groupId = item.sessionModel.groupId;
    if (groupId == null || groupId.isEmpty) return false;

    switch (action) {
      case SessionDeleteAction.selfChatDelete:
        await controller.deleteSession(
          viewModel: item,
          isDeleteForRemote: false,
        );
        await Groups.sharedInstance.leaveGroup(
          groupId,
          Localized.text('ox_chat.leave_group_system_message')
              .replaceAll(r'${name}', LoginUserNotifier.instance.name$.value),
        );
        return true;
      case SessionDeleteAction.singleDeleteForMe:
        return controller.deleteSession(
          viewModel: item,
          isDeleteForRemote: false,
        );
      case SessionDeleteAction.singleDeleteForAll:
        await Groups.sharedInstance.leaveGroup(
          groupId,
          Localized.text('ox_chat.leave_group_system_message')
              .replaceAll(r'${name}', LoginUserNotifier.instance.name$.value),
        );
        return true;
      case SessionDeleteAction.clearHistory:
        return controller.deleteSessionMessage(
          viewModel: item,
          isDeleteForRemote: false,
        );
      case SessionDeleteAction.groupDeleteForMe:
        await controller.deleteSession(
          viewModel: item,
          isDeleteForRemote: false,
        );
        if (_isInGroup(item)) {
          await Groups.sharedInstance.leaveGroup(
            groupId,
            Localized.text('ox_chat.leave_group_system_message')
                .replaceAll(r'${name}', LoginUserNotifier.instance.name$.value),
          );
        }
        return true;
      case SessionDeleteAction.groupDeleteForAll:
        Groups.sharedInstance.deleteAndLeave(
          groupId,
          Localized.text('ox_chat.disband_group_toast'),
        );
        return true;
    }
  }
}

