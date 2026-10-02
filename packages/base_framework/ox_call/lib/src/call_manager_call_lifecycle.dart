part of 'call_manager.dart';

/// Extension for managing call lifecycle (start, accept, reject, end).
extension CallManagerCallLifecycle on CallManager {
  /// Start a call to a target.
  ///
  /// [target] - The call target (pubkey + privateGroupId)
  /// [callType] - Audio or video call
  /// [additionalParticipants] - Additional participants for group calls
  Future<void> startCall({
    required UserDBISAR target,
    required String privateGroupId,
    required CallType callType,
    List<UserDBISAR>? additionalParticipants,
  }) async {
    // Check permission before starting call
    final mediaType = callType == CallType.video
        ? CallMessageType.video.text
        : CallMessageType.audio.text;
    final context = OXNavigator.rootContext;
    
    final hasPermission = await PermissionUtils.getCallPermission(
      context,
      mediaType: mediaType,
    );
    if (!hasPermission) {
      // Permission dialog already shown by getCallPermission
      CallLogger.warning('Call permission denied, aborting call start');
      return;
    }

    final sessionId = _generateSessionId();
    final currentPubkey = Account.sharedInstance.currentPubkey;

    final participantPubkeys = [
      currentPubkey,
      target.pubKey,
      ...?additionalParticipants?.map((t) => t.pubKey),
    ];

    final session = CallSession(
      sessionId: sessionId,
      privateGroupId: privateGroupId,
      localPubkey: currentPubkey,
      remotePubkey: target.pubKey,
      participantPubkeys: participantPubkeys,
      callType: callType,
      direction: CallDirection.outgoing,
      state: CallState.initiating,
      startTime: DateTime.now().millisecondsSinceEpoch,
    );

    _addSession(sessionId, session);
    _notifyStateChange(session);

    try {
      await _backgroundKeepAlive.configureForCall();
      await _backgroundKeepAlive.activate();
      await CallForegroundService.start(session);
    } catch (e) {
      CallLogger.error('Failed to start call: $e');
      await _handleError(sessionId, CallErrorType.unknown, 'Failed to start call: $e', e);
    }
  }

  /// Send offer after local stream is ready.
  /// This should be called by CallPageController when local stream is acquired.
  Future<void> sendOfferWhenLocalStreamReady(String sessionId) async {
    final session = _getSession(sessionId);
    if (session == null) {
      CallLogger.error('Session not found for sessionId: $sessionId');
      return;
    }

    if (session.isIncoming) {
      CallLogger.warning('sendOfferWhenLocalStreamReady called for non-outgoing call');
      return;
    }

    if (_localStream == null) {
      CallLogger.error('Local stream not found when sending offer');
      return;
    }

    try {
      final peerConnection = await _createPeerConnection(sessionId);
      _peerConnections[sessionId] = peerConnection;

      for (final track in _localStream!.getTracks()) {
        await peerConnection.addTrack(track, _localStream!);
      }

      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);

      final offerSdp = offer.sdp ?? '';
      final offerJson = jsonEncode({
        'sdp': offerSdp,
        'type': offer.type,
        'media': session.isVideo ? 'video' : 'audio',
        'privateGroupId': session.privateGroupId,
      });

      CallLogger.debug(
        'Send offer, friendPubkey: ${session.remotePubkey}, '
        'privateGroupId: ${session.privateGroupId}, '
      );
      await Contacts.sharedInstance.sendOffer(
        session.sessionId,
        session.remotePubkey,
        session.privateGroupId,
        offerJson,
      );

      _updateSession(sessionId, state: CallState.ringing);
      _startOfferTimer(sessionId);
    } catch (e) {
      CallLogger.error('Failed to send offer: $e');
      await _handleError(sessionId, CallErrorType.unknown, 'Failed to send offer: $e', e);
    }
  }

  Future<void> acceptCall(String sessionId) async {
    final session = _getSession(sessionId);
    if (session == null) {
      CallLogger.error('Session not found for sessionId: $sessionId');
      return;
    }

    if (session.state != CallState.ringing) {
      CallLogger.error('Cannot accept call in state: ${session.state}');
      return;
    }

    if (session.remoteSdp == null) {
      CallLogger.error('Remote SDP not found for session: ${session.sessionId}');
      await rejectCall(sessionId, 'error');
      return;
    }

    CallLogger.info('Accepting call: sessionId=${session.sessionId}');

    _updateSession(session.sessionId, state: CallState.connecting);

    try {
      // Note: Permission check and local stream acquisition are now handled by CallPageController
      // The local stream should already be set when user clicks accept
      
      if (_localStream == null) {
        CallLogger.error('Local stream not found when accepting call');
        await rejectCall(sessionId, 'error');
        return;
      }

      final peerConnection = await _createPeerConnection(session.sessionId);
      _peerConnections[session.sessionId] = peerConnection;

      for (final track in _localStream!.getTracks()) {
        await peerConnection.addTrack(track, _localStream!);
      }
      CallLogger.debug('Added ${_localStream!.getTracks().length} tracks to PeerConnection');

      await peerConnection.setRemoteDescription(
        RTCSessionDescription(session.remoteSdp!, 'offer'),
      );

      // Apply any pending ICE candidates that arrived before PeerConnection was ready
      await _applyPendingCandidates(session.sessionId);

      final answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);

      final answerSdp = answer.sdp ?? '';
      final answerJson = jsonEncode({
        'sdp': answerSdp,
        'type': answer.type,
      });

      await Contacts.sharedInstance.sendAnswer(
        session.sessionId,
        session.remotePubkey,
        session.privateGroupId,
        answerJson,
      );

      await _backgroundKeepAlive.configureForCall();
      await _backgroundKeepAlive.activate();
      await CallForegroundService.start(session);

      CallLogger.info('Answer sent: sessionId=${session.sessionId}');
    } catch (e) {
      CallLogger.error('Failed to accept call: $e');
      await _handleError(session.sessionId, CallErrorType.unknown, 'Failed to accept call: $e', e);
    }
  }

  Future<void> rejectCall(String sessionId, [String? reason]) async {
    final session = _getSession(sessionId);
    if (session == null) {
      CallLogger.error('Session not found for offerId: $sessionId');
      return;
    }

    CallLogger.info('Rejecting call: sessionId=${session.sessionId}, privateGroupId: ${session.privateGroupId}');

    final disconnectContent = jsonEncode({'reason': reason ?? 'reject'});
    await Contacts.sharedInstance.sendDisconnect(
      sessionId,
      session.remotePubkey,
      session.privateGroupId,
      disconnectContent,
    );

    await _endCall(session.sessionId, CallEndReason.reject);
  }

  Future<void> endCall(String sessionId) async {
    CallLogger.info('Ending call: sessionId=$sessionId');

    final session = _getSession(sessionId);
    if (session == null) return;

    final disconnectContent = jsonEncode({'reason': 'hangUp'});
    await Contacts.sharedInstance.sendDisconnect(
      session.sessionId,
      session.remotePubkey,
      session.privateGroupId,
      disconnectContent,
    );

    await _endCall(sessionId, CallEndReason.hangup);
  }

  Future<void> _endCall(String sessionId, CallEndReason reason) async {
    // Prevent concurrent execution of _endCall for the same session
    if (_endingSessions.contains(sessionId)) {
      CallLogger.debug('_endCall already in progress for session: $sessionId, ignoring duplicate call');
      return;
    }

    final session = _getSession(sessionId);
    if (session == null) {
      // Session may have been removed by another concurrent _endCall
      CallLogger.debug('Session not found for _endCall: $sessionId (may have been ended already)');
      return;
    }

    // Mark as ending to prevent concurrent execution
    _endingSessions.add(sessionId);

    try {
      _pendingCandidates.remove(sessionId);

      final endTime = DateTime.now().millisecondsSinceEpoch;
      final duration = endTime - session.startTime;

      session.state = CallState.ended;
      session.endTime = endTime;
      session.endReason = reason;
      session.duration = duration;

      _notifyStateChange(session);

      await _cleanupSession(sessionId);
      _removeSession(sessionId);

      // Mark session as ended to filter out-of-order messages
      _markSessionAsEnded(sessionId);

      if (!_hasActiveSessions()) {
        await _backgroundKeepAlive.deactivate();
        await CallForegroundService.stop();
      }
    } finally {
      // Always remove from ending set, even if an error occurred
      _endingSessions.remove(sessionId);
    }
  }

  Future<void> _cleanupSession(String sessionId) async {
    _cancelOfferTimer(sessionId);
    _pendingCandidates.remove(sessionId);

    final peerConnection = _peerConnections[sessionId];
    if (peerConnection != null) {
      await peerConnection.close();
      _peerConnections.remove(sessionId);
    }

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) => track.stop());
      _localStream = null;
    }

    final remoteStream = _remoteStreams[sessionId];
    if (remoteStream != null) {
      remoteStream.getTracks().forEach((track) => track.stop());
      _remoteStreams.remove(sessionId);
    }
  }
}