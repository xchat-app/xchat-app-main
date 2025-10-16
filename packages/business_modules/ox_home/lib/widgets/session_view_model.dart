import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_chat/utils/chat_session_utils.dart';
import 'package:ox_common/business_interface/ox_chat/utils.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/utils/date_utils.dart';
import 'package:ox_common/utils/extension.dart';

class SessionListViewModel {
  SessionListViewModel(this._raw) {
    updateGroupMemberIfNeeded();
  }

  ChatSessionModelISAR _raw;
  ChatSessionModelISAR get sessionModel => _raw;

  late ValueNotifier entity$ =
      ChatSessionUtils.getChatValueNotifier(_raw) ?? ValueNotifier(null);

  final ValueNotifier<bool> build$ = ValueNotifier(false);

  final ValueNotifier<List<String>> groupMember$ = ValueNotifier([]);

  String get subtitle => _raw.content ?? '';
  String get draft => _raw.draft ?? '';
  bool get isMentioned => _raw.mentionMessageIds.isNotEmpty;
  bool get isMute => ChatSessionUtils.getChatMute(sessionModel);
  bool get isAlwaysTop => sessionModel.alwaysTop;
  bool get isArchived => sessionModel.isArchivedSafe;

  String get updateTime =>
      OXDateUtils.convertTimeFormatString2(_raw.createTime,
          pattern: 'MM-dd');

  String get unreadCountText {
    final count = _raw.unreadCount;
    if (count > 99) return '99+';
    if (count > 0) return count.toString();
    return '';
  }

  String get iconUrl {
    final entity = entity$.value;
    switch (entity) {
      case UserDBISAR user:
        return user.picture ?? '';
      case GroupDBISAR group:
        if(group.isDirectMessage == true){
          UserDBISAR? otherUser = Account.sharedInstance.userCache[group.otherPubkey]?.value;
          return otherUser?.picture ?? '';
        } else {
          return group.picture ?? '';
        }
      case String _:
        return '';
      default:
        assert(false, 'Unknown Type: ${entity.runtimeType}');
        return '';
    }
  }

  String get defaultIcon {
    final entity = entity$.value;
    switch (entity) {
      case UserDBISAR _:
        return 'user_image.png';
      case GroupDBISAR group:
        if(group.isDirectMessage == true) {
          return 'user_image.png';
        } else {
          return 'icon_group_default.png';
        }
      case String _:
        final type = _raw.chatType;
        switch (type) {
          case ChatType.bitchatChannel:
            return 'icon_group_default.png';
          case ChatType.bitchatPrivate:
            return 'user_image.png';
          default :{
            assert(false, 'Unknown Type: $type');
            return '';
          }
        }
      default:
        assert(false, 'Unknown Type: ${entity.runtimeType}');
        return '';
    }
  }

  String get name {
    final entity = entity$.value;
    switch (entity) {
      case UserDBISAR user:
        return user.getUserShowName();
      case GroupDBISAR group:
        if (group.isDirectMessage == true) {
          UserDBISAR? otherUser = Account.sharedInstance.userCache[group.otherPubkey]?.value;
          return otherUser?.getUserShowName() ?? '';
        } else {
          return group.name;
        }
      case ChannelDBISAR channel:
        return channel.name ?? '';
      case RelayGroupDBISAR relayGroup:
        return relayGroup.name;
      case String text:
        return text;
      default:
        assert(false, 'Unknown Type: ${entity.runtimeType}');
        return '';
    }
  }

  bool get isSingleChat {
    final entity = entity$.value;
    final chatType = sessionModel.chatType;
    switch ((entity, chatType)) {
      case (UserDBISAR _, _):
        return true;
      case (GroupDBISAR(isDirectMessage: final dm), _):
        return dm;
      case (_, ChatType.chatSingle):
      case (_, ChatType.bitchatPrivate):
        return true;
      case (_, ChatType.bitchatChannel):
        return false;
      default:
        assert(false, 'Unknown Type: ${entity.runtimeType}, chatType: $chatType');
        return false;
    }
  }

  void updateGroupMemberIfNeeded() async {
    if (isSingleChat) return;

    final groupId = _raw.groupId ?? '';
    List<UserDBISAR> groupList =
        await Groups.sharedInstance.getAllGroupMembers(groupId);
    List<String> avatars = groupList.map((e) => e.picture ?? '').toList();
    avatars.removeWhere((e) => e.isEmpty);

    groupMember$.value = avatars;
  }

  void updateSessionRaw(ChatSessionModelISAR session) {
    _raw = session;
  }

  void rebuild() {
    build$.safeUpdate(!build$.value);
  }
}
