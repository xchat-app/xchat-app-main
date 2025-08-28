import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:ox_chat/utils/chat_session_utils.dart';
import 'package:ox_common/business_interface/ox_chat/utils.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/widget_tool.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_localizable/ox_localizable.dart';

import 'session_list_data_controller.dart';
import 'session_view_model.dart';

enum SessionDeleteAction {
  selfChatDelete,
  singleDeleteForMe,
  singleDeleteForAll,
  clearHistory,
  groupDeleteForMe,
  groupDeleteForAll,
}

class SessionListWidget extends StatefulWidget {
  const SessionListWidget({
    super.key,
    required this.ownerPubkey,
    required this.circle,
    required this.itemOnTap,
  });

  final String ownerPubkey;
  final Circle circle;
  final Function(SessionListViewModel item) itemOnTap;

  @override
  State<SessionListWidget> createState() => _SessionListWidgetState();
}

class _SessionListWidgetState extends State<SessionListWidget> {
  SessionListDataController? controller;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(SessionListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reinitialize controller if ownerPubkey or circle changed
    if (oldWidget.ownerPubkey != widget.ownerPubkey || 
        oldWidget.circle.id != widget.circle.id) {
      _initializeController();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initializeController() {
    if (widget.ownerPubkey.isNotEmpty) {
      controller = SessionListDataController(widget.ownerPubkey, widget.circle);
      controller!.initialized();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading if controller is not initialized or ownerPubkey is empty
    if (controller == null || widget.ownerPubkey.isEmpty) {
      return Center(
        child: CLProgressIndicator.circular(),
      );
    }

    return ValueListenableBuilder(
      valueListenable: controller!.sessionList$,
      builder: (context, value, _) {
        // Show empty state when no sessions
        if (value.isEmpty) {
          return _buildEmptyState(context);
        }
        
        return ListView.separated(
          padding: EdgeInsets.only(bottom: Adapt.bottomSafeAreaHeightByKeyboard),
          itemBuilder: (context, index) => itemBuilder(context, value[index]),
          separatorBuilder: separatorBuilder,
          itemCount: value.length,
        );
      },
    );
  }

  Widget? itemBuilder(BuildContext context, SessionListViewModel item) {
    return ValueListenableBuilder(
      valueListenable: item.build$,
      builder: (context, value, _) {
        return CLListTileActions(
          actions: [
            buildMuteAction(item),
            buildDeleteAction(item),
          ],
          child: Builder(
            builder: (context) {
              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  Slidable.of(context)?.close();
                  widget.itemOnTap(item);
                },
                child: buildItemContent(item),
              );
            }
          ),
        );
      },
    );
  }

  ItemAction buildMuteAction(SessionListViewModel item) {
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

  ItemAction buildDeleteAction(SessionListViewModel item) {
    return ItemAction(
      id: 'delete',
      label: Localized.text('ox_chat.delete'),
      icon: CupertinoIcons.delete_solid,
      destructive: true,
      onTap: (ctx) async {
        await _showDeleteOptions(ctx, item);
        return true;
      }
    );
  }

  Future<void> _showDeleteOptions(BuildContext context, SessionListViewModel item) async {
    final isSingleChat = item.isSingleChat;
    bool isGroupOwner = false;

    final entity = item.entity$.value;
    if (entity is GroupDBISAR) {
      UserDBISAR? currentUser = Account.sharedInstance.me;
      isGroupOwner = currentUser?.pubKey == entity.owner;
    }

    if (item.sessionModel.isSelfChat) {
      await _showSelfChatDeleteOptions(context, item);
    } else if (isSingleChat) {
      await _showPrivateChatDeleteOptions(context, item);
    } else if (isGroupOwner) {
      await _showGroupOwnerDeleteOptions(context, item);
    } else {
      await _showGroupMemberDeleteOptions(context, item);
    }
  }

  bool _isInGroup(SessionListViewModel item) {
    final groupId = item.sessionModel.groupId;
    return groupId != null && groupId.isNotEmpty && 
           Groups.sharedInstance.checkInMyGroupList(groupId);
  }

  Future<void> _showSelfChatDeleteOptions(BuildContext context, SessionListViewModel item) async {
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
      await _handleSessionDeleteAction(item, result);
    }
  }

  Future<void> _showPrivateChatDeleteOptions(BuildContext context, SessionListViewModel item) async {
    final entity = item.entity$.value;
    String otherUserName = '';
    
    if (entity is UserDBISAR) {
      otherUserName = entity.getUserShowName();
    }

    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      title: Localized.text('ox_chat.delete_private_chat_title').replaceAll(r'${userName}', otherUserName),
      items: [
        CLPickerItem(
          label: Localized.text('ox_chat.delete_just_for_me'),
          value: SessionDeleteAction.singleDeleteForMe,
          isDestructive: true,
        ),
        if (_isInGroup(item))
          CLPickerItem(
            label: Localized.text('ox_chat.delete_for_me_and_user').replaceAll(r'${userName}', otherUserName),
            value: SessionDeleteAction.singleDeleteForAll,
            isDestructive: true,
          ),
      ],
    );

    if (result != null) {
      await _handleSessionDeleteAction(item, result);
    }
  }

  Future<void> _showGroupOwnerDeleteOptions(BuildContext context, SessionListViewModel item) async {
    String chatName = item.name;
    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      title: Localized.text('ox_chat.leave_and_delete_group_title').replaceAll(r'${chatName}', chatName),
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
      await _handleSessionDeleteAction(item, result);
    }
  }


  Future<void> _showGroupMemberDeleteOptions(BuildContext context, SessionListViewModel item) async {
    String chatName = item.name;
    final result = await CLPicker.show<SessionDeleteAction>(
      context: context,
      title: Localized.text('ox_chat.leave_group_title').replaceAll(r'${chatName}', chatName),
      items: [
        CLPickerItem(
          label: Localized.text('ox_chat.clear_history'),
          value: SessionDeleteAction.clearHistory,
        ),
        if (_isInGroup(item))
          CLPickerItem(
            label: Localized.text('ox_chat.delete_group_item'),
            value: SessionDeleteAction.groupDeleteForMe,
            isDestructive: true,
          ),
      ],
    );

    if (result != null) {
      await _handleSessionDeleteAction(item, result);
    }
  }

  Future<void> _handleSessionDeleteAction(
    SessionListViewModel item,
    SessionDeleteAction action,
  ) async {
    switch (action) {
      case SessionDeleteAction.selfChatDelete:
        if (!await _confirmDeleteSelfChat(item)) return;
        break;
      case SessionDeleteAction.singleDeleteForMe:
        if (!await _confirmDeleteForMe(item)) return;
        break;
      case SessionDeleteAction.singleDeleteForAll:
        if (!await _confirmDeleteForAll(item)) return;
        break;
      case SessionDeleteAction.clearHistory:
        if (!await _confirmClearHistory(item)) return;
        break;
      case SessionDeleteAction.groupDeleteForMe:
        if (!await _confirmLeaveGroup(item)) return;
        break;
      case SessionDeleteAction.groupDeleteForAll:
        if (!await _confirmDeleteGroupForAll(item)) return;
        break;
    }
    _deleteWithAction(item: item, action: action);
  }

  Future<bool> _confirmDeleteSelfChat(SessionListViewModel item) async {
    final bool? confirmed = await CLAlertDialog.show(
      context: context,
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

  Future<bool> _confirmDeleteForMe(SessionListViewModel item) async {
    final bool? confirmed = await CLAlertDialog.show(
      context: context,
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

  Future<bool> _confirmDeleteForAll(SessionListViewModel item) async {
    final entity = item.entity$.value;
    String otherUserName = '';
    
    if (entity is UserDBISAR) {
      otherUserName = entity.getUserShowName();
    }

    final bool? confirmed = await CLAlertDialog.show(
      context: context,
      content: Localized.text('ox_chat.delete_for_all_content').replaceAll(r'${userName}', otherUserName),
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

  Future<bool> _confirmClearHistory(SessionListViewModel item) async {
    final bool? confirmed = await CLAlertDialog.show(
      context: context,
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

  Future<bool> _confirmLeaveGroup(SessionListViewModel item) async {
    final bool? confirmed = await CLAlertDialog.show(
      context: context,
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

  Future<bool> _confirmDeleteGroupForAll(SessionListViewModel item) async {
    final bool? confirmed = await CLAlertDialog.show(
      context: context,
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
    final controller = this.controller;
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
        await Groups.sharedInstance.leaveGroup(
          groupId,
          Localized.text('ox_chat.leave_group_system_message')
              .replaceAll(r'${name}', LoginUserNotifier.instance.name$.value),
        );
        return true;
      case SessionDeleteAction.groupDeleteForAll:
        Groups.sharedInstance.deleteAndLeave(
          groupId,
          Localized.text('ox_chat.disband_group_toast'),
        );
        return true;
    }
  }

  Widget buildItemContent(SessionListViewModel item) {
    return ValueListenableBuilder(
      valueListenable: item.entity$,
      builder: (context, value, _) {
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 16.px, vertical: 8.px),
          child: Row(
            children: [
              _buildItemIcon(item),
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
                      _buildItemSubtitle(context, item),
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
                      child: _buildUnreadWidget(context, item),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildItemIcon(SessionListViewModel item) {
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
          }
        );
      }
    );
  }

  Widget _buildItemSubtitle(BuildContext context, SessionListViewModel item) {
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
            style: style.copyWith(color: ColorToken.onSecondaryContainer.of(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadWidget(BuildContext context, SessionListViewModel item) {
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

  Widget separatorBuilder(BuildContext context, int index) {
    if (PlatformStyle.isUseMaterial) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: 72.px),
      child: Container(
        height: 0.5,
        color: CupertinoColors.separator,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -120.px),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.px),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Empty state icon using Material Icons
              Icon(
                Icons.forum_outlined,
                size: 120.px,
                color: PlatformStyle.isUseMaterial
                    ? ColorToken.primary.of(context)
                    : CupertinoTheme.of(context).textTheme.actionSmallTextStyle.color,
              ),

              SizedBox(height: 24.px),

              // Title
              CLText.titleMedium(
                Localized.text('ox_chat.no_sessions_title'),
                colorToken: ColorToken.onSurface,
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 8.px),

              // Description
              CLText.bodyMedium(
                Localized.text('ox_chat.no_sessions_description'),
                colorToken: ColorToken.onSurfaceVariant,
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}