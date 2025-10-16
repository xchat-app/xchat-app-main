import 'dart:async';

import 'package:chatcore/chat-core.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';

abstract class CLSessionHandler {
  Future<void> updateLastMessageInfo({
    required String chatId,
    required String previewContent,
    required DateTime msgTime,
  });

  Future<void> updateDraft({
    required String chatId,
    required String? draftContent,
  });

  Future<void> updateReplyDraft({
    required String chatId,
    required String? replyMsgId,
  });

  Future<void> clearUnreadCount({
    required String chatId,
  });

  Future<void> updateMentionStatus({
    required String chatId,
    required bool isMentioned,
  });

  Future<void> updatePinStatus({
    required String chatId,
    required bool isPinned,
  });

  Future<void> updateArchiveStatus({
    required String chatId,
    required bool isArchived,
  });
}

class OXChatBinding {
  static final OXChatBinding sharedInstance = OXChatBinding._internal();

  OXChatBinding._internal();

  factory OXChatBinding() {
    return sharedInstance;
  }

  final List<OXChatObserver> _observers = <OXChatObserver>[];

  String Function(MessageDBISAR messageDB)? sessionMessageTextBuilder;
  bool Function(MessageDBISAR messageDB)? msgIsReaded;

  List<ChatSessionModelISAR> Function()? sessionListFetcher;
  List<ChatSessionModelISAR> get sessionList => sessionListFetcher?.call() ?? [];

  ChatSessionModelISAR? Function(String chatId)? sessionModelFetcher;
  ChatSessionModelISAR? getSessionModel(String chatId) =>
      sessionModelFetcher?.call(chatId);

  CLSessionHandler? _handler;

  void attachHandler(CLSessionHandler handler) {
    _handler = handler;
  }

  void detachHandler(CLSessionHandler handler) {
    if (_handler == handler) {
      _handler = null;
    }
  }

  Future<void> updateLastMessageInfo({
    required String chatId,
    required String previewContent,
    required DateTime msgTime,
  }) async => _handler?.updateLastMessageInfo(
    chatId: chatId,
    previewContent: previewContent,
    msgTime: msgTime,
  );

  Future<void> updateDraft({
    required String chatId,
    required String? draftContent,
  }) async => _handler?.updateDraft(
    chatId: chatId,
    draftContent: draftContent,
  );

  Future<void> updateReplyDraft({
    required String chatId,
    required String? replyMsgId,
  }) async => _handler?.updateReplyDraft(
    chatId: chatId,
    replyMsgId: replyMsgId,
  );

  Future<void> clearUnreadCount({
    required String chatId,
  }) async => _handler?.clearUnreadCount(
    chatId: chatId,
  );

  Future<void> updateMentionStatus({
    required String chatId,
    required bool isMentioned,
  }) async => _handler?.updateMentionStatus(
    chatId: chatId,
    isMentioned: isMentioned,
  );

  Future<void> updatePinStatus({
    required String chatId,
    required bool isPinned,
  }) async => _handler?.updatePinStatus(
    chatId: chatId,
    isPinned: isPinned,
  );

  Future<void> updateArchiveStatus({
    required String chatId,
    required bool isArchived,
  }) async => _handler?.updateArchiveStatus(
    chatId: chatId,
    isArchived: isArchived,
  );

  void addReactionMessage(String chatId, String messageId) {
    for (OXChatObserver observer in _observers) {
      observer.addReactionMessageCallback(chatId, messageId);
    }
  }

  void removeReactionMessage(String chatId, [bool sendNotification = true]) {
    for (OXChatObserver observer in _observers) {
      observer.removeReactionMessageCallback(chatId, sendNotification);
    }
  }

  void addMentionMessage(String chatId, String messageId) {
    for (OXChatObserver observer in _observers) {
      observer.addMentionMessageCallback(chatId, messageId);
    }
  }

  void removeMentionMessage(String chatId, [bool sendNotification = true]) {
    for (OXChatObserver observer in _observers) {
      observer.removeMentionMessageCallback(chatId, sendNotification);
    }
  }

  void deleteMessageHandler(MessageDBISAR delMessage, String newSessionSubtitle) {
    for (OXChatObserver observer in _observers) {
      observer.deleteMessageHandler(delMessage, newSessionSubtitle);
    }
  }

  Future<int> deleteSession(List<String> chatIds) async {
    for (OXChatObserver observer in _observers) {
      observer.deleteSessionCallback(chatIds);
    }
    return chatIds.length;
  }

  void addObserver(OXChatObserver observer) => _observers.add(observer);

  bool removeObserver(OXChatObserver observer) => _observers.remove(observer);

  void contactUpdatedCallBack() {
    for (OXChatObserver observer in _observers) {
      observer.didContactUpdatedCallBack();
    }
  }

  void secretChatAcceptCallBack(SecretSessionDBISAR ssDB) async {
    for (OXChatObserver observer in _observers) {
      observer.didSecretChatAcceptCallBack(ssDB);
    }
  }

  void secretChatRejectCallBack(SecretSessionDBISAR ssDB) async {
    for (OXChatObserver observer in _observers) {
      observer.didSecretChatRejectCallBack(ssDB);
    }
  }

  void didReceiveMessageHandler(MessageDBISAR message) {
    for (OXChatObserver observer in _observers) {
      observer.didReceiveMessageCallback(message);
    }
  }

  void secretChatUpdateCallBack(SecretSessionDBISAR ssDB) {
    for (OXChatObserver observer in _observers) {
      observer.didSecretChatUpdateCallBack(ssDB);
    }
  }

  void secretChatCloseCallBack(SecretSessionDBISAR ssDB) {
    for (OXChatObserver observer in _observers) {
      observer.didSecretChatCloseCallBack(ssDB);
    }
  }

  void privateChatMessageCallBack(MessageDBISAR message) async {
    for (OXChatObserver observer in _observers) {
      observer.didPrivateMessageCallBack(message);
    }
  }

  void chatMessageUpdateCallBack(MessageDBISAR message, String replacedMessageId) async {
    for (OXChatObserver observer in _observers) {
      observer.didChatMessageUpdateCallBack(message, replacedMessageId);
    }
  }

  void secretChatMessageCallBack(MessageDBISAR message) async {
    for (OXChatObserver observer in _observers) {
      observer.didSecretChatMessageCallBack(message);
    }
  }

  void groupMessageCallBack(MessageDBISAR messageDB) async {
    for (OXChatObserver observer in _observers) {
      observer.didGroupMessageCallBack(messageDB);
    }
  }

  void messageDeleteCallback(List<MessageDBISAR> delMessages) {
    for (OXChatObserver observer in _observers) {
      observer.didMessageDeleteCallBack(delMessages);
    }
  }

  void messageActionsCallBack(MessageDBISAR messageDB) async {
    for (OXChatObserver observer in _observers) {
      observer.didMessageActionsCallBack(messageDB);
    }
  }

  void updateMessageDB(MessageDBISAR messageDB) async {
    if (msgIsReaded != null && msgIsReaded!(messageDB) && !messageDB.read){
      messageDB.read = true;
      Messages.saveMessageToDB(messageDB);
    }
  }

  void groupsUpdatedCallBack() {
    for (OXChatObserver observer in _observers) {
      observer.didGroupsUpdatedCallBack();
    }
  }

  void notifySessionUpdate(ChatSessionModelISAR session) {
    for (OXChatObserver observer in _observers) {
      observer.didSessionUpdate(session);
    }
  }

  void offlinePrivateMessageFinishCallBack() {
    for (OXChatObserver observer in _observers) {
      observer.didOfflinePrivateMessageFinishCallBack();
    }
  }

  void offlineSecretMessageFinishCallBack() {
    for (OXChatObserver observer in _observers) {
      observer.didOfflineSecretMessageFinishCallBack();
    }
  }

  void createSessionCallBack(ChatSessionModelISAR session) {
    for (OXChatObserver observer in _observers) {
      observer.didCreateSessionCallBack(session);
    }
  }
}
