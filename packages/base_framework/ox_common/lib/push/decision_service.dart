import 'dart:async';
import 'core/message_models.dart';
import 'core/ports.dart';
import 'core/policy_config.dart';

class NotificationDecisionService {
  NotificationDecisionService({
    required this.state,
    required this.perms,
    required this.mute,
    required this.unread,
    required this.dedupe,
    required this.notifier,
    this.config = const NotificationPolicyConfig(),
  });

  final ForegroundState state;
  final PermissionGateway perms;
  final MuteStore mute;
  final UnreadCounter unread;
  final DedupeStore dedupe;
  final Notifier notifier;
  final NotificationPolicyConfig config;

  final Map<String, _Bucket> _buckets = {};

  Future<void> onMessageArrived(IncomingMessage m) async {
    if (mute.isMuted(m.threadId)) return;
    if (state.isAppInForeground()) return;
    if (state.isThreadOpen(m.threadId)) return;
    if (dedupe.seen(m.id)) return;

    if (!(await perms.notificationsAllowed())) return;

    final b = _buckets.putIfAbsent(m.threadId, () => _Bucket(m.threadId));
    b.messages.add(m);
    b.timer?.cancel();
    b.timer = Timer(config.coalesceWindow, () async {
      final messages = List<IncomingMessage>.from(b.messages);
      _buckets.remove(m.threadId);
      if (state.isAppInForeground()) return;
      if (state.isThreadOpen(m.threadId)) return;

      final latest = messages.last;
      final count = messages.length;
      final (title, body) = _compose(latest, count);

      await notifier.showMessage(
        threadId: latest.threadId,
        title: title,
        body: body,
        high: latest.highPriority,
      );

      dedupe.markSeen(messages.map((e) => e.id));
    });
  }

  (String, String) _compose(IncomingMessage latest, int aggregated) {
    String title = 'New message';
    String body;
    switch (config.previewPolicy) {
      case PreviewPolicy.hidden:
        body = aggregated > 1 ? 'You have $aggregated new messages' : 'You have a new message';
        break;
      case PreviewPolicy.summary:
        if (aggregated == 1) {
          title = latest.title;
        }
        body = aggregated > 1
            ? 'You have $aggregated new messages'
            : (latest.preview?.isNotEmpty == true ? latest.preview! : 'You have a new message');
        break;
      case PreviewPolicy.full:
        if (aggregated == 1) {
          title = latest.title;
        }
        body = aggregated > 1
            ? 'You have $aggregated new messages, latest: ${latest.preview ?? ""}'
            : (latest.preview ?? 'You have a new message');
        break;
    }
    return (title, body);
  }

  Future<void> onAppBecameForeground() async {
    await notifier.cancelAll();
  }
}

class _Bucket {
  _Bucket(this.threadId);
  final String threadId;
  final List<IncomingMessage> messages = [];
  DateTime? lastShownAt;
  Timer? timer;
}