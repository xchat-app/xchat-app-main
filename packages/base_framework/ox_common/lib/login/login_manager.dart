import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_cache_manager/ox_cache_manager.dart';
import 'package:isar/isar.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:convert/convert.dart';
import 'package:ox_common/component.dart';
import 'package:nostr_core_dart/src/signer/signer_config.dart';
import 'package:ox_common/network/tor_network_helper.dart';
import 'package:ox_common/push/push_integration.dart';
import 'package:ox_common/push/push_notification_manager.dart';
import 'package:ox_common/purchase/purchase_manager.dart';
import 'package:ox_common/utils/extension.dart';
import 'package:ox_common/circle/page/circle_expired_prompt_dialog.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_common/navigator/navigator.dart';
import '../utils/ox_chat_binding.dart';
import 'database_manager.dart';
import 'login_models.dart';
import 'account_models.dart';
import 'circle_config_models.dart';
import 'circle_service.dart';
import 'circle_repository.dart';
import 'account_path_manager.dart';
import '../secure/db_key_manager.dart';
import 'demo_review_config.dart';
import 'demo_review_seed.dart';

class LoginUserNotifier {
  LoginUserNotifier._();

  static final LoginUserNotifier _instance = LoginUserNotifier._();
  static LoginUserNotifier get instance => _instance;

  ValueNotifier<UserDBISAR?>? _source;

  ValueNotifier<UserDBISAR?> _userInfo$ = ValueNotifier(null);
  ValueNotifier<UserDBISAR?> get userInfo$ => _userInfo$;

  ValueNotifier<String> get encodedPubkey$ => userInfo$
      .map((userInfo) => userInfo?.encodedPubkey ?? '');

  ValueNotifier<String> get name$ => userInfo$
      .map((userInfo) {
    if (userInfo == null) return '';

    final name = userInfo.name;
    if (name != null && name.isNotEmpty) return name;

    return userInfo.shortEncodedPubkey;
  });

  ValueNotifier<String> get bio$ => userInfo$
      .map((userInfo) => userInfo?.about ?? '');

  void updateUserSource(ValueNotifier<UserDBISAR?>? source) {
    if (_source != null) {
      _source!.removeListener(_onSrc);
      _source = null;
    }

    _source = source;
    userInfo$.value = source?.value;
    source?.addListener(_onSrc);
  }

  void _onSrc() {
    userInfo$.value = _source?.value;
    userInfo$.notifyListeners();
  }

  void updateNickname(String nickname) {
    userInfo$.value?.name = nickname;
    userInfo$.notifyListeners();
  }
}

/// Login manager
///
/// Manages user account and circle login/logout logic, including:
/// - Account login/logout
/// - Circle management and switching
/// - Login state persistence
/// - Auto-login flow
/// - Database reference tracking
class LoginManager {
  LoginManager._internal();

  static final LoginManager _instance = LoginManager._internal();
  static LoginManager get instance => _instance;

  // State management
  final ValueNotifier<LoginState> _state$ = ValueNotifier(LoginState());
  ValueListenable<LoginState> get state$ => _state$;
  LoginState get currentState => _state$.value;

  /// Current circle held in state
  /// UI should use [state$] to react to changes; procedural logic can use this getter.
  Circle? get currentCircle => currentState.currentCircle;

  bool get isLoginCircle => currentCircle != null;

  ValueNotifier<bool> accountUpdated$ = ValueNotifier(false);
  ValueNotifier<bool> circleUpdated$ = ValueNotifier(false);

  bool isMe(String id) {
    return currentPubkey == id;
  }

  String get currentPubkey {
    if (currentCircle?.type == CircleType.bitchat) {
      return BitchatService().cachedPeerID ?? '';
    }
    return currentState.account?.pubkey ?? '';
  }

  // Observer management
  final List<LoginManagerObserver> _observers = [];

  /// Profile from the circle just left, waiting for the next circle's relay
  /// to answer. See [LoginManagerCircle._carryProfileInto].
  (String circleId, UserDBISAR profile)? _profileToCarry;

  // Persistence storage keys
  static const String _keyLastPubkey = 'login_manager_last_pubkey';
  static const String _keySignerPrefix = 'login_manager_signer_';
  static const String _tenantNotFoundErrorCode = 'TENANT_NOT_FOUND';
}

/// Account management related methods
extension LoginManagerAccount on LoginManager {
  /// Login with private key
  ///
  /// [privateKey] User's private key (unencrypted)
  /// Returns whether login succeeded, failure notified via observer callbacks
  Future<bool> loginWithPrivateKey(String privateKey) async {
    try {
      // 1. Validate private key format
      if (!_isValidPrivateKey(privateKey)) {
        _notifyLoginFailure(const LoginFailure(
          type: LoginFailureType.invalidKeyFormat,
          message: 'Invalid private key format',
        ));
        return false;
      }

      // 2. Generate public key
      final pubkey = _generatePubkeyFromPrivate(privateKey);
      if (pubkey.isEmpty) {
        _notifyLoginFailure(const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Failed to generate public key from private key',
        ));
        return false;
      }

      // 3. Unified account login
      return _loginAccount(
        pubkey: pubkey,
        loginType: LoginType.nesc,
        privateKey: privateKey,
      );

    } catch (e) {
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Login failed: $e',
      ));
      return false;
    }
  }

  /// Login with NostrConnect URL
  ///
  /// [nostrConnectUrl] NostrConnect URI for remote signing
  /// Returns whether login succeeded, failure notified via observer callbacks
  Future<bool> loginWithNostrConnect(String nostrConnectUrl) async {
    try {
      String pubkey = await Account.getPublicKeyWithNIP46URI(nostrConnectUrl);
      if (pubkey.isEmpty) {
        _notifyLoginFailure(const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Failed to get public key from NostrConnect URI',
        ));
        return false;
      }

      // Unified account login
      return await _loginAccount(
        pubkey: pubkey,
        loginType: LoginType.remoteSigner,
        nostrConnectUri: nostrConnectUrl,
      );

    } catch (e) {
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'NostrConnect login failed: $e',
      ));
      return false;
    }
  }

  /// Login with Aegis (Android) or external signer
  ///
  /// Returns whether login succeeded, failure notified via observer callbacks
  Future<bool> loginWithAmber() async {
    try {
      // Use the new signer configuration system with Aegis
      return await loginWithSigner('nostr_aegis');
    } catch (e) {
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Aegis login failed: $e',
      ));
      return false;
    }
  }

  /// Login with specific signer configuration
  ///
  /// [signerKey] The signer key (e.g., 'amber', 'nostr_aegis', 'custom')
  /// Returns whether login succeeded, failure notified via observer callbacks
  Future<bool> loginWithSigner(String signerKey) async {
    try {
      debugPrint('LoginWithSigner: Starting login with signer: $signerKey');
      // Initialize and set signer configuration
      await ExternalSignerTool.initialize();
      await ExternalSignerTool.setSigner(signerKey);

      final config = ExternalSignerTool.getCurrentConfig();
      debugPrint('LoginWithSigner: Config found: ${config?.displayName} (${config?.packageName})');
      if (config == null) {
        debugPrint('LoginWithSigner: Configuration not found for signer: $signerKey');
        _notifyLoginFailure(LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Signer configuration not found: $signerKey',
        ));
        return false;
      }

      // Check if signer app is installed (without requiring QUERY_ALL_PACKAGES permission)
      bool isInstalled = await CoreMethodChannel.isAppInstalled(config.packageName);
      if (!isInstalled) {
        // Fallback: Check if nostrsigner scheme is supported by any app
        bool isNostrSignerSupported = await CoreMethodChannel.isNostrSignerSupported();
        if (!isNostrSignerSupported) {
          _notifyLoginFailure(LoginFailure(
            type: LoginFailureType.errorEnvironment,
            message: '${config.displayName} app is not installed',
          ));
          return false;
        }
        // If nostrsigner scheme is supported but specific package check failed,
        // continue with the login attempt as the app might be installed
      }

      // Get public key from signer
      String? signature = await ExternalSignerTool.getPubKey();
      if (signature == null) {
        _notifyLoginFailure(LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: '${config.displayName} signature request was rejected',
        ));
        return false;
      }

      // Decode public key if it's in npub format
      String decodeSignature = signature;
      if (signature.startsWith('npub')) {
        decodeSignature = UserDBISAR.decodePubkey(signature) ?? '';
        if (decodeSignature.isEmpty) {
          _notifyLoginFailure(const LoginFailure(
            type: LoginFailureType.invalidKeyFormat,
            message: 'Invalid npub format',
          ));
          return false;
        }
      }

      // Unified account login
      return _loginAccount(
        pubkey: decodeSignature,
        loginType: LoginType.androidSigner,
        signerKey: signerKey,
      );

    } catch (e) {
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Signer login failed: $e',
      ));
      return false;
    }
  }

  /// Auto login (called on app startup)
  ///
  /// Try to auto-login using last logged pubkey by opening local database
  Future<bool> autoLogin() async {
    try {
      final lastPubkey = await _getLastPubkey();
      if (lastPubkey == null || lastPubkey.isEmpty) {
        return false; // No login record
      }

      // Try to auto-login with existing account
      final accountDb = await _initAccountDb(lastPubkey);
      if (accountDb == null) {
        return false; // Failed to initialize database
      }

      // Load account model
      AccountModel? account = await AccountHelper.fromAccountDataList(
        accountDb,
        lastPubkey,
      );
      if (account == null) {
        return false; // No account data found
      }

      // Update account with missing nostrConnectClientPrivkey if needed
      if (account.loginType == LoginType.remoteSigner &&
          account.nostrConnectUri.isNotEmpty &&
          account.nostrConnectClientPrivkey == null) {
        await updateNostrConnectClientPrivkey(_generateClientPrivkey());
      }

      // Update login state
      updateStateAccount(account);

      // Initialize PurchaseManager after account is set up
      // PurchaseManager needs account to be available for purchase verification
      try {
        await PurchaseManager.instance.initialize();
      } catch (e) {
        debugPrint('Failed to initialize PurchaseManager: $e');
        // Don't fail login if PurchaseManager initialization fails
      }

      // Set up signer configuration for this pubkey
      await _setupSignerForPubkey(lastPubkey);

      // Try to login to last circle or first circle
      await _tryLoginLastCircle();

      _notifyLoginSuccess();
      return true;

    } catch (e) {
      debugPrint('Auto login failed: $e');
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Auto login failed: $e',
      ));
      return false;
    }
  }

  // Throws an [Exception] if the logout operation fails
  Future<void> logoutAccount() async {
    await _cleanupPushNotificationsOnLogout();

    if (isLoginCircle) {
      await logoutCircle();
    }

    // Dispose PurchaseManager before clearing account state
    // PurchaseManager is account-specific and should be released on logout
    try {
      PurchaseManager.instance.dispose();
    } catch (e) {
      debugPrint('Failed to dispose PurchaseManager: $e');
    }

    // Clear login state
    final loginState = _state$.value;
    _state$.value = LoginState();
    LoginUserNotifier.instance.updateUserSource(null);

    final account = loginState.account;
    if (account != null) {
      // Clear signer info for this specific pubkey
      await _clearSignerInfo(account.pubkey);
      await DatabaseUtils.closeAccountDatabase(account.db);
    }

    // Clear persistent data
    await _clearLoginInfo();

    // Clear temp folders for all accounts
    AccountPathManager.clearAllTempFolders();

    // Notify observers
    for (final observer in _observers) {
      observer.onLogout();
    }
  }

  Future<bool> deleteAccount() async {
    final loginState = _state$.value;
    final account = loginState.account;
    if (account == null) return false;

    final pubkey = account.pubkey;

    // First logout to clean up current state
    await logoutAccount();

    // Delete account folder and all its contents
    return await AccountPathManager.deleteAccountFolder(pubkey);
  }

  // ============ Private Authentication Methods ============

  /// Unified account login interface
  ///
  /// Handles account-level authentication and data setup for all login types
  Future<bool> _loginAccount({
    required String pubkey,
    required LoginType loginType,
    String? privateKey,
    String? nostrConnectUri,
    String? signerKey,
  }) async {
    try {
      // 1. Initialize account database
      final accountDb = await _initAccountDb(pubkey);
      if (accountDb == null) {
        _notifyLoginFailure(const LoginFailure(
          type: LoginFailureType.accountDbFailed,
          message: 'Failed to initialize account database',
        ));
        return false;
      }

      // 2. Create or load account model
      final now = DateTime.now().millisecondsSinceEpoch;
      AccountModel? account = (await AccountHelper.fromAccountDataList(
        accountDb,
        pubkey,
      ))?..lastLoginAt = now;

      Future<String>? encryptedPrivKey;
      if (account == null) {
        // Generate default password and encrypt private key for nesc login
        String defaultPassword = '';

        if (loginType == LoginType.nesc) {
          if (privateKey == null) throw Exception('nesc login must has privateKey');
          defaultPassword = _generatePassword();
          encryptedPrivKey = _encryptPrivateKey(privateKey, defaultPassword);
        }

        account = AccountModel(
          pubkey: pubkey,
          loginType: loginType,
          privateKey: privateKey,
          encryptedPrivKey: '',
          encryptedPrivKeyFuture: encryptedPrivKey,
          defaultPassword: defaultPassword,
          nostrConnectUri: nostrConnectUri ?? '',
          nostrConnectClientPrivkey: loginType == LoginType.remoteSigner ? _generateClientPrivkey() : null,
          circles: [],
          createdAt: now,
          lastLoginAt: now,
          db: accountDb,
        );
      } else {
        if (account.nostrConnectUri.isNotEmpty && account.nostrConnectClientPrivkey == null) {
          account.nostrConnectClientPrivkey = _generateClientPrivkey();
        }
      }

      // 3. Save account info to DB.
      // Run encryptedPrivKey update only if still the same account and DB still open (not logged out).
      _saveAccount(account).then((_) async {
        final current = currentState.account;
        if (encryptedPrivKey == null || current == null || account == null) return;
        if (current.pubkey != account.pubkey || !account.db.isOpen) return;
        updateEncryptedPrivKey(await encryptedPrivKey);
      });
      // 4. Update login state
      updateStateAccount(account);

      // 5. Initialize PurchaseManager after account is set up
      // PurchaseManager needs account to be available for purchase verification
      try {
        await PurchaseManager.instance.initialize();
      } catch (e) {
        debugPrint('Failed to initialize PurchaseManager: $e');
        // Don't fail login if PurchaseManager initialization fails
      }

      // 6. Persist login information
      await _persistLoginInfo(pubkey);

      // 7. Persist signer selection if provided
      if (signerKey != null) {
        await _persistSignerInfo(pubkey, signerKey);
        // Also set the signer in ExternalSignerTool for immediate use
        await ExternalSignerTool.setSigner(signerKey);
        debugPrint('LoginManager: Set signer mapping $pubkey -> $signerKey');
      }

      // 7.5 Demo account: ensure one circle (wss://relay.damus.io) so reviewers can use the app
      if (pubkey.toLowerCase() == kDemoAccountPubkey.toLowerCase() &&
          account.circles.isEmpty) {
        final joinResult = await joinCircle(kDemoRelayUrl);
        if (joinResult != null) {
          debugPrint('LoginManager: Demo account failed to join demo circle: ${joinResult.message}');
        }
      }

      // 8. Try to login to last circle or first circle
      await _tryLoginLastCircle();

      _notifyLoginSuccess();
      return true;

    } catch (e) {
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Account login failed: $e',
      ));
      return false;
    }
  }


  /// Validate private key format
  bool _isValidPrivateKey(String privateKey) {
    try {
      if (privateKey.isEmpty) return false;

      // Try to generate public key from private key to verify validity
      final pubkey = _generatePubkeyFromPrivate(privateKey);
      return pubkey.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// Generate public key from private key
  String _generatePubkeyFromPrivate(String privateKey) {
    try {
      // Use Keychain.getPublicKey to generate public key from private key
      return Keychain.getPublicKey(privateKey);
    } catch (e) {
      return '';
    }
  }

  /// Generate strong password for private key encryption
  String _generatePassword() {
    return generateStrongPassword(16);
  }

  /// Encrypt private key using password
  static Future<String> _encryptPrivateKey(String privateKey, String password) {
    return compute(_encryptTask, {
      "privateKey": privateKey,
      "password": password,
    });
  }

  static String _encryptTask(Map data) {
    final privateKey = data['privateKey'] as String;
    final password   = data['password'] as String;

    final privateKeyBytes = hex.decode(privateKey);
    final encryptedBytes = encryptPrivateKey(
      Uint8List.fromList(privateKeyBytes),
      password,
    );
    return hex.encode(encryptedBytes);
  }

  /// Notify login success
  void _notifyLoginSuccess() {
    for (final observer in _observers) {
      observer.onLoginSuccess(currentState);
    }
  }

  /// Notify login failure
  void _notifyLoginFailure(LoginFailure failure) {
    for (final observer in _observers) {
      observer.onLoginFailure(failure);
    }
  }
}

// ============ Circle Management Extension ============
/// Circle management related methods
extension LoginManagerCircle on LoginManager {
  /// Switch to specified circle
  ///
  /// [circle] Target circle
  Future<LoginFailure?> switchToCircle(Circle circle) async {
    final currentState = this.currentState;
    final account = currentState.account;
    if (account == null) {
      return LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'No account logged in',
      );
    }

    if (!account.circles.contains(circle)) {
      return LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Circle not found in account',
        circleId: circle.id,
      );
    }

    // Read before logging out: the profile belongs to the circle being left.
    // Set before logging in, because the new circle can connect before
    // switchToCircle gets control back.
    final previousProfile = Account.sharedInstance.me;
    _profileToCarry = circle.type == CircleType.relay &&
            previousProfile != null &&
            _hasChosenName(previousProfile)
        ? (circle.id, previousProfile)
        : null;

    Circle? originCircle;
    try {
      originCircle = await logoutCircle();
    } catch (e) {
      return LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: e.toString(),
        circleId: circle.id,
      );
    }

    final success = await _loginToCircle(circle);
    if (!success) {
      _profileToCarry = null;
      if (originCircle != null) {
        _loginToCircle(originCircle);
      }
      return LoginFailure(
        type: LoginFailureType.circleDbFailed,
        message: 'Login circle failed',
        circleId: circle.id,
      );
    }

    return null;
  }

  /// Each circle has its own database, and a profile reaches a circle's relay
  /// only when it is edited there. So in a circle joined later you appear —
  /// to yourself and to everyone in it — as a bare npub. Called once the
  /// circle's relay has answered the profile reload: if it holds no name for
  /// you either, publish the profile from the circle you came from.
  void _carryProfileInto(Circle circle) {
    final carry = _profileToCarry;
    if (carry == null || carry.$1 != circle.id) return;
    _profileToCarry = null;

    final previous = carry.$2;
    final current = Account.sharedInstance.me;
    if (current == null || current.pubKey != previous.pubKey) return;
    if (_hasChosenName(current)) return;

    () async {
      try {
        final saved = await Account.sharedInstance
            .updateProfile(previous)
            .timeout(const Duration(seconds: 30), onTimeout: () => null);
        if (saved == null) debugPrint('[LoginManager] profile not accepted by ${circle.relayUrl}');
      } catch (e) {
        debugPrint('[LoginManager] carrying profile into ${circle.relayUrl} failed: $e');
      }
    }();
  }

  /// A user row with no profile is not empty: getUserFromDB fills `name`
  /// with the short npub, so treat that placeholder as no name.
  bool _hasChosenName(UserDBISAR user) {
    final name = (user.name ?? '').trim();
    return name.isNotEmpty && name != user.shortEncodedPubkey;
  }

  Future<(bool isSuccess, List<Circle> originCircles)> addCircle(List<Circle> newCircles) async {
    final account = currentState.account;
    if (account == null) return (false, <Circle>[]);

    // Add circle to account's circle list
    final originCircles = [...account.circles];
    final success = await updatedCircles([...originCircles, ...newCircles]);

    // Fetch remote circle info on background
    if (success && newCircles.isNotEmpty) {
      Future.microtask(() async {
        await CircleService.fetchRemoteCircleInfoAndUpdateLocal(List.from(newCircles));
        _refreshState();
      });
    }

    return (success, originCircles);
  }

  /// Join circle
  ///
  /// [relayUrl] Circle's relay address
  /// [type] Circle type
  /// [groupId] Subscription group id when circle is from purchase/restore (e.g. loc1).
  /// When groupId is set, [pubkey] is set to current account so circle counts as "owned" for subscription slots.
  Future<LoginFailure?> joinCircle(
    String relayUrl, {
    CircleType type = CircleType.relay,
    String? groupId,
  }) async {
    try {
      final currentState = this.currentState;

      final account = currentState.account;
      if (account == null) {
        return const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'No account logged in',
        );
      }

      // Check if circle with same relayUrl already exists
      final existingCircle = account.circles.where(
        (circle) => circle.type == type && circle.relayUrl == relayUrl,
      );

      // If circle already exists, just switch to it
      if (existingCircle.isNotEmpty) {
        debugPrint('[LoginManager] Circle already exists, switching to existing circle: relayUrl=$relayUrl');
        final switchResult = await switchToCircle(existingCircle.first);
        return switchResult;
      }

      // Circle doesn't exist, create new one.
      // When groupId is set (purchase/restore), set pubkey so circle counts as "owned" for subscription slots.
      final newCircle = Circle(
        name: _extractCircleName(relayUrl, type),
        relayUrl: relayUrl,
        groupId: groupId,
        ownerPubkey: (groupId != null && groupId.isNotEmpty) ? account.pubkey : null,
      );

      final (isSuccess, originCircles) = await addCircle([newCircle]);
      if (!isSuccess) {
        return const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Add circle fail',
        );
      }

      final switchResult = await switchToCircle(newCircle);
      if (switchResult != null) {
        // Switch failed, remove the circle from the list
        await updatedCircles([...originCircles]);
        return switchResult;
      }

      return null;

    } catch (e) {
      return LoginFailure(
        type: LoginFailureType.circleDbFailed,
        message: 'Failed to join circle: $e',
      );
    }
  }

  // Throws an [Exception] if the logout operation fails
  Future<Circle?> logoutCircle() async {
    final originCircle = currentState.currentCircle;
    if (originCircle != null) {
      // Stop BitchatService if it was a bitchat circle
      if (originCircle.type == CircleType.bitchat) {
        await _stopBitchatService();
      }
      await Account.sharedInstance.logout();
      CLCacheManager.clearCircleMemCacheById(originCircle.id);
      AccountPathManager.clearCircleTempFolder(
        currentState.account!.pubkey,
        originCircle.id,
      );
    }
    return originCircle;
  }

  /// Stop BitchatService when logging out of bitchat circle
  Future<void> _stopBitchatService() async {
    try {
      final bitchatService = BitchatService();
      await bitchatService.stop();
      debugPrint('BitchatService stopped successfully');
    } catch (e) {
      debugPrint('Failed to stop BitchatService: $e');
    }
  }

  Future<void> _cleanupPushNotificationsOnLogout() async {
    try {
      final event = await NotificationHelper.sharedInstance.removeNotification();
      if (!event.status) {
        debugPrint('Failed to clear push token on server: ${event.message}');
        await _fallbackUnregisterPushToken('server rejection');
      }
    } catch (e) {
      debugPrint('Exception while clearing push token: $e');
      await _fallbackUnregisterPushToken('exception');
    }
  }

  Future<void> _fallbackUnregisterPushToken(String reason) async {
    debugPrint('Fallback unregister notification due to $reason');
    try {
      await CLPushIntegration.instance.unregisterNotification();
    } catch (e) {
      debugPrint('Fallback unregister notification failed: $e');
    }
  }

  /// Delete circle completely
  ///
  /// [circleId] Circle ID to delete
  /// Returns true if deletion was successful, false otherwise
  /// Throws an [Exception] if the logout operation fails
  Future<bool> deleteCircle(String circleId) async {
    try {
      final currentState = this.currentState;
      final account = currentState.account;
      if (account == null) {
        _notifyCircleChange(false, const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'No account logged in',
        ));
        return false;
      }

      if (circleId.isEmpty) {
        _notifyCircleChange(false, LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Circle ID cannot be empty',
          circleId: circleId,
        ));
        return false;
      }

      final circleToDelete = account.circles.where((c) => c.id == circleId).firstOrNull;
      if (circleToDelete == null) {
        _notifyCircleChange(false, LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Circle not found',
          circleId: circleId,
        ));
        return false;
      }

      // Check if this is the current circle
      final isCurrentCircle = currentState.currentCircle?.id == circleId;

      // Check if this is a paid relay and user is tenant admin
      // If so, delete tenant before deleting local circle data
      bool needToDeleteTenant = false;
      bool wasSwitchedToTargetCircle = false;
      Circle? circleToSwitchBack = null;

      // Check if it's a paid relay
      final isPaidRelay = CircleApi.isPaidRelay(circleToDelete.relayUrl);
      if (isPaidRelay) {
        // Get CircleDBISAR to check tenant admin
        final circleDB = await Account.sharedInstance.getCircleById(circleId);
        if (circleDB != null && circleDB.tenantAdminPubkey != null && circleDB.tenantAdminPubkey!.isNotEmpty) {
          final userPubkey = currentPubkey;
          final isTenantAdmin = circleDB.tenantAdminPubkey!.toLowerCase() == userPubkey.toLowerCase();
          if (isTenantAdmin) {
            needToDeleteTenant = true;
            
            // If not currently in target circle, switch to it first
            if (!isCurrentCircle) {
              // Save current circle to switch back later
              circleToSwitchBack = currentState.currentCircle;
              
              // Switch to target circle to delete tenant
              final switchResult = await switchToCircle(circleToDelete);
              if (switchResult != null) {
                // Failed to switch, log error but continue with deletion
                LogUtils.w(() => 'Failed to switch to circle $circleId for tenant deletion: ${switchResult.message}');
                needToDeleteTenant = false;
              } else {
                wasSwitchedToTargetCircle = true;
              }
            }
            // If already in target circle, we can delete tenant directly without switching
          }
        }
      }

      // Delete tenant if needed
      if (needToDeleteTenant) {
        try {
          await CircleMemberService.sharedInstance.deleteTenant();
          LogUtils.v(() => 'Successfully deleted tenant for circle $circleId');
        } catch (e) {
          // Log error but don't block circle deletion
          LogUtils.w(() => 'Failed to delete tenant for circle $circleId: $e');
        }
      }

      // Switch back to original circle if we switched to target circle
      if (wasSwitchedToTargetCircle && circleToSwitchBack != null) {
        final switchResult = await switchToCircle(circleToSwitchBack);
        if (switchResult != null) {
          LogUtils.w(() => 'Failed to switch back to original circle: ${switchResult.message}');
        }
      }

      final remainingCircles = account.circles.where((c) => c.id != circleId).toList();

      final isSwitch = remainingCircles.isNotEmpty;
      if (isSwitch) {
        final nextCircle = remainingCircles.first;
        if (isCurrentCircle) {
          final switchResult = await switchToCircle(nextCircle);
          if (switchResult != null) {
            _notifyCircleChange(false, switchResult);
            return false;
          }
        }
      } else {
        await logoutCircle();
      }

      // Delete circle folder and all its contents directly
      final deleteSuccess = await AccountPathManager.deleteCircleFolder(
        account.pubkey,
        circleId,
      );
      if (!deleteSuccess) {
        return false;
      }

      await CircleService.deleteCircle(account.db, circleId);

      final newCircle = account.circles.where((c) => c.id != circleId).toList();
      await updatedCircles(newCircle);

      // Update state
      if (!isSwitch) {
        LoginUserNotifier.instance.updateUserSource(null);
        updateStateCircle(null);
      }

      return true;
    } catch (e) {
      _notifyCircleChange(false, LoginFailure(
        type: LoginFailureType.circleDbFailed,
        message: 'Failed to delete circle: $e',
        circleId: circleId,
      ));
      return false;
    }
  }

  Future<bool> _tryLoginLastCircle() async {
    final account = currentState.account;
    if (account == null) return false;

    final lastCircleId = account.lastLoginCircleId ?? '';
    if (lastCircleId.isNotEmpty && account.circles.isNotEmpty) {
      final targetCircle = account.circles.where((c) => c.id == lastCircleId).firstOrNull;
      if (targetCircle != null) {
        return await _loginToCircle(targetCircle);
      }
    }

    return false;
  }

  /// Login to specified circle
  ///
  /// This performs circle-level login using Account.sharedInstance methods
  Future<bool> _loginToCircle(Circle circle) async {
    try {
      final account = currentState.account;
      if (account == null) {
        _notifyCircleChange(false, LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Account is null',
          circleId: circle.id,
        ));
        return false;
      }

      // Initialize circle database using DatabaseUtils
      final circleDb = await DatabaseUtils.initCircleDatabase(
        account.pubkey,
        circle,
      );
      if (circleDb == null) {
        _notifyCircleChange(false, LoginFailure(
          type: LoginFailureType.circleDbFailed,
          message: 'Failed to initialize circle database',
          circleId: circle.id,
        ));
        return false;
      }

      circle.db = circleDb;

      // Load circle level configuration and attach to circle instance.
      try {
        final cfg = await CircleConfigHelper.loadConfig(circleDb, circle.id);
        circle.initConfig(cfg);
      } catch (e) {
        debugPrint('Failed to load circle config: $e');
      }

      // Initialize Account system
      Account.sharedInstance.init();

      // Perform circle-level login based on account login type
      final user = await _performNostrLogin(account);
      if (user == null) {
        _notifyCircleChange(false, LoginFailure(
          type: LoginFailureType.circleDbFailed,
          message: 'Circle login failed',
          circleId: circle.id,
        ));
        return false;
      }

      updateStateCircle(circle);

      _loginCircleSuccessHandler(account, circle);

      _notifyCircleChange(true);

      return true;
    } catch (e) {
      _notifyCircleChange(false, LoginFailure(
        type: LoginFailureType.circleDbFailed,
        message: 'Failed to login to circle: $e',
        circleId: circle.id,
      ));
      return false;
    }
  }

  /// Perform circle-level login based on account login type
  Future<UserDBISAR?> _performNostrLogin(AccountModel account) async {
    try {
      final loginType = account.loginType;
      switch (loginType) {
        case LoginType.nesc:
          // Use private key login
          String? privateKey = account.privateKey;
          if (privateKey == null || privateKey.isEmpty) {
            privateKey = AccountHelperEx.getPrivateKey(
              account.encryptedPrivKey,
              account.defaultPassword,
            );
          }
          final result = await Account.sharedInstance.loginWithPriKey(
            privateKey,
            false,
          );
          return result;
        case LoginType.androidSigner:
          // Use Amber signer login
          return Account.sharedInstance.loginWithPubKey(
            account.pubkey,
            SignerApplication.androidSigner,
          );
        case LoginType.remoteSigner:
          // Use NostrConnect login
          final nostrConnectUri = account.nostrConnectUri;
          if (nostrConnectUri.isNotEmpty) {
            return Account.sharedInstance.loginWithNip46URI(
              nostrConnectUri,
              clientPrivkey: account.nostrConnectClientPrivkey,
            );
          }
          break;
      }

      return null;
    } catch (e, s) {
      debugPrint('Circle login failed: $e, $s');
      return null;
    }
  }

  void _notifyCircleChange(bool isSuccess, [LoginFailure? failure]) {
    for (final observer in _observers) {
      observer.onCircleChange(isSuccess, failure);
    }
  }

  void _notifyCircleConnectedChange(bool isConnected) {
    for (final observer in _observers) {
      observer.onCircleConnected(isConnected);
    }
  }

  void _loginCircleSuccessHandler(AccountModel account, Circle circle) async {
    final circleType = circle.type;
    switch (circleType) {
      case CircleType.relay:
        _loginRelayCircleSuccessHandler(account, circle);
        break;
      case CircleType.bitchat:
        _initializeBitchatService(account, circle);
        break;
    }
  }

  void _loginRelayCircleSuccessHandler(AccountModel account, Circle circle) async {
    final pubkey = account.pubkey;
    final circleId = circle.id;
    final relayUrl = circle.relayUrl;
    final config = ChatCoreInitConfig(
      pubkey: account.pubkey,
      databasePath: await AccountPathManager.getCircleFolderPath(account.pubkey, circleId),
      encryptionPassword: await _getEncryptionPassword(account),
      circleId: circleId,
      isLite: true,
      circleRelay: relayUrl,
      circleConnectCallback: (isConnected) {
        if (isConnected) {
          Account.sharedInstance
              .reloadProfileFromRelay(pubkey)
              .then((_) => _carryProfileInto(circle));
        }
        _notifyCircleConnectedChange(isConnected);
      },
      contactUpdatedCallBack: Contacts.sharedInstance.contactUpdatedCallBack,
      channelsUpdatedCallBack: Channels.sharedInstance.myChannelsUpdatedCallBack,
      groupsUpdatedCallBack: Groups.sharedInstance.myGroupsUpdatedCallBack,
      relayGroupsUpdatedCallBack: RelayGroup.sharedInstance.myGroupsUpdatedCallBack,
      // nopu on the relay box (deploy/install-nopu.sh in private-relay). The
      // old ws://www.0xchat.com:9090 server is shut down.
      pushServerRelay: 'wss://push.xchat.chat',
    );
    await ChatCoreManager().initChatCoreWithConfig(config);
    LoginUserNotifier.instance.updateUserSource(Account.sharedInstance.getUserNotifier(pubkey));
    Account.sharedInstance.syncFollowingListFromRelay(pubkey, relay: relayUrl);

    // Demo account: pre-populate one contact and chat for App Review (Guideline 2.1(a))
    await runDemoReviewSeedIfNeeded();

    initializePushCore();

    if (TorNetworkHelper.isOnionUrl(relayUrl)) {
      TorNetworkHelper.initialize();
    }

    // Wait for relay connection then: ensure keypackage (paid relay), refresh circle info (paid relay)
    Connect.sharedInstance.waitForRelayConnection(relayKind: RelayKind.circleRelay).then((connected) {
      if (!connected) return;
      KeyPackageManager.ensurePermanentKeyPackageOnRelay().catchError((e) {
        debugPrint('Failed to ensure keypackage on relay: $e');
      });
      refreshCircleFromRemote();
    }).catchError((e) {
      debugPrint('Failed to wait for relay connection: $e');
    });
  }

  /// Fetches latest circle (tenant) info from remote, updates cache (mem + store), and returns it.
  /// Use when procedural logic needs up-to-date data. For current circle only (paid relay).
  /// Returns [currentCircle] after update, or null if not applicable / notfound deleted.
  Future<Circle?> fetchCircleFromRemote() async {
    final circle = currentState.currentCircle;
    if (circle == null || !circle.isPaidRelay) return circle;
    await _fetchAndUpdateTenantInfo(circle);
    return currentState.currentCircle;
  }

  /// Refreshes circle info from remote (same as [fetchCircleFromRemote]) but does not return.
  /// Use with UI that reads from [state$] (e.g. startup, entering circle detail page).
  Future<void> refreshCircleFromRemote() async {
    final circle = currentState.currentCircle;
    if (circle == null || !circle.isPaidRelay) return;
    await _fetchAndUpdateTenantInfo(circle);
  }

  /// Returns cached tenant info for [circleId] (for UI first-paint or non-current circle).
  /// Prefer mem when it's the current circle and [tenantInfo] is already loaded; otherwise store (CircleDB).
  /// Use this instead of calling [Account.loadTenantInfoFromCircleDB] directly.
  Future<Map<String, dynamic>?> getCachedTenantInfoForCircle(String circleId) async {
    if (currentState.currentCircle?.id == circleId &&
        currentState.currentCircle?.tenantInfo != null) {
      return currentState.currentCircle!.tenantInfo!.toJson();
    }
    return await Account.sharedInstance.loadTenantInfoFromCircleDB(circleId);
  }

  /// Internal: fetch tenant info, update mem + store, handle tenant-not-found (404) / expired.
  /// Server returns 404 with code TENANT_NOT_FOUND when circle was deleted remotely.
  Future<void> _fetchAndUpdateTenantInfo(Circle circle) async {
    if (!circle.isPaidRelay) return;
    try {
      final tenantInfo = await CircleMemberService.sharedInstance.getTenantInfoForRelay(
        circle.relayUrl,
        circleId: circle.id,
      );
      final statusLower = tenantInfo.status.toLowerCase();

      await Account.sharedInstance.saveTenantInfoToCircleDB(
        circleId: circle.id,
        tenantInfo: tenantInfo.toJson(),
      );

      updateCircleTenantInfo(tenantInfo);

      if (tenantInfo.name.isNotEmpty && tenantInfo.name != circle.name) {
        circle.name = tenantInfo.name;
        final account = currentState.account;
        if (account != null) {
          await CircleRepository.update(account.db, circle);
          _refreshState();
        }
      }

      final expiresAt = tenantInfo.expiresAt;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final isExpired = statusLower == 'expired' ||
          (expiresAt != null && expiresAt > 0 && expiresAt < now);
      if (isExpired) {
        CircleExpiredPromptDialog.show(OXNavigator.rootContext, circle);
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.contains(LoginManager._tenantNotFoundErrorCode)) {
        await deleteCircleAndShowDeletedPrompt(circle.id, circle.name);
        return;
      }
      LogUtils.w(() => 'Fetch and update tenant info failed: $e');
    }
  }

  /// Called when circle was deleted remotely (API 404 TENANT_NOT_FOUND or relay OK "tenant not found").
  /// Deletes circle locally and shows "circle deleted" prompt.
  Future<void> deleteCircleAndShowDeletedPrompt(String circleId, String circleName) async {
    _showCircleDeletedPrompt(circleName);
    await deleteCircle(circleId);
  }

  void _showCircleDeletedPrompt(String circleName) {
    final context = OXNavigator.navigatorKey.currentContext;
    if (context != null && context.mounted) {
      OXNavigator.popToRoot(context);
      final title = Localized.text('ox_common.circle_deleted_title');
      final content = Localized.text('ox_common.circle_deleted_message').replaceAll('{name}', circleName);
      CLAlertDialog.show<void>(
        context: context,
        title: title,
        content: content,
        actions: [CLAlertAction.ok()],
      );
    }
  }

  void initializePushCore() async {
    await CLPushIntegration.instance.initialize();
    await CLUserPushNotificationManager.instance.initialize();
  }

  /// Initialize and start BitchatService for bitchat circles
  Future<void> _initializeBitchatService(AccountModel account, Circle circle) async {
    if(Platform.isAndroid) return;

    try {
      final bitchatService = BitchatService();

      // Initialize the service
      await bitchatService.initialize();
      debugPrint('BitchatService initialized successfully');

      await bitchatService.startBroadcasting();
      bitchatService.setMessageCallback((message) {
        Messages.saveMessageToDB(message);
        OXChatBinding.sharedInstance.didReceiveMessageHandler(message);
      });

      LoginUserNotifier.instance.userInfo$.value = UserDBISAR(
        pubKey: bitchatService.cachedPeerID ?? '',
        name: bitchatService.cachedNickname,
      )..updateEncodedPubkey(bitchatService.cachedPeerID ?? '');
    } catch (e, stack) {
      debugPrint('Failed to initialize BitchatService: $e, $stack');
    }
  }
}

/// Observer management related methods
extension LoginManagerObserverEx on LoginManager {
  /// Add observer
  void addObserver(LoginManagerObserver observer) {
    if (!_observers.contains(observer)) {
      _observers.add(observer);
    }
  }

  /// Remove observer
  void removeObserver(LoginManagerObserver observer) {
    _observers.remove(observer);
  }

  /// Dispose resources
  void dispose() {
    _state$.dispose();
    _observers.clear();
  }
}

/// Database and persistence related methods
extension LoginManagerDatabase on LoginManager {
  /// Initialize account database using new DatabaseUtils
  Future<Isar?> _initAccountDb(String pubkey) async {
    try {
      // Use new DatabaseUtils instead of legacy logic
      return await DatabaseUtils.initAccountDatabase(pubkey);
    } catch (e) {
      debugPrint('Failed to init account DB: $e');
      return null;
    }
  }

  /// Persist login information
  Future<void> _persistLoginInfo(String pubkey) async {
    await OXCacheManager.defaultOXCacheManager.saveForeverData(
      LoginManager._keyLastPubkey,
      pubkey,
    );
  }

  Future<void> _persistSignerInfo(String pubkey, String signerKey) async {
    final key = '${LoginManager._keySignerPrefix}$pubkey';
    await OXCacheManager.defaultOXCacheManager.saveForeverData(
      key,
      signerKey,
    );
  }

  /// Clear login information
  Future<void> _clearLoginInfo() async {
    await OXCacheManager.defaultOXCacheManager.saveForeverData(
      LoginManager._keyLastPubkey,
      null,
    );
  }

  /// Clear signer information for specific pubkey
  Future<void> _clearSignerInfo(String pubkey) async {
    final key = '${LoginManager._keySignerPrefix}$pubkey';
    await OXCacheManager.defaultOXCacheManager.saveForeverData(
      key,
      null,
    );
  }

  /// Get last logged pubkey
  Future<String?> _getLastPubkey() async {
    return await OXCacheManager.defaultOXCacheManager.getForeverData(
      LoginManager._keyLastPubkey,
    );
  }

  /// Get signer for specific pubkey
  Future<String?> getSignerForPubkey(String pubkey) async {
    final key = '${LoginManager._keySignerPrefix}$pubkey';
    return await OXCacheManager.defaultOXCacheManager.getForeverData(
      key,
    );
  }

  /// Set up signer configuration for specific pubkey
  Future<void> _setupSignerForPubkey(String pubkey) async {
    // Only set up external signer on Android
    if (!Platform.isAndroid) {
      debugPrint('AutoLogin: External signer not supported on this platform');
      return;
    }

    try {
      final signerKey = await getSignerForPubkey(pubkey);
      if (signerKey != null) {
        debugPrint('AutoLogin: Setting up signer $signerKey for pubkey $pubkey');
        await ExternalSignerTool.initialize();
        await ExternalSignerTool.setSigner(signerKey);
      } else {
        debugPrint('AutoLogin: No saved signer for pubkey $pubkey, trying to detect available signer');
        await ExternalSignerTool.initialize();
        // Try to detect which signer is available instead of defaulting to amber
        await _detectAndSetAvailableSigner();
        // Set the detected signer for this pubkey
        final detectedSigner = ExternalSignerTool.getCurrentConfig()?.packageName;
        if (detectedSigner != null) {
          // Find the signer key for this package name
          final signerKeys = SignerConfigs.getAvailableSigners();
          for (final signerKey in signerKeys) {
            final config = SignerConfigs.getConfig(signerKey);
            if (config?.packageName == detectedSigner) {
              await ExternalSignerTool.setSigner(signerKey);
              break;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('AutoLogin: Error setting up signer for pubkey $pubkey: $e');
      // Fallback to detecting available signer
      await ExternalSignerTool.initialize();
      await _detectAndSetAvailableSigner();
    }
  }

  /// Detect and set available signer based on installed apps
  Future<void> _detectAndSetAvailableSigner() async {
    try {
      // Get all available signer configurations
      final signerKeys = SignerConfigs.getAvailableSigners();

      // Check which signers are installed
      for (final signerKey in signerKeys) {
        try {
          final config = SignerConfigs.getConfig(signerKey);
          if (config != null) {
            final isInstalled = await CoreMethodChannel.isAppInstalled(config.packageName);
            if (isInstalled) {
              debugPrint('AutoLogin: Found available signer: $signerKey (${config.displayName})');
              ExternalSignerTool.setSigner(signerKey);
              // Note: We don't have the pubkey here, so we can't set the mapping
              // This will be handled by the caller
              return;
            }
          }
        } catch (e) {
          debugPrint('AutoLogin: Error checking signer $signerKey: $e');
        }
      }

      // If no specific signer found, check if nostrsigner scheme is supported
      final isNostrSignerSupported = await CoreMethodChannel.isNostrSignerSupported();
      if (isNostrSignerSupported) {
        debugPrint('AutoLogin: NostrSigner scheme supported, using first available signer');
        // Use the first available signer as fallback
        if (signerKeys.isNotEmpty) {
          ExternalSignerTool.setSigner(signerKeys.first);
        }
      } else {
        debugPrint('AutoLogin: No signer apps found');
      }
    } catch (e) {
      debugPrint('AutoLogin: Error detecting available signer: $e');
    }
  }

  /// Get encryption password from account
  String _generateClientPrivkey() {
    // Generate a new client private key for NIP46 connections
    final keychain = Keychain.generate();
    return keychain.private;
  }

  Future<String> _getEncryptionPassword(AccountModel account) async {
    // Use database encryption key from DBKeyManager
    return await DBKeyManager.getKey();
  }
}

extension AccountUpdateMethod on LoginManager {
  void _refreshState() {
    _state$.value = currentState.copy();
  }

  void updateStateAccount(AccountModel? account) {
    currentState.account = account;
    _refreshState();
  }

  void updateStateCircle(Circle? circle) {
    currentState.currentCircle = circle;
    _refreshState();
    updateLastLoginCircle(circle);
  }

  /// Updates [Circle.tenantInfo] for the current circle and refreshes state.
  void updateCircleTenantInfo(TenantInfo? tenantInfo) {
    currentState.currentCircle?.tenantInfo = tenantInfo;
    _refreshState();
  }

  Future<bool> updateEncryptedPrivKey(String encryptedPrivKey) async {
    final account = currentState.account;
    if (account == null) return false;

    account.encryptedPrivKey = encryptedPrivKey;
    await _saveAccount(account);

    return true;
  }

  Future<bool> updatedCircles(List<Circle> circles) async {
    final account = currentState.account;
    if (account == null) return false;

    // Save circles to CircleISAR collection using CircleService
    final accountDb = account.db;
    for (final circle in circles) {
      await CircleService.createCircle(accountDb, circle);
    }

    account.circles = circles;
    await _saveAccount(account);

    return true;
  }

  Future<bool> updateNostrConnectClientPrivkey(String privkey) async {
    final account = currentState.account;
    if (account == null) return false;

    account.nostrConnectClientPrivkey = privkey;
    await _saveAccount(account);

    return true;
  }

  Future<bool> updatePushToken(String token) async {
    final account = currentState.account;
    if (account == null) return false;

    account.pushToken = token;
    await _saveAccount(account);

    return true;
  }

  Future<bool> updateLastLoginCircle(Circle? circle) async {
    final account = currentState.account;
    if (account == null) return false;

    account.lastLoginCircleId = circle?.id;
    await _saveAccount(account);

    return true;
  }

  /// Save AccountModel to database.
  /// No-op if account's Isar was already closed (e.g. after logout).
  Future<void> _saveAccount(AccountModel account) async {
    final db = account.db;
    if (!db.isOpen) return;
    final accountDataList = AccountHelper.toAccountDataList(account);
    await db.writeAsync((accountDb) {
      accountDb.accountDataISARs.putAll(accountDataList);
    });

    accountUpdated$.value = !accountUpdated$.value;
  }
}

/// Utility methods for LoginManager
extension LoginManagerUtils on LoginManager {
  /// Extract circle name from relay URL
  String _extractCircleName(String relayUrl, CircleType type) {
    switch (type) {
      case CircleType.relay:
        try {
          final uri = Uri.parse(relayUrl);
          final host = uri.host;
          // Remove common prefixes and return a clean name
          return host.replaceAll('relay.', '').replaceAll('www.', '').split('.').first;
        } catch (e) {
          // Fallback to simplified name
          return relayUrl.replaceAll('wss://', '').replaceAll('ws://', '').split('/').first;
        }
      case CircleType.bitchat:
        return 'bitchat';
    }
  }
}

/// Extension so that [Circle.isAdmin] is available when [LoginManager] is in scope.
extension CircleAdminExtension on Circle {
  /// Whether current user is admin of this circle (paid relay only).
  /// Uses [tenantInfo]; prefer [Circle.isAdminFor] when passing a pubkey explicitly.
  bool get isAdmin => isAdminFor(LoginManager.instance.currentPubkey);
}