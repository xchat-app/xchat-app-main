import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ox_call/src/models/call_session.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'package:ox_localizable/ox_localizable.dart';

/// Android's system UI for calls, driven from here.
///
/// - The ongoing call: a foreground service (VoiceCallService) held for the
///   length of the call. Android silences the microphone, and stops the
///   camera, of an app that is not on screen unless such a service is
///   running, so switching away mid-call left the other side hearing nothing.
///   Its notification returns to the call or hangs up.
/// - The incoming call while the app is off screen: a ringing notification
///   (IncomingCallNotification) with Answer and Decline. Without it the call
///   page opened inside the backgrounded app and nothing rang.
class CallNotifications {
  CallNotifications._();

  static const MethodChannel _channel = MethodChannel('com.oxchat.global/call');
  static bool _ongoing = false;

  /// Whether the app is in front of the user, so the call page itself rings.
  static bool get isAppOnScreen {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  /// Actions taken in the notifications, outside the app.
  static void listen({
    required Future<void> Function() onHangUp,
    required void Function(String sessionId) onAnswer,
    required Future<void> Function(String sessionId) onDecline,
  }) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      final sessionId = call.arguments is String ? call.arguments as String : '';
      CallLogger.info('Call notification action: ${call.method} $sessionId');
      switch (call.method) {
        case 'onHangUpFromNotification':
          await onHangUp();
        case 'onAnswerFromNotification':
          // Empty when the push service rang it: answer the call that arrives.
          onAnswer(sessionId);
        case 'onDeclineFromNotification':
          if (sessionId.isNotEmpty) await onDecline(sessionId);
      }
    });
  }

  /// Call while the app is on screen (the user just started or answered the
  /// call): Android refuses to start a microphone service from the background.
  static Future<void> startOngoing(CallSession session) async {
    if (!Platform.isAndroid || _ongoing) return;
    try {
      _ongoing = await _channel.invokeMethod<bool>('startVoiceCallService', {
            ..._describe(session),
            'hangUpLabel': Localized.text('ox_chat.call_hang_up'),
          }) ??
          false;
    } catch (e) {
      CallLogger.error('Failed to start the call service: $e');
    }
  }

  static Future<void> stopOngoing() async {
    if (!Platform.isAndroid || !_ongoing) return;
    _ongoing = false;
    try {
      await _channel.invokeMethod('stopVoiceCallService');
    } catch (e) {
      CallLogger.error('Failed to stop the call service: $e');
    }
  }

  static Future<void> showIncoming(CallSession session) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('showIncomingCall', {
        ..._describe(session),
        'sessionId': session.sessionId,
        'answerLabel': Localized.text('ox_chat.call_accept'),
        'declineLabel': Localized.text('ox_chat.call_decline'),
      });
    } catch (e) {
      CallLogger.error('Failed to show the incoming call: $e');
    }
  }

  /// Also clears one the push service rang while the app was not running.
  static Future<void> cancelIncoming() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('cancelIncomingCall');
    } catch (e) {
      CallLogger.error('Failed to cancel the incoming call: $e');
    }
  }

  /// Whether the app was started by Answer on a call the push service rang
  /// (no session yet: the offer arrives once the app has synced).
  static Future<bool> takePendingAnswer() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('takePendingCallAnswer') ?? false;
    } catch (e) {
      CallLogger.error('Failed to read a pending answer: $e');
      return false;
    }
  }

  static Map<String, Object> _describe(CallSession session) {
    final remote = session.remoteUser$.value;
    return {
      'remoteName': remote?.name ?? remote?.shortEncodedPubkey ?? '',
      'isVideo': session.isVideo,
      'content': Localized.text(session.isVideo ? 'ox_chat.video_call' : 'ox_chat.voice_call'),
    };
  }
}
