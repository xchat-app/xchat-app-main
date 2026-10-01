import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_call/src/models/iceserver_db_isar.dart';
import 'package:ox_call/src/utils/call_logger.dart';
import 'package:ox_common/login/login_models.dart';

class IceServerConfig {
  final List<ICEServerDBISAR> servers;

  IceServerConfig({required this.servers});

  List<Map<String, dynamic>> toRTCIceServers() {
    return servers.map((server) {
      return <String, dynamic>{
        'urls': server.url,
        if (server.username != null)
          'username': server.username,
        if (server.credential != null)
          'credential': server.credential,
      };
    }).toList();
  }

  static Future<IceServerConfig?> load() async {
    try {
      final currentCircleId = LoginManager.instance.currentCircle?.id;
      if (currentCircleId == null) {
        CallLogger.warning('No active circle');
        return null;
      }

      final isar = DBISAR.sharedInstance.isar;
      final servers = isar.iCEServerDBISARs
          .where()
          .circleIdEqualTo(currentCircleId)
          .findAll();

      if (servers.isEmpty) {
        CallLogger.warning('ICE server list empty for circle $currentCircleId');
        return null;
      }

      CallLogger.info('Loaded ${servers.length} ICE servers');
      return IceServerConfig(servers: servers);
    } catch (e) {
      CallLogger.error('Failed to load ICE server config: $e');
      return null;
    }
  }

  static Future<void> save(IceServerConfig config) async {
    final currentCircleId = LoginManager.instance.currentCircle?.id;
    if (currentCircleId == null) {
      CallLogger.warning('No active circle, skip saving ICE servers');
      return;
    }

    final isar = DBISAR.sharedInstance.isar;
    await isar.writeAsync((isar) async {
      // Clean old records for this circle
      isar.iCEServerDBISARs
          .where()
          .circleIdEqualTo(currentCircleId)
          .deleteAll();

      // set auto increment id
      final servers = config.servers.map((server) {
        server.id = isar.iCEServerDBISARs.autoIncrement();
        return server;
      }).toList();

      // Insert new records
      isar.iCEServerDBISARs.putAll(servers);
    });
  }

  /// Injected at build time with --dart-define=TURN_CREDENTIAL=..., from
  /// the TURN_CREDENTIAL secret in CI, because this repository is public.
  /// Empty in a local build, which then has STUN only.
  static const _turnCredential = String.fromEnvironment('TURN_CREDENTIAL');

  static IceServerConfig defaultPublicConfig(Circle circle) => IceServerConfig(
    servers: [
      // STUN server (free, for NAT traversal)
      ICEServerDBISAR(
        circleId: circle.id,
        url: 'stun:stun.l.google.com:19302',
      ),
      // Our own STUN, for networks where Google's is blocked.
      ICEServerDBISAR(
        circleId: circle.id,
        url: 'stun:relay.xchat.chat:3478',
      ),
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