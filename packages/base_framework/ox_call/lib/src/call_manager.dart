import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:chatcore/chat-core.dart';
import 'package:nostr_core_dart/nostr.dart' show SignalingState, generate64RandomHexChars;
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_call/src/models/call_state.dart';
import 'package:ox_call/src/models/call_error.dart';
import 'package:ox_call/src/models/call_session.dart';
import 'package:ox_call/src/models/call_device_info.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'package:ox_call/src/utils/background_keep_alive.dart';
import 'package:ox_call/src/utils/call_notifications.dart';
import 'package:ox_call/src/utils/ice_server_config.dart';
import 'package:ox_call/src/device_manager.dart';
import 'package:ox_common/utils/permission_utils.dart';
import 'package:ox_common/business_interface/ox_chat/call_message_type.dart';
import 'package:ox_common/navigator/navigator.dart';

// Extensions (using part files to access private members)
part 'call_manager_signaling.dart';
part 'call_manager_call_lifecycle.dart';
part 'call_manager_webrtc.dart';
part 'call_manager_media.dart';
part 'call_manager_session.dart';
part 'call_manager_timer.dart';
part 'call_manager_device.dart';
part 'call_manager_error.dart';

typedef CallStateCallback = void Function(CallSession session);
typedef CallErrorCallback = void Function(CallSession session, CallError error);
typedef RemoteStreamCallback = void Function(String sessionId, MediaStream stream);
typedef LocalStreamCallback = void Function(MediaStream stream);

/// Core call manager for WebRTC call logic.
///
/// Manages call sessions, peer connections, and media streams.
/// Coordinates with signaling layer (Contacts) for call setup.
class CallManager {
  static final CallManager _instance = CallManager._internal();
  factory CallManager() => _instance;
  CallManager._internal();

  // State storage
  final Map<String, CallSession> _activeSessions = {};
  final Map<String, RTCPeerConnection?> _peerConnections = {};
  MediaStream? _localStream;
  final Map<String, MediaStream?> _remoteStreams = {};
  final Map<String, Timer?> _offerTimers = {};

  /// Cache for ICE candidates received before PeerConnection is ready.
  /// Key: sessionId, Value: list of pending candidates
  final Map<String, List<RTCIceCandidate>> _pendingCandidates = {};

  /// Set of ended session IDs, used to filter out-of-order messages.
  /// Sessions are kept here for a short period (e.g., 30 seconds) after ending
  /// to handle delayed signaling messages.
  final Set<String> _endedSessions = {};

  /// Set of session IDs currently being ended, used to prevent concurrent _endCall execution.
  /// This prevents race conditions when both sides hang up simultaneously.
  final Set<String> _endingSessions = {};

  /// Multiple listeners support
  final List<CallStateCallback> _stateCallbacks = [];
  final List<CallErrorCallback> _errorCallbacks = [];
  final List<RemoteStreamCallback> _streamCallbacks = [];
  final List<LocalStreamCallback> _localStreamCallbacks = [];

  bool _initialized = false;
  final BackgroundKeepAlive _backgroundKeepAlive = BackgroundKeepAlive();

  /// Add a state change listener. Returns a function to remove the listener.
  void Function() addStateListener(CallStateCallback callback) {
    _stateCallbacks.add(callback);
    return () => _stateCallbacks.remove(callback);
  }

  /// Add an error listener. Returns a function to remove the listener.
  void Function() addErrorListener(CallErrorCallback callback) {
    _errorCallbacks.add(callback);
    return () => _errorCallbacks.remove(callback);
  }

  /// Add a remote stream listener. Returns a function to remove the listener.
  void Function() addStreamListener(RemoteStreamCallback callback) {
    _streamCallbacks.add(callback);
    return () => _streamCallbacks.remove(callback);
  }

  /// Add a local stream listener. Returns a function to remove the listener.
  void Function() addLocalStreamListener(LocalStreamCallback callback) {
    _localStreamCallbacks.add(callback);
    return () => _localStreamCallbacks.remove(callback);
  }

  /// Whether this circle can start calls. A call needs a TURN server
  /// wherever two phones cannot connect directly: a Private Circle has ours,
  /// a free circle only the one its owner added under Call Server.
  static Future<bool> canStartCallInCurrentCircle() async {
    final circle = LoginManager.instance.currentCircle;
    if (circle == null) return false;
    if (CircleApi.isPaidRelay(circle.relayUrl)) return true;
    return (await IceServerConfig.customServers(circle.id)).isNotEmpty;
  }

  /// Initialize the call manager.
  Future<void> initialize() async {
    if (_initialized) return;
    _setupSignalingListener();
    _initialized = true;
    CallLogger.info('CallManager initialized');
  }

  void _setupSignalingListener() {
    Contacts.sharedInstance.onCallStateChange = (
      String friend,
      SignalingState state,
      String data,
      String? offerId,
      String? groupId,
    ) {
      _handleSignalingMessage(friend, state, data, offerId, groupId);
    };
  }

  // Public API - Session access
  CallSession? getSession(String sessionId) {
    return _getSession(sessionId);
  }

  MediaStream? getLocalStream() {
    return _localStream;
  }

  MediaStream? getRemoteStream(String sessionId) {
    return _remoteStreams[sessionId];
  }

  List<CallSession> getActiveSessions() {
    return _getAllSessions();
  }
}
