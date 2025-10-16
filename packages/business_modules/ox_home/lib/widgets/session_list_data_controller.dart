import 'dart:collection';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/push/push_integration.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';
import 'package:ox_common/utils/session_helper.dart';

import 'session_view_model_handler.dart';
import 'session_view_model.dart';

class SessionListDataController extends CLSessionHandler with OXChatObserver, SessionViewModelHandler {
  SessionListDataController(this.ownerPubkey, this.circle);
  final String ownerPubkey;
  final Circle circle;

  HashMap<String, SessionListViewModel> allSessionCache =
    HashMap<String, SessionListViewModel>();

  ValueNotifier<bool> hasArchivedChats$ = ValueNotifier(false);

  // SessionListMixin
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

    OXChatBinding.sharedInstance.attachHandler(this);
    OXChatBinding.sharedInstance.sessionModelFetcher = fetchSessionFromDB;
    OXChatBinding.sharedInstance.sessionListFetcher = fetchAllSessionFromDB;
  }

  @override
  void dispose() {
    OXChatBinding.sharedInstance.sessionListFetcher = null;
    OXChatBinding.sharedInstance.sessionModelFetcher = null;
    OXChatBinding.sharedInstance.detachHandler(this);
    super.dispose();
  }

  @override
  void didCreateSessionCallBack(ChatSessionModelISAR session) async {
    ChatSessionModelISAR? existSession = fetchSessionFromDB(session.chatId);
    if (existSession != null) return;

    await _saveSessionToDB(session);
    OXChatBinding.sharedInstance.notifySessionUpdate(session);
  }

  @override
  void didSessionUpdate(ChatSessionModelISAR session) {
    super.didSessionUpdate(session);

    final viewModel = sessionCache[session.chatId];
    if (viewModel != null && session.isArchivedSafe) {
      removeViewModel(viewModel);
    } else if (viewModel == null && !session.isArchivedSafe) {
      addViewModel(SessionListViewModel(session));
    } else {
      viewModel?.rebuild();
    }

    _updateArchivedChatsStatus();
  }

  @override
  Future deleteSessionCallback(List<String> chatIds) async {
    super.deleteSessionCallback(chatIds);

    chatIds = chatIds.where((e) => e.isNotEmpty).toList();
    if (chatIds.isEmpty) return;

    final isar = DBISAR.sharedInstance.isar;
    await isar.writeAsync((isar) {
      isar.chatSessionModelISARs
          .where()
          .anyOf(chatIds, (q, chatId) => q.chatIdEqualTo(chatId))
          .deleteAll();
    });

    _updateArchivedChatsStatus();
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
    ChatSessionModelISAR? session = fetchSessionFromDB(chatId);
    bool isNewSession = session == null;

    late ChatSessionModelISAR sessionModel;
    if (isNewSession) {
      final params = SessionCreateParams.fromMessage(message);
      sessionModel = await SessionHelper.createSessionModel(params);
      if (!messageIsRead) {
        sessionModel.unreadCount = 1;
      }
    } else {
      sessionModel = session;
      sessionModel.updateWithMessage(message);
    }

    await _saveSessionToDB(sessionModel, isNewSession);
    if (!isNewSession) {
      OXChatBinding.sharedInstance.notifySessionUpdate(session);
    }

    // 3. Push notification
    final viewModel = SessionListViewModel(sessionModel);
    CLPushIntegration.instance.putReceiveMessage(viewModel.name, message);

    // 4. Add new session to home list (if needed)
    if (!sessionCache.containsKey(chatId) && !viewModel.isArchived) {
      addViewModel(viewModel);
    }
  }

  @override
  void didChatMessageUpdateCallBack(MessageDBISAR message, String replacedMessageId) {
    _updateSession(
      chatId: message.chatId,
      handler: (session) {
        session.updateWithMessage(message);
        return true;
      },
    );
  }

  @override
  void deleteMessageHandler(MessageDBISAR delMessage, String newSessionSubtitle) {
    super.deleteMessageHandler(delMessage, newSessionSubtitle);

    final chatId = delMessage.chatId;
    _updateSession(
      chatId: chatId,
      handler: (session) {
        session.content = newSessionSubtitle;
        return true;
      },
    );
  }

  @override
  void addReactionMessageCallback(String chatId, String messageId) {
    _updateSession(
      chatId: chatId,
      handler: (session) {
        final reactionMsgIds = [...session.reactionMessageIds];
        if (reactionMsgIds.contains(messageId)) return false;

        session.reactionMessageIds = [messageId, ...reactionMsgIds];
        return true;
      },
    );
  }

  @override
  void removeReactionMessageCallback(String chatId, [bool sendNotification = true]) {
    _updateSession(
      chatId: chatId,
      handler: (session) {
        if (session.reactionMessageIds.isEmpty) return false;

        session.reactionMessageIds = [];
        return true;
      },
    );
  }

  @override
  void addMentionMessageCallback(String chatId, String messageId) async {
    _updateSession(
      chatId: chatId,
      handler: (session) {
        final mentionMsgIds = [...session.mentionMessageIds];
        if (mentionMsgIds.contains(messageId)) return false;

        session.reactionMessageIds = [];
        return true;
      },
    );
  }

  @override
  void removeMentionMessageCallback(String chatId, [bool sendNotification = true]) async {
    _updateSession(
      chatId: chatId,
      handler: (session) {
        if (session.mentionMessageIds.isEmpty) return false;

        session.mentionMessageIds = [];
        return true;
      },
    );
  }

  // CLSessionHandler
  @override
  Future<void> updateLastMessageInfo({
    required String chatId,
    required String previewContent,
    required DateTime msgTime,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      final timestamp = msgTime.millisecondsSinceEpoch;
      if (session.createTime > timestamp) return false;

      session.createTime = timestamp;
      if (session.lastActivityTime < timestamp) {
        session.lastActivityTime = timestamp;
      }

      session.content = previewContent;

      return true;
    },
  );

  @override
  Future<void> updateDraft({
    required String chatId,
    required String? draftContent,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      if (session.draft == draftContent) return false;
      session.draft = draftContent;
      return true;
    },
  );

  @override
  Future<void> updateReplyDraft({
    required String chatId,
    required String? replyMsgId,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      if (session.replyMessageId == replyMsgId) return false;
      session.replyMessageId = replyMsgId;
      return true;
    },
  );

  @override
  Future<void> clearUnreadCount({
    required String chatId,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      if (session.unreadCount == 0) return false;
      session.unreadCount = 0;
      return true;
    },
  );

  @override
  Future<void> updateMentionStatus({
    required String chatId,
    required bool isMentioned,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      if (session.isMentioned == isMentioned) return false;
      session.isMentioned = isMentioned;
      return true;
    },
  );

  @override
  Future<void> updatePinStatus({
    required String chatId,
    required bool isPinned,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      if (session.alwaysTop == isPinned) return false;
      session.alwaysTop = isPinned;
      return true;
    },
  );

  @override
  Future<void> updateArchiveStatus({
    required String chatId,
    required bool isArchived,
  }) => _updateSession(
    chatId: chatId,
    handler: (session) {
      if (session.isArchivedSafe == isArchived) return false;
      session.isArchived = isArchived;
      return true;
    },
    synchronize: true,
  );
}

extension _SessionListDataControllerEx on SessionListDataController {
  void _updateArchivedChatsStatus() {
    final isar = DBISAR.sharedInstance.isar;
    final archivedSession = isar.chatSessionModelISARs.where()
        .isArchivedEqualTo(true)
        .findAll();
    hasArchivedChats$.value = archivedSession.isNotEmpty;
  }

  ChatSessionModelISAR? fetchSessionFromDB(String chatId) {
    final isar = DBISAR.sharedInstance.isar;
    return isar.chatSessionModelISARs
        .where()
        .chatIdEqualTo(chatId)
        .findFirst();
  }

  List<ChatSessionModelISAR> fetchAllSessionFromDB() {
    final isar = DBISAR.sharedInstance.isar;
    return isar.chatSessionModelISARs
        .where()
        .findAll();
  }

  Future<void> _updateSession({
    required String chatId,
    required bool Function(ChatSessionModelISAR session) handler,
    bool synchronize = false,
  }) async {
    ChatSessionModelISAR? session = fetchSessionFromDB(chatId);
    if (session == null) return;

    final isNeedsUpdate = handler(session);
    if (!isNeedsUpdate) return;

    await _saveSessionToDB(session, synchronize);
    OXChatBinding.sharedInstance.notifySessionUpdate(session);
  }

  Future<void> _saveSessionToDB(ChatSessionModelISAR chatSessionModel, [bool synchronize = false]) async {
    if (synchronize) {
      await DBISAR.sharedInstance.isar.writeAsyncWith(chatSessionModel, (isar, chatSessionModel) {
        chatSessionModel.id = isar.chatSessionModelISARs.autoIncrement();
        isar.chatSessionModelISARs.put(chatSessionModel);
      });
    } else {
      await DBISAR.sharedInstance.saveToDB(chatSessionModel);
    }
  }
}