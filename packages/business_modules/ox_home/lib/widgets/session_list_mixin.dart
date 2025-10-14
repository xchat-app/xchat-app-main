import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';

import 'session_view_model.dart';

mixin SessionListMixin on OXChatObserver {
  ValueNotifier<List<SessionListViewModel>> sessionList$ = ValueNotifier([]);

  HashMap<String, SessionListViewModel> sessionCache = HashMap<String, SessionListViewModel>();

  /// Compare two sessions to determine their order
  /// Returns:
  ///   < 0 if a should come before b
  ///   > 0 if a should come after b
  ///   = 0 if they are equal
  @protected
  int compareSession(ChatSessionModelISAR a, ChatSessionModelISAR b);

  @protected
  QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterFilterCondition>
    sessionListQuery(IsarCollection<int, ChatSessionModelISAR> collection);
  
  @protected
  QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterSortBy>
    sessionListSort(QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterFilterCondition> query);

  Future<void> initialized() async {
    final isar = DBISAR.sharedInstance.isar;
    final sessionList = sessionListSort(
      sessionListQuery(
        isar.chatSessionModelISARs
      )
    ).findAll();

    final viewModelData = <SessionListViewModel>[];
    for (var sessionModel in sessionList) {
      final viewModel = SessionListViewModel(sessionModel);
      viewModelData.add(viewModel);
      sessionCache[sessionModel.chatId] = viewModel;
    }
    sessionList$.value = viewModelData;

    OXChatBinding.sharedInstance.addObserver(this);
    OXChatBinding.sharedInstance.updateChatSessionFn.add(updateChatSession);
  }

  void dispose() {
    OXChatBinding.sharedInstance.updateChatSessionFn.remove(updateChatSession);
    OXChatBinding.sharedInstance.removeObserver(this);
  }

  @override
  void deleteMessageHandler(MessageDBISAR delMessage, String newSessionSubtitle) {
    final chatId = delMessage.groupId;

    final viewModel = sessionCache[chatId];
    if (viewModel == null) return;

    final sessionModel = viewModel.sessionModel;
    sessionModel.content = newSessionSubtitle;

    viewModel.rebuild();
    ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);
  }

  @override
  void addReactionMessageCallback(String chatId, String messageId) async {
    final viewModel = sessionCache[chatId];
    if (viewModel == null) return;

    final sessionModel = viewModel.sessionModel;
    final reactionMessageIds = [...sessionModel.reactionMessageIds];
    if (!reactionMessageIds.contains(messageId)) {
      sessionModel.reactionMessageIds = [messageId, ...reactionMessageIds];
      viewModel.rebuild();
      ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);
    }
  }

  @override
  void removeReactionMessageCallback(String chatId, [bool sendNotification = true]) async {
    final viewModel = sessionCache[chatId];
    if (viewModel == null) return;

    final sessionModel = viewModel.sessionModel;
    sessionModel.reactionMessageIds = [];
    if (sendNotification) {
      viewModel.rebuild();
    }
    ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);
  }

  @override
  void addMentionMessageCallback(String chatId, String messageId) async {
    if (chatId.isEmpty) return;

    final viewModel = sessionCache[chatId];
    if (viewModel == null) return;

    final sessionModel = viewModel.sessionModel;
    final mentionMessageIds = [...sessionModel.mentionMessageIds];
    if (!mentionMessageIds.contains(messageId)) {
      sessionModel.mentionMessageIds = [messageId, ...sessionModel.mentionMessageIds];
      viewModel.rebuild();
      ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);
    }
  }

  @override
  void removeMentionMessageCallback(String chatId, [bool sendNotification = true]) async {
    final viewModel = sessionCache[chatId];
    if (viewModel == null) return;

    final sessionModel = viewModel.sessionModel;
    sessionModel.mentionMessageIds = [];
    ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);
    if (sendNotification) {
      viewModel.rebuild();
    }
  }


  @override
  Future deleteSessionCallback(List<String> chatIds) async {
    chatIds = chatIds.where((e) => e.isNotEmpty).toList();
    if (chatIds.isEmpty) return;

    final isar = DBISAR.sharedInstance.isar;
    await isar.writeAsync((isar) {
      isar.chatSessionModelISARs
          .where()
          .anyOf(chatIds, (q, chatId) => q.chatIdEqualTo(chatId))
          .deleteAll();
    });

    for (var chatId in chatIds) {
      final viewModel = sessionCache[chatId];
      if (viewModel == null) continue;

      removeViewModel(viewModel);
    }
  }

  @override
  void didReceiveMessageCallback(MessageDBISAR message) async {
    var viewModel = sessionCache[message.chatId];
    if (viewModel != null) {
      viewModel.sessionModel.updateWithMessage(message);
      viewModel.rebuild();
      updateSessionPosition(viewModel);
    }
  }

  @override
  void didChatMessageUpdateCallBack(MessageDBISAR message, String replacedMessageId) {
    final chatType = message.chatType;
    if (chatType == null) return;

    final chatId = message.chatId;

    final viewModel = sessionCache[chatId];
    if (viewModel == null) return;

    // Update session with the new message
    viewModel.sessionModel.updateWithMessage(message);
    viewModel.rebuild();
    updateSessionPosition(viewModel);

    ChatSessionModelISAR.saveChatSessionModelToDB(viewModel.sessionModel);
  }

  @override
  void didCreateSessionCallBack(ChatSessionModelISAR session) {
    final chatId = session.chatId;
    if (sessionCache.containsKey(chatId)) return;

    final viewModel = SessionListViewModel(session);
    addViewModel(viewModel);
    ChatSessionModelISAR.saveChatSessionModelToDB(session);
  }

  void addViewModel(SessionListViewModel viewModel) {
    final chatId = viewModel.sessionModel.chatId;

    if (sessionCache.containsKey(chatId)) return;

    sessionCache[chatId] = viewModel;

    final newList = [...sessionList$.value];

    int flagIndex = newList.length;
    for (int index = 0; index < newList.length; index++) {
      final data = newList[index];

      if (compareSession(viewModel.sessionModel, data.sessionModel) < 0) {
        flagIndex = index;
        break;
      }
    }

    newList.insert(flagIndex, viewModel);

    sessionList$.value = newList;
  }

  void removeViewModel(SessionListViewModel viewModel) {
    final chatId = viewModel.sessionModel.chatId;

    final del = sessionCache.remove(chatId);
    if (del == null) return;

    final newList = [...sessionList$.value];
    newList.remove(del);
    sessionList$.value = newList;
  }

  void updateSessionPosition(SessionListViewModel viewModel) {
    final newList = [...sessionList$.value];
    final currentIndex = newList.indexOf(viewModel);

    if (currentIndex == -1) return;

    // Remove the viewModel from its current position
    newList.removeAt(currentIndex);

    // Find the correct position to insert based on compareSession
    int insertIndex = 0;
    for (int i = 0; i < newList.length; i++) {
      if (compareSession(viewModel.sessionModel, newList[i].sessionModel) < 0) {
        insertIndex = i;
        break;
      }
      insertIndex = i + 1;
    }

    // Insert at the correct position
    newList.insert(insertIndex, viewModel);

    // Only update if the position actually changed
    if (insertIndex != currentIndex) {
      sessionList$.value = newList;
    }
  }

  Future<bool> deleteSession({
    required SessionListViewModel viewModel,
    required bool isDeleteForRemote,
  }) async {
    final chatId = viewModel.sessionModel.chatId;

    final isar = DBISAR.sharedInstance.isar;
    int count = await isar.writeAsync((isar) {
      return isar.chatSessionModelISARs
          .where()
          .chatIdEqualTo(chatId)
          .deleteAll();
    });

    if (count > 0) {
      removeViewModel(viewModel);
    }

    final deleteSuc = await deleteSessionMessage(
      viewModel: viewModel,
      isDeleteForRemote: isDeleteForRemote,
    );

    return deleteSuc;
  }

  Future<bool> deleteSessionMessage({
    required SessionListViewModel viewModel,
    required bool isDeleteForRemote,
  }) async {
    final groupId = viewModel.sessionModel.groupId;
    final chatType = viewModel.sessionModel.chatType;
    if (chatType != ChatType.chatGroup || groupId == null || groupId.isEmpty) return false;

    final group = Groups.sharedInstance.getPrivateGroupNotifier(groupId).value;
    List<MessageDBISAR> allMessage = (await Messages.loadMessagesFromDB(
      groupId: groupId,
    ))['messages'] ?? <MessageDBISAR>[];
    final messageIds = allMessage.map((e) => e.messageId).toList();

    await Groups.sharedInstance.deleteMLSGroupMessages(
      messageIds,
      group,
      requestDeleteForAll: isDeleteForRemote,
    );

    return true;
  }

  Future<bool> updateChatSession(String chatId, {
    String? chatName,
    String? content,
    String? pic,
    int? unreadCount,
    bool? alwaysTop,
    bool? isArchived,
    String? draft,
    String? replyMessageId,
    int? messageKind,
    bool? isMentioned,
    int? expiration,
    int? lastMessageTime,
    int? lastActivityTime,
  }) async {
    final viewModel = sessionCache[chatId];
    if (viewModel == null) return false;

    final sessionModel = viewModel.sessionModel;

    sessionModel.chatName = chatName ?? sessionModel.chatName;
    sessionModel.content = content ?? sessionModel.content;
    sessionModel.avatar = pic ?? sessionModel.avatar;
    sessionModel.unreadCount = unreadCount ?? sessionModel.unreadCount;
    sessionModel.alwaysTop = alwaysTop ?? sessionModel.alwaysTop;
    sessionModel.isArchived = isArchived ?? sessionModel.isArchived;
    sessionModel.draft = draft ?? sessionModel.draft;
    sessionModel.replyMessageId = replyMessageId ?? sessionModel.replyMessageId;
    sessionModel.isMentioned = isMentioned ?? sessionModel.isMentioned;
    sessionModel.messageKind = messageKind ?? sessionModel.messageKind;
    sessionModel.expiration = expiration ?? sessionModel.expiration;
    sessionModel.createTime = lastMessageTime ?? sessionModel.createTime;
    sessionModel.lastActivityTime = lastActivityTime ?? sessionModel.lastActivityTime;

    viewModel.rebuild();

    if (lastActivityTime != null || alwaysTop != null) {
      updateSessionPosition(viewModel);
    }

    await ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);

    OXChatBinding.sharedInstance.notifySessionUpdate(sessionModel);

    return true;
  }
}

extension ChatSessionModelISARUpdateEx on ChatSessionModelISAR {
  void updateWithMessage(MessageDBISAR message) {
    final sessionMessageTextBuilder =
        OXChatBinding.sharedInstance.sessionMessageTextBuilder;
    final text = sessionMessageTextBuilder?.call(message) ?? '';

    // Convert message createTime from seconds to milliseconds
    final createTimeInMs = message.createTime * 1000;
    if (createTime < createTimeInMs) {
      createTime = createTimeInMs;
      content = text;
    }
    if (lastActivityTime < createTimeInMs) {
      lastActivityTime = createTimeInMs;
    }

    if (!message.read) {
      unreadCount += 1;
    }
  }
}

extension MessageDBISAREx on MessageDBISAR {
  String get chatId {
    return groupId;
  }
}