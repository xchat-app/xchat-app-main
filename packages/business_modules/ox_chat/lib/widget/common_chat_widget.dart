import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:ox_chat/manager/chat_draft_manager.dart';
import 'package:ox_chat/message_handler/chat_message_builder.dart';
import 'package:ox_chat/message_handler/chat_message_helper.dart';
import 'package:ox_chat/manager/chat_page_config.dart';
import 'package:ox_chat/utils/chat_voice_helper.dart';
import 'package:ox_chat/utils/general_handler/chat_general_handler.dart';
import 'package:ox_chat/widget/chat_highlight_message_widget.dart';
import 'package:ox_chat/utils/general_handler/chat_mention_handler.dart';
import 'package:ox_chat/utils/general_handler/message_data_controller.dart';
import 'package:ox_chat_ui/ox_chat_ui.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/chat_prompt_tone.dart';
import 'package:ox_common/utils/extension.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/ox_chat_observer.dart';
import 'package:ox_common/utils/platform_utils.dart';
import 'package:ox_common/utils/web_url_helper.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../utils/general_handler/chat_highlight_message_handler.dart';

class CommonChatWidget extends StatefulWidget {
  CommonChatWidget({
    required this.handler,
    this.title,
    this.actions = const [],
    this.showUserNames = false,
    this.customTopWidget,
    this.customCenterWidget,
    this.customBottomWidget,
    this.bottomHintParam,
  });

  // Basic

  final ChatGeneralHandler handler;

  final String? title;
  final List<Widget> actions;
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

      session.unreadCount = 0;
      OXChatBinding.sharedInstance.updateChatSession(
        session.chatId,
        unreadCount: 0,
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
      OXChatBinding.sharedInstance.updateChatSession(session.chatId, isMentioned: false);
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

  CLAppBar buildAppBar() {
    return CLAppBar(
      title: widget.title,
      actions: widget.actions,
    );
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
            theme: pageConfig.pageTheme,
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