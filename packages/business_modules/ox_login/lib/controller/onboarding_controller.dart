import 'dart:async';
import 'dart:io';

import 'package:chatcore/chat-core.dart';
import 'package:flutter/widgets.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/utils/circle_join_utils.dart';
import 'package:ox_common/upload/upload_utils.dart';

/// Where an account goes when it arrives with no invite and no subscription.
/// A public relay is the only entry that costs nothing, and without one the
/// choices on the circle page are "pay" or "run your own server".
const kPublicRelayUrl = 'wss://relay.damus.io';

class OnboardingResult {
  final bool success;
  final String? errorMessage;

  const OnboardingResult.success() : success = true, errorMessage = null;
  const OnboardingResult.failure(this.errorMessage) : success = false;
}

class OnboardingController with LoginManagerObserver {
  OnboardingController({
    required this.isCreateNewAccount,
    Keychain? initialKeychain,
  }) : keychain = initialKeychain ?? Account.generateNewKeychain() {
    LoginManager.instance.addObserver(this);
  }

  /// Keychain: either from Apple (or other social) login derivation, or newly generated.
  final Keychain keychain;

  bool isCreateNewAccount;

  String _firstName = '';
  String _lastName = '';
  File? avatarFile;

  String get fullName {
    if (_lastName.isEmpty) return _firstName;
    return '$_firstName $_lastName';
  }

  Future<bool> Function()? loginAction;
  Completer<bool> updateProfileCmp = Completer<bool>();

  Future<OnboardingResult> invokeLoginAction() async {
    if (LoginManager.instance.currentState.account != null) return OnboardingResult.success();
    final action = loginAction ?? () {
      return LoginManager.instance.loginWithPrivateKey(
        keychain.private,
      );
    };

    final success = await action();
    if (!success) {
      return OnboardingResult.failure(
          isCreateNewAccount
              ? 'Failed to create account'
              : 'Failed to login account'
      );
    }

    return OnboardingResult.success();
  }

  @override
  void onCircleConnected(bool isConnected) {
    if (updateProfileCmp.isCompleted) return;

    updateProfileCmp.complete(isConnected);
  }

  void dispose() {
    LoginManager.instance.removeObserver(this);
  }
}

extension OnboardingControllerProfileEx on OnboardingController {
  bool get hasValidProfile => _firstName.isNotEmpty;

  void setFirstName(String value) {
    _firstName = value.trim();
  }

  void setLastName(String value) {
    _lastName = value.trim();
  }

  void setAvatarFile(File? file) {
    avatarFile = file;
  }
}

extension OnboardingControllerCircleEx on OnboardingController {
  Future<OnboardingResult> joinPublicCircle() async {
    final result = await _joinCircle(
      relayUrl: kPublicRelayUrl,
      forceJoin: true,
    );
    return result;
  }

  /// Join private/self-hosted circle with normal network checks
  Future<OnboardingResult> joinPrivateCircle({
    required String relayUrl,
    required BuildContext context,
    bool supportInvite = false,
  }) async {
    return _joinCircle(
      relayUrl: relayUrl,
      forceJoin: false,
      context: context,
      supportInvite: supportInvite,
    );
  }
}

extension _NewAccountEx on OnboardingController {
  Future<OnboardingResult> _joinCircle({
    required String relayUrl,
    required bool forceJoin,
    BuildContext? context,
    bool supportInvite = false,
  }) async {
    try {
      await CircleJoinUtils.processJoinCircle(
        input: relayUrl,
        usePreCheck: !forceJoin,
        context: context,
        supportInvite: supportInvite,
      );

      if (isCreateNewAccount) {
        _updateProfile();
      }
    } catch (e) {
      // Do not logout on join failure; only return failure so UI can show error
      return OnboardingResult.failure(e.toString());
    }

    return OnboardingResult.success();
  }

  Future<void> _updateProfile() async {
    final user = Account.sharedInstance.me;
    if (user == null) throw 'Current user is null';

    user.name = fullName;
    if (avatarFile != null) {
      final uploadResult = await _uploadAvatarFile(avatarFile!);
      if (!uploadResult.isSuccess) {
        throw uploadResult.errorMsg!;
      }
      user.picture = uploadResult.url;
    }

    final isUpdateSuccess = await updateProfileCmp.future;
    if (!isUpdateSuccess) throw 'Circle connected failed';

    final newUser = await Account.sharedInstance.updateProfile(user);
    if (newUser == null) throw 'Update profile failed';
  }

  Future<UploadResult> _uploadAvatarFile(File avatarFile) async {
    return UploadUtils.uploadFile(
      fileType: FileType.image,
      file: avatarFile,
      filename: 'avatar_${DateTime.now().millisecondsSinceEpoch}.png',
    );
  }
}