import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';

import 'session_view_model.dart';

mixin SessionViewModelHandler on OXChatObserver {
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
  }

  void dispose() {
    OXChatBinding.sharedInstance.removeObserver(this);
  }

  @override
  @mustCallSuper
  void didSessionUpdate(ChatSessionModelISAR session) {
    final viewModel = sessionCache[session.chatId];
    if (viewModel != null) {
      viewModel.updateSessionRaw(session);
      updateSessionPosition(viewModel);
    }
  }

  @override
  @mustCallSuper
  Future deleteSessionCallback(List<String> chatIds) async {
    chatIds = chatIds.where((e) => e.isNotEmpty).toList();
    if (chatIds.isEmpty) return;

    for (var chatId in chatIds) {
      final viewModel = sessionCache[chatId];
      if (viewModel == null) continue;

      removeViewModel(viewModel);
    }
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