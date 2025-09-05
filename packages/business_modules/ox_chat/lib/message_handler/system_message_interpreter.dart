import 'package:ox_localizable/ox_localizable.dart';

typedef Detector = bool Function(String content);

// Record typedefs (tuples) for params of different system types
typedef GenericParams = ({String text});
typedef InviteChatParams = ({String inviter, String text});

class SystemMessageInterpreter {
  // Regex: "<name> invite you to join the private chat|group"
  static final RegExp _reInvite = RegExp(
    r'^(.+?) invite you to join the private (chat|group)$',
    caseSensitive: false,
  );
  // Regex: "Private chat created!" / "Private group created!" (exclamation mark optional)
  static final RegExp _rePrivateChatCreated = RegExp(
    r'^Private chat created!?$',
    caseSensitive: false,
  );
  static final RegExp _rePrivateGroupCreated = RegExp(
    r'^Private group created!?$',
    caseSensitive: false,
  );
  // Regex: "You have been removed from the group" (exclamation mark optional)
  static final RegExp _reRemovedFromGroup = RegExp(
    r'^You have been removed from the group!?$',
    caseSensitive: false,
  );
  // Regex: "<userName> left the group" (exclamation mark optional)
  static final RegExp _reUserLeftGroup = RegExp(
    r'^(.+?) left the group!?$',
    caseSensitive: false,
  );
  // Regex: "<userName> joined the group" (exclamation mark optional)
  static final RegExp _reUserJoinedGroup = RegExp(
    r'^(.+?) joined the group!?$',
    caseSensitive: false,
  );

  static final List<SystemSpec> _specs = [
    SystemSpec(
      detect: (content) => _rePrivateChatCreated.hasMatch(content),
      sysType: SystemType.generic,
      toParams: (content) {
        return (text: Localized.text('ox_chat.private_chat_created'));
      },
    ),
    SystemSpec(
      detect: (content) => _rePrivateGroupCreated.hasMatch(content),
      sysType: SystemType.generic,
      toParams: (content) {
        return (text: Localized.text('ox_chat.private_group_created'));
      },
    ),
    SystemSpec(
      detect: (content) => _reRemovedFromGroup.hasMatch(content),
      sysType: SystemType.generic,
      toParams: (content) {
        return (text: Localized.text('ox_chat.removed_from_group'));
      },
    ),
    SystemSpec(
      detect: (content) => _reUserLeftGroup.hasMatch(content),
      sysType: SystemType.generic,
      toParams: (content) {
        final match = _reUserLeftGroup.firstMatch(content)!;
        final userName = match.group(1) ?? '';
        return (text: Localized.text('ox_chat.user_left_group').replaceAll(r'${userName}', userName));
      },
    ),
    SystemSpec(
      detect: (content) => _reUserJoinedGroup.hasMatch(content),
      sysType: SystemType.generic,
      toParams: (content) {
        final match = _reUserJoinedGroup.firstMatch(content)!;
        final userName = match.group(1) ?? '';
        return (text: Localized.text('ox_chat.user_joined_group').replaceAll(r'${userName}', userName));
      },
    ),
    SystemSpec(
      detect: (content) {
        final match = _reInvite.firstMatch(content);
        return match != null && match.group(2)?.toLowerCase() == 'chat';
      },
      sysType: SystemType.invitePrivateChat,
      toParams: (content) {
        final match = _reInvite.firstMatch(content)!;
        final inviter = match.group(1) ?? '';
        return (inviter: inviter, text: Localized.text('ox_chat.invite_private_chat').replaceAll(r'${userName}', inviter));
      },
    ),
    SystemSpec(
      detect: (content) {
        final match = _reInvite.firstMatch(content);
        return match != null && match.group(2)?.toLowerCase() == 'group';
      },
      sysType: SystemType.invitePrivateGroup,
      toParams: (content) {
        final match = _reInvite.firstMatch(content)!;
        final inviter = match.group(1) ?? '';
        return (inviter: inviter, text: Localized.text('ox_chat.invite_private_group').replaceAll(r'${userName}', inviter));
      },
    ),
  ];

  SystemMeta interpret(String messageId, String content) {
    SystemSpec? best;
    for (final spec in _specs) {
      if (spec.detect(content)) {
        best = spec;
        break;
      }
    }

    if (best != null) {
      return SystemMeta(
        messageId: messageId,
        sysType: best.sysType,
        parsedAt: DateTime.now(),
        params: best.toParams(content),
      );
    }

    // fallback: generic system message with raw text as params
    return SystemMeta(
      messageId: messageId,
      sysType: SystemType.generic,
      parsedAt: DateTime.now(),
      params: (text: content),
    );
  }

  static String getSystemMessageText(String content) {
    try {
      final interpreter = SystemMessageInterpreter();
      return interpreter.interpret('', content).text;
    } catch (_) {}
    return content;
  }
}

enum SystemType {
  generic,
  invitePrivateChat,
  invitePrivateGroup,
}

class SystemMeta {
  final String messageId;
  final SystemType sysType;
  final DateTime parsedAt;
  /// Params are typed records (records/tuples) per sysType:
  /// - generic: GenericParams
  /// - inviteChat: InviteChatParams
  final Object params;

  String get text => switch (sysType) {
    SystemType.generic => (params as GenericParams).text,
    SystemType.invitePrivateChat ||
    SystemType.invitePrivateGroup => (params as InviteChatParams).text,
  };

  const SystemMeta({
    required this.messageId,
    required this.sysType,
    required this.parsedAt,
    required this.params,
  });

  Map<String, dynamic> toMap() {
    return {
      SystemMetaFields.messageId: messageId,
      SystemMetaFields.sysType: sysType.name,
      SystemMetaFields.parsedAt: parsedAt.millisecondsSinceEpoch,
      SystemMetaFields.params: _paramsToMap(),
    };
  }

  Map<String, dynamic> _paramsToMap() {
    switch (sysType) {
      case SystemType.invitePrivateChat:
      case SystemType.invitePrivateGroup:
        final p = params as InviteChatParams;
        return {'inviter': p.inviter, 'text': p.text};
      case SystemType.generic:
        final p = params as GenericParams;
        return {'text': p.text};
    }
  }

  static SystemMeta? fromMap(Map<String, dynamic> map) {
    if (!map.containsKey(SystemMetaFields.sysType) ||
        !map.containsKey(SystemMetaFields.params)) return null;

    final sysTypeName = map[SystemMetaFields.sysType] as String?;
    final sysType = SystemType.values.firstWhere(
      (e) => e.name == sysTypeName,
      orElse: () => SystemType.generic,
    );
    final paramsMap = Map<String, dynamic>.from((map[SystemMetaFields.params] as Map?) ?? const {});

    return SystemMeta(
      messageId: (map[SystemMetaFields.messageId] as String?) ?? '',
      sysType: sysType,
      parsedAt: DateTime.fromMillisecondsSinceEpoch(
        (map[SystemMetaFields.parsedAt] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
      params: _paramsFromMap(sysType, paramsMap),
    );
  }

  static Object _paramsFromMap(SystemType st, Map<String, dynamic> m) {
    switch (st) {
      case SystemType.invitePrivateChat:
      case SystemType.invitePrivateGroup:
        return (inviter: (m['inviter'] as String?) ?? '', text: (m['text'] as String?) ?? '');
      case SystemType.generic:
        return (text: (m['text'] as String?) ?? '');
    }
  }
}

class SystemMetaFields {
  static const String messageId = 'messageId';
  static const String sysType = 'sysType';
  static const String priority = 'priority';
  static const String specVersion = 'specVersion';
  static const String parsedAt = 'parsedAt';
  static const String params = 'params';
}

extension SystemMetaMapX on Map<String, dynamic>? {
  SystemType get sysTypeEnum {
    final name = this?[SystemMetaFields.sysType] as String?;
    return SystemType.values.firstWhere(
      (e) => e.name == (name ?? SystemType.generic.name),
      orElse: () => SystemType.generic,
    );
  }
  int get metaPriority => (this?[SystemMetaFields.priority] as int?) ?? 0;
  int get metaSpecVersion => (this?[SystemMetaFields.specVersion] as int?) ?? 1;
  DateTime get metaParsedAt {
    final ts = this?[SystemMetaFields.parsedAt] as int?;
    return DateTime.fromMillisecondsSinceEpoch(ts ?? 0, isUtc: false);
  }
  String get metaMessageId => (this?[SystemMetaFields.messageId] as String?) ?? '';

  Map<String, dynamic> get metaParamsMap =>
      Map<String, dynamic>.from(this?[SystemMetaFields.params] as Map? ?? const {});

  // Typed helpers
  GenericParams get genericParams =>
      (text: (metaParamsMap['text'] as String?) ?? '');
  InviteChatParams get inviteChatParams =>
      (inviter: (metaParamsMap['inviter'] as String?) ?? '', text: (metaParamsMap['text'] as String?) ?? '');
}

class SystemSpec {
  final Detector detect;
  final SystemType sysType;
  final Object Function(String content) toParams; // returns the record for this sysType
  const SystemSpec({
    required this.detect,
    required this.toParams,
    required this.sysType,
  });
}