part of 'chat_general_handler.dart';

extension ChatMessageSendEx on ChatGeneralHandler {
  static Future sendTextMessageHandler(
    String receiverPubkey,
    String text, {
    int chatType = ChatType.chatSingle,
    BuildContext? context,
    ChatSessionModelISAR? session,
    String secretSessionId = '',
  }) async {
    final sender = LoginManager.instance.currentPubkey;
    if (sender.isEmpty) return;

    session ??= _getSessionModel(
      receiverPubkey,
      chatType,
      secretSessionId,
    );
    if (session == null) return;

    ChatGeneralHandler(session: session).sendTextMessage(context, text);
  }

  static void sendTemplateMessage({
    required String receiverPubkey,
    String title = '',
    String subTitle = '',
    String icon = '',
    String link = '',
    int chatType = ChatType.chatSingle,
    String secretSessionId = '',
    ChatSessionModelISAR? session,
  }) {
    final sender = LoginManager.instance.currentPubkey;
    if (sender.isEmpty) return;

    session ??= _getSessionModel(
      receiverPubkey,
      chatType,
      secretSessionId,
    );
    if (session == null) return;

    ChatGeneralHandler(session: session)._sendTemplateMessage(
      title: title,
      content: subTitle,
      icon: icon,
      link: link,
    );
  }

  static void staticSendImageMessageWithFile({
    required String receiverPubkey,
    required String imageFilePath,
    int chatType = ChatType.chatSingle,
    String secretSessionId = '',
    ChatSessionModelISAR? session,
  }) {
    final sender = LoginManager.instance.currentPubkey;
    if (sender.isEmpty) return;

    session ??= _getSessionModel(
      receiverPubkey,
      chatType,
      secretSessionId,
    );
    if (session == null) return;

    ChatGeneralHandler(session: session).sendImageMessageWithFile(
      null,
      [File(imageFilePath)],
    );
  }

  static void staticSendVideoMessageWithFile({
    required String receiverPubkey,
    required String videoFilePath,
    int chatType = ChatType.chatSingle,
    String secretSessionId = '',
    ChatSessionModelISAR? session,
  }) {
    final sender = LoginManager.instance.currentPubkey;
    if (sender.isEmpty) return;

    session ??= _getSessionModel(
      receiverPubkey,
      chatType,
      secretSessionId,
    );
    if (session == null) return;

    ChatGeneralHandler(session: session).sendVideoMessageWithFile(
      null,
      [Media()..path = videoFilePath],
    );
  }

  static Future sendSystemMessageHandler(
    String receiverPubkey,
    String text, {
    int chatType = ChatType.chatSingle,
    BuildContext? context,
    ChatSessionModelISAR? session,
    String secretSessionId = '',
  }) async {
    final sender = LoginManager.instance.currentPubkey;
    if (sender.isEmpty) return;

    session ??= _getSessionModel(
      receiverPubkey,
      chatType,
      secretSessionId,
    );
    if (session == null) return;

    ChatGeneralHandler(session: session).sendSystemMessage(text, context: context);
  }

  static ChatSessionModelISAR? _getSessionModel(String receiverPubkey, int type,
      [String secretSessionId = '']) {
    final sender = LoginManager.instance.currentPubkey;
    if (sender.isEmpty) return null;

    final session = OXChatBinding.sharedInstance.getSessionModel(receiverPubkey);
    if (session != null) return session;

    return ChatSessionModelISAR.getDefaultSession(
      type,
      receiverPubkey,
      sender,
      secretSessionId: secretSessionId,
    );
  }

  Future<types.Message?> _sendMessageHandler({
    BuildContext? context,
    required String? content,
    required MessageType? messageType,
    String? decryptSecret,
    String? decryptNonce,
    types.Message? resendMessage,
    ChatSendingType sendingType = ChatSendingType.remote,
    String? replaceMessageId,
  }) async {
    if (session.isSelfChat && sendingType == ChatSendingType.remote) {
      sendingType = ChatSendingType.store;
    }

    types.Message? message;
    int tempCreateTime = DateTime.now().millisecondsSinceEpoch;
    if (resendMessage != null) {
      message = resendMessage.copyWith(
        createdAt: tempCreateTime,
        status: null,
      );
    } else if (content != null && messageType != null) {
      final mid = Uuid().v4();
      message = await ChatMessageHelper.createUIMessage(
        messageId: mid,
        authorPubkey: author.id,
        contentString: content,
        type: messageType,
        createTime: tempCreateTime,
        chatId: session.chatId,
        chatType: session.chatType,
        replyId: messageType == MessageType.text ? replyHandler.replyMessage?.remoteId : null,
        decryptSecret: decryptSecret,
        decryptNonce: decryptNonce,
      );
    }
    if (message == null) return null;

    if (replaceMessageId != null) {
      final replaceMessage = dataController.getMessage(replaceMessageId);
      message = message.copyWith(
        id: replaceMessageId,
        createdAt: replaceMessage?.createdAt ?? message.createdAt,
      );
    }

    if (resendMessage == null) {
      message = await tryPrepareSendFileMessage(context, message);
    }
    if (message == null) return null;

    if (sendingType == ChatSendingType.memory) {
      tempMessageSet.add(message);
    }

    var sendFinish = OXValue(false);
    final sentMessage = await ChatSendMessageHelper.sendMessage(
      session: session,
      message: message,
      sendingType: sendingType,
      contentEncoder: messageContentEncoder,
      sourceCreator: (message) {
        return null;
      },
      replaceMessageId: replaceMessageId,
      sendRemoteEventHandler: (event, sendMsg) => _sendRemoteEventHandler(
        event: event,
        sendMsg: sendMsg,
        sendFinish: sendFinish,
        replaceMessageId: replaceMessageId,
      ),
    );
    if (sentMessage == null) {
      CommonToast.instance.show(context, 'send message fail');
    } else {
      _sendActionFinishHandler(
        message: sentMessage,
        sendFinish: sendFinish,
        sendingType: sendingType,
        replaceMessageId: replaceMessageId,
      );
    }
    return sentMessage;
  }

  Future _sendRemoteEventHandler({
    required OKEvent event,
    required types.Message sendMsg,
    required OXValue sendFinish,
    String? replaceMessageId,
  }) async {
    sendFinish.value = true;
    final originMessageId = replaceMessageId ?? sendMsg.id;
    final message = await dataController.getMessage(originMessageId);
    if (message == null) return;

    final updatedMessage = message.copyWith(
      status: event.status ? types.Status.sent : types.Status.error,
    );
    dataController.updateMessage(updatedMessage, originMessageId: originMessageId);

    // Save OKEvent to database
    final messageDB = await Messages.sharedInstance.loadMessageDBFromDB(originMessageId);
    if (messageDB != null) {
      messageDB.sendOkEvent = event.serialize();
      await Messages.saveMessageToDB(messageDB);
    }
  }

  void _sendActionFinishHandler({
    required types.Message message,
    required OXValue<bool> sendFinish,
    required ChatSendingType sendingType,
    String? replaceMessageId,
  }) {
    if (LoginManager.instance.currentCircle?.type == CircleType.bitchat) return;

    if (replaceMessageId != null && replaceMessageId.isNotEmpty) {
      dataController.updateMessage(
        message.copyWith(
          id: replaceMessageId,
        ),
        originMessageId: replaceMessageId,
      );
    } else {
      dataController.addMessage(message);
      dataController.galleryCache.tryAddPreviewImage(message: message);
    }

    // Update session position after sending message
    _updateSessionAfterSendMessage(message);

    if (sendingType == ChatSendingType.remote) {
      // If the message is not sent within a short period of time, change the status to the sending state
      _setMessageSendingStatusIfNeeded(sendFinish, message);
    } else if (session.isSelfChat) {
      _updateMessageStatus(message, types.Status.sent);
    }
  }

  void _updateSessionAfterSendMessage(types.Message message) {
    // Get the session model and update its lastActivityTime
    OXChatBinding.sharedInstance.updateLastMessageInfo(
      chatId: session.chatId,
      previewContent: ChatMessageHelper.getMessagePreviewText(
        message.content,
        message.dbMessageType,
        message.author.id,
      ), 
      msgTime: DateTime.fromMillisecondsSinceEpoch(message.createdAt),
    );
  }

  void _setMessageSendingStatusIfNeeded(OXValue<bool> sendFinish, types.Message message) {
    Future.delayed(const Duration(milliseconds: 500), () async {
      if (!sendFinish.value) {
        final msg = await dataController.getMessage(message.id);
        if (msg == null) return;
        _updateMessageStatus(msg, types.Status.sending);
      }
    });
  }

  void _updateMessageStatus(types.Message message, types.Status status) {
    final updatedMessage = message.copyWith(
      status: status,
    );
    dataController.updateMessage(updatedMessage);
    ChatMessageHelper.updateMessageWithMessageId(
      messageId: updatedMessage.remoteId!,
      status: status,
    );
  }

  FutureOr<String?> messageContentEncoder(types.Message message) {
    List<MessageContentParser> parserList = [
      if (mentionHandler != null) mentionHandler!.tryEncoder,
    ];

    for (final fn in parserList) {
      final result = fn(message);
      if (result != null) return result;
    }

    return null;
  }

  void resendMessage(BuildContext context, types.Message message) {
    if (message.isImageSendingMessage) {
      sendImageMessage(
        context: context,
        resendMessage: message.copyWith(
          createdAt: DateTime.now().millisecondsSinceEpoch,
          status: null,
        ) as types.CustomMessage,
      );
      return;
    } else if (message.isVideoSendingMessage) {
      sendVideoMessage(
        context: context,
        resendMessage: message.copyWith(
          createdAt: DateTime.now().millisecondsSinceEpoch,
          status: null,
        ) as types.CustomMessage,
      );
      return;
    }

    _sendMessageHandler(
      context: context,
      content: null,
      messageType: null,
      resendMessage: message,
    );
  }

  Future<bool> sendTextMessage(BuildContext? context, String text) async {
    if (text.length > 30000) {
      CommonToast.instance.show(context, 'chat_input_length_over_hint'.localized());
      return false;
    }
    await _sendMessageHandler(
      content: text,
      messageType: MessageType.text,
      context: context,
    );
    replyHandler.updateReplyMessage(null);
    return true;
  }

  Future sendImageMessageWithFile(BuildContext? context, List<File> images) async {
    for (final imageFile in images) {
      final fileId = await EncodeUtils.generateMultiSampleFileKey(imageFile);
      final bytes = await imageFile.readAsBytes();
      final image = await decodeImageFromList(bytes);

      String? encryptedKey;
      String? encryptedNonce;
      String? imageURL;
      final uploadResult = UploadManager.shared.getUploadResult(fileId, otherUser?.pubKey);
      if (uploadResult?.isSuccess == true) {
        final url = uploadResult?.url;
        encryptedKey = uploadResult?.encryptedKey;
        encryptedNonce = uploadResult?.encryptedNonce;
        if (url != null && url.isNotEmpty) {
          imageURL = generateUrlWithInfo(
            originalUrl: url,
            width: image.width,
            height: image.height,
          );
        }

        await sendImageMessage(
          context: context,
          fileId: fileId,
          imageFile: null,
          imageWidth: image.width,
          imageHeight: image.height,
          encryptedKey: encryptedKey,
          encryptedNonce: encryptedNonce,
          url: imageURL,
        );

        return;
      } else {
        encryptedKey =
            fileEncryptionType == types.EncryptionType.encrypted ? createEncryptKey() : null;
        encryptedNonce =
            fileEncryptionType == types.EncryptionType.encrypted ? createEncryptNonce() : null;
      }

      final encryptedFile = await encryptFile(
        origin: imageFile,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
        fileType: CacheFileType.image,
      );
      imageFile.delete();
      if (encryptedFile == null) {
        assert(false, 'encryptedFile is null');
        return;
      }

      await sendImageMessage(
        context: context,
        fileId: fileId,
        imageFile: encryptedFile,
        imageWidth: image.width,
        imageHeight: image.height,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
        url: imageURL,
      );
    }
  }

  Future sendImageMessage({
    BuildContext? context,
    String? fileId,
    File? imageFile,
    String? fileName,
    String? url,
    int? imageWidth,
    int? imageHeight,
    String? encryptedKey,
    String? encryptedNonce,
    types.CustomMessage? resendMessage,
  }) async {
    if (resendMessage != null) {
      fileId ??= ImageSendingMessageEx(resendMessage).fileId;
      imageFile ??= File(ImageSendingMessageEx(resendMessage).path);
      imageWidth ??= ImageSendingMessageEx(resendMessage).width;
      imageHeight ??= ImageSendingMessageEx(resendMessage).height;
      encryptedKey ??= ImageSendingMessageEx(resendMessage).encryptedKey;
      encryptedNonce ??= ImageSendingMessageEx(resendMessage).encryptedNonce;
      url ??= ImageSendingMessageEx(resendMessage).url;
    }

    if (url != null && url.isRemoteURL) {
      sendImageMessageWithURL(
        imageURL: url,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
        resendMessage: resendMessage,
      );
      return;
    }

    if (imageFile == null || fileId == null) {
      ChatLogUtils.error(
        className: 'ChatMessageSendEx',
        funcName: 'sendImageMessage',
        message: 'filePath: ${imageFile?.path}, fileId: $fileId',
      );
      return;
    }

    String content = '';
    try {
      content = jsonEncode(CustomMessageEx.imageSendingMetaData(
        fileId: fileId,
        path: imageFile.path,
        url: url ?? '',
        width: imageWidth,
        height: imageHeight,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
      ));
    } catch (_) {}
    if (content.isEmpty) {
      ChatLogUtils.error(
        className: 'ChatMessageSendEx',
        funcName: 'sendImageMessage',
        message: 'content is empty',
      );
      return;
    }

    UploadManager.shared.prepareUploadStream(fileId, otherUser?.pubKey);
    final sendMessage = await _sendMessageHandler(
      context: context,
      content: content,
      messageType: MessageType.template,
      resendMessage: resendMessage,
      sendingType: ChatSendingType.store,
      decryptSecret: encryptedKey,
      decryptNonce: encryptedNonce,
    );
    if (sendMessage == null) return;

    if (session.isSelfChat) return;

    final (uploadResult, isFromCache) = await UploadManager.shared.uploadFile(
      fileType: FileType.image,
      filePath: imageFile.path,
      uploadId: fileId,
      receivePubkey: otherUser?.pubKey ?? '',
      encryptedKey: encryptedKey,
      encryptedNonce: encryptedNonce,
      autoStoreImage: false,
    );

    var imageURL = uploadResult.url;
    if (!uploadResult.isSuccess || imageURL.isEmpty) {
      final status = types.Status.error;
      dataController.updateMessage(sendMessage.copyWith(
        status: status,
      ));
      ChatMessageHelper.updateMessageWithMessageId(
        messageId: sendMessage.id,
        status: status,
      );
      return;
    }

    imageURL = generateUrlWithInfo(
      originalUrl: imageURL,
      width: imageWidth,
      height: imageHeight,
    );

    if (!isFromCache) {
      final cacheManager = await CLCacheManager.getCircleCacheManager(CacheFileType.image);
      imageFile = await cacheManager.putFile(
        imageURL,
        imageFile.readAsBytesSync(),
        fileExtension: imageFile.path.getFileExtension(),
      );
    }

    sendImageMessageWithURL(
      imageURL: imageURL,
      imagePath: imageFile.path,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      encryptedKey: encryptedKey,
      encryptedNonce: encryptedNonce,
      replaceMessageId: sendMessage.id,
    );
  }

  void sendImageMessageWithURL({
    required String imageURL,
    String? fileId,
    String? imagePath,
    int? imageWidth,
    int? imageHeight,
    String? encryptedKey,
    String? encryptedNonce,
    String? replaceMessageId,
    types.Message? resendMessage,
  }) {
    try {
      final content = jsonEncode(CustomMessageEx.imageSendingMetaData(
        fileId: fileId ?? '',
        url: imageURL,
        path: imagePath ?? '',
        width: imageWidth,
        height: imageHeight,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
      ));

      _sendMessageHandler(
        content: content,
        messageType: MessageType.template,
        replaceMessageId: replaceMessageId,
        resendMessage: resendMessage,
        decryptSecret: encryptedKey,
        decryptNonce: encryptedNonce,
      );
    } catch (_) {
      return;
    }
  }

  Future sendGifImageMessage(BuildContext context, GiphyImage image) async {
    File? file;
    String? url;
    if (image.url.isRemoteURL) {
      url = image.url;
    } else {
      file = File(image.url);
    }

    await sendImageMessage(
      context: context,
      imageFile: file,
      url: url,
    );
  }

  void sendInsertedContentMessage(BuildContext context, KeyboardInsertedContent insertedContent) {
    String base64String =
        'data:${insertedContent.mimeType};base64,${base64.encode(insertedContent.data!)}';
    _sendMessageHandler(
      context: context,
      content: base64String,
      messageType: MessageType.text,
    );
  }

  Future sendVoiceMessage(BuildContext context, String path, Duration duration) async {
    OXLoading.show();
    // File audioFile = File(path);
    // final duration = await ChatVoiceMessageHelper.getAudioDuration(audioFile.path);
    // final bytes = await audioFile.readAsBytes();

    await _sendMessageHandler(
      context: context,
      content: path,
      messageType: fileEncryptionType == types.EncryptionType.encrypted
          ? MessageType.encryptedAudio
          : MessageType.audio,
    );

    OXLoading.dismiss();
  }

  Future sendVideoMessageWithFile(BuildContext? context, List<Media> videos) async {
    for (final videoMedia in videos) {
      final videoPath = videoMedia.path ?? '';
      if (videoPath.isEmpty) continue;

      OXLoading.show();
      final videoFile = File(videoPath);
      final fileId = await EncodeUtils.generateMultiSampleFileKey(videoFile);

      File? thumbnailImageFile;
      final thumbPath = videoMedia.thumbPath ?? '';
      if (thumbPath.isNotEmpty) {
        thumbnailImageFile = File(thumbPath);
      } else {
        thumbnailImageFile = await VideoDataManager.shared.fetchVideoThumbnailWithLocalFile(
          videoFilePath: videoFile.path,
          cacheKey: fileId,
        );
      }

      if (thumbnailImageFile == null) {
        assert(false, 'thumbnailImageFile is null');
        OXLoading.dismiss();
        return;
      }

      ui.Image? thumbnailImage;
      final bytes = await thumbnailImageFile.readAsBytes();
      thumbnailImage = await decodeImageFromList(bytes);

      String? encryptedKey;
      String? encryptedNonce;
      String? videoURL;
      final uploadResult = UploadManager.shared.getUploadResult(fileId, otherUser?.pubKey);
      if (uploadResult?.isSuccess == true) {
        OXLoading.dismiss();
        final url = uploadResult?.url;
        encryptedKey = uploadResult?.encryptedKey;
        encryptedNonce = uploadResult?.encryptedNonce;
        if (url != null && url.isNotEmpty) {
          videoURL = generateUrlWithInfo(
            originalUrl: url,
            width: thumbnailImage.width,
            height: thumbnailImage.height,
          );
        }

        await sendVideoMessage(
          context: context,
          videoPath: null,
          videoURL: videoURL,
          snapshotPath: null,
          imageWidth: thumbnailImage.width,
          imageHeight: thumbnailImage.height,
          fileId: fileId,
          encryptedKey: encryptedKey,
          encryptedNonce: encryptedNonce,
        );

        return;
      } else {
        encryptedKey =
            fileEncryptionType == types.EncryptionType.encrypted ? createEncryptKey() : null;
        encryptedNonce =
            fileEncryptionType == types.EncryptionType.encrypted ? createEncryptNonce() : null;
      }

      final encryptedVideoFile = await encryptFile(
        origin: videoFile,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
        fileType: CacheFileType.video,
      );
      videoFile.delete();
      if (encryptedVideoFile == null) {
        assert(false, 'encryptedVideoFile is null');
        OXLoading.dismiss();
        return;
      }

      final encryptedThumbnailImageFile = await encryptFile(
        origin: thumbnailImageFile,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
        fileType: CacheFileType.image,
      );
      thumbnailImageFile.delete();
      if (encryptedThumbnailImageFile == null) {
        assert(false, 'encryptedThumbnailImageFile is null');
        OXLoading.dismiss();
        return;
      }

      OXLoading.dismiss();
      await sendVideoMessage(
        context: context,
        videoPath: encryptedVideoFile.path,
        videoURL: videoURL,
        snapshotPath: encryptedThumbnailImageFile.path,
        imageWidth: thumbnailImage.width,
        imageHeight: thumbnailImage.height,
        fileId: fileId,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
      );
    }
  }

  Future sendVideoMessage({
    BuildContext? context,
    String? videoPath,
    String? videoURL,
    String? snapshotPath,
    int? imageWidth,
    int? imageHeight,
    String? fileId,
    String? encryptedKey,
    String? encryptedNonce,
    types.CustomMessage? resendMessage,
  }) async {
    if (resendMessage != null) {
      videoPath = VideoMessageEx(resendMessage).videoPath;
      videoURL = VideoMessageEx(resendMessage).url;
      snapshotPath = VideoMessageEx(resendMessage).snapshotPath;
      imageWidth = VideoMessageEx(resendMessage).width;
      imageHeight = VideoMessageEx(resendMessage).height;
      fileId = VideoMessageEx(resendMessage).fileId;
      encryptedKey = resendMessage.decryptKey;
      encryptedNonce = resendMessage.decryptNonce;
    }

    if (videoURL != null && videoURL.isRemoteURL) {
      sendVideoMessageWithURL(
        videoURL: videoURL,
        fileId: fileId ?? '',
        videoPath: videoPath,
        snapshotPath: snapshotPath,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        resendMessage: resendMessage,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
      );
      return;
    }

    if (videoPath == null || fileId == null) return;
    String content = '';
    try {
      content = jsonEncode(CustomMessageEx.videoMetaData(
        fileId: fileId,
        snapshotPath: snapshotPath ?? '',
        videoPath: videoPath,
        url: videoURL ?? '',
        width: imageWidth,
        height: imageHeight,
        encryptedKey: encryptedKey,
        encryptedNonce: encryptedNonce,
      ));
    } catch (_) {}
    if (content.isEmpty) return;

    UploadManager.shared.prepareUploadStream(fileId, otherUser?.pubKey);
    final sendMessage = await _sendMessageHandler(
      context: context,
      content: content,
      messageType: MessageType.template,
      sendingType: ChatSendingType.store,
      decryptSecret: encryptedKey,
      decryptNonce: encryptedNonce,
    );
    if (sendMessage == null) return;

    if (session.isSelfChat) return;

    final (uploadResult, isFromCache) = await UploadManager.shared.uploadFile(
      fileType: FileType.video,
      filePath: videoPath,
      uploadId: fileId,
      receivePubkey: otherUser?.pubKey ?? '',
      encryptedKey: encryptedKey,
      encryptedNonce: encryptedNonce,
    );

    videoURL = uploadResult.url;
    if (!uploadResult.isSuccess || videoURL.isEmpty) {
      final status = types.Status.error;
      dataController.updateMessage(sendMessage.copyWith(
        status: status,
      ));
      ChatMessageHelper.updateMessageWithMessageId(
        messageId: sendMessage.id,
        status: status,
      );
      return;
    }

    videoURL = generateUrlWithInfo(
      originalUrl: videoURL,
      width: imageWidth,
      height: imageHeight,
    );

    if (snapshotPath != null && snapshotPath.isNotEmpty && !isFromCache) {
      snapshotPath = (await VideoDataManager.shared.putThumbnailToCacheWithURL(
        videoURL: videoURL,
        thumbnailPath: snapshotPath,
      )).path;
    }
    
    CacheManagerHelper.cacheFile(
      file: File(videoPath),
      url: videoURL,
      fileType: CacheFileType.video,
    );

    sendVideoMessageWithURL(
      videoURL: videoURL,
      fileId: fileId,
      videoPath: videoPath,
      snapshotPath: snapshotPath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      replaceMessageId: sendMessage.id,
      encryptedKey: encryptedKey,
      encryptedNonce: encryptedNonce,
    );
  }

  void sendVideoMessageWithURL({
    required String videoURL,
    String fileId = '',
    String? videoPath,
    String? snapshotPath,
    int? imageWidth,
    int? imageHeight,
    String? replaceMessageId,
    String? encryptedKey,
    String? encryptedNonce,
    types.Message? resendMessage,
  }) {
    try {
      final contentJson = jsonEncode(
        CustomMessageEx.videoMetaData(
          fileId: fileId,
          snapshotPath: snapshotPath ?? '',
          videoPath: videoPath ?? '',
          url: videoURL,
          width: imageWidth,
          height: imageHeight,
          encryptedKey: encryptedKey,
          encryptedNonce: encryptedNonce,
        ),
      );
      _sendMessageHandler(
        content: contentJson,
        messageType: MessageType.template,
        replaceMessageId: replaceMessageId,
        resendMessage: resendMessage,
        decryptSecret: encryptedKey,
        decryptNonce: encryptedNonce,
      );
    } catch (_) {}
  }

  void _sendTemplateMessage({
    BuildContext? context,
    String title = '',
    String content = '',
    String icon = '',
    String link = '',
  }) {
    try {
      final contentJson = jsonEncode(
        CustomMessageEx.templateMetaData(
          title: title,
          content: content,
          icon: icon,
          link: link,
        ),
      );
      _sendMessageHandler(
        context: context,
        content: contentJson,
        messageType: MessageType.template,
      );
    } catch (_) {}
  }

  void sendSystemMessage(
    String text, {
    BuildContext? context,
    String? localTextKey,
    ChatSendingType sendingType = ChatSendingType.remote,
  }) {
    _sendMessageHandler(
      context: context,
      content: localTextKey ?? text,
      messageType: MessageType.system,
      sendingType: sendingType,
    );
  }
}

extension ChatMessageSendUtileEx on ChatGeneralHandler {
  String createEncryptKey() => bytesToHex(AesEncryptUtils.secureRandom());
  String createEncryptNonce() => bytesToHex(AesEncryptUtils.secureRandomNonce());

  Future<UploadResult> uploadFile({
    required FileType fileType,
    required String filePath,
    required String messageId,
    String? encryptedKey,
    String? encryptedNonce,
  }) async {
    final file = File(filePath);
    final ext = filePath.getFileExtension();
    final fileName = '$messageId$ext';
    return await UploadUtils.uploadFile(
        fileType: fileType, file: file, filename: fileName, encryptedKey: encryptedKey, encryptedNonce: encryptedNonce);
  }

  Future<types.Message?> tryPrepareSendFileMessage(
      BuildContext? context, types.Message message) async {
    types.Message? updatedMessage;
    if (message is types.AudioMessage) {
      updatedMessage = await prepareSendAudioMessage(
        message: message,
        context: context,
      );
    } else {
      return message;
    }

    return updatedMessage;
  }

  Future<types.Message?> prepareSendAudioMessage({
    BuildContext? context,
    required types.AudioMessage message,
  }) async {
    final filePath = message.uri;
    final uriIsLocalPath = filePath.isLocalPath;

    if (uriIsLocalPath == null) {
      ChatLogUtils.error(
        className: 'ChatMessageSendEx',
        funcName: 'prepareSendAudioMessage',
        message: 'uriIsLocalPath is null, message: ${message.toJson()}',
      );
      return null;
    }
    if (uriIsLocalPath) {
      final encryptedKey =
          fileEncryptionType == types.EncryptionType.encrypted ? createEncryptKey() : null;
      final encryptedNonce =
          fileEncryptionType == types.EncryptionType.encrypted ? createEncryptNonce() : null;
      final result = await uploadFile(
          fileType: FileType.voice,
          filePath: filePath,
          messageId: message.id,
          encryptedKey: encryptedKey,
          encryptedNonce: encryptedNonce);
      if (!result.isSuccess) {
        CommonToast.instance.show(
            context, '${Localized.text('ox_chat.message_send_audio_fail')}: ${result.errorMsg}');
        return null;
      }

      final audioURL = result.url;
      final audioFile = File(filePath);

      return message.copyWith(
        uri: audioURL,
        audioFile: audioFile,
        decryptKey: encryptedKey,
        decryptNonce: encryptedNonce,
      );
    }
    return message;
  }

  String generateUrlWithInfo({
    required String originalUrl,
    int? width,
    int? height,
  }) {
    Uri uri;
    try {
      uri = Uri.parse(originalUrl);
    } catch (_) {
      return originalUrl;
    }

    final originalQuery = uri.queryParameters;
    final updatedUri = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        if (width != null && !originalQuery.containsKey('width')) 'width': width.toString(),
        if (height != null && !originalQuery.containsKey('height')) 'height': height.toString(),
      },
    );

    return updatedUri.toString();
  }

  Future<File?> encryptFile({
    required File origin,
    required String? encryptedKey,
    required String? encryptedNonce,
    required CacheFileType fileType
  }) async {
    if (encryptedKey == null && encryptedNonce == null) return origin;

    final fileName = '${Uuid().v1()}.${origin.path.getFileExtension()}';
    File? encryptedFile;

    final cacheManager = await CLCacheManager.getCircleCacheManager(fileType);
    encryptedFile = await cacheManager.store.fileSystem.createFile(fileName);
    await AesEncryptUtils.encryptFileInIsolate(
      origin,
      encryptedFile,
      encryptedKey ?? '',
      nonce: encryptedNonce,
      mode: AESMode.gcm,
    );
    return encryptedFile;
  }
}
