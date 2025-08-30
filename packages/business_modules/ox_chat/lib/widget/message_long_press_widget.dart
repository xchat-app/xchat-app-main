import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:ox_chat/manager/chat_message_helper.dart';
import 'package:ox_chat/model/constant.dart';
import 'package:ox_chat/utils/custom_message_utils.dart';
import 'package:ox_chat/utils/general_handler/chat_general_handler.dart';
import 'package:ox_common/business_interface/ox_chat/custom_message_type.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:super_context_menu/super_context_menu.dart';

class MessageLongPressMenu {
  static Menu buildContextMenu(
    BuildContext context,
    types.Message message,
    ChatGeneralHandler handler,
  ) {
    final List<MenuElement> menuItems = [];

    if (message is types.TextMessage || message.isImageMessage) {
      menuItems.add(
        MenuAction(
          title: Localized.text('ox_chat.message_menu_copy'),
          image: MenuImage.icon(CupertinoIcons.doc_on_doc),
          callback: () {
            handler.menuItemPressHandler(context, message, MessageLongPressEventType.copy);
          },
        ),
      );
    }
    
    // Quote action
    if (message.canReply) {
      menuItems.add(
        MenuAction(
          title: Localized.text('ox_chat.message_menu_quote'),
          image: MenuImage.icon(CupertinoIcons.reply),
          callback: () {
            handler.menuItemPressHandler(
              context,
              message,
              MessageLongPressEventType.quote,
            );
          },
        ),
      );
    }

    // Save action for image messages
    if (message.isImageMessage) {
      menuItems.add(
        MenuAction(
          title: Localized.text('ox_chat.message_menu_save'),
          image: MenuImage.icon(Icons.save_alt_outlined),
          callback: () {
            handler.menuItemPressHandler(context, message, MessageLongPressEventType.save);
          },
        ),
      );
    }

    // Report action
    if (!handler.session.isSingleChat && !message.isMe) {
      menuItems.add(
        MenuAction(
          title: Localized.text('ox_chat.message_menu_report'),
          image: MenuImage.icon(CupertinoIcons.exclamationmark_circle),
          callback: () {
            handler.menuItemPressHandler(context, message, MessageLongPressEventType.report);
          },
        ),
      );
    }
    
    // Delete action with red color
    menuItems.add(
      MenuAction(
        title: Localized.text('ox_chat.message_menu_delete'),
        image: MenuImage.icon(CupertinoIcons.delete),
        attributes: const MenuActionAttributes(
          destructive: true,
        ),
        callback: () {
          handler.menuItemPressHandler(context, message, MessageLongPressEventType.delete);
        },
      ),
    );
    
    return Menu(
      children: menuItems,
    );
  }
  
  static Widget buildContextMenuWidget({
    required BuildContext context,
    required types.Message message,
    required ChatGeneralHandler handler,
    required Widget child,
  }) {
    return ContextMenuWidget(
      // liftBuilder: (BuildContext context, Widget child) => SizedBox(),
      menuProvider: (MenuRequest request) {
        return buildContextMenu(context, message, handler);
      },
      child: child,
    );
  }
}