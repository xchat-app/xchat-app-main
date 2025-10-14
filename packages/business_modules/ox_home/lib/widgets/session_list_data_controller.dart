import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/push/push_integration.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';
import 'package:ox_common/utils/session_helper.dart';

import 'session_list_mixin.dart';
import 'session_view_model.dart';

class SessionListDataController with OXChatObserver, SessionListMixin {
  SessionListDataController(this.ownerPubkey, this.circle);
  final String ownerPubkey;
  final Circle circle;

  HashMap<String, SessionListViewModel> allSessionCache =
    HashMap<String, SessionListViewModel>();

  ValueNotifier<bool> hasArchivedChats$ = ValueNotifier(false);

  @override
  int compareSession(ChatSessionModelISAR a, ChatSessionModelISAR b) {
    if (a.alwaysTop != b.alwaysTop) {
      return b.alwaysTop ? 1 : -1;
    }
    return b.lastActivityTime.compareTo(a.lastActivityTime);
  }

  @override
  QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterFilterCondition>
    sessionListQuery(IsarCollection<int, ChatSessionModelISAR> collection) =>
      collection
      .where()
      .chatIdIsNotEmpty()
      .group((q) => q.isArchivedIsNull().or().isArchivedEqualTo(false));

  @override
  QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterSortBy>
    sessionListSort(QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterFilterCondition> query) =>
      query
      .sortByAlwaysTopDesc()
      .thenByLastActivityTimeDesc();

  @override
  Future<void> initialized() async {
    await super.initialized();

    _updateArchivedChatsStatus();

    OXChatBinding.sharedInstance.sessionModelFetcher =
        (chatId) => allSessionCache[chatId]?.sessionModel;
    OXChatBinding.sharedInstance.sessionListFetcher =
        () => sessionList$.value.map((e) => e.sessionModel).toList();
  }

  @override
  Future deleteSessionCallback(List<String> chatIds) async {
    await super.deleteSessionCallback(chatIds);
    _updateArchivedChatsStatus();
  }

  @override
  void didSessionUpdate(ChatSessionModelISAR session) {
    final viewModel = sessionCache[session.chatId];
    if (viewModel != null && session.isArchivedSafe) {
      removeViewModel(viewModel);
    } else if (viewModel == null && !session.isArchivedSafe) {
      addViewModel(SessionListViewModel(session));
    }
  }

  @override
  void didReceiveMessageCallback(MessageDBISAR message) async {
    // 1. Message preprocessing
    final messageIsRead =
        OXChatBinding.sharedInstance.msgIsReaded?.call(message) ?? false;
    if (messageIsRead) {
      message.read = messageIsRead;
      Messages.saveMessageToDB(message);
    }

    // 2. Session data update
    final chatId = message.chatId;
    ChatSessionModelISAR? session = DBISAR.sharedInstance.isar
        .chatSessionModelISARs
        .where()
        .chatIdEqualTo(chatId)
        .findFirst();

    late ChatSessionModelISAR sessionModel;
    if (session == null) {
      final params = SessionCreateParams.fromMessage(message);
      sessionModel = await SessionHelper.createSessionModel(params);
    } else {
      sessionModel = session;
      sessionModel.updateWithMessage(message);
    }
    await ChatSessionModelISAR.saveChatSessionModelToDB(sessionModel);

    // 3. Push notification
    final viewModel = SessionListViewModel(sessionModel);
    CLPushIntegration.instance.putReceiveMessage(viewModel.name, message);

    // 4. Add new session to home list (if needed)
    if (!sessionCache.containsKey(chatId) && !viewModel.isArchived) {
      addViewModel(viewModel);
    }

    super.didReceiveMessageCallback(message);
  }
}

extension SessionDCInterface on SessionListDataController {
  void _updateArchivedChatsStatus() {
    final isar = DBISAR.sharedInstance.isar;
    final archivedSession = isar.chatSessionModelISARs.where()
        .isArchivedEqualTo(true)
        .findAll();
    hasArchivedChats$.value = archivedSession.isNotEmpty;
  }
}