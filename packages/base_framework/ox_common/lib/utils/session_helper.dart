
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';

class SessionCreateParams {
  final String chatId;
  final String? chatName;
  final String? receiver;
  final String? sender;
  final String? groupId;
  final int chatType;
  final String content;
  final int? createTime;
  final String? avatar;
  final bool isSingleChat;

  SessionCreateParams({
    required this.chatId,
    this.chatName,
    this.receiver,
    this.sender,
    this.groupId,
    required this.chatType,
    required this.content,
    this.createTime,
    this.avatar,
    this.isSingleChat = false,
  });

  factory SessionCreateParams.fromMessage(MessageDBISAR message) {
    final chatId = message.groupId;
    final defaultChatName = (message.chatType == ChatType.bitchatChannel && message.groupId.isEmpty) ? 'Global' : null;
    
    return SessionCreateParams(
      chatId: chatId,
      chatName: defaultChatName,
      receiver: message.receiver,
      sender: message.sender,
      groupId: message.groupId,
      chatType: message.chatType!,
      content: message.content,
      createTime: message.createTime * 1000,
      isSingleChat: false, // Will be determined later
    );
  }

  factory SessionCreateParams.fromGroup(GroupDBISAR groupDB, UserDBISAR user) {
    return SessionCreateParams(
      chatId: groupDB.privateGroupId,
      groupId: groupDB.privateGroupId,
      chatType: ChatType.chatGroup,
      content: '',
      chatName: groupDB.name,
      createTime: groupDB.updateTime,
      avatar: groupDB.picture,
      sender: LoginManager.instance.currentPubkey,
      receiver: user.pubKey,
      isSingleChat: true,
    );
  }
}

class SessionHelper {
  static Future<ChatSessionModelISAR> createSessionModel(SessionCreateParams params) async {
    final createTime = params.createTime ?? DateTime.now().millisecondsSinceEpoch;
    final sessionModel = ChatSessionModelISAR(
      chatId: params.chatId,
      chatName: params.chatName,
      receiver: params.receiver ?? '',
      sender: params.sender ?? '',
      groupId: params.groupId,
      chatType: params.chatType,
      content: params.content,
      createTime: createTime,
      lastActivityTime: createTime,
      avatar: params.avatar,
      isSingleChat: params.isSingleChat,
    );

    if (!params.isSingleChat) {
      await _updateIsSingleChatIfNeeded(sessionModel);
    }

    return sessionModel;
  }

  static Future<void> _updateIsSingleChatIfNeeded(ChatSessionModelISAR sessionModel) async {
    final groupId = sessionModel.groupId;
    if (groupId == null || groupId.isEmpty) return;

    try {
      // Get group information from Groups instance
      final groupNotifier = Groups.sharedInstance.getPrivateGroupNotifier(groupId);
      final groupDB = groupNotifier.value;
      
      // Set isSingleChat based on group's isDirectMessage property
      sessionModel.isSingleChat = groupDB.isDirectMessage;
      
      // Only proceed with receiver setup if it's a direct message
      if (!groupDB.isDirectMessage) return;
      
      final members = await Groups.sharedInstance.getAllGroupMembers(groupId);
      
      if (members.length > 2) return;

      final currentUserPubkey = LoginManager.instance.currentPubkey;
      if (currentUserPubkey.isEmpty) return;

      String? receiverPubkey;

      // self-chat
      if (members.length == 1 && members.first.pubKey == currentUserPubkey) {
        receiverPubkey = currentUserPubkey;
      } else if (members.length == 2) {
        for (final member in members) {
          if (member.pubKey != currentUserPubkey) {
            receiverPubkey = member.pubKey;
            break;
          }
        }
      }

      if (receiverPubkey != null && receiverPubkey.isNotEmpty) {
        sessionModel.receiver = receiverPubkey;
      }
    } catch (e) {
      // Handle error silently, avoid breaking the flow
    }
  }
}