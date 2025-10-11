import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/push/push_integration.dart';
import 'package:ox_common/utils/chat_prompt_tone.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';
import 'package:ox_common/utils/session_helper.dart';

import 'session_view_model.dart';

class SessionListDataController with OXChatObserver {
  SessionListDataController(this.ownerPubkey, this.circle);
  final String ownerPubkey;
  final Circle circle;

  ValueNotifier<List<SessionListViewModel>> sessionList$ = ValueNotifier([]);

  // Key: chatId
  HashMap<String, SessionListViewModel> sessionCache =
      HashMap<String, SessionListViewModel>();

  @override
  void deleteSessionCallback(List<String> chatIds) async {
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

      _removeViewModel(viewModel);
    }
  }

  @override
  void didReceiveMessageCallback(MessageDBISAR message) async {
    final messageIsRead =
        OXChatBinding.sharedInstance.msgIsReaded?.call(message) ?? false;
    if (messageIsRead) {
      message.read = messageIsRead;
      Messages.saveMessageToDB(message);
    }

    final chatType = message.chatType;
    if (chatType == null) return;

    final chatId = message.chatId;
    var viewModel = sessionCache[chatId];
    if (viewModel == null) {
      final params = SessionCreateParams.fromMessage(message);
      final sessionModel = await SessionHelper.createSessionModel(params);

      viewModel = SessionListViewModel(sessionModel);
      viewModel.sessionModel.updateWithMessage(message);
      _addViewModel(viewModel);
    } else {
      viewModel.sessionModel.updateWithMessage(message);
      viewModel.rebuild();
      _updateSessionPosition(viewModel);
    }

    ChatSessionModelISAR.saveChatSessionModelToDB(viewModel.sessionModel);
    CLPushIntegration.instance.putReceiveMessage(viewModel.name, message);
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
    _updateSessionPosition(viewModel);

    ChatSessionModelISAR.saveChatSessionModelToDB(viewModel.sessionModel);
  }

  @override
  void deleteMessageHandler(MessageDBISAR delMessage, String newSessionSubtitle) {
    final chatId = delMessage.chatId;

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

    final isCurrencyChatPage = PromptToneManager.sharedInstance.isCurrencyChatPage?.call(
      chatId,
      messageId,
    ) ?? false;

    if (isCurrencyChatPage) return;

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
  void didCreateSessionCallBack(ChatSessionModelISAR session) {
    final chatId = session.chatId;
    if (sessionCache.containsKey(chatId)) return;

    final viewModel = SessionListViewModel(session);
    _addViewModel(viewModel);
    ChatSessionModelISAR.saveChatSessionModelToDB(session);
  }
}

extension SessionDCInterface on SessionListDataController {
  void initialized() async {
    final isar = DBISAR.sharedInstance.isar;
    final List<ChatSessionModelISAR> sessionList = isar
        .chatSessionModelISARs
        .where()
        .findAll();

    // Filter out empty chatIds and sort: first by alwaysTop (pinned first), then by lastActivityTime descending
    sessionList.removeWhere((session) => session.chatId.isEmpty);
    sessionList.sort((a, b) {
      // First compare by alwaysTop (pinned sessions come first)
      if (a.alwaysTop != b.alwaysTop) {
        return b.alwaysTop ? 1 : -1;
      }
      // Then sort by lastActivityTime descending
      return b.lastActivityTime.compareTo(a.lastActivityTime);
    });

    final viewModelData = <SessionListViewModel>[];
    for (var sessionModel in sessionList) {
      final viewModel = SessionListViewModel(sessionModel);
      viewModelData.add(viewModel);
      sessionCache[sessionModel.chatId] = viewModel;
    }

    sessionList$.value = viewModelData;

    OXChatBinding.sharedInstance.addObserver(this);
    OXChatBinding.sharedInstance.sessionModelFetcher =
        (chatId) => sessionCache[chatId]?.sessionModel;
    OXChatBinding.sharedInstance.updateChatSessionFn = updateChatSession;
    OXChatBinding.sharedInstance.sessionListFetcher =
        () => sessionList$.value.map((e) => e.sessionModel).toList();
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
      _removeViewModel(viewModel);
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
    String? draft,
    String? replyMessageId,
    int? messageKind,
    bool? isMentioned,
    int? expiration,
    int? lastMessageTime,
    int? lastActivityTime,
  }) async {
    final viewModel = sessionCache[chatId];
    if (viewModel == null) return true;

    final sessionModel = viewModel.sessionModel;

    sessionModel.chatName = chatName ?? sessionModel.chatName;
    sessionModel.content = content ?? sessionModel.content;
    sessionModel.avatar = pic ?? sessionModel.avatar;
    sessionModel.unreadCount = unreadCount ?? sessionModel.unreadCount;
    sessionModel.alwaysTop = alwaysTop ?? sessionModel.alwaysTop;
    sessionModel.draft = draft ?? sessionModel.draft;
    sessionModel.replyMessageId = replyMessageId ?? sessionModel.replyMessageId;
    sessionModel.isMentioned = isMentioned ?? sessionModel.isMentioned;
    sessionModel.messageKind = messageKind ?? sessionModel.messageKind;
    sessionModel.expiration = expiration ?? sessionModel.expiration;
    sessionModel.createTime = lastMessageTime ?? sessionModel.createTime;
    sessionModel.lastActivityTime = lastActivityTime ?? sessionModel.lastActivityTime;

    viewModel.rebuild();

    // Update session position if lastActivityTime or alwaysTop changed
    if (lastActivityTime != null || alwaysTop != null) {
      _updateSessionPosition(viewModel);
    }

    ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);

    return true;
  }
}

extension _DataControllerEx on SessionListDataController {
  void _addViewModel(SessionListViewModel viewModel) {
    final chatId = viewModel.sessionModel.chatId;

    if (sessionCache.containsKey(chatId)) return;

    sessionCache[chatId] = viewModel;

    final newList = [...sessionList$.value];

    int flagIndex = newList.length;
    for (int index = 0; index < newList.length; index++) {
      final data = newList[index];

      // Compare by alwaysTop first, then by lastActivityTime
      if (viewModel.sessionModel.alwaysTop && !data.sessionModel.alwaysTop) {
        flagIndex = index;
        break;
      }
      if (viewModel.sessionModel.alwaysTop == data.sessionModel.alwaysTop &&
          data.sessionModel.lastActivityTime < viewModel.sessionModel.lastActivityTime) {
        flagIndex = index;
        break;
      }
    }

    newList.insert(flagIndex, viewModel);

    sessionList$.value = newList;
  }

  void _removeViewModel(SessionListViewModel viewModel) {
    final chatId = viewModel.sessionModel.chatId;

    final del = sessionCache.remove(chatId);
    if (del == null) return;

    final newList = [...sessionList$.value];
    newList.remove(del);
    sessionList$.value = newList;
  }

  void _updateSessionPosition(SessionListViewModel viewModel) {
    final newList = [...sessionList$.value];
    final currentIndex = newList.indexOf(viewModel);

    if (currentIndex == -1) return;

    // Remove the viewModel from its current position
    newList.removeAt(currentIndex);

    // Find the correct position to insert based on alwaysTop first, then lastActivityTime
    int insertIndex = 0;
    for (int i = 0; i < newList.length; i++) {
      // Pinned sessions come first
      if (viewModel.sessionModel.alwaysTop && !newList[i].sessionModel.alwaysTop) {
        insertIndex = i;
        break;
      }
      // Among same pin status, sort by lastActivityTime
      if (viewModel.sessionModel.alwaysTop == newList[i].sessionModel.alwaysTop &&
          viewModel.sessionModel.lastActivityTime > newList[i].sessionModel.lastActivityTime) {
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
}

extension _MessageDBISAREx on MessageDBISAR {
  String get chatId {
    return groupId;
  }
}

extension _ChatSessionModelISAREx on ChatSessionModelISAR {
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
