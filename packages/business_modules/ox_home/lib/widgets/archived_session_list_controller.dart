import 'package:isar/isar.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';

import 'session_list_mixin.dart';
import 'session_view_model.dart';

class ArchivedSessionListController with OXChatObserver, SessionListMixin {
  ArchivedSessionListController(this.ownerPubkey, this.circle);
  final String ownerPubkey;
  final Circle circle;

  @override
  int compareSession(ChatSessionModelISAR a, ChatSessionModelISAR b) {
    return b.lastActivityTime.compareTo(a.lastActivityTime);
  }

  @override
  QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterFilterCondition>
    sessionListQuery(IsarCollection<int, ChatSessionModelISAR> collection) =>
      collection
      .where()
      .chatIdIsNotEmpty()
      .isArchivedEqualTo(true);

  @override
  QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterSortBy>
    sessionListSort(QueryBuilder<ChatSessionModelISAR, ChatSessionModelISAR, QAfterFilterCondition> query) =>
      query
      .sortByLastActivityTimeDesc();

  @override
  void didSessionUpdate(ChatSessionModelISAR session) {
    final viewModel = sessionCache[session.chatId];
    if (viewModel != null && !session.isArchivedSafe) {
      removeViewModel(viewModel);
    } else if (viewModel == null && session.isArchivedSafe) {
      addViewModel(SessionListViewModel(session));
    }
  }
}