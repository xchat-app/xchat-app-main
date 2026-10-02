import 'dart:io';

import 'package:flutter/services.dart';
import 'package:ox_call/src/models/call_session.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'package:ox_localizable/ox_localizable.dart';

/// The Android foreground service held for the length of a call
/// (VoiceCallService).
///
/// Android silences the microphone, and stops the camera, of an app that is
/// not on screen unless a foreground service of that type is running, so
/// switching away mid-call left the other side hearing nothing. The service
/// also shows the ongoing-call notification, from which the user can return
/// to the call or hang up.
class CallForegroundService {
  CallForegroundService._();

  static const MethodChannel _channel = MethodChannel('com.oxchat.global/call');
  static bool _running = false;

  /// [onHangUp] runs when the user taps Hang Up in the notification.
  static void listenForHangUp(Future<void> Function() onHangUp) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onHangUpFromNotification') {
        CallLogger.info('Hang up from the call notification');
        await onHangUp();
      }
    });
  }

  /// Call while the app is on screen (the user just started or answered the
  /// call): Android refuses to start a microphone service from the background.
  static Future<void> start(CallSession session) async {
    if (!Platform.isAndroid || _running) return;
    final remote = session.remoteUser$.value;
    try {
      _running = await _channel.invokeMethod<bool>('startVoiceCallService', {
            'remoteName': remote?.name ?? remote?.shortEncodedPubkey ?? '',
            'isVideo': session.isVideo,
            'content': Localized.text(session.isVideo ? 'ox_chat.video_call' : 'ox_chat.voice_call'),
            'hangUpLabel': Localized.text('ox_chat.call_hang_up'),
          }) ??
          false;
    } catch (e) {
      CallLogger.error('Failed to start the call service: $e');
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid || !_running) return;
    _running = false;
    try {
      await _channel.invokeMethod('stopVoiceCallService');
    } catch (e) {
      CallLogger.error('Failed to stop the call service: $e');
    }
  }
}
