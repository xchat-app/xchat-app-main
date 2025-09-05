import 'package:json_annotation/json_annotation.dart';
import 'package:meta/meta.dart';

import '../message.dart';
import '../user.dart' show User;

// part 'system_message.g.dart'; // TODO: Restore when json_serializable generation is available

/// A class that represents a system message (anything around chat management). Use [metadata] to store anything
/// you want.
@JsonSerializable()
@immutable
abstract class SystemMessage extends Message {
  /// Creates a custom message.
  const SystemMessage._({
    required super.author,
    required super.createdAt,
    required super.id,
    super.sourceKey,
    super.metadata,
    super.remoteId,
    super.repliedMessage,
    super.repliedMessageId,
    super.roomId,
    super.showStatus,
    super.status,
    required this.text,
    MessageType? type,
    super.updatedAt,
    super.expiration,
    super.reactions,
    super.zapsInfoList,
    super.isMe,
  }) : super(type: type ?? MessageType.system);

  const factory SystemMessage({
    required User author,
    required int createdAt,
    required String id,
    dynamic sourceKey,
    Map<String, dynamic>? metadata,
    String? remoteId,
    Message? repliedMessage,
    String? repliedMessageId,
    String? roomId,
    bool? showStatus,
    Status? status,
    required String text,
    MessageType? type,
    int? updatedAt,
    int? expiration,
    List<Reaction> reactions,
    List<ZapsInfo> zapsInfoList,
    bool isMe,
  }) = _SystemMessage;

  /// Creates a custom message from a map (decoded JSON).
  factory SystemMessage.fromJson(Map<String, dynamic> _json) =>
      throw UnimplementedError('JSON deserialization temporarily disabled');

  /// System message content (could be text or translation key).
  @Deprecated('Always empty. Use metadata for system message rendering.')
  final String text;

  @override
  String get content => metadata?['localTextKey'] ?? text;

  /// Equatable props.
  @override
  List<Object?> get props => [
        author,
        createdAt,
        id,
        metadata,
        remoteId,
        repliedMessage,
        roomId,
        showStatus,
        status,
        text,
        updatedAt,
        expiration,
      ];

  @override
  Message copyWith({
    User? author,
    int? createdAt,
    String? id,
    dynamic sourceKey,
    Map<String, dynamic>? metadata,
    String? remoteId,
    Message? repliedMessage,
    String? repliedMessageId,
    String? roomId,
    bool? showStatus,
    Status? status,
    String? text,
    int? updatedAt,
    EncryptionType? fileEncryptionType,
    String? decryptKey,
    String? decryptNonce,
    int? expiration,
    List<Reaction>? reactions,
    List<ZapsInfo>? zapsInfoList,
    bool? isMe,
  });

  /// Converts a custom message to the map representation,
  /// encodable to JSON.
  @override
  Map<String, dynamic> toJson() => throw UnimplementedError('JSON serialization temporarily disabled');
}

/// A utility class to enable better copyWith.
class _SystemMessage extends SystemMessage {

  @override
  bool get viewWithoutBubble => true;

  const _SystemMessage({
    required super.author,
    required super.createdAt,
    required super.id,
    super.sourceKey,
    super.metadata,
    super.remoteId,
    super.repliedMessage,
    super.repliedMessageId,
    super.roomId,
    super.showStatus,
    super.status,
    required super.text,
    super.type,
    super.updatedAt,
    super.expiration,
    super.reactions,
    super.zapsInfoList,
    super.isMe,
  }) : super._();

  @override
  Message copyWith({
    User? author,
    int? createdAt,
    String? id,
    dynamic sourceKey,
    dynamic metadata = _Unset,
    dynamic remoteId = _Unset,
    dynamic repliedMessage = _Unset,
    String? repliedMessageId,
    dynamic roomId,
    dynamic showStatus = _Unset,
    dynamic status = _Unset,
    String? text,
    dynamic updatedAt = _Unset,
    EncryptionType? fileEncryptionType,
    String? decryptKey,
    String? decryptNonce,
    int? expiration,
    List<Reaction>? reactions,
    List<ZapsInfo>? zapsInfoList,
    dynamic isMe = _Unset,
  }) =>
      _SystemMessage(
        author: author ?? this.author,
        createdAt: createdAt ?? this.createdAt,
        id: id ?? this.id,
        sourceKey: sourceKey ?? this.sourceKey,
        metadata: metadata == _Unset
            ? this.metadata
            : metadata as Map<String, dynamic>?,
        remoteId: remoteId == _Unset ? this.remoteId : remoteId as String?,
        repliedMessage: repliedMessage == _Unset
            ? this.repliedMessage
            : repliedMessage as Message?,
        repliedMessageId: repliedMessageId ?? this.repliedMessageId,
        roomId: roomId == _Unset ? this.roomId : roomId as String?,
        showStatus:
            showStatus == _Unset ? this.showStatus : showStatus as bool?,
        status: status == _Unset ? this.status : status as Status?,
        text: text ?? this.text,
        updatedAt: updatedAt == _Unset ? this.updatedAt : updatedAt as int?,
        expiration: expiration ?? this.expiration,
        reactions: reactions ?? this.reactions,
        zapsInfoList: zapsInfoList ?? this.zapsInfoList,
        isMe: isMe == _Unset ? this.isMe : isMe as bool,
      );
}

class _Unset {}
