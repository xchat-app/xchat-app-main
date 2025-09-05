import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ox_chat/manager/chat_data_cache.dart';
import 'package:ox_chat/message_handler/chat_message_helper.dart';
import 'package:ox_chat/page/contacts/contact_user_info_page.dart';
import 'package:ox_chat/page/contacts/groups/group_info_page.dart';
import 'package:ox_chat/page/session/chat_message_page.dart';
import 'package:ox_chat/page/session/chat_video_play_page.dart';
import 'package:ox_chat/utils/general_handler/chat_general_handler.dart';
import 'package:ox_chat/utils/general_handler/chat_nostr_scheme_handler.dart';
import 'package:ox_common/business_interface/ox_chat/interface.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/model/chat_session_model_isar.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/scheme/scheme_helper.dart';
import 'package:ox_common/utils/ox_chat_binding.dart';
import 'package:ox_module_service/ox_module_service.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:chatcore/chat-core.dart';
import 'package:isar/isar.dart';

class OXChat extends OXFlutterModule {
  @override
  Future<void> setup() async {
    super.setup();
    LoginManager.instance.addObserver(ChatDataCache.shared);
    OXChatBinding.sharedInstance.sessionMessageTextBuilder = ChatMessageHelper.sessionMessageTextBuilder;
  }

  @override
  Map<String, Function> get interfaces => {
    'sendSystemMsg': _sendSystemMsg,
    'contactUserInfoPage': _contactUserInfoPage,
    'groupInfoPage': _groupInfoPage,
    'sendTemplateMessage': _sendTemplateMessage,
    'getTryDecodeNostrScheme': getTryDecodeNostrScheme,
  };

  @override
  String get moduleName => OXChatInterface.moduleName;

  @override
  List<IsarGeneratedSchema> get isarDBSchemes => [];

  @override
  Future<T?>? navigateToPage<T>(BuildContext context, String pageName, Map<String, dynamic>? params) {
    switch (pageName) {
      case 'ChatRelayGroupMsgPage':
      case 'ChatGroupMessagePage':
        return ChatMessagePage.open(
          context: context,
          communityItem: ChatSessionModelISAR(
            chatId: params?['chatId'] ?? '',
            chatName: params?['chatName'] ?? '',
            chatType: params?['chatType'] ?? 0,
            createTime: params?['time'] ?? '',
            avatar: params?['avatar'] ?? '',
            groupId: params?['groupId'] ?? '',
          ),
          anchorMsgId: params?['msgId'],
        );
      case 'ContactUserInfoPage':
        return OXNavigator.pushPage(
          context,
          (context) => ContactUserInfoPage(
            pubkey: params?['pubkey'],
            chatId: params?['chatId'],
          ),
        );
      case 'GroupInfoPage':
        return OXNavigator.pushPage(
          context,
              (context) => GroupInfoPage(
            groupId: params?['groupId'],
          ),
        );
      case 'ChatVideoPlayPage':
        return OXNavigator.pushPage(context, (context) => ChatVideoPlayPage(
          videoUrl: params?['videoUrl'] ?? '',
        ),fullscreenDialog:true,
          type: OXPushPageType.present,
        );
    }
    return null;
  }

  void _contactUserInfoPage(BuildContext? context,{required String pubkey}){
    OXNavigator.pushPage(context!, (context) => ContactUserInfoPage(pubkey: pubkey));
  }

  Future<void> _groupInfoPage(BuildContext? context,{required String groupId}) async {
    OXNavigator.pushPage(context!, (context) => GroupInfoPage(groupId: groupId));
  }

  void _sendSystemMsg(BuildContext context,{required String chatId,required String content, required String localTextKey}){
    UserDBISAR? userDB = Account.sharedInstance.me;

    ChatSessionModelISAR? sessionModel = OXChatBinding.sharedInstance.sessionModelFetcher?.call(chatId);
    if(sessionModel == null) return;

    ChatGeneralHandler chatGeneralHandler = ChatGeneralHandler(
      author: types.User(
        id: userDB!.pubKey,
        sourceObject: userDB,
      ),
      session: sessionModel,
    );

    chatGeneralHandler.sendSystemMessage(
      content,
      context: context,
      localTextKey:localTextKey,
    );
  }

  void _sendTemplateMessage(
    BuildContext? context, {
      String receiverPubkey = '',
      String title = '',
      String subTitle = '',
      String icon = '',
      String link = '',
      int chatType = ChatType.chatSingle,
  }) {
    ChatMessageSendEx.sendTemplateMessage(
      receiverPubkey: receiverPubkey,
      title: title,
      subTitle: subTitle,
      icon: icon,
      link: link,
      chatType: chatType,
    );
  }

  Future<String> loadFileByAndroid(File file) async {
    String fileContent = '';
    final content = await file.readAsString();
    fileContent = Uri.dataFromString(
      content,
      mimeType: 'text/html',
      encoding: Encoding.getByName('utf-8'),
    ).toString();
    return fileContent;
  }

  Future<String?> getTryDecodeNostrScheme(String content) async {
    String? result = await ChatNostrSchemeHandle.tryDecodeNostrScheme(content);
    return result;
  }
}
