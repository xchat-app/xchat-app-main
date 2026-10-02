import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:ox_chat/manager/chat_draft_manager.dart';
import 'package:ox_chat/message_handler/chat_message_builder.dart';
import 'package:ox_chat/message_handler/chat_message_helper.dart';
import 'package:ox_chat/manager/chat_page_config.dart';
import 'package:ox_chat/page/contacts/contact_user_info_page.dart';
import 'package:ox_chat/page/contacts/groups/group_info_page.dart';
import 'package:ox_chat/utils/chat_voice_helper.dart';
import 'package:ox_chat/utils/general_handler/chat_general_handler.dart';
import 'package:ox_chat/widget/chat_highlight_message_widget.dart';
import 'package:ox_chat/utils/general_handler/chat_mention_handler.dart';
import 'package:ox_chat/utils/general_handler/message_data_controller.dart';
import 'package:ox_chat_ui/ox_chat_ui.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_call/ox_call.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_module_service/ox_module_service.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_common/utils/chat_prompt_tone.dart';
import 'package:ox_common/utils/extension.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';
import 'package:ox_common/utils/platform_utils.dart';
import 'package:ox_common/utils/web_url_helper.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../utils/general_handler/chat_highlight_message_handler.dart';
import 'chat_icons.dart';

class CommonChatWidget extends StatefulWidget {
  CommonChatWidget({
    required this.handler,
    this.title,
    this.showUserNames = false,
    this.customTopWidget,
    this.customCenterWidget,
    this.customBottomWidget,
    this.bottomHintParam,
  });

  // Basic

  final ChatGeneralHandler handler;

  final String? title;
  final bool showUserNames;

  // Custom

  final Widget? customTopWidget;
  final Widget? customCenterWidget;
  final Widget? customBottomWidget;
  final ChatHintParam? bottomHintParam;

  @override
  State<StatefulWidget> createState() => CommonChatWidgetState();
}

class CommonChatWidgetState extends State<CommonChatWidget> with OXChatObserver {

  ChatGeneralHandler get handler => widget.handler;
  ChatSessionModelISAR get session => handler.session;
  MessageDataController get dataController => handler.dataController;
  ChatHighlightMessageHandler get highlightMessageHandler => handler.highlightMessageHandler;

  final pageConfig = ChatPageConfig();

  final GlobalKey<ChatState> chatWidgetKey = GlobalKey<ChatState>();
  final FocusNode pageFocusNode = FocusNode();
  final AutoScrollController scrollController = AutoScrollController();
  Duration scrollDuration = const Duration(milliseconds: 100);

  // Use ValueNotifier to control scroll to bottom widget visibility
  final ValueNotifier<bool> isShowScrollToBottomWidget$ = ValueNotifier<bool>(false);
  
  // Controller for managing input height related UI refresh
  late final InputHeightController _inputHeightController;

  @override
  void initState() {
    super.initState();
    // Initialize input height controller
    _inputHeightController = InputHeightController();
    
    // Listen to reply message changes and rebuild input height
    handler.replyHandler.replyMessageNotifier.addListener(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputHeightController.rebuild();
      });
    });

    tryInitDraft();
    tryInitReply();
    mentionStateInitialize();
    if (!handler.isPreviewMode) {
      PromptToneManager.sharedInstance.isCurrencyChatPage = dataController.isMentionInCurrentSession;
      OXChatBinding.sharedInstance.msgIsReaded = dataController.isInCurrentSession;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      handler.chatWidgetKey = chatWidgetKey;

      OXChatBinding.sharedInstance.clearUnreadCount(
        chatId: session.chatId,
      );
    });

    OXChatBinding.sharedInstance.addObserver(this);
  }

  void tryInitDraft() {
    final draft = session.draft ?? '';
    if (draft.isEmpty) return ;

    handler.inputController.text = draft;
    ChatDraftManager.shared.updateTempDraft(session.chatId, draft);
  }

  void tryInitReply() async {
    final replyMessageId = session.replyMessageId ?? '';
    if (replyMessageId.isEmpty) return ;

    final message = (await dataController.getLocalMessageWithIds([replyMessageId])).firstOrNull;
    if (message == null) return ;

    handler.replyHandler.updateReplyMessage(message);
  }

  void mentionStateInitialize() {
    if (session.isMentioned) {
      OXChatBinding.sharedInstance.updateMentionStatus(
        chatId: session.chatId,
        isMentioned: false,
      );
    }
  }

  @override
  void dispose() {
    OXChatBinding.sharedInstance.removeObserver(this);
    PromptToneManager.sharedInstance.isCurrencyChatPage = null;
    OXChatBinding.sharedInstance.msgIsReaded = null;
    ChatDraftManager.shared.updateSessionDraft(session.chatId);
    isShowScrollToBottomWidget$.dispose();
    _inputHeightController.dispose();
    handler.dispose();

    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    if (widget.handler.isPreviewMode) {
      return Column(
        children: [
          buildAppBar(),
          Expanded(child: buildChatContentWidget()),
        ],
      );
    }

    return CLScaffold(
      appBar: buildAppBar(),
      resizeToAvoidBottomInset: false,
      body: pasteActionListenerWrapper(
        child: buildChatContentWidget(),
      ),
    );
  }

  void _onAppBarTap() {
    if (session.isSelfChat) return;
    if (session.isSingleChat) {
      OXNavigator.pushPage(context, (_) => ContactUserInfoPage(
        chatId: session.chatId,
        user: handler.otherUser,
      ));
    } else {
      final groupId = session.groupId;
      if (groupId == null || groupId.isEmpty) return;
      final group = Groups.sharedInstance.getPrivateGroupNotifier(groupId);
      OXNavigator.pushPage(context, (_) => GroupInfoPage(
        privateGroupId: group.value.privateGroupId,
      ));
    }
  }

  CLAppBar buildAppBar() {
    return CLAppBar(
      leading: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _onAppBarTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CLButton.back(),
            SizedBox(width: 16.px),
            buildAppBarAvatar(),
            SizedBox(width: 8.px),
            CLText.labelLarge(widget.title ?? ''),
            if (session.isSelfChat)
              Padding(
                padding: EdgeInsetsDirectional.only(start: 8.px),
                child: ChatIconWidget.selfAuthIcon(context),
              )
          ],
        ),
      ),
      title: session.isSelfChat
          ? null
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _onAppBarTap,
              child: const SizedBox.expand(),
            ),
      actions: buildAppBarActions(),
    );
  }

  Widget buildAppBarAvatar() {
    if (session.isSingleChat) {
      return buildUserAvatar();
    } else {
      return buildGroupAvatar();
    }
  }

  Widget buildUserAvatar() {
    // Check if this is a self chat, show note icon
    if (session.isSelfChat) {
      return _buildSelfChatIcon(36.px);
    }
    
    return OXUserAvatar(
      chatId: session.chatId,
      user: handler.otherUser,
      size: 36.px,
      onReturnFromNextPage: () {
        if (!mounted) return;
        setState(() {});
      },
    );
  }

  Widget _buildSelfChatIcon(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFE5E5), // Light pink background
      ),
      child: Center(
        child: Container(
          width: size * 0.5,
          height: size * 0.6,
          decoration: BoxDecoration(
            color: const Color(0xFFE53935), // Red color
            borderRadius: BorderRadius.circular(4.px),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.px, vertical: 3.px),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Top line (shorter, like a title)
                Container(
                  width: size * 0.25,
                  height: 2.px,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(1.px),
                  ),
                ),
                SizedBox(height: 2.5.px),
                // Three lines below (body text)
                Container(
                  width: size * 0.35,
                  height: 2.px,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(1.px),
                  ),
                ),
                SizedBox(height: 2.5.px),
                Container(
                  width: size * 0.3,
                  height: 2.px,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(1.px),
                  ),
                ),
                SizedBox(height: 2.5.px),
                Container(
                  width: size * 0.32,
                  height: 2.px,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(1.px),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildGroupAvatar() {
    final groupId = session.groupId;
    if (groupId == null) return const SizedBox();

    return ValueListenableBuilder<GroupDBISAR>(
      valueListenable: Groups.sharedInstance.getPrivateGroupNotifier(groupId),
      builder: (context, group, child) {
        return Container(
          alignment: Alignment.center,
          child: SmartGroupAvatar(
            group: group,
            size: 36.px,
            onTap: () async {
              await OXModuleService.pushPage(context, 'ox_chat', 'GroupInfoPage', {
                'groupId': group.privateGroupId,
              });
              if (!mounted) return;
              setState(() {});
            },
          ),
        );
      },
    );
  }

  List<Widget> buildAppBarActions() {
    if (!session.isSingleChat) return [];
    
    // Don't show call buttons for self chat
    if (session.isSelfChat) return [];

    // Calls are a paid-circle feature.
    if (!CallManager.isAvailableInCurrentCircle) return [];
    
    final otherUser = handler.otherUser;
    if (otherUser == null) return [];
    return [
      CLButton.icon(
        iconName: 'icon_message_call.png',
        package: 'ox_chat',
        iconSize: 24.px,
        onTap: () => _startCall(otherUser, CallType.audio),
      ),
      CLButton.icon(
        iconName: 'icon_message_camera.png',
        package: 'ox_chat',
        iconSize: 24.px,
        onTap: () => _startCall(otherUser, CallType.video),
      ),
    ];
  }

  Future<void> _startCall(UserDBISAR user, CallType callType) async {
    try {
      String groupId = session.groupId ?? '';
      if (groupId.isEmpty) {
        groupId = session.chatId;
      }
      if (groupId.isEmpty) {
        throw Exception('PrivateGroupId is empty');
      }

      await CallManager().startCall(
        target: user,
        privateGroupId: groupId,
        callType: callType,
      );
    } catch (e) {
      if (mounted) {
        CommonToast.instance.show(context, e.toString());
      }
    }
  }

  Widget buildChatContentWidget() {
    return ValueListenableBuilder(
        valueListenable: dataController.messageValueNotifier,
        builder: (BuildContext context, messages, Widget? child) {
          return Chat(
            key: chatWidgetKey,
            inputHeightController: _inputHeightController,
            uiConfig: ChatUIConfig(
              avatarBuilder: (message) => OXUserAvatar(
                user: message.author.sourceObject,
                size: 40.px,
                isCircular: true,
                isClickable: true,
                onReturnFromNextPage: () {
                  setState(() { });
                },
                onLongPress: () {
                  final user = message.author.sourceObject;
                  if (user != null)
                    handler.mentionHandler?.addMentionText(user);
                },
              ),
              contextMenuBuilder: (context, message, child) => pageConfig.contextMenuBuilder(
                context: context,
                message: message,
                child: child,
                handler: handler,
              ),
              customMessageBuilder: ({
                required types.CustomMessage message,
                required int messageWidth,
                required BorderRadius borderRadius,
              }) => ChatMessageBuilder.buildCustomMessage(
                message: message,
                messageWidth: messageWidth,
                borderRadius: borderRadius,
                receiverPubkey: handler.otherUser?.pubKey,
                messageUpdateCallback: (newMessage) {
                  dataController.updateMessage(newMessage);
                },
                isSelfChat: handler.session.isSelfChat,
              ),
              systemMessageBuilder: ChatMessageBuilder.buildSystemMessage,
              repliedMessageBuilder: ({
                required types.Message message,
                required int messageWidth,
                required bool currentUserIsAuthor,
              }) => ChatMessageBuilder.buildRepliedMessageView(
                message: message,
                messageWidth: messageWidth,
                currentUserIsAuthor: currentUserIsAuthor,
                onTap: (message) async {
                  scrollToMessage(message?.id);
                },
              ),
              codeBlockBuilder: ChatMessageBuilder.buildCodeBlockWidget,
              moreButtonBuilder: ChatMessageBuilder.moreButtonBuilder,
            ),
            scrollController: scrollController,
            isContentInteractive: !handler.isPreviewMode,
            chatId: handler.session.chatId,
            theme: pageConfig.pageTheme(context),
            anchorMsgId: handler.anchorMsgId,
            messages: messages,
            isFirstPage: !dataController.hasMoreNewMessage,
            isLastPage: !dataController.canLoadMoreMessage,
            onEndReached: () async {
              if (dataController.isMessageLoading) return ;
              dataController.loadMoreMessage(
                loadMsgCount: ChatPageConfig.messagesPerPage,
                isLoadOlderData: true,
              );
            },
            onHeaderReached: () async {
              if (dataController.isMessageLoading) return ;
              dataController.loadMoreMessage(
                loadMsgCount: ChatPageConfig.messagesPerPage,
                isLoadOlderData: false,
              );
            },
            onMessageTap: handler.messagePressHandler,
            onPreviewDataFetched: _handlePreviewDataFetched,
            onSendPressed: (msg) => handler.sendTextMessage(context, msg.text),
            showUserNames: widget.showUserNames,
            //Group chat display nickname
            user: handler.author,
            useTopSafeAreaInset: true,
            inputMoreItems: pageConfig.inputMoreItemsWithHandler(handler),
            onVoiceSend: (String path, Duration duration) => handler.sendVoiceMessage(context, path, duration),
            onGifSend: (GiphyImage image) => handler.sendGifImageMessage(context, image),
            onAttachmentPressed: () {},
            onMessageStatusTap: handler.messageStatusPressHandler,
            textMessageOptions: handler.textMessageOptions(context),
            imageGalleryOptions: pageConfig.imageGalleryOptions,
            customTopWidget: widget.customTopWidget,
            customCenterWidget: widget.customCenterWidget,
            customBottomWidget: widget.customBottomWidget,
            imageMessageBuilder: ChatMessageBuilder.buildImageMessage,
            inputOptions: handler.inputOptions,
            enableBottomWidget: !handler.isPreviewMode,
            inputBottomView: handler.replyHandler.buildReplyMessageWidget(),
            bottomHintParam: widget.bottomHintParam,
            onFocusNodeInitialized: (focusNode) {
              handler.inputFocusNode = focusNode;
              handler.replyHandler.inputFocusNode = focusNode;
            },
            highlightMessageWidget: ValueListenableBuilder<bool>(
              valueListenable: isShowScrollToBottomWidget$,
              builder: (context, showScrollToBottomItem, child) {
                return ChatHighlightMessageWidget(
                  handler: highlightMessageHandler,
                  anchorMessageOnTap: scrollToMessage,
                  scrollToBottomOnTap: scrollToNewestMessage,
                  showScrollToBottomItem: showScrollToBottomItem,
                );
              },
            ),
            isShowScrollToBottomButton: dataController.hasMoreNewMessage,
            isShowScrollToBottomButtonUpdateCallback: (value) {
              isShowScrollToBottomWidget$.value = value || dataController.hasMoreNewMessage;
            },
            mentionUserListWidget: handler.mentionHandler?.buildMentionUserList(),
            onAudioDataFetched: (message) async {
              final (sourceFile, duration) = await ChatVoiceMessageHelper.populateMessageWithAudioDetails(
                session: handler.session,
                message: message,
              );
              if (duration != null) {
                dataController.updateMessage(
                  message.copyWith(
                    audioFile: sourceFile,
                    duration: duration,
                  ),
                );
              }
            },
            onInsertedContent: (KeyboardInsertedContent insertedContent) =>
                handler.sendInsertedContentMessage(context, insertedContent),
            onContentHeightChanged: (_) {
              // Trigger refresh when content height changes
              _inputHeightController.rebuild();
            },
            textFieldHasFocus: () async {
              if (PlatformUtils.isMobile) {
                scrollToNewestMessage();
              }
            },
            messageHasBuilder: (message, index) async {
              if (index == null) return ;

              highlightMessageHandler.tryRemoveMessageHighlightState(message.id);
            },
            replySwipeTriggerCallback: (message) {
              handler.replyHandler.quoteMenuItemPressHandler(message);
            },
            onBackgroundTap: () {
              pageFocusNode.requestFocus();
            },
          );
        }
    );
  }

  Widget pasteActionListenerWrapper({required Widget child}) {
    final pasteTextAction = handler.inputOptions.pasteTextAction;
    if (!PlatformUtils.isDesktop || pasteTextAction == null) return child;
    return Actions(
      actions: {
        PasteTextIntent: pasteTextAction,
      },
      child: Focus(
        autofocus: true,
        focusNode: pageFocusNode,
        child: child,
      ),
    );
  }

  void _handlePreviewDataFetched(
    types.TextMessage message,
    PreviewData previewData,
  ) {
    final messageId = message.remoteId ?? '';
    if (messageId.isEmpty) return ;

    final targetMessage = dataController.getMessage(messageId);
    if (targetMessage is! types.TextMessage) return ;

    // Update Mem
    final updatedMessage = targetMessage.copyWith(
      previewData: previewData,
    );
    dataController.updateMessage(updatedMessage);

    // Update DB
    ChatMessageHelper.updateMessageWithMessageId(
      messageId: messageId,
      previewData: previewData,
    );
  }

  void scrollToMessage(String? messageId) async {
    if (messageId == null || messageId.isEmpty) return ;

    var index = dataController.getMessageIndex(messageId);
    if (index > -1) {
      // Anchor message in cache
      await chatWidgetKey.currentState?.scrollToMessage(messageId);
    } else {
      // Anchor message not in cache
      await dataController.replaceWithNearbyMessage(targetMessageId: messageId);
      await Future.delayed(Duration(milliseconds: 300));
      index = dataController.getMessageIndex(messageId);
      if (index > -1) {
        await chatWidgetKey.currentState?.scrollToMessage(messageId);
      }
    }
  }

  void scrollToNewestMessage() {
    if (dataController.hasMoreNewMessage) {
      dataController.insertFirstPageMessages(
        firstPageMessageCount: ChatPageConfig.messagesPerPage,
        scrollAction: () async {
          scrollTo(0.0);
        },
      );
    } else {
      scrollTo(0.0);
    }
  }

  void scrollTo(double offset) async {
    if (!scrollController.hasClients) return ;

    await scrollController.animateTo(
      offset,
      duration: scrollDuration,
      curve: Curves.easeInQuad,
    );

    isShowScrollToBottomWidget$.safeUpdate(false);
  }

  @override
  void deleteSessionCallback(List<String> chatIds) async {
    chatIds = chatIds.where((e) => e.isNotEmpty).toList();
    if (chatIds.isEmpty) return;

    if (chatIds.contains(session.chatId) && mounted) {
      OXNavigator.popToRoot(context);
    }
  }
}