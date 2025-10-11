import 'package:chatcore/chat-core.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:isar/isar.dart';

part 'chat_session_model_isar.g.dart';

@collection
class ChatSessionModelISAR {
  int id = 0;

  @Index(unique: true)
  String chatId;

  String? chatName;

  // pubkey
  String sender;

  // receiver pubkey
  String receiver;

  // channel or group id
  String? groupId;
  String? content;
  int unreadCount;

  //last message timestamp(ms)
  int createTime;

  //last activity timestamp(ms)
  int lastActivityTime;

  // 0 Chat  1 Normal Group  2 Channel Group  3 Secret Chat 4 Stranger Chat  5 Stranger secret Chat 7 Relay Group Chat
  int chatType;

  bool isSingleChat;

  //text, image, video, audio, file, template
  String? messageType;

  String? avatar;

  bool alwaysTop;

  bool isArchived;

  String? draft;
  String? replyMessageId;

  bool isMentioned;
  bool isZapsFromOther;

  int? messageKind;

  // added @v5
  int? expiration;

  List<String> reactionMessageIds = [];

  List<String> mentionMessageIds = [];

  ChatSessionModelISAR({
    this.chatId = '',
    this.chatName,
    this.sender = '',
    this.receiver = '',
    this.groupId,
    this.content,
    this.unreadCount = 0,
    this.createTime = 0,
    this.lastActivityTime = 0,
    this.chatType = 0,
    this.isSingleChat = false,
    this.messageType = 'text',
    this.avatar,
    this.alwaysTop = false,
    this.isArchived = false,
    this.draft,
    this.replyMessageId,
    this.isMentioned = false,
    this.isZapsFromOther = false,
    this.messageKind,
    this.expiration,
  });

  @ignore
  String get getOtherPubkey {
    return this.sender != LoginManager.instance.currentPubkey ? this.sender : this.receiver;
  }

  @ignore
  bool get isSelfChat {
    return sender == LoginManager.instance.currentPubkey && sender == receiver;
  }

  static ChatSessionModelISAR fromMap(Map<String, Object?> map) {
    return _chatSessionModelFromMap(map);
  }

  @override
  String toString() {
    return 'ChatSessionModel{chatId: $chatId, chatName: $chatName, sender: $sender, receiver: $receiver, groupId: $groupId, content: $content, unreadCount: $unreadCount, createTime: $createTime, lastActivityTime: $lastActivityTime, chatType: $chatType, messageType: $messageType, avatar: $avatar, alwaysTop: $alwaysTop, isArchived: $isArchived, draft: $draft, messageKind: $messageKind, expiration: $expiration}';
  }

  @ignore
  bool get hasMultipleUsers {
    switch (chatType) {
      case ChatType.bitchatChannel: return true;
      case ChatType.chatGroup: return false;
      default: return true;
    }
  }

  static ChatSessionModelISAR getDefaultSession(int type, String receiverPubkey, String sender, {String secretSessionId = ''}) {
    String chatId = '';
    String receiver = '';
    switch (type) {
      case ChatType.chatSingle:
        chatId = receiverPubkey;
        receiver = receiverPubkey;
        break;
      case ChatType.chatGroup:
        chatId = receiverPubkey;
        break;
      case ChatType.bitchatChannel:
      case ChatType.bitchatPrivate:
        chatId = receiverPubkey;
        break;
    }
    return ChatSessionModelISAR(
      chatId: chatId,
      receiver: receiver,
      chatType: type,
      sender: sender,
    );
  }

  static Future<void> saveChatSessionModelToDB(ChatSessionModelISAR chatSessionModel) async {
    await DBISAR.sharedInstance.saveToDB(chatSessionModel);
  }
}

ChatSessionModelISAR _chatSessionModelFromMap(Map<String, dynamic> map) {
  return ChatSessionModelISAR(
    chatId: map['chatId'],
    chatName: map['chatName'],
    sender: map['sender'],
    receiver: map['receiver'],
    groupId: map['groupId'],
    content: map['content'],
    unreadCount: map['unreadCount'],
    createTime: map['createTime'],
    lastActivityTime: map['lastActivityTime'],
    chatType: map['chatType'],
    messageType: map['messageType'],
    avatar: map['avatar'],
    alwaysTop: map['alwaysTop'] == 1,
    isArchived: map['isArchived'] == 1,
    draft: map['draft'],
    replyMessageId: map['replyMessageId'],
    isMentioned: map['isMentioned'] == 1,
    isZapsFromOther: map['isZapsFromOther'] == 1,
    messageKind: map['messageKind'],
    expiration: map['expiration'],
  );
}
