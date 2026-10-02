import 'local_push_kit.dart';
import 'ports.dart';

class LocalNotifier implements Notifier {
  LocalNotifier(this._kit, this._channelId, this._channelName, this._channelDesc);
  final LocalPushKit _kit;
  final String _channelId;
  final String _channelName;
  final String _channelDesc;

  @override
  Future<void> showMessage({
    required String threadId,
    required String title,
    required String body,
    required bool high,
  }) async {
    final nid = threadId.hashCode & 0x7fffffff; // stable per thread
    await _kit.showInstant(
      id: nid,
      title: title,
      body: body,
      payload: 'thread:$threadId',
      androidGroupKey: threadId,
      iOSThreadId: threadId,
      channelId: _channelId,
      channelName: _channelName,
      channelDescription: _channelDesc,
      high: high,
    );
  }

  @override
  Future<void> cancelAll() => _kit.cancelAllExceptCalls();
}