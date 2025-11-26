import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:chatcore/chat-core.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:ox_common/component.dart';
import 'package:ox_localizable/ox_localizable.dart';

class MessageDetailPage extends StatefulWidget {
  const MessageDetailPage({
    super.key,
    required this.message,
    this.previousPageTitle,
  });

  final types.Message message;
  final String? previousPageTitle;

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  MessageDBISAR? _messageDB;
  OKEvent? _okEvent;

  @override
  void initState() {
    super.initState();
    _loadMessageData();
  }

  Future<void> _loadMessageData() async {
    try {
      final messageDB = await Messages.sharedInstance.loadMessageDBFromDB(widget.message.id);
      _messageDB = messageDB;
      if (messageDB != null) {
        final sendOkEvent = messageDB.sendOkEvent;
        if (sendOkEvent != null && sendOkEvent.isNotEmpty) {
          final data = jsonDecode(sendOkEvent);
          _okEvent = OKEvent.deserialize(data);
        }
      }
    } finally {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_chat.message_detail'),
        previousPageTitle: widget.previousPageTitle,
      ),
      isSectionListPage: true,
      body: _messageDB == null
          ? Center(child: CLText(Localized.text('ox_chat.message_detail_not_found')))
          : CLSectionListView(
        items: [
          _buildMessagePropertiesSection(),
          if (_okEvent != null) _buildSendEventSection(),
        ],
      ),
    );
  }

  SectionListViewItem _buildMessagePropertiesSection() {
    return SectionListViewItem(
      header: Localized.text('ox_chat.message_properties'),
      data: [
        _buildLabelItem('messageId', _messageDB!.messageId),
        _buildLabelItem('sender', _messageDB!.sender),
        _buildLabelItem('groupId', _messageDB!.groupId),
        _buildLabelItem('kind', _messageDB!.kind.toString()),
        _buildLabelItem('tags', _messageDB!.tags),
        _buildLabelItem('createTime', _formatTimestamp(_messageDB!.createTime)),
        _buildLabelItem('type', _messageDB!.type),
        _buildLabelItem('decryptContent', _messageDB!.decryptContent),
      ],
    );
  }

  SectionListViewItem _buildSendEventSection() {
    return SectionListViewItem(
      header: Localized.text('ox_chat.send_event_info'),
      data: [
        _buildLabelItem('eventId', _okEvent!.eventId),
        _buildLabelItem('status', _okEvent!.status ? 'Success' : 'Failed'),
        _buildLabelItem('message', _okEvent!.message),
      ],
    );
  }

  LabelItemModel _buildLabelItem(String title, String value) {
    return LabelItemModel(
      title: title,
      value$: ValueNotifier(value.isEmpty ? '-' : value),
      maxLines: null,
      overflow: TextOverflow.fade,
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}