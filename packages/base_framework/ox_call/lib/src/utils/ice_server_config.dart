import 'dart:async';

import 'package:chatcore/chat-core.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:isar/isar.dart';
import 'package:ox_call/src/models/iceserver_db_isar.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'package:ox_common/login/login_models.dart';

/// The ICE servers a call uses, which follow the circle it is made in.
///
/// A Private Circle (on our relay) uses ours: STUN, and our TURN server to
/// carry the call when two phones cannot reach each other directly. A free
/// circle uses the TURN server its owner added under Call Server, if any, and
/// STUN otherwise; our TURN is part of the Private Circle.
class IceServerConfig {
  final List<ICEServerDBISAR> servers;

  IceServerConfig({required this.servers});

  List<Map<String, dynamic>> toRTCIceServers() {
    return servers.map(_toRTCIceServer).toList();
  }

  static Map<String, dynamic> _toRTCIceServer(ICEServerDBISAR server) => <String, dynamic>{
        'urls': server.url,
        if (server.username != null) 'username': server.username,
        if (server.credential != null) 'credential': server.credential,
      };

  static Future<IceServerConfig> forCircle(Circle circle) async {
    if (CircleApi.isPaidRelay(circle.relayUrl)) return defaultPublicConfig(circle);
    final custom = await customServers(circle.id);
    CallLogger.info('Free circle: ${custom.length} call server(s) of its own');
    return IceServerConfig(servers: [..._stun(circle.id), ...custom]);
  }

  /// The TURN server(s) added for [circleId] under Call Server.
  static Future<List<ICEServerDBISAR>> customServers(String circleId) async {
    try {
      return DBISAR.sharedInstance.isar.iCEServerDBISARs
          .where()
          .circleIdEqualTo(circleId)
          .findAll();
    } catch (e) {
      CallLogger.error('Failed to load call servers: $e');
      return [];
    }
  }

  /// Replaces the circle's call server with [server].
  static Future<void> saveCustomServer(String circleId, ICEServerDBISAR server) async {
    await DBISAR.sharedInstance.isar.writeAsync((isar) {
      isar.iCEServerDBISARs.where().circleIdEqualTo(circleId).deleteAll();
      server
        ..circleId = circleId
        ..id = isar.iCEServerDBISARs.autoIncrement();
      isar.iCEServerDBISARs.put(server);
    });
  }

  static Future<void> removeCustomServers(String circleId) async {
    await DBISAR.sharedInstance.isar.writeAsync((isar) {
      isar.iCEServerDBISARs.where().circleIdEqualTo(circleId).deleteAll();
    });
  }

  /// Whether [server] actually relays: asks it for a relay address the way
  /// a call would, with nothing but that server allowed. A wrong address,
  /// username or password all end in no relay candidate.
  static Future<bool> testTurnServer(ICEServerDBISAR server,
      {Duration timeout = const Duration(seconds: 10)}) async {
    RTCPeerConnection? pc;
    final relayFound = Completer<bool>();
    try {
      pc = await createPeerConnection({
        'iceServers': [_toRTCIceServer(server)],
        'iceTransportPolicy': 'relay',
      });
      pc.onIceCandidate = (candidate) {
        if ((candidate.candidate ?? '').contains(' typ relay') && !relayFound.isCompleted) {
          relayFound.complete(true);
        }
      };
      pc.onIceGatheringState = (state) {
        if (state == RTCIceGatheringState.RTCIceGatheringStateComplete && !relayFound.isCompleted) {
          relayFound.complete(false);
        }
      };
      // A data channel gives the offer something to gather candidates for.
      await pc.createDataChannel('turn-test', RTCDataChannelInit());
      await pc.setLocalDescription(await pc.createOffer());
      return await relayFound.future.timeout(timeout, onTimeout: () => false);
    } catch (e) {
      CallLogger.warning('Call server test failed: $e');
      return false;
    } finally {
      await pc?.close();
    }
  }

  static List<ICEServerDBISAR> _stun(String circleId) => [
        ICEServerDBISAR(circleId: circleId, url: 'stun:stun.l.google.com:19302'),
        // Our own STUN, for networks where Google's is blocked.
        ICEServerDBISAR(circleId: circleId, url: 'stun:relay.xchat.chat:3478'),
      ];

  /// Injected at build time with --dart-define=TURN_CREDENTIAL=..., from
  /// the TURN_CREDENTIAL secret in CI, because this repository is public.
  /// Empty in a local build, which then has STUN only.
  static const _turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  static IceServerConfig defaultPublicConfig(Circle circle) => IceServerConfig(
    servers: [
      ..._stun(circle.id),
      // TURN, for when no direct path exists (symmetric NAT, most mobile
      // carriers). coturn on the relay server, addressed by name so the
      // server can move without an app release. UDP first, then TCP, then
      // TLS on 5349 for networks that only let TLS out.
      if (_turnCredential.isNotEmpty) ...[
        ICEServerDBISAR(
          circleId: circle.id,
          url: 'turn:relay.xchat.chat:3478?transport=udp',
          username: 'xchat',
          credential: _turnCredential,
        ),
        ICEServerDBISAR(
          circleId: circle.id,
          url: 'turn:relay.xchat.chat:3478?transport=tcp',
          username: 'xchat',
          credential: _turnCredential,
        ),
        ICEServerDBISAR(
          circleId: circle.id,
          url: 'turns:relay.xchat.chat:5349?transport=tcp',
          username: 'xchat',
          credential: _turnCredential,
        ),
      ],
    ],
  );
}
