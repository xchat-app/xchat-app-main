import 'dart:async';

import 'package:chatcore/chat-core.dart';
import 'package:flutter/widgets.dart';
import 'package:ox_chat/page/session/chat_message_page.dart';
import 'package:ox_chat/utils/general_handler/chat_general_handler.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/scheme/scheme_helper.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/utils/web_url_helper.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_home/widgets/session_view_model.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_chat/utils/widget_tool.dart';

enum ShareSearchType {
  friends,
  groups,
  recentChats,
}

class ShareSearchGroup {
  final String title;
  final ShareSearchType type;
  final List<SessionListViewModel> items;

  ShareSearchGroup({
    required this.title,
    required this.type,
    required this.items,
  });
}

class ChatChooseSharePage extends StatefulWidget {
  final Key? key;
  final String msg;
  final String type; // text, image , file
  final String? path;

  ChatChooseSharePage({this.key, required this.msg, this.type = 'text', this.path}) : super(key: key);

  @override
  _ChatChooseSharePageState createState() => _ChatChooseSharePageState();
}

class _ChatChooseSharePageState extends State<ChatChooseSharePage> {
  List<ShareSearchGroup> _recentChatList = [];
  List<ShareSearchGroup> _showChatList = [];
  String receiverPubkey = '';
  ValueNotifier<bool> _isClear = ValueNotifier(false);
  TextEditingController _controller = TextEditingController();
  final maxItemsCount = 3;

  @override
  void initState() {
    super.initState();
    _fetchListAsync();
    _controller.addListener(() {
      if (_controller.text.isNotEmpty) {
        _isClear.value = true;
      } else {
        _isClear.value = false;
      }
    });
  }

  Future<void> _fetchListAsync() async {
    List<SessionListViewModel> sessions = OXChatBinding.sharedInstance.sessionList.map(
            (e) => SessionListViewModel(e)).toList();
    sessions.sort((session1, session2) {
      return session2.sessionModel.createTime.compareTo(
          session1.sessionModel.createTime);
    });
    ShareSearchGroup searchGroup = ShareSearchGroup(
      title: 'str_recent_chats'.commonLocalized(),
      type: ShareSearchType.recentChats,
      items: sessions,
    );
    _recentChatList.add(searchGroup);
    _showChatList = _recentChatList;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_chat.select_chat'),
      ),
      body: LoseFocusWrap(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: CLLayout.horizontalPadding,
            left: CLLayout.horizontalPadding,
            right: CLLayout.horizontalPadding,
          ),
          child: CLSearch(
            controller: _controller,
            onChanged: _handlingSearch,
          ),
        ),
        Expanded(
          child: CLSectionListView(
            items: _buildSectionItems(),
            padding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  List<SectionListViewItem> _buildSectionItems() {
    return _showChatList.map((group) {
      final listItems = group.items.map((item) {
        return CustomItemModel(
          leading: _buildItemIcon(item),
          titleWidget: CLText.bodyLarge(
            item.name,
            customColor: ColorToken.onSurface.of(context),
            maxLines: 1,
          ),
          onTap: () => buildSendPressed(item),
        );
      }).toList();

      return SectionListViewItem(
        data: listItems,
        header: group.title,
      );
    }).toList();
  }

  Widget _buildItemIcon(SessionListViewModel item) {
    return ValueListenableBuilder(
        valueListenable: item.entity$,
        builder: (context, entity, _) {
          return ValueListenableBuilder(
              valueListenable: item.groupMember$,
              builder: (context, groupMember, _) {
                final size = 30.px;
                if (entity is UserDBISAR) {
                  return OXUserAvatar(
                    user: entity,
                    size: size,
                    isCircular: true,
                  );
                } else {
                  return SmartGroupAvatar(
                    groupId: item.sessionModel.groupId,
                    size: size,
                  );
                }
              }
          );
        }
    );
  }

  void _handlingSearch(String searchQuery) {
    setState(() {
      if (searchQuery.isEmpty) {
        _showChatList = _recentChatList;
      } else {
        List<ShareSearchGroup> searchResult = [];
        List<SessionListViewModel> friendSessions = [];
        List<SessionListViewModel> groupSessions = [];

        final allSession = _recentChatList.expand((e) => e.items).toList();
        for (var item in allSession) {
          if (!item.name.toLowerCase().contains(searchQuery.toLowerCase())) continue;

          if (item.isSingleChat) {
            friendSessions.add(item);
          } else {
            groupSessions.add(item);
          }
        }

        if (friendSessions.isNotEmpty) {
          searchResult.add(ShareSearchGroup(
            title: 'str_title_contacts'.commonLocalized(),
            type: ShareSearchType.friends,
            items: friendSessions,
          ));
        }

        if (groupSessions.isNotEmpty) {
          searchResult.add(ShareSearchGroup(
            title: 'str_title_groups'.commonLocalized(),
            type: ShareSearchType.groups,
            items: groupSessions,
          ));
        }

        _showChatList = searchResult;
      }
    });
  }

  buildSendPressed(SessionListViewModel item) async {
    final result = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_common.tips'),
      content: 'str_share_msg_confirm_content'
          .localized({r'${name}': item.name}),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.str_share'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    );

    if (result != true) return;

    final chatId = item.sessionModel.chatId;
    if (widget.type == SchemeShareType.text.typeText) {
      OXLoading.show();
      final urlPreviewData = await WebURLHelper.getPreviewData(
          widget.msg,
          isShare: true);
      OXLoading.dismiss();

      final title = urlPreviewData?.title ?? '';
      final link = urlPreviewData?.link ?? '';
      if (urlPreviewData != null && title.isNotEmpty && link.isNotEmpty) {
        ChatMessageSendEx.sendTemplateMessage(
          receiverPubkey: chatId,
          title: title,
          subTitle: urlPreviewData.description ?? '',
          icon: urlPreviewData.image?.url ?? '',
          link: link,
        );
      } else {
        ChatMessageSendEx.sendTextMessageHandler(
          chatId,
          widget.msg,
        );
      }
    } else if (widget.type == SchemeShareType.image.typeText) {
      ChatMessageSendEx.staticSendImageMessageWithFile(
        receiverPubkey: chatId,
        imageFilePath: widget.path ?? '',
      );
    } else if (widget.type == SchemeShareType.video.typeText) {
      ChatMessageSendEx.staticSendVideoMessageWithFile(
        receiverPubkey: chatId,
        videoFilePath: widget.path ?? '',
      );
    }

    if (!mounted) return;

    OXNavigator.pop(context);
    ChatMessagePage.open(
      context: context,
      communityItem: item.sessionModel,
      unreadMessageCount: item.sessionModel.unreadCount,
    );
  }
}
