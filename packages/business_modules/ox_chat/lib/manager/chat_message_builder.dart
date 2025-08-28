import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:ox_chat/manager/chat_message_helper.dart';
import 'package:ox_chat/utils/custom_message_utils.dart';
import 'package:ox_chat/widget/chat_video_message.dart';
import 'package:ox_chat/widget/chat_image_preview_widget.dart';
import 'package:ox_common/business_interface/ox_chat/call_message_type.dart';
import 'package:ox_common/business_interface/ox_chat/custom_message_type.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/upload/upload_utils.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/color_extension.dart';
import 'package:ox_common/utils/date_utils.dart';
import 'package:ox_common/utils/platform_utils.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/utils/theme_color.dart';
import 'package:ox_common/utils/took_kit.dart';
import 'package:ox_common/utils/widget_tool.dart';
import 'package:ox_common/widgets/common_image.dart';
import 'package:ox_common/widgets/common_long_content_page.dart';

part 'chat_message_builder_custom.dart';

class ChatMessageBuilder {
  static Widget bubbleWrapper({
    required bool isMe,
    required Widget child,
  }) {
    final ctx = OXNavigator.navigatorKey.currentContext!;
    return Container(
      color: isMe
          ? ColorToken.primary.of(ctx)
          : ColorToken.surfaceContainer.of(ctx),
      child: child,
    );
  }

  static Widget buildRepliedMessageView({
    required types.Message message,
    required int messageWidth,
    required bool currentUserIsAuthor,
    Function(types.Message? message)? onTap,
  }) {
    final repliedMessageId = message.repliedMessageId;
    final repliedMessage = message.repliedMessage;
    if (repliedMessageId == null || repliedMessageId.isEmpty || repliedMessage == null)
      return SizedBox();

    Color bgColor = ColorToken.secondaryXChat.of(OXNavigator.rootContext)
        .withValues(alpha: 0.3);

    Color bgBorderColor;
    if (currentUserIsAuthor) {
      bgBorderColor = Colors.white;
    } else {
      bgBorderColor = ColorToken.xChat.of(OXNavigator.rootContext).withValues(alpha: 0.5);
    }

    return GestureDetector(
      onTap: () => onTap?.call(repliedMessage),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: messageWidth.toDouble(),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: bgBorderColor,
                  width: 4,
                ),
              ),
              color: bgColor,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 6.px,
              vertical: 4.px,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAuthorName(
                  message: repliedMessage,
                  currentUserIsAuthor: currentUserIsAuthor,
                ),
                SizedBox(height: 2.px,),
                _buildMsgContent(
                  message: repliedMessage,
                  currentUserIsAuthor: currentUserIsAuthor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildAuthorName({
    required types.Message message,
    required bool currentUserIsAuthor,
  }) {
    String name = message.author.firstName ?? '[Not Found]';
    return Padding(
      padding: EdgeInsetsDirectional.only(
        end: 4.px,
      ),
      child: CLText.labelMedium(
        name,
        colorToken: currentUserIsAuthor ? ColorToken.white : ColorToken.onSurface,
        isBold: true,
      ),
    );
  }

  static Widget _buildMsgContent({
    required types.Message message,
    required bool currentUserIsAuthor,
  }) {
    return CLText.labelSmall(
      message.messagePreviewText,
      maxLines: 2,
      colorToken: currentUserIsAuthor ? ColorToken.white : ColorToken.onSurface,
      overflow: TextOverflow.ellipsis,
    );
  }

  static Widget buildCodeBlockWidget({
    required BuildContext context,
    required String codeText,
  }) {
    Widget codeTextWidget = Text(
      codeText,
      style: TextStyle(
        fontSize: 14.sp,
        color: ThemeColor.white,
      ),
    );

    Widget widget =  GestureDetector(
      onTap: () {
        TookKit.copyKey(context, codeText);
      },
      child: Opacity(
        opacity: 0.8,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Colors.white,
                width: 2,
              ),
            ),
          ),
          child: IntrinsicWidth(
            child: Column(
              children: [
                Container(
                  color: ThemeColor.color170,
                  height: 20.px,
                  padding: EdgeInsets.symmetric(horizontal: 8.px),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'copy',
                        style: TextStyle(
                          fontSize: 14.sp,
                          color: ThemeColor.white,
                        ),
                      ),
                      SizedBox(width: 20.px,),
                      CommonImage(
                        iconName: 'icon_copy.png',
                        package: 'ox_chat',
                        size: 12.px,
                      ),
                    ],
                  ),
                ),
                Container(
                  color: ThemeColor.darkColor,
                  padding: EdgeInsets.symmetric(
                    horizontal: 8.px,
                    vertical: 4.px,
                  ),
                  alignment: Alignment.centerLeft,
                  child: codeTextWidget,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (PlatformUtils.isDesktop) {
      widget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: widget,
      );
    }

    return widget;
  }

  static InlineSpan moreButtonBuilder({
    required BuildContext context,
    required types.TextMessage message,
    required String moreText,
    required bool isMessageSender,
    TextStyle? bodyTextStyle,
  }) {
    final moreBtnColor = isMessageSender
        ? Colors.black.withValues(alpha: 0.6)
        : ThemeColor.gradientMainStart;
    bodyTextStyle ;
    Widget textWidget = Text(
      moreText,
      style: bodyTextStyle?.copyWith(
        color: moreBtnColor,
        height: 1.1,
      ),
    );

    if (PlatformUtils.isDesktop) {
      textWidget = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => CommonLongContentPage.present(
            context: context,
            content: message.text.trim(),
            author: message.author.sourceObject,
            timeStamp: message.createdAt,
          ),
          child: textWidget,
        ),
      );
    }

    return WidgetSpan(
      child: textWidget,
    );
  }

  static Widget buildImageMessage(types.ImageMessage message, {
    required int messageWidth,
  }) {
    return ChatImagePreviewWidget(
      uri: message.uri,
      imageWidth: message.width?.toInt(),
      imageHeight: message.height?.toInt(),
      maxWidth: messageWidth.toDouble(),
      decryptKey: message.decryptKey,
      decryptNonce: message.decryptNonce
    );
  }

  static Widget buildCustomMessage({
    required types.CustomMessage message,
    required int messageWidth,
    required BorderRadius borderRadius,
    String? receiverPubkey,
    Function(types.Message newMessage)? messageUpdateCallback,
    required bool isSelfChat,
  }) {
    final isMe = message.isMe;
    final type = message.customType;

    switch (type) {
      case CustomMessageType.template:
        return ChatMessageBuilderCustomEx._buildTemplateMessage(message, isMe);
      case CustomMessageType.note:
        return ChatMessageBuilderCustomEx._buildNoteMessage(message, isMe);
      case CustomMessageType.imageSending:
        return ChatMessageBuilderCustomEx._buildImageSendingMessage(
          message,
          messageWidth,
          borderRadius,
          receiverPubkey,
          isMe,
          isSelfChat,
        );
      case CustomMessageType.video:
        return ChatMessageBuilderCustomEx._buildVideoMessage(
          message,
          messageWidth,
          borderRadius,
          receiverPubkey,
          isMe,
          messageUpdateCallback,
          isSelfChat,
        );
      default:
        return SizedBox();
    }
  }
}

extension CallMessageTypeEx on CallMessageType {
  String get iconName {
    switch (this) {
      case CallMessageType.audio:
        return 'icon_message_call.png';
      case CallMessageType.video:
        return 'icon_message_camera.png';
    }
  }
}