import 'dart:async';
import 'dart:io';

import 'package:chatcore/chat-core.dart';
import 'package:flutter/widgets.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/utils/circle_join_utils.dart';
import 'package:ox_common/upload/upload_utils.dart';

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
    // Nobody awaits this on most paths; a failure there is not an uncaught error.
    profilePublished.ignore();
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

  /// Completes once the name (and photo) entered during onboarding has been
  /// published in the first circle this account connects to.
  ///
  /// A new account has no circle when it types its name, and a profile only
  /// reaches a circle's relay when it is published there. Only joining by
  /// invite or relay address used to do that, so an account that bought its
  /// circle showed up in it as a bare npub. Publishing on the first connection
  /// covers every way in; the subscribe page waits on this before it leaves.
  Future<void> get profilePublished => _profilePublished.future;
  final Completer<void> _profilePublished = Completer<void>();
  bool _isPublishingProfile = false;

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
    if (!updateProfileCmp.isCompleted) updateProfileCmp.complete(isConnected);

    if (!isConnected || !isCreateNewAccount || _isPublishingProfile) return;
    // Only the account this controller created; never rename another one
    // that was logged into after onboarding was abandoned.
    if (Account.sharedInstance.me?.pubKey != keychain.public) return;
    _isPublishingProfile = true;
    _updateProfile().then(
      (_) => _profilePublished.complete(),
      onError: (Object e) => _profilePublished.completeError(e),
    ).whenComplete(() {
      if (_isDisposed) LoginManager.instance.removeObserver(this);
    });
  }

  bool _isDisposed = false;

  void dispose() {
    _isDisposed = true;
    // Joining by invite pops these pages before the new circle connects.
    // A new account still owes that circle its name, so keep listening until
    // it has been published; onCircleConnected lets go after that.
    if (isCreateNewAccount && !_isPublishingProfile) return;
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