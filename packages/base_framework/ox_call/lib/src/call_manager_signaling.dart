part of 'call_manager.dart';

/// Extension for handling signaling messages (offer, answer, candidate, disconnect).
extension CallManagerSignaling on CallManager {
  void _handleSignalingMessage(
    String friend,
    SignalingState state,
    String data,
    String? offerId,
    String? groupId,
  ) {
    CallLogger.debug('Received signaling: friend=$friend, state=$state, offerId=$offerId');

    switch (state) {
      case SignalingState.offer:
        _handleOffer(friend, data, offerId, groupId);
        break;
      case SignalingState.answer:
        _handleAnswer(friend, data, offerId);
        break;
      case SignalingState.candidate:
        _handleCandidate(friend, data, offerId);
        break;
      case SignalingState.disconnect:
        _handleDisconnect(friend, data, offerId);
        break;
    }
  }

  Future<void> _handleOffer(String caller, String data, String? offerId, String? groupId) async {
    if (offerId == null || offerId.isEmpty || groupId == null || groupId.isEmpty) return;

    // Check if this session was already ended (out-of-order message)
    if (_isSessionEnded(offerId)) {
      CallLogger.debug('Ignoring offer for ended session: offerId=$offerId');
      return;
    }

    // Check if this session already exists and is ended
    final existingSession = _getSession(offerId);
    if (existingSession != null && existingSession.state == CallState.ended) {
      CallLogger.debug('Ignoring offer for ended session: offerId=$offerId');
      return;
    }

    CallLogger.info('Received offer: offerId=$offerId');
    String privateGroupId = '';

    try {
      final offerData = jsonDecode(data) as Map<String, dynamic>;
      final sdp = offerData['sdp'] as String;
      final media = offerData['media'] as String? ?? 'audio';
      final callType = media == 'video' ? CallType.video : CallType.audio;
      privateGroupId = offerData['privateGroupId'];

      final sessionId = offerId;
      if (offerId.isEmpty) {
        CallLogger.warning('offerId is empty');
        return;
      }
      if (privateGroupId.isEmpty) {
        CallLogger.warning('privateGroupId is empty');
        return;
      }

      // Check if already in a call
      if (_hasActiveSessions()) {
        CallLogger.warning('Already in a call, rejecting incoming call');
        final disconnectContent = jsonEncode({'reason': 'inCalling'});
        await Contacts.sharedInstance.sendDisconnect(
          sessionId,
          caller,
          privateGroupId,
          disconnectContent,
        );
        return;
      }

      final currentPubkey = Account.sharedInstance.currentPubkey;

      final session = CallSession(
        sessionId: sessionId,
        privateGroupId: privateGroupId,
        localPubkey: currentPubkey,
        remotePubkey: caller,
        participantPubkeys: [caller, currentPubkey],
        callType: callType,
        direction: CallDirection.incoming,
        state: CallState.ringing,
        startTime: DateTime.now().millisecondsSinceEpoch,
        remoteSdp: sdp,
      );

      _addSession(sessionId, session);
      _notifyStateChange(session);

      _startOfferTimer(sessionId);

      CallLogger.info('Incoming call ringing: offerId=$offerId, waiting for user to accept');
    } catch (e) {
      CallLogger.error('Failed to handle offer: $e');
      final disconnectContent = jsonEncode({'reason': 'error'});
      await Contacts.sharedInstance.sendDisconnect(
        offerId,
        caller,
        privateGroupId,
        disconnectContent,
      );
    }
  }

  Future<void> _handleAnswer(String callee, String data, String? offerId) async {
    if (offerId == null) return;

    // Check if this session was already ended (out-of-order message)
    if (_isSessionEnded(offerId)) {
      CallLogger.debug('Ignoring answer for ended session: offerId=$offerId');
      return;
    }

    final session = _getSession(offerId);
    if (session == null) {
      CallLogger.warning('Session not found for offerId: $offerId (may be ended or not created yet)');
      return;
    }

    // Ignore answer for ended sessions (out-of-order message)
    if (session.state == CallState.ended) {
      CallLogger.debug('Ignoring answer for ended session: offerId=$offerId');
      return;
    }

    CallLogger.info('Received answer: offerId=$offerId');

    try {
      final answerData = jsonDecode(data) as Map<String, dynamic>;
      final sdp = answerData['sdp'] as String;

      final peerConnection = _peerConnections[session.sessionId];
      if (peerConnection == null) {
        CallLogger.error('PeerConnection not found for session: ${session.sessionId}');
        return;
      }

      await peerConnection.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'),
      );

      // Apply any pending ICE candidates that arrived before answer
      await _applyPendingCandidates(session.sessionId);

      _updateSession(session.sessionId, state: CallState.connecting);
      CallLogger.info('Answer processed: offerId=$offerId');
    } catch (e) {
      CallLogger.error('Failed to handle answer: $e');
      await _handleError(session.sessionId, CallErrorType.sdpSetupFailed, 'Failed to handle answer: $e', e);
    }
  }

  Future<void> _handleCandidate(String peer, String data, String? offerId) async {
    if (offerId == null) return;

    // Check if this session was already ended (out-of-order message)
    if (_isSessionEnded(offerId)) {
      CallLogger.debug('Ignoring candidate for ended session: offerId=$offerId');
      return;
    }

    final session = _getSession(offerId);
    if (session == null) {
      CallLogger.debug('Session not found for offerId: $offerId (candidate may be late or session ended)');
      return;
    }

    // Ignore candidates for ended sessions (out-of-order message)
    if (session.state == CallState.ended) {
      CallLogger.debug('Ignoring candidate for ended session: offerId=$offerId');
      return;
    }

    try {
      final candidateData = jsonDecode(data) as Map<String, dynamic>;
      final candidate = candidateData['candidate'] as String;
      final sdpMLineIndex = candidateData['sdpMLineIndex'] as int?;
      final sdpMid = candidateData['sdpMid'] as String?;

      final iceCandidate = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
      final peerConnection = _peerConnections[session.sessionId];

      if (peerConnection == null) {
        // Cache candidate for later when PeerConnection is ready
        _pendingCandidates.putIfAbsent(session.sessionId, () => []).add(iceCandidate);
        CallLogger.debug('Cached ICE candidate for session: ${session.sessionId} (PeerConnection not ready yet)');
      } else {
        await peerConnection.addCandidate(iceCandidate);
        CallLogger.debug('ICE candidate added: offerId=$offerId');
      }
    } catch (e) {
      CallLogger.error('Failed to handle candidate: $e');
    }
  }

  /// Apply pending ICE candidates to a PeerConnection.
  /// Call this after creating PeerConnection and setting remote description.
  Future<void> _applyPendingCandidates(String sessionId) async {
    final pendingCandidates = _pendingCandidates.remove(sessionId);
    if (pendingCandidates == null || pendingCandidates.isEmpty) {
      return;
    }

    final peerConnection = _peerConnections[sessionId];
    if (peerConnection == null) {
      CallLogger.warning('Cannot apply pending candidates: PeerConnection not found for session: $sessionId');
      return;
    }

    CallLogger.info('Applying ${pendingCandidates.length} pending ICE candidates for session: $sessionId');
    for (final candidate in pendingCandidates) {
      try {
        await peerConnection.addCandidate(candidate);
        CallLogger.debug('Applied pending ICE candidate');
      } catch (e) {
        CallLogger.error('Failed to apply pending candidate: $e');
      }
    }
  }

  Future<void> _handleDisconnect(String peer, String data, String? offerId) async {
    if (offerId == null) return;

    // Check if this session was already ended (duplicate disconnect)
    if (_isSessionEnded(offerId)) {
      CallLogger.debug('Ignoring duplicate disconnect for ended session: offerId=$offerId');
      return;
    }

    final session = _getSession(offerId);
    if (session == null) {
      CallLogger.debug('Session not found for offerId: $offerId (may have been ended already)');
      return;
    }

    // Ignore duplicate disconnect messages
    if (session.state == CallState.ended) {
      CallLogger.debug('Ignoring disconnect for already ended session: offerId=$offerId');
      return;
    }

    CallLogger.info('Received disconnect: offerId=$offerId');

    try {
      final disconnectData = jsonDecode(data) as Map<String, dynamic>;
      final reason = disconnectData['reason'] as String? ?? 'unknown';

      CallEndReason endReason;
      switch (reason) {
        case 'hangUp':
          endReason = CallEndReason.hangup;
          break;
        case 'reject':
          endReason = CallEndReason.reject;
          break;
        case 'timeout':
          endReason = CallEndReason.timeout;
          break;
        case 'inCalling':
          endReason = CallEndReason.busy;
          break;
        default:
          endReason = CallEndReason.unknown;
      }

      await _endCall(session.sessionId, endReason);
    } catch (e) {
      CallLogger.error('Failed to handle disconnect: $e');
      await _endCall(session.sessionId, CallEndReason.unknown);
    }
  }

  Future<void> _sendIceCandidate(String sessionId, RTCIceCandidate candidate) async {
    final session = _getSession(sessionId);
    if (session == null) return;

    try {
      final candidateJson = jsonEncode({
        'candidate': candidate.candidate,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'sdpMid': candidate.sdpMid,
      });

      await Contacts.sharedInstance.sendCandidate(
        session.sessionId,
        session.remotePubkey,
        session.privateGroupId,
        candidateJson,
      );

      // Send to additional participants
      for (final participantPubkey in session.participantPubkeys) {
        if (participantPubkey != session.remotePubkey &&
            participantPubkey != session.localPubkey) {
          await Contacts.sharedInstance.sendCandidate(
            session.sessionId,
            participantPubkey,
            session.privateGroupId,
            candidateJson,
          );
          CallLogger.debug('ICE candidate sent to additional participant: $participantPubkey');
        }
      }
    } catch (e) {
      CallLogger.error('Failed to send ICE candidate: $e');
    }
  }
}