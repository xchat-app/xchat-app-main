import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_cache_manager/ox_cache_manager.dart';
import 'package:isar/isar.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:convert/convert.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/push/push_integration.dart';
import 'package:ox_common/push/push_notification_manager.dart';
import 'package:ox_common/utils/extension.dart';
import 'package:uuid/uuid.dart';
import '../utils/ox_chat_binding.dart';
import 'database_manager.dart';
import 'login_models.dart';
import 'account_models.dart';
import 'circle_config_models.dart';
import 'account_path_manager.dart';
import '../secure/db_key_manager.dart';

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

  ValueNotifier<String> get avatarUrl$ => userInfo$
      .map((userInfo) => userInfo?.picture ?? '');
  
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

  Circle? get currentCircle => currentState.currentCircle;
  bool get isLoginCircle => currentCircle != null;

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

  // Persistence storage keys
  static const String _keyLastPubkey = 'login_manager_last_pubkey';
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

  /// Login with Amber (Android) or external signer
  ///
  /// Returns whether login succeeded, failure notified via observer callbacks
  Future<bool> loginWithAmber() async {
    try {
      // Check if Amber is installed (Android only)
      bool isInstalled = await CoreMethodChannel.isInstalledAmber();
      if (!isInstalled) {
        _notifyLoginFailure(const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Amber app is not installed',
        ));
        return false;
      }

      // Get public key from Amber
      String? signature = await ExternalSignerTool.getPubKey();
      if (signature == null) {
        _notifyLoginFailure(const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Amber signature request was rejected',
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
      );

    } catch (e) {
      _notifyLoginFailure(LoginFailure(
        type: LoginFailureType.errorEnvironment,
        message: 'Amber login failed: $e',
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
      final account = await AccountHelper.fromAccountDataList(
        accountDb,
        lastPubkey,
      );
      if (account == null) {
        return false; // No account data found
      }

      // Update login state
      final loginState = LoginState(account: account);
      _state$.value = loginState;

      // Try to login to last circle or first circle
      await _tryLoginLastCircle(loginState);

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
    if (isLoginCircle) {
      await logoutCircle();
    }

    // Clear login state
    final loginState = _state$.value;
    _state$.value = LoginState();
    LoginUserNotifier.instance.updateUserSource(null);

    final account = loginState.account;
    if (account != null) {
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

  Future<bool> savePushToken(String token) async {
    if (token.isEmpty) return false;

    final account = currentState.account;
    if (account == null) return false;

    account.pushToken = token;
    await account.saveToDB();
    return true;
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
      ))?.copyWith(
        lastLoginAt: now,
      );

      if (account == null) {
        // Generate default password and encrypt private key for nesc login
        String encryptedPrivKey = '';
        String defaultPassword = '';

        if (loginType == LoginType.nesc) {
          if (privateKey == null) throw Exception('nesc login must has privateKey');
          defaultPassword = _generatePassword();
          encryptedPrivKey = _encryptPrivateKey(privateKey, defaultPassword);
        }

        account = AccountModel(
          pubkey: pubkey,
          loginType: loginType,
          encryptedPrivKey: encryptedPrivKey,
          defaultPassword: defaultPassword,
          nostrConnectUri: nostrConnectUri ?? '',
          circles: [],
          createdAt: now,
          lastLoginAt: now,
          db: accountDb,
        );
      }

      // 3. Save account info to DB.
      await account.saveToDB();

      // 4. Update login state
      final loginState = LoginState(account: account);
      _state$.value = loginState;

      // 5. Persist login information
      await _persistLoginInfo(pubkey);

      // 6. Try to login to last circle or first circle
      await _tryLoginLastCircle(loginState);

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
  String _encryptPrivateKey(String privateKey, String password) {
    final privateKeyBytes = hex.decode(privateKey);
    final encryptedBytes = encryptPrivateKey(Uint8List.fromList(privateKeyBytes), password);
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

    final success = await _loginToCircle(circle, currentState);
    if (!success) {
      if (originCircle != null) {
        _loginToCircle(originCircle, currentState);
      }
      return LoginFailure(
        type: LoginFailureType.circleDbFailed,
        message: 'Login circle failed',
        circleId: circle.id,
      );
    }

    return null;
  }

  /// Join circle
  ///
  /// [relayUrl] Circle's relay address
  /// [type] Circle type
  Future<LoginFailure?> joinCircle(String relayUrl, {CircleType type = CircleType.relay}) async {
    try {
      final currentState = this.currentState;

      final account = currentState.account;
      if (account == null) {
        return const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'No account logged in',
        );
      }

      // Generate circle ID from relay URL (simplified for now)
      final circleId = _generateCircleId(relayUrl);

      // Check if circle already exists in account
      final existingCircle = account.circles.where((c) => c.id == circleId).firstOrNull;
      if (existingCircle != null) {
        // Circle already exists, just switch to it
        return switchToCircle(existingCircle);
      }

      // Create new circle
      final newCircle = Circle(
        id: circleId,
        name: _extractCircleName(relayUrl, type),
        relayUrl: relayUrl,
        type: type,
      );

      // Add circle to account's circle list
      final updatedCircles = [...account.circles, newCircle];
      final updatedAccount = account.copyWith(
        circles: updatedCircles,
      );
      await updatedAccount.saveToDB();

      // Update state with new account (but not current circle yet)
      _state$.value = currentState.copyWith(
        account: updatedAccount,
      );

      final switchResult = await switchToCircle(newCircle);
      if (switchResult != null) {
        // Switch failed, remove the circle from the list
        final revertedCircles = [...account.circles]; // original circles
        final revertedAccount = account.copyWith(
          circles: revertedCircles,
        );
        await revertedAccount.saveToDB();
        _state$.value = currentState.copyWith(
          account: revertedAccount,
        );
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
      CLUserPushNotificationManager.instance.dispose();
      CLCacheManager.clearCircleCacheById(originCircle.id);
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
        _notifyCircleChangeFailed(const LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'No account logged in',
        ));
        return false;
      }

      if (circleId.isEmpty) {
        _notifyCircleChangeFailed(LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Circle ID cannot be empty',
          circleId: circleId,
        ));
        return false;
      }

      final circleToDelete = account.circles.where((c) => c.id == circleId).firstOrNull;
      if (circleToDelete == null) {
        _notifyCircleChangeFailed(LoginFailure(
          type: LoginFailureType.errorEnvironment,
          message: 'Circle not found',
          circleId: circleId,
        ));
        return false;
      }

      // Check if this is the current circle
      final isCurrentCircle = currentState.currentCircle?.id == circleId;

      final remainingCircles = account.circles.where((c) => c.id != circleId).toList();

      final isSwitch = remainingCircles.isNotEmpty;
      if (isSwitch) {
        final nextCircle = remainingCircles.first;
        if (isCurrentCircle) {
          final switchResult = await switchToCircle(nextCircle);
          if (switchResult != null) {
            _notifyCircleChangeFailed(switchResult);
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

      // Remove circle from account's circle list and save
      final updatedCircles = account.circles.where((c) => c.id != circleId).toList();
      final updatedAccount = account.copyWith(circles: updatedCircles);
      await updatedAccount.saveToDB();

      // Update state
      if (!isSwitch) {
        LoginUserNotifier.instance.updateUserSource(null);
      }
      final updatedState = this.currentState.copyWith(
        account: updatedAccount,
        currentCircle: isSwitch ? this.currentState.currentCircle : null,
      );
      _state$.value = updatedState;

      return true;
    } catch (e) {
      _notifyCircleChangeFailed(LoginFailure(
        type: LoginFailureType.circleDbFailed,
        message: 'Failed to delete circle: $e',
        circleId: circleId,
      ));
      return false;
    }
  }

  Future<bool> _tryLoginLastCircle(LoginState loginState) async {
    final account = loginState.account;
    if (account == null) return false;

    final lastCircleId = account.lastLoginCircleId ?? '';
    if (lastCircleId.isNotEmpty && account.circles.isNotEmpty) {
      final targetCircle = account.circles.where((c) => c.id == lastCircleId).firstOrNull;
      if (targetCircle != null) {
        return await _loginToCircle(targetCircle, loginState);
      }
    }

    return false;
  }

  /// Login to specified circle
  ///
  /// This performs circle-level login using Account.sharedInstance methods
  Future<bool> _loginToCircle(Circle circle, LoginState loginState) async {
    try {
      final account = loginState.account;
      if (account == null) {
        _notifyCircleChangeFailed(LoginFailure(
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
        _notifyCircleChangeFailed(LoginFailure(
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
        _notifyCircleChangeFailed(LoginFailure(
          type: LoginFailureType.circleDbFailed,
          message: 'Circle-level login failed',
          circleId: circle.id,
        ));
        return false;
      }

      // Login success
      account.updateLastLoginCircle(circle.id);
      _state$.value = loginState.copyWith(
        currentCircle: circle,
      );

      _loginCircleSuccessHandler(account, circle);

      // Notify circle change success
      for (final observer in _observers) {
        observer.onCircleChanged(circle);
      }

      return true;
    } catch (e) {
      _notifyCircleChangeFailed(LoginFailure(
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
          final privateKey = AccountHelperEx.getPrivateKey(
            account.encryptedPrivKey,
            account.defaultPassword,
          );
          return Account.sharedInstance.loginWithPriKey(privateKey);

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
            );
          }
          break;
      }

      return null;
    } catch (e) {
      debugPrint('Circle login failed: $e');
      return null;
    }
  }

  /// Notify circle change failure
  void _notifyCircleChangeFailed(LoginFailure failure) {
    for (final observer in _observers) {
      observer.onCircleChangeFailed(failure);
    }
  }

  void _loginCircleSuccessHandler(AccountModel account, Circle circle) async {
    final pubkey = account.pubkey;
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
    final config = ChatCoreInitConfig(
      pubkey: account.pubkey,
      databasePath: await AccountPathManager.getCircleFolderPath(account.pubkey, circle.id),
      encryptionPassword: await _getEncryptionPassword(account),
      circleId: circle.id,
      isLite: true,
      circleRelay: circle.relayUrl,
      contactUpdatedCallBack: Contacts.sharedInstance.contactUpdatedCallBack,
      channelsUpdatedCallBack: Channels.sharedInstance.myChannelsUpdatedCallBack,
      groupsUpdatedCallBack: Groups.sharedInstance.myGroupsUpdatedCallBack,
      relayGroupsUpdatedCallBack: RelayGroup.sharedInstance.myGroupsUpdatedCallBack,
      pushServerRelay: 'ws://www.0xchat.com:9090'
    );
    await ChatCoreManager().initChatCoreWithConfig(config);
    LoginUserNotifier.instance.updateUserSource(Account.sharedInstance.getUserNotifier(pubkey));
    Account.sharedInstance.reloadProfileFromRelay(pubkey);
    Account.sharedInstance.syncFollowingListFromRelay(pubkey, relay: circle.relayUrl);

    initializePushCore();
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

  /// Clear login information
  Future<void> _clearLoginInfo() async {
    await OXCacheManager.defaultOXCacheManager.saveForeverData(
      LoginManager._keyLastPubkey,
      null,
    );
  }

  /// Get last logged pubkey
  Future<String?> _getLastPubkey() async {
    return await OXCacheManager.defaultOXCacheManager.getForeverData(
      LoginManager._keyLastPubkey,
    );
  }

  /// Get encryption password from account
  Future<String> _getEncryptionPassword(AccountModel account) async {
    // Use database encryption key from DBKeyManager
    return await DBKeyManager.getKey();
  }
}

/// Utility methods for LoginManager
extension LoginManagerUtils on LoginManager {
  /// Generate circle ID from relay URL
  String _generateCircleId(String relayUrl) {
    // Simple hash of the relay URL to create a unique ID
    return Uuid().v4();
  }

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