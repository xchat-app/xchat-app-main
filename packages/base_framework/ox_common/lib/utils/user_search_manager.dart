import 'package:flutter/foundation.dart';
import 'package:ox_common/utils/chat_user_utils.dart';
import 'package:ox_common/utils/search_manager.dart';
import 'package:chatcore/chat-core.dart';

/// Generic user search manager that handles both local and remote user searches
/// with support for different user model types through conversion
class UserSearchManager<T> {
  final SearchManager<T> _searchManager;
  List<ValueNotifier<UserDBISAR>> _allUsers = [];
  bool _isLoading = false;

  // Conversion functions
  final T Function(ValueNotifier<UserDBISAR>) _convertToTargetModel;
  final String Function(T) _getUserId;

  static UserSearchManager<ValueNotifier<UserDBISAR>> defaultCreate({
    Duration debounceDelay = const Duration(milliseconds: 300),
    int minSearchLength = 1,
    int maxResults = 50,
  }) => _DefaultUserSearchManager(
    debounceDelay: debounceDelay,
    minSearchLength: minSearchLength,
    maxResults: maxResults,
  );

  /// Constructor for custom user models
  /// Use this when your user model is different from UserDBISAR
  UserSearchManager.custom({
    required T Function(ValueNotifier<UserDBISAR>) convertToTargetModel,
    required String Function(T) getUserId,
    Duration debounceDelay = const Duration(milliseconds: 300),
    int minSearchLength = 1,
    int maxResults = 50,
  })  : _convertToTargetModel = convertToTargetModel,
        _getUserId = getUserId,
        _searchManager = SearchManager<T>(
          debounceDelay: debounceDelay,
          minSearchLength: minSearchLength,
          maxResults: maxResults,
        );

  /// Get the underlying search manager's result notifier
  ValueNotifier<SearchResult<T>> get resultNotifier =>
      _searchManager.resultNotifier;

  /// Get current search results
  List<T> get results => _searchManager.results;

  /// Get current search state
  SearchState get state => _searchManager.state;

  /// Get current search query
  String get currentQuery => _searchManager.currentQuery;

  /// Check if currently loading users
  bool get isLoading => _isLoading;

  /// Initialize and load user data
  Future<void> initialize({
    List<String>? excludeUserPubkeys,
    List<ValueNotifier<UserDBISAR>>? externalUsers,
  }) async {
    if (_isLoading) return;

    _isLoading = true;
    try {
      if (externalUsers != null) {
        // Use externally provided user list
        _allUsers = [...externalUsers];
      } else {
        // Default behavior: use ChatUserUtils to get all users from cache
        _allUsers = (await ChatUserUtils.getAllUsers()).map(
          (e) => Account.sharedInstance.getUserNotifier(e.pubKey)
        ).toList();
      }
      
      // Filter out excluded users if provided
      if (excludeUserPubkeys != null && excludeUserPubkeys.isNotEmpty) {
        _allUsers = _allUsers.where((notifier) =>
          !excludeUserPubkeys.contains(notifier.value.pubKey)
        ).toList();
      }
    } catch (e) {
      print('Error loading users: $e');
      _allUsers = [];
    } finally {
      _isLoading = false;
    }
  }

  /// Get all loaded users converted to target model
  List<T> get allUsers => _allUsers.map(_convertToTargetModel).toList();

  /// Perform search with the given query
  void search(String query) {
    _searchManager.search(
      query,
      localSearch: _performLocalSearch,
      remoteSearch: _performRemoteSearch,
      isDuplicate: (local, remote) => _getUserId(local) == _getUserId(remote),
    );
  }

  /// Perform immediate search without debouncing
  Future<void> searchImmediate(String query) async {
    await _searchManager.searchImmediate(
      query,
      localSearch: _performLocalSearch,
      remoteSearch: _performRemoteSearch,
      isDuplicate: (local, remote) => _getUserId(local) == _getUserId(remote),
    );
  }

  /// Clear search results
  void clear() {
    _searchManager.clear();
  }

  /// Dispose resources
  void dispose() {
    _searchManager.dispose();
  }

  /// Perform local search on loaded users
  Future<List<T>> _performLocalSearch(String query) async {
    final lowerQuery = query.toLowerCase();
    return _allUsers
        .where((notifier) {
          final user = notifier.value;
          final name = (user.name ?? '').toLowerCase();
          final nickName = (user.nickName ?? '').toLowerCase();
          final encodedPubkey = user.encodedPubkey.toLowerCase();

          return name.contains(lowerQuery) ||
              nickName.contains(lowerQuery) ||
              encodedPubkey.contains(lowerQuery);
        })
        .map(_convertToTargetModel)
        .toList();
  }

  /// Perform remote search for users by pubkey or DNS (public method)
  Future<List<T>> performRemoteSearch(String query) async {
    return _performRemoteSearch(query);
  }

  /// Perform remote search for users by pubkey or DNS
  Future<List<T>> _performRemoteSearch(String query) async {
    final isPubkeyFormat = query.startsWith('npub');
    final isDnsFormat = query.contains('@');

    if (!isPubkeyFormat && !isDnsFormat) {
      return [];
    }

    String pubkey = '';
    if (isPubkeyFormat) {
      pubkey = UserDBISAR.decodePubkey(query) ?? '';
    } else if (isDnsFormat) {
      pubkey = await Account.getDNSPubkey(
            query.substring(0, query.indexOf('@')),
            query.substring(query.indexOf('@') + 1),
          ) ??
          '';
    }

    if (pubkey.isNotEmpty) {
      ValueNotifier<UserDBISAR> user$ =
        await Account.sharedInstance.getUserNotifier(pubkey);

      // Add to local users if not already present
      if (!_allUsers.any((notifier) => notifier.value.pubKey == user$.value.pubKey)) {
        _allUsers.add(user$);
      }

      // Reload user info from remote
      Account.sharedInstance.reloadProfileFromRelay(user$.value.pubKey,);

      return [_convertToTargetModel(user$)];
    }

    return [];
  }
}

/// Default UserSearchManager for UserDBISAR
/// Use this when your user model is UserDBISAR (no conversion needed)
class _DefaultUserSearchManager extends UserSearchManager<ValueNotifier<UserDBISAR>> {
  _DefaultUserSearchManager({
    Duration debounceDelay = const Duration(milliseconds: 300),
    int minSearchLength = 1,
    int maxResults = 50,
  }) : super.custom(
          convertToTargetModel: defaultConvertToTargetModel,
          getUserId: defaultGetUserId,
          debounceDelay: debounceDelay,
          minSearchLength: minSearchLength,
          maxResults: maxResults,
        );

  static ValueNotifier<UserDBISAR> defaultConvertToTargetModel(ValueNotifier<UserDBISAR> user$) => user$;

  static String defaultGetUserId(ValueNotifier<UserDBISAR> user$) =>
      user$.value.pubKey;
}
