import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/const/app_config.dart';
import 'package:ox_common/utils/compression_utils.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_chat/utils/chat_session_utils.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/login/circle_repository.dart';
import 'package:ox_common/login/login_manager.dart';

/// Type of invite link
enum InviteType {
  keypackage,  // KeyPackage invite (personal chat)
  circle,      // Circle invite (join tenant)
}

/// Type of keypackage invite link
enum InviteLinkType {
  oneTime,    // One-time invite link
  permanent,  // Permanent invite link
}

/// Manager for generating and regenerating invite links
class InviteLinkManager {
  InviteLinkManager._();

  /// Generate keypackage invite link
  /// 
  /// [linkType] Type of keypackage invite (oneTime or permanent)
  /// [context] BuildContext for showing dialogs and loading
  /// 
  /// Returns the invite link string
  /// Throws exception on error
  static Future<String> generateKeyPackageInviteLink({
    required InviteLinkType linkType,
    required BuildContext context,
  }) async {
    try {
      OXLoading.show();

      KeyPackageEvent? keyPackageEvent;

      if (linkType == InviteLinkType.oneTime) {
        keyPackageEvent = await Groups.sharedInstance.createOneTimeKeyPackage();
      } else {
        keyPackageEvent = await Groups.sharedInstance.createPermanentKeyPackage(
          Account.sharedInstance.getCurrentCircleRelay(),
        );
      }

      if (keyPackageEvent == null) {
        await OXLoading.dismiss();
        // Check if it's a keypackage expiration issue
        // Show dialog asking if user wants to refresh their keypackage
        final shouldRefresh = await CLAlertDialog.show<bool>(
          context: context,
          title: Localized.text('ox_chat.key_package_expired'),
          content: Localized.text('ox_chat.key_package_may_expired'),
          actions: [
            CLAlertAction.cancel(),
            CLAlertAction<bool>(
              label: Localized.text('ox_chat.refresh'),
              value: true,
              isDefaultAction: true,
            ),
          ],
        );

        if (shouldRefresh == true) {
          // Refresh keypackage and retry
          return await generateKeyPackageInviteLink(
            linkType: linkType,
            context: context,
          );
        }
        throw Exception('Failed to create keypackage');
      }

      // Get relay URL
      List<String> relays = Account.sharedInstance.getCurrentCircleRelay();
      String? relayUrl = relays.firstOrNull;
      if (relayUrl == null || relayUrl.isEmpty) {
        await OXLoading.dismiss();
        throw Exception('Error circle info');
      }

      // Generate invite link with compression
      String inviteLink;
      if (linkType == InviteLinkType.oneTime || linkType == InviteLinkType.permanent) {
        // For one-time invites, include sender's pubkey
        final senderPubkey = Account.sharedInstance.currentPubkey;

        // Try to compress the keypackage data
        String? compressedKeyPackage = await CompressionUtils.compressWithPrefix(keyPackageEvent.encoded_key_package);
        String keyPackageParam = compressedKeyPackage ?? keyPackageEvent.encoded_key_package;

        inviteLink = '${AppConfig.inviteBaseUrl}?keypackage=$keyPackageParam&pubkey=${Uri.encodeComponent(senderPubkey)}&relay=${Uri.encodeComponent(relayUrl)}';

        // Log compression results
        if (compressedKeyPackage != null) {
          double ratio = CompressionUtils.getCompressionRatio(keyPackageEvent.encoded_key_package, compressedKeyPackage);
          LogUtil.v(() => 'Keypackage compressed: ${(ratio * 100).toStringAsFixed(1)}% of original size');
        }
      } else {
        inviteLink = '${AppConfig.inviteBaseUrl}?eventid=${Uri.encodeComponent(keyPackageEvent.eventId)}&relay=${Uri.encodeComponent(relayUrl)}';
      }

      await OXLoading.dismiss();
      return inviteLink;
    } catch (e) {
      await OXLoading.dismiss();
      
      // Handle KeyPackageError
      final handled = await ChatSessionUtils.handleKeyPackageError(
        context: context,
        error: e,
        onRetry: () async {
          // Retry generating invite link
          await generateKeyPackageInviteLink(
            linkType: linkType,
            context: context,
          );
        },
        onOtherError: (message) {
          throw Exception('${Localized.text('ox_usercenter.invite_link_generation_failed')}: $e');
        },
      );

      if (!handled) {
        // Other errors
        throw Exception('${Localized.text('ox_usercenter.invite_link_generation_failed')}: $e');
      }
      
      // This should not be reached, but needed for type safety
      throw Exception('Failed to generate invite link');
    }
  }

  /// Generate circle invite link
  /// 
  /// [circle] The circle object
  /// [forceRegenerate] Force regenerate even if invitation code exists
  /// 
  /// Returns a map containing:
  /// - 'inviteLink': The invite link string
  /// - 'invitationCode': The invitation code
  /// Throws exception on error
  static Future<Map<String, dynamic>> generateCircleInviteLink({
    required Circle circle,
    bool forceRegenerate = false,
  }) async {
    try {
      String invitationCode;
      
      // 1. Check if invitation code exists in database
      if (!forceRegenerate && circle.invitationCode != null && circle.invitationCode!.isNotEmpty) {
        // Use existing invitation code
        invitationCode = circle.invitationCode!;
        LogUtil.v(() => 'Using cached invitation code for circle: ${circle.id}');
      } else {
        // 2. Generate new invitation code
        final invitationData = await CircleMemberService.sharedInstance.generateInvitationCode();
        invitationCode = invitationData['code'] as String? ?? '';
        
        if (invitationCode.isEmpty) {
          throw Exception('Failed to generate invitation code');
        }
        
        // 3. Update database
        final accountDb = LoginManager.instance.currentState.account?.db;
        if (accountDb != null) {
          final success = await CircleRepository.updateInvitationCode(
            accountDb,
            circle.id,
            invitationCode,
          );
          if (success) {
            // Update Circle object
            circle.invitationCode = invitationCode;
            LogUtil.v(() => 'Invitation code saved to database for circle: ${circle.id}');
          } else {
            LogUtil.w(() => 'Failed to save invitation code to database for circle: ${circle.id}');
          }
        }
      }
      
      // 4. Build invite link with circle address and invite code
      // Format: https://0xchat.com/x/invite?code={code}&relay={relayUrl}
      final inviteLink = 'https://0xchat.com/x/invite?code=${Uri.encodeComponent(invitationCode)}&relay=${Uri.encodeComponent(circle.relayUrl)}';
      
      return {
        'inviteLink': inviteLink,
        'invitationCode': invitationCode,
        'circleRelayUrl': circle.relayUrl,
      };
    } catch (e) {
      LogUtil.e(() => 'Failed to generate circle invite link: $e');
      rethrow;
    }
  }

  /// Regenerate keypackage invite link
  /// 
  /// [context] BuildContext for showing dialogs and loading
  /// 
  /// Returns the new invite link string
  /// Throws exception on error
  static Future<String> regenerateKeyPackageInviteLink({
    required BuildContext context,
  }) async {
    try {
      OXLoading.show();

      // Recreate permanent keypackage
      KeyPackageEvent? keyPackageEvent = await Groups.sharedInstance.recreatePermanentKeyPackage(
        Account.sharedInstance.getCurrentCircleRelay(),
      );

      if (keyPackageEvent == null) {
        await OXLoading.dismiss();
        throw Exception(Localized.text('ox_usercenter.invite_link_generation_failed'));
      }

      // Get relay URL. getCurrentCircleRelay always returns one element, which
      // is the empty string when there is no current circle, so isNotEmpty is
      // always true and the old fallback here could never run — the link was
      // built with relay= and nothing after it, which the receiving app
      // rejects as invalid_invite_link_missing_relay. Match the check that
      // generateKeyPackageInviteLink already does and fail loudly instead.
      // (The fallback it named, wss://relay.0xchat.com, is shut down anyway.)
      List<String> relays = Account.sharedInstance.getCurrentCircleRelay();
      String? relayUrl = relays.firstOrNull;
      if (relayUrl == null || relayUrl.isEmpty) {
        await OXLoading.dismiss();
        throw Exception('Error circle info');
      }

      // Generate new invite link
      final inviteLink = '${AppConfig.inviteBaseUrl}?eventid=${Uri.encodeComponent(keyPackageEvent.eventId)}&relay=${Uri.encodeComponent(relayUrl)}';

      await OXLoading.dismiss();
      return inviteLink;
    } catch (e) {
      await OXLoading.dismiss();
      throw Exception('${Localized.text('ox_usercenter.invite_link_generation_failed')}: $e');
    }
  }

  /// Regenerate circle invite link (reset invitation code)
  /// 
  /// [circle] The circle object
  /// [maxUses] Optional maximum number of uses
  /// [expiresAt] Optional expiration timestamp
  /// 
  /// Returns a map containing:
  /// - 'inviteLink': The new invite link string
  /// - 'invitationCode': The new invitation code
  /// Throws exception on error
  static Future<Map<String, dynamic>> regenerateCircleInviteLink({
    required Circle circle,
    int? maxUses,
    int? expiresAt,
  }) async {
    try {
      // 1. Call reset invitation code API
      final invitationData = await CircleMemberService.sharedInstance.resetInvitationCode(
        maxUses: maxUses,
        expiresAt: expiresAt,
      );
      final invitationCode = invitationData['code'] as String? ?? '';
      
      if (invitationCode.isEmpty) {
        throw Exception('Failed to reset invitation code');
      }
      
      // 2. Update database
      final accountDb = LoginManager.instance.currentState.account?.db;
      if (accountDb != null) {
        final success = await CircleRepository.updateInvitationCode(
          accountDb,
          circle.id,
          invitationCode,
        );
        if (success) {
          // Update Circle object
          circle.invitationCode = invitationCode;
          LogUtil.v(() => 'Invitation code reset and saved to database for circle: ${circle.id}');
        } else {
          LogUtil.w(() => 'Failed to save reset invitation code to database for circle: ${circle.id}');
        }
      }
      
      // 3. Build invite link with circle address and invite code
      // Format: https://0xchat.com/x/invite?code={code}&relay={relayUrl}
      final inviteLink = 'https://0xchat.com/x/invite?code=${Uri.encodeComponent(invitationCode)}&relay=${Uri.encodeComponent(circle.relayUrl)}';
      
      return {
        'inviteLink': inviteLink,
        'invitationCode': invitationCode,
        'circleRelayUrl': circle.relayUrl,
      };
    } catch (e) {
      LogUtil.e(() => 'Failed to regenerate circle invite link: $e');
      rethrow;
    }
  }
}

