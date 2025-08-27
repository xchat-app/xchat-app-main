import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';

/// Utility class for profile refresh operations
class ProfileRefreshUtils {
  ProfileRefreshUtils._();

  /// Shows a profile refresh confirmation dialog and executes the refresh operation
  /// Returns true if refresh was successful, false if cancelled or failed
  static Future<bool> showProfileRefreshDialog(
    BuildContext context, {
    String? titleKey,
    String? contentKey,
    String? successKey,
    String? failureKey,
    String? userNotFoundKey,
    String? relayConnectionFailedKey,
    String? specificRelay = 'wss://relay.nostr.band',
  }) async {
    // Show confirmation dialog
    final shouldRefreshFromSpecificRelay = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text(titleKey ?? 'ox_usercenter.refresh_profile'),
      content: Localized.text(contentKey ?? 'ox_usercenter.refresh_profile_from_relay_confirm'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.confirm'),
          value: true,
        ),
      ],
    );

    if (shouldRefreshFromSpecificRelay != true) return false;

    try {
      final currentUser = LoginManager.instance.currentState.account;
      if (currentUser == null) {
        CommonToast.instance.show(
          context, 
          Localized.text(userNotFoundKey ?? 'ox_common.user_not_found')
        );
        return false;
      }

      // Show loading indicator
      OXLoading.show();

      // Connect to specific relay as temp type
      final connectSuccess = await Connect.sharedInstance.connectRelays(
        [specificRelay!], 
        relayKind: RelayKind.temp
      );

      if (!connectSuccess) {
        CommonToast.instance.show(
          context, 
          '${Localized.text(relayConnectionFailedKey ?? 'ox_usercenter.relay_connection_failed')}: $specificRelay'
        );
        return false;
      }

      // Reload profile from specific relay
      await Account.sharedInstance.reloadProfileFromRelay(
        currentUser.pubkey, 
        relays: [specificRelay]
      );

      // Close temp relay connection after use
      await Connect.sharedInstance.closeTempConnects([specificRelay!]);

      // Dismiss loading and show success message
      OXLoading.dismiss();
      CommonToast.instance.show(
        context, 
        Localized.text(successKey ?? 'ox_usercenter.refresh_profile_success')
      );

      return true;

    } catch (e) {
      OXLoading.dismiss();
      CommonToast.instance.show(
        context, 
        '${Localized.text(failureKey ?? 'ox_usercenter.refresh_profile_failed')}: $e'
      );
      return false;
    }
  }

  /// Shows a user profile refresh confirmation dialog and executes the refresh operation
  /// Returns true if refresh was successful, false if cancelled or failed
  static Future<bool> showUserProfileRefreshDialog(
    BuildContext context, {
    required String pubkey,
    String? titleKey,
    String? contentKey,
    String? successKey,
    String? failureKey,
    String? userPubkeyNotFoundKey,
    String? relayConnectionFailedKey,
    String? specificRelay = 'wss://relay.nostr.band',
  }) async {
    if (pubkey.isEmpty) {
      CommonToast.instance.show(
        context, 
        Localized.text(userPubkeyNotFoundKey ?? 'ox_chat.user_pubkey_not_found')
      );
      return false;
    }

    // Show confirmation dialog
    final shouldRefreshFromSpecificRelay = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text(titleKey ?? 'ox_usercenter.refresh_user_profile'),
      content: Localized.text(contentKey ?? 'ox_usercenter.refresh_user_profile_from_relay_confirm'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.confirm'),
          value: true,
        ),
      ],
    );

    if (shouldRefreshFromSpecificRelay != true) return false;

    try {
      // Show loading indicator
      OXLoading.show();

      // Connect to specific relay as temp type
      final connectSuccess = await Connect.sharedInstance.connectRelays(
        [specificRelay!], 
        relayKind: RelayKind.temp
      );

      if (!connectSuccess) {
        CommonToast.instance.show(
          context, 
          '${Localized.text(relayConnectionFailedKey ?? 'ox_usercenter.relay_connection_failed')}: $specificRelay'
        );
        return false;
      }

      // Reload profile from specific relay
      await Account.sharedInstance.reloadProfileFromRelay(
        pubkey, 
        relays: [specificRelay]
      );

      // Close temp relay connection after use
      await Connect.sharedInstance.closeTempConnects([specificRelay!]);

      // Dismiss loading and show success message
      OXLoading.dismiss();
      CommonToast.instance.show(
        context, 
        Localized.text(successKey ?? 'ox_usercenter.refresh_user_profile_success')
      );

      return true;

    } catch (e) {
      OXLoading.dismiss();
      CommonToast.instance.show(
        context, 
        '${Localized.text(failureKey ?? 'ox_usercenter.refresh_user_profile_failed')}: $e'
      );
      return false;
    }
  }
}
