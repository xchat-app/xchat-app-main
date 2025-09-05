import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/scheme/scheme_helper.dart';
import 'package:ox_common/utils/scan_utils.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/component.dart';
import 'package:ox_module_service/ox_module_service.dart';
import 'package:ox_localizable/ox_localizable.dart';

import 'page/chat_choose_share_page.dart';


class OxChatHome extends OXFlutterModule {
  @override
  String get moduleName => 'ox_home';

  @override
  Future<void> setup() async {
    await super.setup();
    SchemeHelper.defaultHandler = nostrHandler;
    SchemeHelper.register('nostr', nostrHandler);
    SchemeHelper.register('nprofile', nostrHandler);
    SchemeHelper.register('xchat', nostrHandler);
    SchemeHelper.register('shareLinkWithScheme', shareLinkWithScheme);
  }

  @override
  Future<T?>? navigateToPage<T>(
      BuildContext context, String pageName, Map<String, dynamic>? params) {
    return null;
  }

  nostrHandler(
      String scheme, String action, Map<String, String> queryParameters) async {
    BuildContext? context = OXNavigator.navigatorKey.currentContext;
    if (context == null) return;

    // Handle Universal Links for invite links
    if (action == 'invite_link') {
      await ScanUtils.analysis(context, scheme);
      return;
    }

    // Handle Universal Links
    if (action == 'universal_lite') {
      await ScanUtils.analysis(context, scheme);
      return;
    }



    String nostrString = '';
    if (action == 'nostr') {
      nostrString = queryParameters['value'] ?? '';
    } else if (action == 'nprofile') {
      nostrString = queryParameters['value'] ?? '';
    } else {
      nostrString = action;
    }
    if (nostrString.isEmpty) return;

    // Special handling for xchat scheme
    if (scheme == 'xchat') {
      // Extract the nprofile part from the full URL
      final nprofilePart =
          nostrString.replaceFirst('xchat://', '').replaceFirst('//', '');
      await _handlexchatNprofile(context, nprofilePart);
    } else {
      // Use existing ScanUtils for other schemes
      ScanUtils.analysis(context, nostrString);
    }
  }

  Future<void> _handlexchatNprofile(
      BuildContext context, String nprofileString) async {
    try {
      // Decode nprofile to get pubkey and relays
      final data = Account.decodeProfile(nprofileString);

      if (data == null || data.isEmpty) {
        _showErrorDialog(context, Localized.text('ox_home.invalid_nprofile_format'));
        return;
      }

      final pubkey = data['pubkey'] as String? ?? '';
      final relays = (data['relays'] as List<dynamic>?)?.cast<String>() ?? [];

      if (pubkey.isEmpty) {
        _showErrorDialog(context, Localized.text('ox_home.invalid_pubkey'));
        return;
      }

      // Check if we're already in a circle with these relays
      final currentCircle = LoginManager.instance.currentCircle;
      bool isInSameCircle = false;

      if (currentCircle != null && relays.isNotEmpty) {
        // Check if any of the nprofile relays match current circle relay
        for (final relay in relays) {
          if (currentCircle.relayUrl == relay ||
              currentCircle.relayUrl.replaceFirst(RegExp(r'/+$'), '') ==
                  relay.replaceFirst(RegExp(r'/+$'), '')) {
            isInSameCircle = true;
            break;
          }
        }
      }

      if (isInSameCircle) {
        // Already in the same circle, navigate to user detail page
        await _navigateToUserDetail(context, pubkey);
      } else if (relays.isNotEmpty) {
        // Not in the same circle, show join circle dialog
        await _showJoinCircleDialog(context, relays, pubkey);
      } else {
        // No relays specified, navigate directly to user detail
        await _navigateToUserDetail(context, pubkey);
      }
    } catch (e) {
      _showErrorDialog(context, Localized.text('ox_home.failed_to_process_nprofile').replaceAll(r'${error}', e.toString()));
    }
  }

  Future<void> _showJoinCircleDialog(
      BuildContext context, List<String> relays, String pubkey) async {
    final primaryRelay = relays.first;
    final relayName = _extractRelayName(primaryRelay);

    final result = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_home.join_circle_dialog_title'),
      content:
          Localized.text('ox_home.join_circle_dialog_content').replaceAll(r'${relayName}', relayName),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.join_circle'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    );

    if (result == true) {
      // Join the circle
      await _joinCircleAndNavigate(context, primaryRelay, pubkey);
    }
  }

  Future<void> _joinCircleAndNavigate(
      BuildContext context, String relayUrl, String pubkey) async {
    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CLProgressIndicator.circular()),
      );

      // Create circle and join
      final circle = Circle(
        id: _generateCircleId(relayUrl),
        name: _extractRelayName(relayUrl),
        type: CircleType.relay,
        relayUrl: relayUrl,
      );

      // Join the circle
      final failure = await LoginManager.instance.joinCircle(relayUrl);

      // Hide loading
      Navigator.of(context).pop();

      if (failure == null) {
        // Navigate to user detail page
        await _navigateToUserDetail(context, pubkey);
      } else {
        _showErrorDialog(context, Localized.text('ox_home.failed_to_join_circle').replaceAll(r'${message}', failure.message));
      }
    } catch (e) {
      // Hide loading
      Navigator.of(context).pop();
              _showErrorDialog(context, Localized.text('ox_home.error_joining_circle').replaceAll(r'${error}', e.toString()));
    }
  }

  Future<void> _navigateToUserDetail(
      BuildContext context, String pubkey) async {
    // Get user info
    UserDBISAR? user = await Account.sharedInstance.getUserInfo(pubkey);
    if (user == null) {
      _showErrorDialog(context, Localized.text('ox_common.user_not_found'));
      return;
    }

    // Navigate to user detail page
    OXModuleService.pushPage(context, 'ox_chat', 'ContactUserInfoPage', {
      'pubkey': user.pubKey,
    });
  }

  void _showErrorDialog(BuildContext context, String message) {
    CLAlertDialog.show(
      context: context,
      title: Localized.text('ox_common.error'),
      content: message,
      actions: [
        CLAlertAction(
          label: Localized.text('ox_common.ok'),
          isDefaultAction: true,
        ),
      ],
    );
  }

  String _extractRelayName(String relayUrl) {
    try {
      final uri = Uri.parse(relayUrl);
      final host = uri.host;
      return host
          .replaceAll('relay.', '')
          .replaceAll('www.', '')
          .split('.')
          .first;
    } catch (e) {
      return relayUrl
          .replaceAll('wss://', '')
          .replaceAll('ws://', '')
          .split('/')
          .first;
    }
  }

  String _generateCircleId(String relayUrl) {
    // Simple hash of the relay URL to create a unique ID
    return relayUrl.hashCode.toString();
  }

  void shareLinkWithScheme(String scheme, String action, Map<String, String> queryParameters) {
    final text = queryParameters['text'] ?? '';
    final type = queryParameters['type'] ?? '';
    final path = queryParameters['path'] ?? '';
    if (text.isEmpty && path.isEmpty) return ;
    OXNavigator.pushPage(null, (context) => ChatChooseSharePage(
      msg: text,
      type: type,
      path: path,
    ));
  }
}
