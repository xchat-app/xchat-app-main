part of 'call_manager.dart';

/// Extension for managing WebRTC PeerConnection and connection state.
extension CallManagerWebRTC on CallManager {
  Future<RTCPeerConnection> _createPeerConnection(String sessionId) async {
    final circle = LoginManager.instance.currentCircle;
    if (circle == null) {
      throw 'No active circle for creating peer connection';
    }

    final iceServerConfig = await IceServerConfig.forCircle(circle);

    final iceServers = iceServerConfig.toRTCIceServers();
    CallLogger.debug('Creating PeerConnection with ${iceServers.length} ICE servers: $iceServers');

    final configuration = <String, dynamic>{
      'iceServers': iceServers,
    };

    final peerConnection = await createPeerConnection(configuration);
    CallLogger.debug('PeerConnection created successfully');

    peerConnection.onIceCandidate = (RTCIceCandidate candidate) {
      _sendIceCandidate(sessionId, candidate);
    };

    peerConnection.onConnectionState = (RTCPeerConnectionState state) {
      _handleConnectionStateChange(sessionId, state);
    };

    peerConnection.onIceConnectionState = (RTCIceConnectionState state) {
      _handleIceConnectionStateChange(sessionId, state);
    };

    peerConnection.onAddStream = (MediaStream stream) {
      _handleRemoteStream(sessionId, stream);
    };

    peerConnection.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _handleRemoteStream(sessionId, event.streams[0]);
      }
    };

    return peerConnection;
  }

  void _handleConnectionStateChange(String sessionId, RTCPeerConnectionState state) {
    CallLogger.debug('Connection state changed: sessionId=$sessionId, state=$state');

    final session = _getSession(sessionId);
    if (session == null) return;

    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _updateSession(sessionId, state: CallState.connected);
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        if (session.state != CallState.ended) {
          _endCall(sessionId, CallEndReason.networkError);
        }
        break;
      default:
        break;
    }
  }

  void _handleIceConnectionStateChange(String sessionId, RTCIceConnectionState state) {
    CallLogger.debug('ICE connection state changed: sessionId=$sessionId, state=$state');

    final session = _getSession(sessionId);
    if (session == null) return;

    switch (state) {
      case RTCIceConnectionState.RTCIceConnectionStateConnected:
      case RTCIceConnectionState.RTCIceConnectionStateCompleted:
        if (session.state == CallState.connecting) {
          _updateSession(sessionId, state: CallState.connected);
        }
        break;
      case RTCIceConnectionState.RTCIceConnectionStateFailed:
        _handleError(sessionId, CallErrorType.iceFailed, 'ICE connection failed', null);
        break;
      case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        if (session.state == CallState.connected) {
          _updateSession(sessionId, state: CallState.reconnecting);
        }
        break;
      default:
        break;
    }
  }

  void _handleRemoteStream(String sessionId, MediaStream stream) {
    CallLogger.info('Remote stream received: sessionId=$sessionId');
    _remoteStreams[sessionId] = stream;
    for (final callback in _streamCallbacks) {
      callback(sessionId, stream);
    }
  }
}