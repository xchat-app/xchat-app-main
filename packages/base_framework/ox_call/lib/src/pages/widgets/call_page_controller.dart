import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_call/src/call_manager.dart';
import 'package:ox_call/src/models/call_state.dart';
import 'package:ox_call/src/models/call_session.dart';
import 'package:ox_common/utils/chat_prompt_tone.dart';
import 'package:ox_common/utils/permission_utils.dart';
import 'package:ox_common/business_interface/ox_chat/call_message_type.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'package:ox_call/src/utils/call_notifications.dart';
import 'package:ox_call/src/services/call_service.dart';

/// Controller for managing call page state and business logic.
///
/// Encapsulates all interactions with CallManager,
/// exposing state via ValueNotifiers for UI consumption.
///
/// Directly listens to CallManager (not through CallService).
class CallPageController {
  CallPageController(CallSession initialSession, BuildContext context)
      : _session = initialSession,
        _context = context {
    callState$.value = _session.state;
    isConnected$.value = _session.state == CallState.connected;
    // A video call is held at arm's length, a voice call at the ear.
    isSpeakerOn$.value = _session.isVideo;
    _initialize();
  }

  // Private state
  CallSession _session;
  final BuildContext _context;
  Stopwatch? _stopwatch;
  Timer? _durationTimer;
  Timer? _autoHideTimer;
  void Function()? _removeStateListener;
  void Function()? _removeStreamListener;
  void Function()? _removeLocalStreamListener;
  bool _permissionChecked = false;

  final Completer<void> _waitInitializeCmp = Completer<void>();
  bool _isInitializing = false;
  Future<void> get waitInitialize => _waitInitializeCmp.future;

  // Video renderers
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  // Observable state
  final ValueNotifier<CallState> callState$ = ValueNotifier<CallState>(CallState.initiating);
  final ValueNotifier<bool> isConnected$ = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> duration$ = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<bool> isMuted$ = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isCameraOn$ = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isSpeakerOn$ = ValueNotifier<bool>(true);
  final ValueNotifier<bool> isControlsVisible$ = ValueNotifier<bool>(true);
  final ValueNotifier<bool> hasPopped$ = ValueNotifier<bool>(false);
  final ValueNotifier<bool> actionInProgress$ = ValueNotifier<bool>(false);

  // Derived state getters
  bool get isVideoCall => _session.isVideo;
  bool get isIncoming => _session.isIncoming;
  bool get isActionInProgress => actionInProgress$.value;
  String get sessionId => _session.sessionId;

  ValueNotifier<UserDBISAR?> get remoteUser$ => _session.remoteUser$;
  ValueNotifier<UserDBISAR?> get localUser$ => _session.localUser$;

  // Initialization
  Future<void> _initialize() async {
    if (_waitInitializeCmp.isCompleted || _isInitializing) return;
    _isInitializing = true;

    await localRenderer.initialize();
    await remoteRenderer.initialize();

    _setupListeners();
    _updateStreams();

    // Init: start ringtone. An incoming call that arrives off screen rings
    // through its notification instead.
    if (!isIncoming || CallNotifications.isAppOnScreen) {
      PromptToneManager.sharedInstance.playCalling();
    }

    // Start auto-hide timer for video calls
    if (isVideoCall) {
      _startAutoHideTimer();
    }

    // For outgoing calls: get local stream in initState (permission already checked before startCall)
    if (!isIncoming) {
      await _getLocalStream();
    }

    if (!_waitInitializeCmp.isCompleted) {
      _waitInitializeCmp.complete();
    }
    _isInitializing = false;
  }

  void _setupListeners() {
    // Directly listen to CallManager
    _removeStateListener = CallManager().addStateListener(_onCallStateChanged);
    _removeStreamListener = CallManager().addStreamListener(_onRemoteStreamReady);
    _removeLocalStreamListener = CallManager().addLocalStreamListener(_onLocalStreamReady);
    CallService.instance.answerRequested$.addListener(_answerIfRequested);
  }

  /// Answer, tapped in the incoming-call notification. Accepting needs the
  /// microphone, which this page only gets once the app is back on screen, so
  /// this runs on the request and again when the local stream is ready.
  void _answerIfRequested() {
    if (!isIncoming || CallService.instance.answerRequested$.value != _session.sessionId) return;
    if (CallManager().getLocalStream() == null || _session.state != CallState.ringing) return;
    CallService.instance.answerRequested$.value = null;
    accept();
  }

  /// Check permission and get local stream for incoming calls.
  /// Should be called after first frame is rendered (use WidgetsBinding.instance.addPostFrameCallback).
  Future<void> checkPermissionAndGetLocalStreamForIncoming() async {
    if (!isIncoming || _permissionChecked) return;
    _permissionChecked = true;
    
    final mediaType = isVideoCall ? CallMessageType.video.text : CallMessageType.audio.text;
    final hasPermission = await PermissionUtils.getCallPermission(_context, mediaType: mediaType);

    if (!hasPermission) {
      // For incoming calls, any button click should reject the call
      await reject();
      return;
    }

    // Get local stream
    await _getLocalStream();
  }

  Future<void> _getLocalStream() async {
    try {
      final localStream = await CallManager().getUserMedia(_session.callType);
      CallManager().setLocalStream(localStream);
      // The local stream will be set to renderer via _onLocalStreamReady callback
    } catch (e) {
      CallLogger.error('Failed to get local stream: $e');
      if (isIncoming) {
        await reject();
      }
    }
  }

  void _onLocalStreamReady(MediaStream stream) {
    localRenderer.srcObject = stream;
    _applySpeaker();

    // For outgoing calls: send offer after local stream is ready
    if (!isIncoming) {
      CallManager().sendOfferWhenLocalStreamReady(_session.sessionId);
    } else {
      _answerIfRequested();
    }
  }

  void _syncRingtoneWithState(CallState state) {
    final ringtoneStates = {
      CallState.idle,
      CallState.initiating,
      CallState.ringing,
      CallState.connecting,
    };
    if (!ringtoneStates.contains(state)) {
      PromptToneManager.sharedInstance.stopPlay();
    }
  }

  void _onCallStateChanged(CallSession session) {
    // Only handle events for this session
    if (session.sessionId != _session.sessionId) return;

    _session = session;
    callState$.value = session.state;

    _syncRingtoneWithState(session.state);

    if (session.state == CallState.connected && !isConnected$.value) {
      isConnected$.value = true;
    }

    if (session.state == CallState.connected) {
      _startDurationTimer();
      _updateStreams();
      _applySpeaker();
    }

    if (session.state == CallState.ended && !hasPopped$.value) {
      _stopDurationTimer();
      hasPopped$.value = true;
    }
  }

  void _onRemoteStreamReady(String sessionId, MediaStream stream) {
    if (sessionId != _session.sessionId) return;
    remoteRenderer.srcObject = stream;
  }

  void _updateStreams() {
    final localStream = CallManager().getLocalStream();
    final remoteStream = CallManager().getRemoteStream(_session.sessionId);

    if (localStream != null) {
      localRenderer.srcObject = localStream;
    }
    if (remoteStream != null) {
      remoteRenderer.srcObject = remoteStream;
    }
  }

  void _startDurationTimer() {
    final stopwatch = Stopwatch()..start();
    _stopwatch = stopwatch;
    duration$.value = stopwatch.elapsed;

    _durationTimer?.cancel();
    // Update ValueNotifier every second for UI refresh
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_stopwatch != null) {
        duration$.value = _stopwatch!.elapsed;
      }
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
    // Update final duration
    if (_stopwatch != null) {
      _stopwatch!.stop();
      duration$.value = _stopwatch!.elapsed;
      _stopwatch = null;
    }
  }

  /// Formats duration as MM:SS.
  String formatDuration(Duration duration) {
    // Round to nearest second to handle timer jitter
    // This prevents "jumping" seconds when timer delays occur
    final totalSeconds = (duration.inMilliseconds / 1000).round();
    final minutes = totalSeconds ~/ 60;
    final secs = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  // Auto-hide controls timer (for video calls)
  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 5), () {
      if (isVideoCall && isConnected$.value) {
        isControlsVisible$.value = false;
      }
    });
  }

  void _resetAutoHideTimer() {
    if (isVideoCall && isConnected$.value) {
      _startAutoHideTimer();
    }
  }

  /// Toggle controls visibility (for video calls)
  void toggleControlsVisibility() {
    isControlsVisible$.value = !isControlsVisible$.value;
    if (isControlsVisible$.value) {
      _resetAutoHideTimer();
    }
  }

  /// Show controls and reset auto-hide timer
  void showControls() {
    isControlsVisible$.value = true;
    _resetAutoHideTimer();
  }

  // Call actions
  Future<void> accept() async {
    if (actionInProgress$.value) return;
    actionInProgress$.value = true;
    try {
      await CallManager().acceptCall(_session.sessionId);
    } finally {
      actionInProgress$.value = false;
    }
  }

  Future<void> reject() async {
    if (actionInProgress$.value) return;
    actionInProgress$.value = true;
    try {
      await CallManager().rejectCall(_session.sessionId);
    } finally {
      actionInProgress$.value = false;
    }
  }

  Future<void> hangUp() async {
    if (actionInProgress$.value) return;
    actionInProgress$.value = true;
    try {
      await CallManager().endCall(_session.sessionId);
    } finally {
      actionInProgress$.value = false;
    }
  }

  Future<void> toggleMute() async {
    final newValue = !isMuted$.value;
    await CallManager().setMuted(_session.sessionId, newValue);
    isMuted$.value = newValue;
  }

  Future<void> toggleCamera() async {
    final newValue = !isCameraOn$.value;
    await CallManager().setVideoEnabled(_session.sessionId, newValue);
    isCameraOn$.value = newValue;
  }

  Future<void> toggleSpeaker() async {
    isSpeakerOn$.value = !isSpeakerOn$.value;
    await CallManager().setSpeakerOn(isSpeakerOn$.value);
  }

  /// The audio route follows [isSpeakerOn$]. Applied once audio starts, and
  /// again on connect: WebRTC picks its own route when the call's audio
  /// comes up, and the button showed one thing while the sound came from
  /// the other.
  void _applySpeaker() {
    final on = isSpeakerOn$.value;
    CallManager().setSpeakerOn(on, preferBluetooth: on);
  }

  Future<void> switchCamera() async {
    await CallManager().switchCamera(_session.sessionId);
  }

  // Cleanup
  void dispose() {
    PromptToneManager.sharedInstance.stopPlay();
    _stopDurationTimer();
    _autoHideTimer?.cancel();

    _removeStateListener?.call();
    _removeStreamListener?.call();
    _removeLocalStreamListener?.call();
    CallService.instance.answerRequested$.removeListener(_answerIfRequested);

    localRenderer.dispose();
    remoteRenderer.dispose();

    callState$.dispose();
    isConnected$.dispose();
    duration$.dispose();
    isMuted$.dispose();
    isCameraOn$.dispose();
    isSpeakerOn$.dispose();
    isControlsVisible$.dispose();
    hasPopped$.dispose();
    actionInProgress$.dispose();
  }
}