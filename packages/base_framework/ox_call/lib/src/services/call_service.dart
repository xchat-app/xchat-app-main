import 'package:flutter/widgets.dart';
import 'package:ox_call/ox_call.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/chat_prompt_tone.dart';
import 'package:ox_call/src/call_manager.dart';
import 'package:ox_call/src/models/call_state.dart';
import 'package:ox_call/src/models/call_session.dart';
import 'package:ox_call/src/pages/call_page.dart';
import 'package:ox_call/src/utils/call_notifications.dart';

class CallService with WidgetsBindingObserver {
  CallService._();

  static final CallService _instance = CallService._();
  static CallService get instance => _instance;

  bool _initialized = false;
  bool _isCallPageShowing = false;
  String? _currentSessionId;
  void Function()? _removeStateListener;

  /// The incoming call the user answered from the notification. The call page
  /// accepts it once it has the microphone, which it only gets after the app
  /// is back on screen. [_answerAny] stands for "the next incoming call": Answer
  /// on a call the push service rang, before the app had the call itself.
  final ValueNotifier<String?> answerRequested$ = ValueNotifier<String?>(null);
  static const String _answerAny = '*';
  DateTime? _answerAnyUntil;

  bool isAnswerRequestedFor(CallSession session) {
    final requested = answerRequested$.value;
    if (requested == session.sessionId) return true;
    return requested == _answerAny &&
        session.isIncoming &&
        (_answerAnyUntil?.isAfter(DateTime.now()) ?? false);
  }

  void _requestAnswer(String sessionId) {
    if (sessionId.isEmpty) {
      _answerAnyUntil = DateTime.now().add(const Duration(seconds: 60));
      answerRequested$.value = _answerAny;
    } else {
      answerRequested$.value = sessionId;
    }
  }

  /// Initialize the call service.
  /// Should be called after CallManager is initialized.
  void initialize() {
    if (_initialized) return;
    _removeStateListener = CallManager().addStateListener(_onCallStateChanged);
    WidgetsBinding.instance.addObserver(this);
    CallNotifications.listen(
      onHangUp: () async {
        for (final session in CallManager().getActiveSessions()) {
          await CallManager().endCall(session.sessionId);
        }
      },
      onAnswer: _requestAnswer,
      onDecline: (sessionId) => CallManager().rejectCall(sessionId),
    );
    _initialized = true;
    CallNotifications.takePendingAnswer().then((answer) {
      if (answer) _requestAnswer('');
    });
    // Started from a call the push service rang: its notification keeps
    // ringing until the call page takes over (below), or is cleared here if
    // no call turns up, the caller having hung up meanwhile.
    Future.delayed(const Duration(seconds: 15), () {
      final ringing = CallManager().getActiveSessions().any(
          (session) => session.isIncoming && session.state == CallState.ringing);
      if (!ringing) CallNotifications.cancelIncoming();
    });
  }

  /// Cleanup the call service.
  void cleanup() {
    _removeStateListener?.call();
    _removeStateListener = null;
    WidgetsBinding.instance.removeObserver(this);
    CallNotifications.cancelIncoming();
    answerRequested$.value = null;
    _isCallPageShowing = false;
    _currentSessionId = null;
    _initialized = false;
  }

  void _onCallStateChanged(CallSession session) {
    // Handle incoming call - show call page
    if (session.state == CallState.ringing && session.isIncoming) {
      _showCallPage(session);
      // Off screen, the page is pushed but nobody sees or hears it. On screen
      // it rings itself, so a ringing notification the push service posted
      // before the app was running goes.
      if (CallNotifications.isAppOnScreen) {
        CallNotifications.cancelIncoming();
      } else {
        CallNotifications.showIncoming(session);
      }
      return;
    }

    // Answered, declined, cancelled by the caller or timed out.
    if (session.isIncoming) {
      CallNotifications.cancelIncoming();
      if (answerRequested$.value == session.sessionId &&
          session.state != CallState.connecting) {
        answerRequested$.value = null;
      }
    }

    // Handle outgoing call - show call page if not showing
    if ((session.state == CallState.ringing ||
            session.state == CallState.connecting ||
            session.state == CallState.initiating) &&
        !session.isIncoming &&
        !_isCallPageShowing) {
      _showCallPage(session);
      return;
    }

    // Handle call ended - update tracking state
    if (session.state == CallState.ended &&
        _currentSessionId == session.sessionId) {
      _isCallPageShowing = false;
      _currentSessionId = null;
    }
  }

  void _showCallPage(CallSession session) {
    if (_isCallPageShowing) return;

    final context = OXNavigator.navigatorKey.currentContext;
    if (context == null) return;

    _isCallPageShowing = true;
    _currentSessionId = session.sessionId;

    OXNavigator.pushPage(
      null,
      (context) => CallPage(session: session),
      type: OXPushPageType.present,
      fullscreenDialog: true,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ringing = CallManager().getActiveSessions().where(
        (session) => session.isIncoming && session.state == CallState.ringing);
    if (ringing.isEmpty) return;
    final session = ringing.first;
    if (state == AppLifecycleState.resumed) {
      // Back on screen: the call page rings, unless this is the user answering.
      CallNotifications.cancelIncoming();
      if (!isAnswerRequestedFor(session)) {
        PromptToneManager.sharedInstance.playCalling();
      }
    } else if (state == AppLifecycleState.paused) {
      PromptToneManager.sharedInstance.stopPlay();
      CallNotifications.showIncoming(session);
    }
  }

  /// Notify that call page has been dismissed.
  /// Called by CallPage when it's popped.
  void notifyCallPageDismissed() {
    _isCallPageShowing = false;
    _currentSessionId = null;
  }

  /// Check if call page is currently showing.
  bool get isCallPageShowing => _isCallPageShowing;

  /// Get current call session ID.
  String? get currentSessionId => _currentSessionId;
}