import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ox_chat/message_handler/chat_message_helper.dart';
import 'package:ox_chat/manager/chat_page_config.dart';
import 'package:ox_chat/model/constant.dart';
import 'package:ox_chat/message_handler/custom_message_utils.dart';
import 'package:ox_chat/utils/general_handler/chat_mention_handler.dart';
import 'package:ox_chat/utils/general_handler/chat_reply_handler.dart';
import 'package:ox_chat/utils/message_parser/define.dart';
import 'package:ox_chat/message_sender/chat_send_message_helper.dart';
import 'package:ox_chat/widget/chat_send_image_prepare_dialog.dart';
import 'package:ox_common/business_interface/ox_chat/call_message_type.dart';
import 'package:ox_common/business_interface/ox_chat/utils.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/ox_common.dart';
import 'package:ox_common/upload/file_type.dart';
import 'package:ox_common/upload/upload_utils.dart';
import 'package:ox_common/utils/aes_encrypt_utils.dart';
import 'package:ox_common/utils/clipboard.dart';
import 'package:ox_common/utils/encode_utils.dart';
import 'package:ox_common/utils/file_encryption_utils.dart';
import 'package:ox_common/utils/file_utils.dart';
import 'package:ox_common/utils/image_picker_utils.dart';
import 'package:ox_common/utils/list_extension.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_common/utils/platform_utils.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/utils/custom_uri_helper.dart';
import 'package:ox_common/utils/took_kit.dart';
import 'package:ox_common/utils/video_data_manager.dart';
import 'package:ox_common/widgets/common_image_gallery.dart';
import 'package:ox_common/widgets/common_long_content_page.dart';
import 'package:ox_common/widgets/common_video_page.dart';
import 'package:ox_module_service/ox_module_service.dart';
import 'package:uuid/uuid.dart';
import 'package:encrypt/encrypt.dart';
import 'package:ox_chat/manager/chat_draft_manager.dart';
import 'package:ox_chat/manager/chat_data_cache.dart';
import 'package:ox_chat_ui/ox_chat_ui.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:ox_chat/page/contacts/contact_user_info_page.dart';
import 'package:ox_chat/page/message_detail_page.dart';
import 'package:ox_chat/utils/chat_log_utils.dart';
import 'package:ox_chat/utils/message_report.dart';
import 'package:ox_chat/utils/widget_tool.dart';
import 'package:ox_chat/widget/report_dialog.dart';
import 'package:ox_common/business_interface/ox_chat/custom_message_type.dart';
import 'package:ox_common/business_interface/ox_calling/interface.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/permission_utils.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart' hide Filter;
import 'package:nostr_core_dart/nostr.dart';
import 'package:sqflite_sqlcipher/sqlite_api.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:ox_usercenter/page/settings/file_server_page.dart';
import 'package:ox_common/utils/file_server_helper.dart';
import 'package:ox_common/utils/image_save_utils.dart';

import '../../manager/chat_data_manager_models.dart';
import 'chat_highlight_message_handler.dart';
import 'message_data_controller.dart';

part 'chat_send_message_handler.dart';

enum DeleteOption {
  local,
  remote,
}

class ChatGeneralHandler {

  ChatGeneralHandler({
    required this.session,
    types.User? author,
    this.anchorMsgId,
    int unreadMessageCount = 0,
  }) : author = author ?? _defaultAuthor(),
       fileEncryptionType = _fileEncryptionType(session) {
    setupDataController();
    setupOtherUserIfNeeded();
    setupReplyHandler();
    setupMentionHandlerIfNeeded();
    setupHighlightMessageHandler(session, unreadMessageCount);
  }

  final types.User author;
  UserDBISAR? otherUser;
  final ChatSessionModelISAR session;
  final types.EncryptionType fileEncryptionType;
  final String? anchorMsgId;

  GlobalKey<ChatState>? chatWidgetKey;
  late ChatReplyHandler replyHandler;
  ChatMentionHandler? mentionHandler;
  late MessageDataController dataController;
  late ChatHighlightMessageHandler highlightMessageHandler;

  TextEditingController inputController = TextEditingController();
  FocusNode? inputFocusNode;

  final tempMessageSet = <types.Message>{};

  bool isPreviewMode = false;

  static types.User _defaultAuthor() {
    if (LoginManager.instance.currentCircle?.type == CircleType.bitchat) {
      return types.User(
        id: BitchatService().cachedPeerID!,
      );
    }
    UserDBISAR? userDB = Account.sharedInstance.me;
    return types.User(
      id: userDB!.pubKey,
      sourceObject: userDB,
    );
  }

  static types.EncryptionType _fileEncryptionType(ChatSessionModelISAR session) {
    final sessionType = session.chatType;
    switch (sessionType) {
      case ChatType.chatSingle:
      case ChatType.chatGroup:
        return types.EncryptionType.encrypted;
      default:
        return types.EncryptionType.none;
    }
  }

  static UserDBISAR? _defaultOtherUser(ChatSessionModelISAR session) {
    return Account.sharedInstance.userCache[session.getOtherPubkey]?.value;
  }

  void setupDataController() {
    final chatType = session.chatTypeKey;
    if (chatType == null) throw Exception('setupDataController: chatType is null');
    dataController = MessageDataController(chatType);
  }

  void setupOtherUserIfNeeded() {
    if (!session.isSingleChat) return ;

    otherUser = _defaultOtherUser(session);

    if (otherUser == null) {
      final userFuture = Account.sharedInstance.getUserInfo(session.getOtherPubkey);
      if (userFuture is Future<UserDBISAR?>) {
        userFuture.then((value){
          otherUser = value;
        });
      } else {
        otherUser = userFuture;
      }
    }
  }

  void setupReplyHandler() {
    replyHandler = ChatReplyHandler(session.chatId);
  }

  void setupMentionHandlerIfNeeded() {
    final userListGetter = session.userListGetter;
    if (userListGetter == null) return ;

    final mentionHandler = ChatMentionHandler(
      allUserGetter: userListGetter,
    );
    userListGetter().then((userList) {
      mentionHandler.allUserCache = userList;
    });
    mentionHandler.inputController = inputController;

    this.mentionHandler = mentionHandler;
  }

  void setupHighlightMessageHandler(ChatSessionModelISAR session, int unreadMessageCount) {
    highlightMessageHandler = ChatHighlightMessageHandler(session.chatId)
      ..dataController = dataController
      ..unreadMessageCount = unreadMessageCount;

    highlightMessageHandler.initialize(session).then((_) {
      if (!isPreviewMode) {
        OXChatBinding.sharedInstance.removeReactionMessage(session.chatId, false);
        OXChatBinding.sharedInstance.removeMentionMessage(session.chatId, false);
      }
    });
  }

  Future initializeMessage() async {
    final anchorMsgId = this.anchorMsgId;
    if (anchorMsgId != null && anchorMsgId.isNotEmpty) {
      await dataController.loadNearbyMessage(
        targetMessageId: anchorMsgId,
        beforeCount: ChatPageConfig.messagesPerPage,
        afterCount: ChatPageConfig.messagesPerPage,
      );
    } else {
      final messages = await dataController.loadMoreMessage(
        loadMsgCount: ChatPageConfig.messagesPerPage,
      );

      // Try request more messages
      final chatType = session.coreChatType;
      if (chatType != null) {
        // Try request newer messages
        int? since = messages.firstOrNull?.createdAt;
        if (since != null) since ~/= 1000;
        Messages.recoverMessagesFromRelay(
          session.chatId,
          chatType,
          since: since,
        );
      }
    }

    initializeImageGallery();
  }

  Future initializeImageGallery() async {
    final messageList = await dataController.getLocalMessage(
      messageTypes: [
        MessageType.image,
        MessageType.encryptedImage,
        MessageType.template,
      ],
    );
    dataController.galleryCache.initializePreviewImages(messageList);
  }

  void dispose() {
    dataController.dispose();
    highlightMessageHandler.dispose();
    inputController.dispose();
  }
}

extension ChatGestureHandlerEx on ChatGeneralHandler {

  void messageStatusPressHandler(BuildContext context, types.Message message) async {
    final status = message.status;
    switch (status) {
      case types.Status.warning:
        await CLAlertDialog.show(
          context: context,
          title: Localized.text('ox_usercenter.warn_title'),
          content: Localized.text('ox_chat.gift_wrapped_message_warning'),
          actions: [
            CLAlertAction<bool>(
              label: Localized.text('ox_chat.ok'),
              value: true,
              isDefaultAction: true,
            ),
          ],
        );
      case types.Status.error:
        final result = await CLAlertDialog.show<bool>(
          context: context,
          title: Localized.text('ox_chat.message_resend_hint'),
          actions: [
            CLAlertAction.cancel(),
            CLAlertAction.ok(),
          ],
        );
        if (result == true) {
          resendMessage(context, message);
        }
        break ;
      default:
        break ;
    }
  }

  /// Handles the avatar click event in chat messages.
  Future avatarPressHandler(context, {required String userId}) async {

    if (LoginManager.instance.isMe(userId)) {
      ChatLogUtils.info(className: 'ChatMessagePage', funcName: '_avatarPressHandler', message: Localized.text('ox_chat.not_allowed_push_own_detail'));
      return ;
    }

    var userDB = await Account.sharedInstance.getUserInfo(userId);

    if (userDB == null) {
      CommonToast.instance.show(context, Localized.text('ox_chat.user_not_found'));
      return ;
    }

    await OXNavigator.pushPage(context, (context) => ContactUserInfoPage(pubkey: userDB.pubKey));
  }

  TextMessageOptions textMessageOptions(BuildContext context) =>
      TextMessageOptions(
        isTextSelectable: PlatformUtils.isDesktop,
        openOnPreviewTitleTap: true,
        onLinkPressed: (url) => _onLinkTextPressed(context, url),
      );

  void _onLinkTextPressed(BuildContext context, String text) {
    OXModuleService.invoke('ox_common', 'gotoWebView', [context, text, null, null, null, null]);
  }

  Future messagePressHandler(BuildContext context, types.Message message) async {
    if (message is types.VideoMessage) {
      CommonVideoPage.show(
        message.videoURL,
        encryptedKey: message.decryptKey,
        encryptedNonce: message.decryptNonce,
      );
    } else if (message is types.ImageMessage) {
      imageMessagePressHandler(
        messageId: message.id,
        imageUri: message.uri,
      );
    } else if (message is types.CustomMessage) {
      switch(message.customType) {
        // case CustomMessageType.zaps:
        //   await zapsMessagePressHandler(context, message);
        //   break;
        // case CustomMessageType.call:
        //   callMessagePressHandler(context, message);
        //   break;
        case CustomMessageType.template:
          templateMessagePressHandler(context, message);
          break;
        case CustomMessageType.note:
          noteMessagePressHandler(context, message);
          break;
        // case CustomMessageType.ecash:
        // case CustomMessageType.ecashV2:
        //   ecashMessagePressHandler(context, message);
        //   break;
        case CustomMessageType.imageSending:
          imageMessagePressHandler(
            messageId: message.id,
            imageUri: ImageSendingMessageEx(message).url,
          );
          break;
        case CustomMessageType.video:
          final videoURI = VideoMessageEx(message).videoURI;
          final encryptedKey = VideoMessageEx(message).encryptedKey;
          final encryptedNonce = VideoMessageEx(message).encryptedNonce;
          if (videoURI.isEmpty) return ;

          CommonVideoPage.show(
            videoURI,
            encryptedKey: encryptedKey,
            encryptedNonce: encryptedNonce,
          );
          break;
        default:
          break;
      }
    } else if (message is types.TextMessage && message.text.length > message.maxLimit) {
      final text = message.text;
      CommonLongContentPage.present(
        context: context,
        content: text,
        author: message.author.sourceObject,
        timeStamp: message.createdAt,
      );
    }
  }

  Future imageMessagePressHandler({
    required String messageId,
    required String imageUri,
  }) async {

    final galleryCache = dataController.galleryCache;

    await galleryCache.initializeComplete;

    final gallery = galleryCache.gallery;
    final initialPage = gallery.indexWhere(
      (element) => element.id == messageId || element.uri == imageUri,
    );
    if (initialPage < 0) {
      ChatLogUtils.error(
        className: 'ChatGeneralHandler',
        funcName: 'imageMessagePressHandler',
        message: Localized.text('ox_chat.image_not_found'),
      );
      return ;
    }

    CommonImageGallery.show(
      imageList: gallery.map((e) => ImageEntry(
        id: e.id,
        url: e.uri,
        decryptedKey: e.decryptSecret,
        decryptedNonce: e.decryptNonce,
      )).toList(),
      initialPage: initialPage,
    );
  }

  // Future zapsMessagePressHandler(BuildContext context, types.CustomMessage message) async {
  //
  //   OXLoading.show();
  //
  //   final senderPubkey = message.author.sourceObject?.encodedPubkey ?? '';
  //   final myPubkey = Account.sharedInstance.me?.encodedPubkey ?? '';
  //
  //   if (senderPubkey.isEmpty) {
  //     CommonToast.instance.show(context, 'Error');
  //     return ;
  //   }
  //   if (myPubkey.isEmpty) {
  //     CommonToast.instance.show(context, 'Error');
  //     return ;
  //   }
  //
  //   final receiverPubkey = senderPubkey == myPubkey
  //       ? session.chatId : myPubkey;
  //   final invoice = ZapsMessageEx(message).invoice;
  //   final zapper = ZapsMessageEx(message).zapper;
  //   final description = ZapsMessageEx(message).description;
  //
  //   final requestInfo = Zaps.getPaymentRequestInfo(invoice);
  //   final amount = Zaps.getPaymentRequestAmount(invoice);
  //
  //   final zapsReceiptList = await Zaps.getZapReceipt(zapper, invoice: invoice);
  //   final zapsReceipt = zapsReceiptList.length > 0 ? zapsReceiptList.first : null;
  //
  //   OXLoading.dismiss();
  //
  //   final zapsDetail = ZapsRecordDetail(
  //     invoice: invoice,
  //     amount: amount,
  //     fromPubKey: senderPubkey,
  //     toPubKey: receiverPubkey,
  //     zapsTime: (requestInfo.timestamp.toInt() * 1000).toString(),
  //     description: description,
  //     isConfirmed: zapsReceipt != null,
  //   );
  //
  //   OXUserCenterInterface.jumpToZapsRecordPage(context, zapsDetail);
  // }

  void callMessagePressHandler(BuildContext context, types.CustomMessage message) {
    final otherUser = this.otherUser;
    CallMessageType? pageType;
    switch (CallMessageEx(message).callType) {
      case CallMessageType.audio:
        pageType = CallMessageType.audio;
        break ;
      case CallMessageType.video:
        pageType = CallMessageType.video;
        break ;
      default:
        break ;
    }
    if (otherUser == null || pageType == null) return ;
    OXCallingInterface.pushCallingPage(
      context,
      otherUser,
      pageType,
    );
  }

  void templateMessagePressHandler(BuildContext context, types.CustomMessage message) {
    final link = TemplateMessageEx(message).link;
    if (link.isRemoteURL) {
      OXModuleService.invoke('ox_common', 'gotoWebView', [context, link, null, null, null, null]);
    } else {
      link.tryHandleCustomUri(context: context);
    }
  }

  void noteMessagePressHandler(BuildContext context, types.CustomMessage message) {
    final link = NoteMessageEx(message).link;
    link.tryHandleCustomUri(context: context);
  }

  // void ecashMessagePressHandler(BuildContext context, types.CustomMessage message) async {
  //   if (!OXWalletInterface.checkWalletActivate()) return ;
  //   final package = await EcashHelper.createPackageFromMessage(message);
  //   EcashOpenDialog.show(
  //     context: context,
  //     package: package,
  //     approveOnTap: () async {
  //       if (message.customType != CustomMessageType.ecashV2) return ;
  //
  //       await Future.wait([
  //         ecashApproveHandler(context, message),
  //         Future.delayed(const Duration(seconds: 1)),
  //       ]);
  //
  //       OXNavigator.pop(context);
  //     },
  //   );
  // }
}

extension ChatMenuHandlerEx on ChatGeneralHandler {
  /// Handles the press event for a menu item.
  void menuItemPressHandler(BuildContext context, types.Message message, MessageLongPressEventType type) {
    switch (type) {
      case MessageLongPressEventType.copy:
        _copyMenuItemPressHandler(context, message);
        break;
      case MessageLongPressEventType.save:
        _saveMenuItemPressHandler(context, message);
        break;
      case MessageLongPressEventType.delete:
        _deleteMenuItemPressHandler(context, message);
        break;
      case MessageLongPressEventType.report:
        _reportMenuItemPressHandler(context, message);
        break;
      case MessageLongPressEventType.quote:
        replyHandler.quoteMenuItemPressHandler(message);
        break;
      case MessageLongPressEventType.info:
        _infoMenuItemPressHandler(context, message);
        break;
      // case MessageLongPressEventType.zaps:
      //   _zapMenuItemPressHandler(context, message);
      //   break;
      default:
        break;
    }
  }

  /// Handles the press event for the "Copy" button in a menu item.
  void _copyMenuItemPressHandler(BuildContext context, types.Message message) async {
    if (message is types.TextMessage) {
      TookKit.copyKey(context, message.text, '');
    } else if (message.isImageMessage) {
      await _copyImageToClipboardFromMessage(message as types.CustomMessage);
    }
  }

  /// Copy image to clipboard from message by getting binary data
  Future<void> _copyImageToClipboardFromMessage(types.CustomMessage message) async {
    final imageUrl = ImageSendingMessageEx(message).url;
    final decryptKey = ImageSendingMessageEx(message).encryptedKey;
    final decryptNonce = ImageSendingMessageEx(message).encryptedNonce;
    
    Uint8List imageData;
    if (imageUrl.isImageBase64) {
      imageData = await Base64ImageProvider.decodeBase64ToBytes(imageUrl);
    } else {
      final imageFile = await CacheManagerHelper.getCacheFile(
        url: imageUrl,
        fileType: CacheFileType.image,
      );
      if (imageFile == null) {
        CommonToast.instance.show(OXNavigator.rootContext, Localized.text('ox_chat.get_image_data_failed'));
        return;
      }
      if (decryptKey != null) {
        imageData = await FileEncryptionUtils.decryptFileInMemory(
          imageFile,
          decryptKey,
          decryptNonce,
        );
      } else {
        imageData = await imageFile.readAsBytes();
      }
    }

    await OXClipboard.copyImageToClipboardFromBytes(imageData);
  }

  /// Handles the press event for the "Save" button in a menu item.
  void _saveMenuItemPressHandler(BuildContext context, types.Message message) async {
    if (!message.isImageMessage) return;

    final imageMessage = message as types.CustomMessage;

    final imageUri = ImageSendingMessageEx(imageMessage).url;
    final decryptKey = ImageSendingMessageEx(imageMessage).encryptedKey;
    final decryptNonce = ImageSendingMessageEx(imageMessage).encryptedNonce;

    final success = await ImageSaveUtils.saveImageToGallery(
      imageUri: imageUri,
      decryptKey: decryptKey,
      decryptNonce: decryptNonce,
      context: context,
      fileName: message.id,
    );

    if (!success) {
      CommonToast.instance.show(context, Localized.text('ox_chat.save_image_failed'));
    }

  }

  /// Handles the press event for the "Delete" button in a menu item.
  void _deleteMenuItemPressHandler(BuildContext context, types.Message message) async {
    final messageId = message.remoteId;
    if (messageId == null || messageId.isEmpty) {
      // For messages without remoteId, only local deletion is possible
      messageDeleteHandler(message);
      return;
    }

    // Show CLPicker with deletion options
    final deleteOption = await CLPicker.show<DeleteOption>(
      context: context,
      title: Localized.text('ox_chat.message_delete_hint'),
      items: session.isSelfChat
          ? _buildSelfChatDeleteOptions()
          : _buildDeleteOptions(message),
    );

    if (deleteOption != null) {
      await _performDeleteAction(context, message, deleteOption);
    }
  }

  List<CLPickerItem<DeleteOption>> _buildSelfChatDeleteOptions() {
    return [
      CLPickerItem<DeleteOption>(
        label: Localized.text('ox_chat.delete'),
        value: DeleteOption.local,
        isDestructive: true,
      )
    ];
  }

  List<CLPickerItem<DeleteOption>> _buildDeleteOptions(types.Message message) {
    final options = <CLPickerItem<DeleteOption>>[];
    
    // Always show "Delete for me" option
    options.add(CLPickerItem<DeleteOption>(
      label: Localized.text('ox_chat.delete_message_me_action_mode'),
      value: DeleteOption.local,
      isDestructive: true,
    ));
    
    // For private chats, show "Delete for me and [other person's name]"
    if (session.isSingleChat) {
      final otherName = _getOtherPersonName();
      final localizedText = Localized.text('ox_chat.delete_message_me_and_other_action_mode');
      final finalText = localizedText.replaceAll(r'${otherName}', otherName);
      options.add(CLPickerItem<DeleteOption>(
        label: finalText,
        value: DeleteOption.remote,
        isDestructive: true,
      ));
    } else {
      if (_canDeleteRemotely(message)) {
        // For group chats, show "Delete for everyone"
        options.add(CLPickerItem<DeleteOption>(
          label: Localized.text('ox_chat.delete_message_everyone_action_mode'),
          value: DeleteOption.remote,
          isDestructive: true,
        ));
      }
    }
    
    return options;
  }
  
  String _getOtherPersonName() {
    // Get the other person's name in private chat
    if (session.isSingleChat) {
      final otherPubkey = session.getOtherPubkey;
      final contact = Account.sharedInstance.getUserInfo(otherPubkey);
      if (contact is UserDBISAR) {
        return contact.getUserShowName();
      }
      return otherPubkey;
    }
    return '';
  }

  bool _canDeleteRemotely(types.Message message) {
    // If it's own message, can always delete remotely
    if (message.isMe) {
      return true;
    }

    // Check if it's a group chat and user has admin permissions
    if (session.chatType == ChatType.chatGroup && session.groupId != null) {
      return _hasGroupDeletePermission(session.groupId!);
    }

    // For other chat types, non-owners cannot delete others' messages remotely
    return false;
  }

  bool _hasGroupDeletePermission(String groupId) {
    // Check if current user is group owner
    final currentUser = Account.sharedInstance.me;
    if (currentUser == null) return false;

    final group = Groups.sharedInstance.groups[groupId]?.value;
    if (group == null) return false;

    // Group owner can delete any message
    if (group.owner == currentUser.pubKey) {
      return true;
    }

    return false;
  }

  Future<void> _performDeleteAction(
    BuildContext context,
    types.Message message,
    DeleteOption option,
  ) async {
    OXLoading.show();
    
    try {
      switch (option) {
        case DeleteOption.local:
          await _deleteMessageLocally(message);
          break;
        case DeleteOption.remote:
          await _deleteMessageRemotely(context, message);
          break;
      }
    } catch (e) {
      CommonToast.instance.show(context, Localized.text('ox_chat.delete_failed').replaceAll('{error}', e.toString()));
    } finally {
      OXLoading.dismiss();
    }
  }

  Future<void> _deleteMessageLocally(types.Message message) async {
    // Delete message from local database only
    final messageId = message.remoteId ?? '';
    if (messageId.isNotEmpty) {
      // Check if it's an MLS group and use the appropriate deletion method
      if (session.chatType == ChatType.chatGroup && session.groupId != null) {
        final group = Groups.sharedInstance.groups[session.groupId!]?.value;
        if (group != null && group.isMLSGroup) {
          await Groups.sharedInstance.deleteMLSGroupMessages([messageId], group, requestDeleteForAll: false);
        } else {
          await Messages.deleteMessagesFromDB(messageIds: [messageId], notify: false);
        }
      } else {
        await Messages.deleteMessagesFromDB(messageIds: [messageId], notify: false);
      }
    }
    
    // Remove from UI
    messageDeleteHandler(message);
  }

  Future<void> _deleteMessageRemotely(BuildContext context, types.Message message) async {
    final messageId = message.remoteId;
    if (messageId == null || messageId.isEmpty) {
      throw Exception(Localized.text('ox_chat.message_no_remote_id'));
    }

    // Check if it's an MLS group and use the appropriate deletion method
    if (session.chatType == ChatType.chatGroup && session.groupId != null) {
      final group = Groups.sharedInstance.groups[session.groupId!]?.value;
      if (group != null && group.isMLSGroup) {
        await Groups.sharedInstance.deleteMLSGroupMessages([messageId], group, requestDeleteForAll: true);
        messageDeleteHandler(message);
        return;
      }
    }

    // For non-MLS groups or other chat types, use the existing method
    final result = await Messages.deleteMessageFromRelay(messageId, '');
    
    if (result.status) {
      messageDeleteHandler(message);
    } else {
      throw Exception(result.message);
    }
  }

  /// Handles the press event for the "Report" button in a menu item.
  void _infoMenuItemPressHandler(BuildContext context, types.Message message) {
    OXNavigator.pushPage(
      context,
      (context) => MessageDetailPage(message: message),
    );
  }

  void _reportMenuItemPressHandler(BuildContext context, types.Message message) async {

    ChatLogUtils.info(
      className: 'ChatMessagePage',
      funcName: '_reportMenuItemPressHandler',
      message: 'id: ${message.id}, content: ${message.content}',
    );

    ReportDialog.show(
      context,
      target: MessageReportTarget(
        message: message,
        completeAction: () {
          messageDeleteHandler(message);
        }
      ),
    );
  }

  void messageDeleteHandler(types.Message message) {
    dataController.removeMessage(message: message);
  }
}

extension ChatInputMoreHandlerEx on ChatGeneralHandler {

  // type: 1 - image, 2 - video
  Future albumPressHandler(BuildContext context, int type) async {
    // Ensure file server is configured before proceeding.
    if (!await _ensureFileServerConfigured(context)) return;

    if(PlatformUtils.isDesktop){
      await _goToPhoto(context, type);
      return;
    }
    DeviceInfoPlugin plugin = DeviceInfoPlugin();
    bool storagePermission = false;
    if (Platform.isAndroid && (await plugin.androidInfo).version.sdkInt >= 34) {
      Map<String, bool> result = await OXCommon.request34MediaPermission(type);
      bool readMediaImagesGranted = result['READ_MEDIA_IMAGES'] ?? false;
      bool readMediaVideoGranted = result['READ_MEDIA_VIDEO'] ?? false;
      bool readMediaVisualUserSelectedGranted = result['READ_MEDIA_VISUAL_USER_SELECTED'] ?? false;
      if (readMediaImagesGranted || readMediaVideoGranted) {
        storagePermission = true;
      } else if (readMediaVisualUserSelectedGranted) {
        final filePaths = await OXCommon.select34MediaFilePaths(type);

        bool isVideo = type == 2;
        if (isVideo) {
          List<Media> fileList = [];
          await Future.forEach(filePaths, (path) async {
            fileList.add(Media()..path = path);
          });
          sendVideoMessageWithFile(context, fileList);
        } else {
          List<File> fileList = [];
          await Future.forEach(filePaths, (path) async {
            fileList.add(File(path));
          });
          sendImageMessageWithFile(context, fileList);
        }
        return;
      }
    } else {
      storagePermission = await PermissionUtils.getPhotosPermission(context,type: type);
    }

    if(storagePermission){
      await _goToPhoto(context, type);
    } else {
    }
  }

  Future cameraPressHandler(BuildContext context,) async {
    if (!await _ensureFileServerConfigured(context)) return;

    _goToCamera(context);
  }

  Future<void> _goToPhoto(BuildContext context, int type) async {
    // type: 1 - image, 2 - video
    final isVideo = type == 2;
    GalleryMode mode = isVideo ? GalleryMode.video : GalleryMode.image;
    List<Media> res = [];
    if(PlatformUtils.isMobile){
      res = await ImagePickerUtils.pickerPaths(
        galleryMode: mode,
        selectCount: 1,
        showGif: false,
        compressSize: 1024,
      );
    }else{
      List<Media>? mediaList = await FileUtils.importClientFile(type);
      if(mediaList != null){
        res = mediaList;
      }
    }


    if (isVideo) {
      sendVideoMessageWithFile(context, res);
    } else {
      List<File> fileList = [];
      await Future.forEach(res, (element) async {
        final entity = element;
        final file = File(entity.path ?? '');
        fileList.add(file);
      });
      sendImageMessageWithFile(context, fileList);
    }
  }

  Future<void> _goToCamera(BuildContext context) async {
    //Open the camera or gallery based on the status indicator
    Media? res = await ImagePickerUtils.openCamera(
      cameraMimeType: CameraMimeType.photo,
      compressSize: 1024,
    );
    if(res == null) return;
    final file = File(res.path ?? '');
    sendImageMessageWithFile(context, [file]);
  }
}

extension ChatInputHandlerEx on ChatGeneralHandler {

  InputOptions get inputOptions => InputOptions(
    onTextChanged: _onTextChanged,
    textEditingController: inputController,
    contextMenuBuilder: _inputContextMenuBuilder,
    pasteTextAction: CallbackAction(onInvoke: (_) => _pasteTextActionHandler())
  );

  void _onTextChanged(String text) {
    final chatId = session.chatId;
    ChatDraftManager.shared.updateTempDraft(chatId, text);
  }

  Widget _inputContextMenuBuilder(BuildContext context, EditableTextState editableTextState) {
    final hasImagesFuture = OXClipboard.hasImages();
    return FutureBuilder(
      future: hasImagesFuture,
      builder: (_, asyncSnapshot) {
        if (asyncSnapshot.data == true) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            buttonItems: [
              ContextMenuButtonItem(
                onPressed: () async {
                  chatWidgetKey?.currentState?.inputUnFocus();
                  _showImageClipboardDataHint();
                },
                type: ContextMenuButtonType.paste,
              ),
              // Add custom select option (select 2 characters by default) only when no text is selected and text is not empty
              if ((!editableTextState.textEditingValue.selection.isValid || 
                  editableTextState.textEditingValue.selection.isCollapsed) && 
                  editableTextState.textEditingValue.text.isNotEmpty)
                ContextMenuButtonItem(
                  onPressed: () {
                    final text = editableTextState.textEditingValue.text;
                    final cursorPosition = editableTextState.textEditingValue.selection.start;
                    if (text.isNotEmpty) {
                      TextSelection selection;
                      if (cursorPosition >= text.length) {
                        // If cursor is at the end, select 2 characters from the end
                        selection = TextSelection(
                          baseOffset: (text.length - 2).clamp(0, text.length),
                          extentOffset: text.length,
                        );
                      } else {
                        // Select 2 characters from current cursor position
                        selection = TextSelection(
                          baseOffset: cursorPosition,
                          extentOffset: (cursorPosition + 2).clamp(0, text.length),
                        );
                      }
                      editableTextState.userUpdateTextEditingValue(
                        editableTextState.textEditingValue.copyWith(
                          selection: selection,
                        ),
                        SelectionChangedCause.toolbar,
                      );
                    }
                  },
                  type: ContextMenuButtonType.custom,
                  label: Localized.text('ox_chat.input_menu_select'),
                ),
              ...editableTextState.contextMenuButtonItems.map(
                      (item) => item.type != ContextMenuButtonType.paste ? item : null
              ).whereNotNull(),
            ],
            anchors: editableTextState.contextMenuAnchors,
          );
        } else if (asyncSnapshot.data == false) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            buttonItems: [
              // Add custom select option (select 2 characters by default) only when no text is selected and text is not empty
              if ((!editableTextState.textEditingValue.selection.isValid || 
                  editableTextState.textEditingValue.selection.isCollapsed) && 
                  editableTextState.textEditingValue.text.isNotEmpty)
                ContextMenuButtonItem(
                  onPressed: () {
                    final text = editableTextState.textEditingValue.text;
                    final cursorPosition = editableTextState.textEditingValue.selection.start;
                    if (text.isNotEmpty) {
                      TextSelection selection;
                      if (cursorPosition >= text.length) {
                        // If cursor is at the end, select 2 characters from the end
                        selection = TextSelection(
                          baseOffset: (text.length - 2).clamp(0, text.length),
                          extentOffset: text.length,
                        );
                      } else {
                        // Select 2 characters from current cursor position
                        selection = TextSelection(
                          baseOffset: cursorPosition,
                          extentOffset: (cursorPosition + 2).clamp(0, text.length),
                        );
                      }
                      editableTextState.userUpdateTextEditingValue(
                        editableTextState.textEditingValue.copyWith(
                          selection: selection,
                        ),
                        SelectionChangedCause.toolbar,
                      );
                    }
                  },
                  type: ContextMenuButtonType.custom,
                  label: Localized.text('ox_chat.input_menu_select'),
                ),
              ...editableTextState.contextMenuButtonItems,
            ],
            anchors: editableTextState.contextMenuAnchors,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _showImageClipboardDataHint() async {

    final context = OXNavigator.navigatorKey.currentContext;
    if (context == null) return;

    final imageFile = (await OXClipboard.getImages()).firstOrNull;
    if (imageFile == null || !imageFile.existsSync()) {
      CommonToast.instance.show(context, Localized.text('ox_chat.get_image_from_clipboard_failed'));
      return;
    }

    final isConfirm = await ChatSendImagePrepareDialog.show(context, imageFile);
    if (!isConfirm) return;

    // Ensure file server is configured before proceeding.
    if (!await _ensureFileServerConfigured(context)) return;

    sendImageMessageWithFile(context, [imageFile]);
  }

  Future<bool> _ensureFileServerConfigured(BuildContext context) async {
    if (session.isSelfChat) return true;
    return FileServerHelper.ensureFileServerConfigured(
      context,
      onGoToSettings: () => OXNavigator.pushPage(
        context,
        (_) => FileServerPage(previousPageTitle: Localized.text('ox_common.back')),
      ),
    );
  }

  void _pasteTextActionHandler() async {
    final hasImages = await OXClipboard.hasImages();
    if (hasImages) {
      _showImageClipboardDataHint();
      return;
    }

    final text = await OXClipboard.getText() ?? '';
    if (text.isNotEmpty) {
      TextSelection selection = inputController.selection;
      if (!selection.isValid) {
        selection = TextSelection.collapsed(offset: 0);
      }
      final int lastSelectionIndex = math.max(selection.baseOffset, selection.extentOffset);
      final TextEditingValue collapsedTextEditingValue = inputController.value.copyWith(
        selection: TextSelection.collapsed(offset: lastSelectionIndex),
      );
      inputController.value = collapsedTextEditingValue.replaced(selection, text);
      inputFocusNode?.requestFocus();
    }
  }
}

extension StringChatEx on String {
  /// Returns whether it is a local path or null if it is not a path String
  bool? get isLocalPath {
    return !this.startsWith('http://') && !this.startsWith('https://') && !this.startsWith('data:image/');
  }
}