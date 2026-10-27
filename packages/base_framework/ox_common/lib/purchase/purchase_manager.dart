import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_common/purchase/purchase_idempotency_manager.dart';
import 'package:ox_common/purchase/subscription_product_prices.dart';
import 'package:ox_common/purchase/subscription_platform.dart';
import 'package:ox_common/purchase/subscription_registry.dart';
import 'package:ox_common/purchase/purchase_service.dart';
import 'package:ox_common/store_shots/store_shots_flag.dart';

/// Purchase result returned from purchaseProduct/restorePurchases
class PurchaseResult {
  PurchaseResult({
    required this.success,
    this.errorMessage,
    this.verificationResult,
    this.purchaseDetails,
    this.isCanceled = false,
    this.isAlreadyRestored = false,
    this.isSubscriptionExpired = false,
  });

  /// Whether the purchase was successful (new delivery completed)
  final bool success;

  /// Error message if purchase failed
  final String? errorMessage;

  /// Payment verification result (available on success)
  final PaymentVerificationResult? verificationResult;

  /// Purchase details (available on success)
  final PurchaseDetails? purchaseDetails;

  /// Whether the purchase was canceled by user
  final bool isCanceled;

  /// Restore only: entitlement already present (circle exists), no new delivery. Not error.
  final bool isAlreadyRestored;

  /// Subscription in receipt is expired; transaction was finished. UI should prompt "Tap to renew".
  final bool isSubscriptionExpired;

  /// Create success result
  factory PurchaseResult.success({
    required PaymentVerificationResult verificationResult,
    required PurchaseDetails purchaseDetails,
  }) {
    return PurchaseResult(
      success: true,
      verificationResult: verificationResult,
      purchaseDetails: purchaseDetails,
      isCanceled: false,
    );
  }

  /// Create error result
  factory PurchaseResult.error(String errorMessage) {
    return PurchaseResult(
      success: false,
      errorMessage: errorMessage,
      isCanceled: false,
    );
  }

  /// Create canceled result.
  /// [message] Optional platform message (e.g. iOS "This transaction has been cancelled by the user.").
  /// UI should show [message] if present, otherwise localized fallback.
  factory PurchaseResult.canceled({String? message}) {
    return PurchaseResult(
      success: false,
      errorMessage: message,
      isCanceled: true,
    );
  }

  /// Restore only: circle already exists, nothing new to restore. Not success, not error.
  factory PurchaseResult.alreadyRestored() {
    return PurchaseResult(
      success: false,
      errorMessage: null,
      isCanceled: false,
      isAlreadyRestored: true,
    );
  }

  /// Subscription in receipt is expired; transaction finished so user can renew. Not success, not error.
  factory PurchaseResult.subscriptionExpired({String? message}) {
    return PurchaseResult(
      success: false,
      errorMessage: message ?? 'Subscription has expired. Please renew your subscription.',
      isCanceled: false,
      isSubscriptionExpired: true,
    );
  }
}


enum _SessionType { purchase, restore }

/// Internal session used to route purchaseStream events and complete Futures.
class _PurchaseSession {
  _PurchaseSession({
    required this.type,
    required this.productIds,
    required this.createdAt,
    required this.window,
    required this.idleTimeout,
    this.completer,
    this.restoreCompleters,
  });

  final _SessionType type;

  /// Allowed products for routing. For restore this is usually empty (allow all).
  final Set<String> productIds;

  /// When the session starts (used by time window filter).
  final DateTime createdAt;

  /// Accept events whose transactionDate is within [createdAt - window, now + window].
  final Duration window;

  /// Restore session ends when no new events arrive for [idleTimeout].
  final Duration idleTimeout;

  /// Completer for purchase session (single product)
  final Completer<PurchaseResult>? completer;

  /// Completers for restore session (multiple products)
  final Map<String, Completer<PurchaseResult>>? restoreCompleters;

  Timer? _idleTimer;

  void touch(VoidCallback onIdle) {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, onIdle);
  }

  void dispose() {
    _idleTimer?.cancel();
    _idleTimer = null;
  }
}

/// Global purchase manager that listens to purchaseStream at app startup,
/// but only processes events when a session (purchase/restore) is active.
///
/// Design goals:
/// - Global listener always on (never resubscribe) to avoid missing events.
/// - No silent restore / no startup processing (per your policy).
/// - Session-based routing with strict filters to avoid old restored events polluting new purchases.
/// - Local txKey de-duplication to prevent duplicated processing & log flood.
/// - Restore session ends by idle-timeout and auto-unregisters.
class PurchaseManager {
  static final PurchaseManager instance = PurchaseManager._();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  bool _isInitialized = false;

  /// Debouncing map to prevent duplicate purchases
  final Map<String, bool> _pendingPurchases = {};

  /// Active routing session (purchase or restore)
  _PurchaseSession? _activeSession;

  /// Local dedupe: txKey -> lastSeenAt
  final Map<String, DateTime> _seenTxKeys = {};

  /// Dedupe retention (prevents log flood & repeated processing)
  final Duration _seenRetention = const Duration(minutes: 10);

  PurchaseManager._();

  /// Initialize the purchase manager and subscribe to purchase stream.
  /// Call early in app init.
  Future<void> initialize() async {
    // Screenshot builds never talk to Play Billing.
    if (kStoreShots) return;
    if (_isInitialized) {
      LogUtil.d(() => 'PurchaseManager already initialized');
      return;
    }

    try {
      _subscription = _inAppPurchase.purchaseStream.listen(
        _handlePurchaseUpdates,
        onError: (error) {
          LogUtil.e(() => 'Purchase stream error: $error');
        },
        cancelOnError: false,
      );

      _isInitialized = true;
      LogUtil.d(() => 'PurchaseManager initialized successfully');

      // Preload subscription product prices so flow pages show price immediately (no loading).
      _preloadProductDetails();
    } catch (e) {
      LogUtil.e(() => 'Error initializing PurchaseManager: $e');
      rethrow;
    }
  }

  /// Preload all subscription product prices into [SubscriptionProductPrices]. Awaited so data is ready before user enters purchase flow.
  Future<void> _preloadProductDetails() async {
    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) {
        SubscriptionProductPrices.instance.updateFromMap({});
        return;
      }
      final productIds = SubscriptionPlatform.instance.productIdsForQuery;
      if (productIds.isEmpty) {
        SubscriptionProductPrices.instance.updateFromMap({});
        return;
      }
      final response = await _inAppPurchase.queryProductDetails(productIds);
      if (response.error != null) {
        LogUtil.w(() => '[PurchaseManager] Preload product details error: ${response.error}');
        SubscriptionProductPrices.instance.updateFromMap({});
        return;
      }
      final idToPriceMap = <String, String>{};
      final idToRawPriceMap = <String, double>{};
      await _fillProductPricesFromResponse(
        response.productDetails,
        idToPriceMap,
        idToRawPriceMap,
      );
      SubscriptionProductPrices.instance.updateFromMap(idToPriceMap, idToRawPriceMap);
      LogUtil.d(() => '[PurchaseManager] Preloaded ${idToPriceMap.length} product prices');
    } catch (e) {
      LogUtil.w(() => '[PurchaseManager] Preload product details failed: $e');
      SubscriptionProductPrices.instance.updateFromMap({});
    }
  }

  /// Fills idToPrice/idToRawPrice from store response.
  /// On iOS each detail has logical id (e.g. loc1.level1.monthly); one-to-one mapping.
  /// On Android product+plan: store returns 2 details per product (same id), we group by id
  /// and assign by rawPrice: lower → .monthly, higher → .yearly.
  Future<void> _fillProductPricesFromResponse(
    List<ProductDetails> details,
    Map<String, String> idToPrice,
    Map<String, double> idToRawPrice,
  ) async {
    final hasLogicalIds = details.any((d) =>
        d.id.endsWith('.monthly') || d.id.endsWith('.yearly'));
    if (hasLogicalIds) {
      for (final d in details) {
        _addDetailToLogicalPriceMaps(d.id, d.price, d.rawPrice, idToPrice, idToRawPrice);
      }
      return;
    }
    // Android: duplicate ids (one per base plan). Prefer base plan id to assign monthly/yearly; fallback to rawPrice order.
    final byId = <String, List<ProductDetails>>{};
    for (final d in details) {
      byId.putIfAbsent(d.id, () => []).add(d);
    }
    for (final entry in byId.entries) {
      final id = entry.key;
      final list = entry.value;
      ProductDetails? monthlyDetail;
      ProductDetails? yearlyDetail;
      for (final d in list) {
        final planId = _getAndroidBasePlanId(d);
        if (planId == 'monthly') monthlyDetail = d;
        if (planId == 'yearly') yearlyDetail = d;
      }
      if (monthlyDetail == null || yearlyDetail == null) {
        list.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
        monthlyDetail ??= list.first;
        yearlyDetail ??= list.length >= 2 ? list[1] : list.first;
      }
      idToPrice['$id.monthly'] = monthlyDetail.price;
      idToRawPrice['$id.monthly'] = monthlyDetail.rawPrice;
      idToPrice['$id.yearly'] = yearlyDetail.price;
      idToRawPrice['$id.yearly'] = yearlyDetail.rawPrice;
    }
  }

  void _addDetailToLogicalPriceMaps(
    String id,
    String price,
    double rawPrice,
    Map<String, String> idToPrice,
    Map<String, double> idToRawPrice,
  ) {
    if (id.endsWith('.monthly') || id.endsWith('.yearly')) {
      idToPrice[id] = price;
      idToRawPrice[id] = rawPrice;
    } else {
      idToPrice['$id.monthly'] = price;
      idToPrice['$id.yearly'] = price;
      idToRawPrice['$id.monthly'] = rawPrice;
      idToRawPrice['$id.yearly'] = rawPrice;
    }
  }

  /// Refreshes price for [productId] from store and updates [SubscriptionProductPrices] (with rawPrice for lowest-price logic).
  Future<void> refreshPrice(String productId) async {
    final d = await getProductDetails(productId);
    if (d != null) {
      SubscriptionProductPrices.instance.setPrice(productId, d.price, d.rawPrice);
    }
  }

  /// Picks the [ProductDetails] to pass to buy (so confirmation dialog shows correct plan/price).
  /// Prefer store base plan id (Android) to match monthly/yearly; fallback to rawPrice order if unavailable.
  ProductDetails _productDetailsForPurchase(
    List<ProductDetails> details,
    String productId,
  ) {
    if (details.length == 1) return details.first;
    final wantYearly = productId.endsWith('.yearly');
    final wantPlanId = wantYearly ? 'yearly' : 'monthly';
    for (final d in details) {
      final planId = _getAndroidBasePlanId(d);
      if (planId == wantPlanId) return d;
    }
    final sorted = List<ProductDetails>.from(details)
      ..sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    return wantYearly ? sorted.last : sorted.first;
  }

  /// Android: base plan id from [ProductDetails] when it is [GooglePlayProductDetails]. Null on iOS or when unavailable.
  static String? _getAndroidBasePlanId(ProductDetails d) {
    if (d is! GooglePlayProductDetails) return null;
    final idx = d.subscriptionIndex;
    final offers = d.productDetails.subscriptionOfferDetails;
    if (idx == null || offers == null || idx < 0 || idx >= offers.length) return null;
    return offers[idx].basePlanId;
  }

  /// Refreshes prices for [productIds] in one query and updates notifiers.
  /// Uses store response list so Android's 2 details per product (monthly/yearly) are both applied.
  Future<void> refreshPrices(Set<String> productIds) async {
    if (productIds.isEmpty) return;
    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) return;
      final idsToQuery = productIds
          .map((id) =>
              SubscriptionPlatform.instance.storeProductIdForQuery(id) ?? id)
          .toSet();
      final response = await _inAppPurchase.queryProductDetails(idsToQuery);
      if (response.error != null) return;
      final idToPrice = <String, String>{};
      final idToRawPrice = <String, double>{};
      await _fillProductPricesFromResponse(
          response.productDetails, idToPrice, idToRawPrice);
      SubscriptionProductPrices.instance.updateFromMap(idToPrice, idToRawPrice);
    } catch (_) {}
  }

  /// Refreshes all subscription product prices. Call from page initState for silent refresh (updates all notifiers).
  /// On Android uses 6 store product IDs; prices are then mapped to 12 logical IDs in _fillProductPricesFromResponse.
  Future<void> refreshAllPrices() async {
    final productIds = SubscriptionPlatform.instance.productIdsForQuery;
    await refreshPrices(productIds);
  }

  /// Returns the lowest price (display string) if all products have a price; null if any product price is missing.
  String? getLowestPrice() => SubscriptionProductPrices.instance.getLowestPrice();

  /// --- Session APIs ---------------------------------------------------------

  /// Start a "new purchase" session. Must be called just before buyNonConsumable.
  ///
  /// Filters:
  /// - productId must match
  /// - ignores restored events entirely
  /// - only accepts transactionDate within a time window (default 2 minutes)
  void _beginPurchaseSession({
    required String productId,
    required Completer<PurchaseResult> completer,
    Duration acceptWindow = const Duration(minutes: 2),
  }) {
    _endSessionInternal(reason: 'beginPurchaseSession replaces old session');

    _activeSession = _PurchaseSession(
      type: _SessionType.purchase,
      productIds: {productId},
      createdAt: DateTime.now(),
      window: acceptWindow,
      idleTimeout: const Duration(seconds: 0), // not used for purchase
      completer: completer,
    );

    LogUtil.d(() => '''
      [PurchaseManager] beginPurchaseSession:
      - productId: $productId
      - createdAt: ${_activeSession!.createdAt.toIso8601String()}
      - window: ${_activeSession!.window}
    ''');
  }

  /// Start a "restore purchases" session and call Store restore.
  ///
  /// Restore session ends automatically when no new events arrive for [idleTimeout].
  void _beginRestoreSession({
    required Map<String, Completer<PurchaseResult>> restoreCompleters,
    Duration acceptWindow = const Duration(days: 3650), // accept almost all
    Duration idleTimeout = const Duration(seconds: 2),
  }) {
    _endSessionInternal(reason: 'beginRestoreSession replaces old session');

    _activeSession = _PurchaseSession(
      type: _SessionType.restore,
      productIds: <String>{}, // allow all (you can restrict if needed)
      createdAt: DateTime.now(),
      window: acceptWindow,
      idleTimeout: idleTimeout,
      restoreCompleters: restoreCompleters,
    );

    LogUtil.d(() => '''
      [PurchaseManager] beginRestoreSession:
      - createdAt: ${_activeSession!.createdAt.toIso8601String()}
      - idleTimeout: $idleTimeout
      - window: $acceptWindow
      - products to restore: ${restoreCompleters.keys.join(', ')}
    ''');
  }

  void _endSessionInternal({required String reason}) {
    if (_activeSession == null) return;
    LogUtil.d(() => '[PurchaseManager] endSession: $reason');
    
    // Complete any pending completers with timeout error
    final session = _activeSession!;
    if (session.completer != null && !session.completer!.isCompleted) {
      session.completer!.completeError(
        Exception('Purchase session ended: $reason'),
      );
    }
    if (session.restoreCompleters != null) {
      for (final completer in session.restoreCompleters!.values) {
        if (!completer.isCompleted) {
          completer.completeError(
            Exception('Restore session ended: $reason'),
          );
        }
      }
    }
    
    session.dispose();
    _activeSession = null;
  }

  /// --- purchaseStream handler ----------------------------------------------

  Future<void> _handlePurchaseUpdates(
      List<PurchaseDetails> purchaseDetailsList,
      ) async {
    final session = _activeSession;
    if (session == null) return;

    _evictSeenKeys();

    for (final purchaseDetails in purchaseDetailsList) {
      try {
        // Log raw event (always), but avoid flooding by txKey dedupe.
        final txKey = _buildTxKey(purchaseDetails);
        if (_markSeen(txKey)) {
          LogUtil.d(() => '''
            [PurchaseManager] Purchase update:
            - txKey: $txKey
            - productID: ${purchaseDetails.productID}
            - purchaseID: ${purchaseDetails.purchaseID}
            - status: ${purchaseDetails.status}
            - transactionDate: ${purchaseDetails.transactionDate}
            - localVerificationData: ${purchaseDetails.verificationData.localVerificationData}
            - source: ${purchaseDetails.verificationData.source}
            - pendingCompletePurchase: ${purchaseDetails.pendingCompletePurchase}
          ''');
        } else {
          // Seen recently; skip verbose log.
          LogUtil.d(() => '[PurchaseManager] Purchase update duplicated (ignored log): txKey=$txKey status=${purchaseDetails.status}');
        }

        // Session routing filters
        if (!_shouldRouteToSession(purchaseDetails, session)) {
          LogUtil.d(() => '''
            [PurchaseManager] Purchase update rejected by routing filter:
            - txKey: $txKey
            - productID: ${purchaseDetails.productID}
            - status: ${purchaseDetails.status}
          ''');
          continue;
        }

        LogUtil.d(() => '''
          [PurchaseManager] Purchase update accepted, processing:
          - txKey: $txKey
          - productID: ${purchaseDetails.productID}
          - status: ${purchaseDetails.status}
          - session type: ${session.type}
        ''');

        // For restore sessions, keep alive until idle timeout.
        if (session.type == _SessionType.restore) {
          session.touch(() {
            // auto end restore session by idle timeout
            _endSessionInternal(reason: 'restore idle timeout');
          });
        }

        // Route & process only once per txKey per session window
        // (We already have global seen-txKey dedupe. This ensures stable behavior.)
        await _processRoutedPurchase(purchaseDetails);
      } catch (e, stack) {
        LogUtil.e(() => 'Error handling purchase update: $e\n$stack');
      }
    }
  }

  bool _shouldRouteToSession(PurchaseDetails p, _PurchaseSession session) {
    // 1) product filter
    if (session.type == _SessionType.purchase) {
      // Android may send canceled/error with empty productID (e.g. user dismisses
      // dialog, or billing fails with resultCode 3). Accept so we complete the
      // session and reset UI. iOS typically sends productID; no platform check.
      if ((p.status == PurchaseStatus.canceled || p.status == PurchaseStatus.error) &&
          p.productID.isEmpty &&
          session.productIds.length == 1) {
        LogUtil.d(() => '''
          [PurchaseManager] Accepting ${p.status} with empty productID (current purchase session):
          - session productId: ${session.productIds.single}
        ''');
        return true;
      }
      // Match by logical product id (on Android, p.productID is store id e.g. loc1.level1; resolve to logical id for comparison).
      final pendingLogical = session.productIds.length == 1 ? session.productIds.single : null;
      final resolvedLogical = SubscriptionPlatform.instance.resolveLogicalProductId(p.productID, pendingLogicalId: pendingLogical);
      if (!session.productIds.contains(resolvedLogical)) return false;

      // For purchase session, handle restored status specially
      // New purchases can come as "restored" with transactionReason="PURCHASE"
      if (p.status == PurchaseStatus.restored) {
        // Check transactionReason to determine if this is a new purchase
        final transactionReason = _parseTransactionReason(p);
        if (transactionReason == 'PURCHASE') {
          // This is a new purchase, accept it regardless of time window
          // The transactionDate might be old (from previous purchase attempt),
          // but transactionReason="PURCHASE" indicates it's a new purchase
          LogUtil.d(() => '''
            [PurchaseManager] Accepting restored status with transactionReason=PURCHASE:
            - productID: ${p.productID}
            - transactionDate: ${p.transactionDate}
            - transactionReason: $transactionReason
            - Skipping time window check for new purchase
          ''');
          // Return true immediately - skip all time window checks
          return true;
        } else {
          // transactionReason is not "PURCHASE" (could be "RENEWAL" or null)
          // Apply time window check to avoid processing old restores
          final txTime = _parseTransactionDate(p.transactionDate);
          if (txTime != null) {
            final minTime = session.createdAt.subtract(session.window);
            final maxTime = DateTime.now().add(session.window);
            final isWithinWindow = !txTime.isBefore(minTime) && !txTime.isAfter(maxTime);
            if (!isWithinWindow) {
              // Out-of-window: either (1) active subscription re-sent, or (2) expired sub, user re-purchased.
              // If subscription has expired, treat as new purchase: accept and route to verify + joinCircle.
              final expired = PurchaseService.instance.isSubscriptionExpired(p);
              if (expired) {
                LogUtil.d(() => '''
                  [PurchaseManager] Accepting out-of-window restored (subscription expired, new purchase flow):
                  - productID: ${p.productID}
                  - transactionDate: ${p.transactionDate}
                  - transactionReason: $transactionReason
                ''');
                return true;
              }

              // Active subscription: user tapped purchase while already subscribed.
              LogUtil.d(() => '''
                [PurchaseManager] Rejecting restored status (out of time window):
                - productID: ${p.productID}
                - transactionDate: ${p.transactionDate}
                - transactionReason: $transactionReason
              ''');
              if (session.type == _SessionType.purchase) {
                _completeAlreadyOwned(p, reason: 'restored out of time window (likely existing subscription)');
              }
              return false;
            }
            // Within window - likely a renewal that should be processed
          } else {
            // If cannot parse time, check session age
            final age = DateTime.now().difference(session.createdAt);
            if (age > session.window) {
              LogUtil.d(() => '''
                [PurchaseManager] Rejecting restored status (session too old):
                - productID: ${p.productID}
                - session age: ${age.inSeconds}s
                - transactionReason: $transactionReason
              ''');
              return false;
            }
            // Recent session - likely a renewal
          }
        }
      }
    } else {
      // restore session: allow all productIds by default
      if (session.productIds.isNotEmpty && !session.productIds.contains(p.productID)) {
        return false;
      }
    }

    // 2) time window filter (for non-restored events in purchase session, or all events in restore session)
    if (session.type == _SessionType.purchase && p.status != PurchaseStatus.restored) {
      // Already checked above for restored, so skip here
    } else {
      final txTime = _parseTransactionDate(p.transactionDate);
      if (txTime != null) {
        final minTime = session.createdAt.subtract(session.window);
        final maxTime = DateTime.now().add(session.window);
        if (txTime.isBefore(minTime) || txTime.isAfter(maxTime)) {
          // Out-of-window (very likely an old restore)
          return false;
        }
      } else {
        // If cannot parse, for purchase session we are stricter: require it to be close in time by session age.
        if (session.type == _SessionType.purchase) {
          final age = DateTime.now().difference(session.createdAt);
          if (age > session.window) return false;
        }
      }
    }

    return true;
  }

  /// Complete current purchase session as "already owned".
  ///
  /// This is used when the store reports a restored/renewal transaction
  /// that is clearly older than the current purchase session window,
  /// which typically means the user already has an active subscription.
  void _completeAlreadyOwned(
    PurchaseDetails purchaseDetails, {
    required String reason,
  }) {
    final session = _activeSession;
    if (session == null ||
        session.type != _SessionType.purchase ||
        session.completer == null ||
        session.completer!.isCompleted) {
      return;
    }

    LogUtil.d(() => '''
      [PurchaseManager] Completing purchase as already owned:
      - productID: ${purchaseDetails.productID}
      - reason: $reason
    ''');

    // Tell caller that the entitlement already exists.
    session.completer!.complete(PurchaseResult.alreadyRestored());

    // Clear pending flag for this product.
    _pendingPurchases.remove(purchaseDetails.productID);

    // End session to clean up timers / state.
    _endSessionInternal(reason: reason);
  }

  DateTime? _parseTransactionDate(String? transactionDate) {
    if (transactionDate == null || transactionDate.isEmpty) return null;
    // transactionDate in plugin is often millis since epoch in string
    final millis = int.tryParse(transactionDate);
    if (millis != null) {
      // Some platforms use seconds; detect by magnitude.
      if (millis < 1000000000000) {
        // seconds
        return DateTime.fromMillisecondsSinceEpoch(millis * 1000);
      }
      return DateTime.fromMillisecondsSinceEpoch(millis);
    }
    // Try ISO8601 as fallback
    try {
      return DateTime.parse(transactionDate);
    } catch (_) {
      return null;
    }
  }

  /// Parse transactionReason from localVerificationData JSON
  /// 
  /// Returns "PURCHASE" for new purchases, "RENEWAL" for renewals, or null if not found
  String? _parseTransactionReason(PurchaseDetails purchaseDetails) {
    try {
      final localVerificationData = purchaseDetails.verificationData.localVerificationData;
      if (localVerificationData.isEmpty) {
        return null;
      }
      
      final json = jsonDecode(localVerificationData) as Map<String, dynamic>;
      return json['transactionReason'] as String?;
    } catch (e) {
      LogUtil.w(() => '[PurchaseManager] Failed to parse transactionReason: $e');
      return null;
    }
  }

  Future<void> _processRoutedPurchase(PurchaseDetails purchaseDetails) async {
    LogUtil.d(() => '''
      [PurchaseManager] _processRoutedPurchase called:
      - productID: ${purchaseDetails.productID}
      - status: ${purchaseDetails.status}
    ''');
    
    // Get transaction ID for idempotency check (your own helper)
    final transactionId = PurchaseIdempotencyManager.getTransactionId(purchaseDetails);

    switch (purchaseDetails.status) {
      case PurchaseStatus.pending:
        LogUtil.d(() => '[PurchaseManager] Handling pending status');
        _onPending(purchaseDetails);
        break;
      case PurchaseStatus.purchased:
        LogUtil.d(() => '[PurchaseManager] Handling purchased status');
        await _handlePurchased(purchaseDetails, transactionId);
        break;
      case PurchaseStatus.restored:
        LogUtil.d(() => '[PurchaseManager] Handling restored status');
        await _handleRestored(purchaseDetails, transactionId);
        break;
      case PurchaseStatus.error:
        LogUtil.d(() => '[PurchaseManager] Handling error status');
        await _handleError(purchaseDetails);
        break;
      case PurchaseStatus.canceled:
        LogUtil.d(() => '[PurchaseManager] Handling canceled status');
        await _handleCanceled(purchaseDetails);
        break;
    }
    
    LogUtil.d(() => '[PurchaseManager] _processRoutedPurchase completed');
  }

  void _onPending(PurchaseDetails purchaseDetails) {
    LogUtil.d(() => 'Purchase pending: ${purchaseDetails.productID}');
    // UI state management is now handled by callers
  }

  /// --- Purchased / Restored processing (unchanged core, but invoked only when routed) ----

  Future<void> _handlePurchased(
      PurchaseDetails purchaseDetails,
      String transactionId,
      ) async {
    LogUtil.d(() => '''
      [PurchaseManager] Processing purchased:
      - productID: ${purchaseDetails.productID}
      - purchaseID: ${purchaseDetails.purchaseID}
      - transactionId: $transactionId
      - transactionDate: ${purchaseDetails.transactionDate}
      - pendingCompletePurchase: ${purchaseDetails.pendingCompletePurchase}
    ''');

    final pendingLogical = _activeSession != null &&
            _activeSession!.type == _SessionType.purchase &&
            _activeSession!.productIds.length == 1
        ? _activeSession!.productIds.single
        : null;
    final logicalProductId = SubscriptionPlatform.instance.resolveLogicalProductId(
      purchaseDetails.productID,
      pendingLogicalId: pendingLogical,
    );
    final response = await PurchaseService.instance.processPurchase(
      purchaseDetails,
      logicalProductId: logicalProductId,
    );

    LogUtil.d(() => '''
      [PurchaseManager] processPurchase completed:
      - productID: "${purchaseDetails.productID}"
      - result: ${response.result}
      - message: ${response.message}
      - hasVerificationResult: ${response.verificationResult != null}
      - relayUrl: ${response.verificationResult?.relayUrl ?? 'N/A'}
      - tenantId: ${response.verificationResult?.tenantId ?? 'N/A'}
    ''');

    // Complete the Future for purchaseProduct
    final session = _activeSession;
    if (session != null && 
        session.type == _SessionType.purchase && 
        session.completer != null &&
        !session.completer!.isCompleted) {
      if (response.result == PurchaseProcessResult.success ||
          response.result == PurchaseProcessResult.alreadyProcessed) {
        if (response.verificationResult != null) {
          session.completer!.complete(PurchaseResult.success(
            verificationResult: response.verificationResult!,
            purchaseDetails: purchaseDetails,
          ));
        } else {
          session.completer!.complete(PurchaseResult(
            success: true,
            purchaseDetails: purchaseDetails,
            isCanceled: false,
          ));
        }
      } else if (response.result == PurchaseProcessResult.subscriptionExpired) {
        session.completer!.complete(PurchaseResult.subscriptionExpired(
          message: response.message,
        ));
      } else {
        session.completer!.complete(PurchaseResult.error(
          response.message ?? 'Purchase processing failed',
        ));
      }
      // Clear pending flag (use logical id so we clear the key we set in purchaseProduct).
      _pendingPurchases.remove(logicalProductId);
      _pendingPurchases.remove(purchaseDetails.productID);
      LogUtil.d(() => '[PurchaseManager] Purchase processed, pending flag cleared for: $logicalProductId');
    }
  }

  Future<void> _handleRestored(
      PurchaseDetails purchaseDetails,
      String transactionId,
      ) async {
    LogUtil.d(() => '''
      [PurchaseManager] _handleRestored called:
      - productID: ${purchaseDetails.productID}
      - transactionId: $transactionId
      - purchaseID: ${purchaseDetails.purchaseID}
    ''');

    // Determine if this is a new purchase or a restore based on session type
    // For subscriptions, new purchases can come as "restored" status
    // We need to use the correct processing method based on context
    final session = _activeSession;
    final bool isNewPurchase = session?.type == _SessionType.purchase;
    
    PurchaseProcessResponse response;
    final logicalProductId = SubscriptionPlatform.instance.resolveLogicalProductId(
      purchaseDetails.productID,
      pendingLogicalId: session != null &&
              session.type == _SessionType.purchase &&
              session.productIds.length == 1
          ? session.productIds.single
          : null,
    );
    if (isNewPurchase) {
      // New purchase that came as "restored" status - use processPurchase
      LogUtil.d(() => '''
        [PurchaseManager] Restored event in purchase session (new purchase):
        - productID: ${purchaseDetails.productID}
        - logicalProductId: $logicalProductId
      ''');
      response = await PurchaseService.instance.processPurchase(
        purchaseDetails,
        logicalProductId: logicalProductId,
      );
    } else {
      response = await PurchaseService.instance.processRestoredPurchase(
        purchaseDetails,
        logicalProductId: logicalProductId,
      );
    }

    LogUtil.d(() => '''
      [PurchaseManager] ${isNewPurchase ? 'processPurchase' : 'processRestoredPurchase'} completed:
      - productID: "${purchaseDetails.productID}"
      - result: ${response.result}
      - message: ${response.message}
      - hasVerificationResult: ${response.verificationResult != null}
    ''');

    // Complete the Future based on session type
    if (session != null) {
      if (session.type == _SessionType.restore &&
          session.restoreCompleters != null) {
        // On Android, purchaseDetails.productID is store id (e.g. loc1.level1); complete both .monthly and .yearly completers.
        final keysToComplete = session.restoreCompleters!.containsKey(purchaseDetails.productID)
            ? [purchaseDetails.productID]
            : [
                '${purchaseDetails.productID}.monthly',
                '${purchaseDetails.productID}.yearly',
              ];
        for (final key in keysToComplete) {
          final completer = session.restoreCompleters![key];
          if (completer != null && !completer.isCompleted) {
            if (response.result == PurchaseProcessResult.success) {
              completer.complete(PurchaseResult.success(
                verificationResult: response.verificationResult!,
                purchaseDetails: purchaseDetails,
              ));
            } else if (response.result == PurchaseProcessResult.alreadyRestored) {
              completer.complete(PurchaseResult.alreadyRestored());
            } else {
              final message =
                  response.message ?? 'No purchase to restore for this product';
              completer.complete(PurchaseResult.error(message));
            }
          }
        }
      } else if (session.type == _SessionType.purchase) {
        // Handle restored event in purchase session (new purchase that came as "restored")
        if (session.completer != null && !session.completer!.isCompleted) {
          if (response.result == PurchaseProcessResult.success) {
            // Success with verification result
            session.completer!.complete(PurchaseResult.success(
              verificationResult: response.verificationResult!,
              purchaseDetails: purchaseDetails,
            ));
          } else if (response.result == PurchaseProcessResult.alreadyProcessed) {
            // Already processed - or re-delivered (circle was missing locally and re-joined)
            LogUtil.d(() => '''
              [PurchaseManager] Purchase already processed, completing as success:
              - productID: ${purchaseDetails.productID}
              - transactionId: $transactionId
              - hasVerificationResult: ${response.verificationResult != null}
            ''');
            if (response.verificationResult != null) {
              session.completer!.complete(PurchaseResult.success(
                verificationResult: response.verificationResult!,
                purchaseDetails: purchaseDetails,
              ));
            } else {
              session.completer!.complete(PurchaseResult(
                success: true,
                purchaseDetails: purchaseDetails,
                isCanceled: false,
              ));
            }
          } else if (response.result == PurchaseProcessResult.subscriptionExpired) {
            session.completer!.complete(PurchaseResult.subscriptionExpired(
              message: response.message,
            ));
          } else {
            session.completer!.complete(PurchaseResult.error(
              response.message ?? 'Purchase processing failed',
            ));
          }
          // Clear pending flag immediately
          _pendingPurchases.remove(purchaseDetails.productID);
          LogUtil.d(() => '[PurchaseManager] Purchase processed (restored), pending flag cleared for: ${purchaseDetails.productID}');
        }
      }
    }
  }

  /// Returns a user-facing message for cancel, or null to use localized fallback.
  /// Android plugin often puts technical strings in error.message (e.g. "BillingResponse.userCanceled");
  /// filter those so UI shows ox_login.purchase_canceled instead.
  String? _userFriendlyCancelMessage(String? platformMessage) {
    if (platformMessage == null || platformMessage.trim().isEmpty) return null;
    final lower = platformMessage.toLowerCase();
    if (lower.contains('billingresponse')) {
      return null; // Technical identifier, not for end user
    }
    return platformMessage.trim();
  }

  /// True when the error represents user cancellation (so we can return
  /// [PurchaseResult.canceled] and align with [PurchaseStatus.canceled] path).
  /// - iOS StoreKit 2: code "storekit2_purchase_cancelled", message "This transaction has been cancelled by the user."
  /// - iOS StoreKit 1: SKError.Code.paymentCancelled = 2 → plugin may expose code "2".
  /// - Android: BillingResponseCode.USER_CANCELED = 1 → plugin may expose "1".
  bool _isUserCancelError(PurchaseDetails purchaseDetails) {
    final err = purchaseDetails.error;
    if (err == null) return false;
    final code = err.code.trim();
    if (code == '1' || code == '2') return true; // Android 1, iOS StoreKit 1 (2)
    if (code == 'storekit2_purchase_cancelled') return true; // iOS StoreKit 2
    final msg = err.message.toLowerCase();
    if (msg.contains('cancel')) return true;
    return false;
  }

  Future<void> _handleError(PurchaseDetails purchaseDetails) async {
    LogUtil.e(() => '''
      [PurchaseManager] Purchase error:
      - productID: ${purchaseDetails.productID}
      - purchaseID: ${purchaseDetails.purchaseID}
      - error code: ${purchaseDetails.error?.code}
      - error message: ${purchaseDetails.error?.message}
      - error details: ${purchaseDetails.error?.details}
      - pendingCompletePurchase: ${purchaseDetails.pendingCompletePurchase}
    ''');

    final session = _activeSession;
    final bool isPurchaseSession =
        session != null &&
        session.type == _SessionType.purchase &&
        session.completer != null &&
        !session.completer!.isCompleted;

    if (isPurchaseSession) {
      final productIdToClear = purchaseDetails.productID.isNotEmpty
          ? purchaseDetails.productID
          : (session.productIds.length == 1 ? session.productIds.single : null);

      if (_isUserCancelError(purchaseDetails)) {
        // Prefer platform message when user-friendly (e.g. iOS); Android often sends "BillingResponse.userCanceled" → use null so UI shows localized text.
        final cancelMessage = _userFriendlyCancelMessage(purchaseDetails.error?.message);
        session.completer!.complete(PurchaseResult.canceled(message: cancelMessage));
        if (productIdToClear != null) {
          _pendingPurchases.remove(productIdToClear);
          LogUtil.d(() => '[PurchaseManager] Purchase error treated as user cancel, pending flag cleared for: $productIdToClear');
        }
        return;
      }

      final errorMessage = purchaseDetails.error?.message ?? 'Purchase error';
      session.completer!.complete(PurchaseResult.error(errorMessage));
      if (productIdToClear != null) {
        _pendingPurchases.remove(productIdToClear);
        LogUtil.d(() => '[PurchaseManager] Purchase error handled, pending flag cleared for: $productIdToClear');
      }
    }

    // Do NOT finish here. PurchaseService decides finish/shouldFinish policy.
  }

  Future<void> _handleCanceled(PurchaseDetails purchaseDetails) async {
    LogUtil.d(() => '''
      Purchase canceled by user:
      - productID: ${purchaseDetails.productID}
      - purchaseID: ${purchaseDetails.purchaseID}
      - pendingCompletePurchase: ${purchaseDetails.pendingCompletePurchase}
    ''');

    // Complete the Future for purchaseProduct
    final session = _activeSession;
    if (session != null &&
        session.type == _SessionType.purchase &&
        session.completer != null &&
        !session.completer!.isCompleted) {
      // Prefer platform message when user-friendly; filter technical strings (e.g. Android "BillingResponse.userCanceled").
      final cancelMessage = _userFriendlyCancelMessage(purchaseDetails.error?.message);
      session.completer!.complete(PurchaseResult.canceled(message: cancelMessage));
      // Clear pending flag: Android may send canceled with empty productID
      final productIdToClear = purchaseDetails.productID.isNotEmpty
          ? purchaseDetails.productID
          : (session.productIds.length == 1 ? session.productIds.single : null);
      if (productIdToClear != null) {
        _pendingPurchases.remove(productIdToClear);
        LogUtil.d(() => '[PurchaseManager] Purchase canceled, pending flag cleared for: $productIdToClear');
      }
    }

    // Do NOT finish here. PurchaseService decides finish/shouldFinish policy.
  }

  /// --- Lifecycle ------------------------------------------------------------

  void dispose() {
    _subscription?.cancel();
    _subscription = null;

    _endSessionInternal(reason: 'dispose');
    _pendingPurchases.clear();
    SubscriptionProductPrices.instance.clear();

    _seenTxKeys.clear();
    _isInitialized = false;

    LogUtil.d(() => 'PurchaseManager disposed');
  }

  bool get isInitialized => _isInitialized;

  /// --- Public operations ----------------------------------------------------

  /// Purchase a product
  /// 
  /// Returns a [Future<PurchaseResult>] that completes when the purchase is processed.
  /// The Future will complete with:
  /// - [PurchaseResult.success] if purchase succeeds
  /// - [PurchaseResult.error] if purchase fails
  /// - [PurchaseResult.canceled] if user cancels
  /// 
  /// **Usage:**
  /// ```dart
  /// final result = await PurchaseManager.instance.purchaseProduct('product_id');
  /// if (result.success) {
  ///   // Handle success
  ///   print('Relay URL: ${result.verificationResult?.relayUrl}');
  /// } else {
  ///   // Handle error
  ///   print('Error: ${result.errorMessage}');
  /// }
  /// ```
  ///
  /// Clears pending purchase state for [productId] and ends the current purchase
  /// session if it matches. Call when the user leaves the checkout page without
  /// completing (e.g. Navigator.pop). Ensures re-entering the flow does not show
  /// "Purchase already in progress". On Android, dismissing the native dialog
  /// does not send any stream event, so pending state can stick without this.
  void clearPendingPurchase(String productId) {
    if (_pendingPurchases.remove(productId) != true) return;
    final session = _activeSession;
    if (session != null &&
        session.type == _SessionType.purchase &&
        session.productIds.contains(productId) &&
        session.completer != null &&
        !session.completer!.isCompleted) {
      session.completer!.complete(PurchaseResult.canceled()); // no platform message when user left page
      LogUtil.d(() => '[PurchaseManager] clearPendingPurchase: completed session with canceled for: $productId');
    }
    if (_activeSession != null && _activeSession!.productIds.contains(productId)) {
      _endSessionInternal(reason: 'clearPendingPurchase (user left checkout)');
    }
  }

  /// Query product details from the store for UI display (e.g. localized price).
  /// On Android, [productId] is logical (e.g. loc1.level1.monthly); we query by store id (loc1.level1).
  Future<ProductDetails?> getProductDetails(String productId) async {
    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) return null;
      final idToQuery =
          SubscriptionPlatform.instance.storeProductIdForQuery(productId) ??
              productId;
      final response = await _inAppPurchase.queryProductDetails({idToQuery});
      if (response.error != null || response.productDetails.isEmpty) return null;
      return response.productDetails.first;
    } catch (_) {
      return null;
    }
  }

  /// Query multiple product details at once. Returns map by product id (logical id on Android).
  Future<Map<String, ProductDetails>> getProductDetailsSet(Set<String> productIds) async {
    final result = <String, ProductDetails>{};
    if (productIds.isEmpty) return result;
    try {
      final available = await _inAppPurchase.isAvailable();
      if (!available) return result;
      final idsToQuery = productIds
          .map((id) =>
              SubscriptionPlatform.instance.storeProductIdForQuery(id) ?? id)
          .toSet();
      final response = await _inAppPurchase.queryProductDetails(idsToQuery);
      if (response.error != null) return result;
      final byStoreId = <String, ProductDetails>{};
      for (final d in response.productDetails) {
        byStoreId[d.id] = d;
      }
      for (final logicalId in productIds) {
        final storeId =
            SubscriptionPlatform.instance.storeProductIdForQuery(logicalId) ??
                logicalId;
        final d = byStoreId[storeId];
        if (d != null) result[logicalId] = d;
      }
      return result;
    } catch (_) {
      return result;
    }
  }

  /// Localized price string for UI (e.g. "\$5.99" or "¥38"). Returns null if unavailable.
  Future<String?> getProductPrice(String productId) async {
    final d = await getProductDetails(productId);
    return d?.price;
  }

  /// Localized price strings for UI. Returns map productId -> price string.
  Future<Map<String, String>> getProductPrices(Set<String> productIds) async {
    final details = await getProductDetailsSet(productIds);
    return details.map((id, d) => MapEntry(id, d.price));
  }

  Future<PurchaseResult> purchaseProduct(String productId) async {
    LogUtil.d(() => '[PurchaseManager] Starting purchase for product: $productId');

    if (_pendingPurchases[productId] == true) {
      LogUtil.w(() => '[PurchaseManager] Purchase already in progress for product: $productId');
      return PurchaseResult.error('Purchase already in progress. Please wait...');
    }

    _pendingPurchases[productId] = true;
    
    // Create completer to return result
    final completer = Completer<PurchaseResult>();
    
    // Helper to complete and clear pending flag
    void completeAndClear(PurchaseResult result) {
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      // Clear pending flag immediately when completer is completed
      _pendingPurchases[productId] = false;
      LogUtil.d(() => '[PurchaseManager] Purchase completed and pending flag cleared for: $productId');
    }
    
    try {
      // Create purchase session BEFORE initiating purchase.
      _beginPurchaseSession(
        productId: productId,
        completer: completer,
      );

      final bool isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        completeAndClear(PurchaseResult.error('Store not available'));
        return completer.future;
      }

      // On Android, query by store product id (e.g. loc1.level1) not logical id (loc1.level1.monthly).
      final productIdToQuery =
          SubscriptionPlatform.instance.storeProductIdForQuery(productId) ??
              productId;
      final ProductDetailsResponse productDetailResponse =
          await _inAppPurchase.queryProductDetails({productIdToQuery});

      if (productDetailResponse.error != null) {
        completeAndClear(PurchaseResult.error(
          'Failed to query product details. Please try again.',
        ));
        return completer.future;
      }

      if (productDetailResponse.productDetails.isEmpty) {
        completeAndClear(PurchaseResult.error(
          'Product not found. Please check if the product is configured correctly.',
        ));
        return completer.future;
      }

      // On Android with product+plan, store returns 2 details per product (same id); pick the one
      // matching the requested base plan so confirmation dialog shows correct price/description.
      final ProductDetails productDetails = _productDetailsForPurchase(
        productDetailResponse.productDetails,
        productId,
      );

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: productDetails,
      );

      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (!success) {
        completeAndClear(PurchaseResult.error('Failed to initiate purchase. Please try again.'));
        return completer.future;
      }

      // If no stream event arrives (e.g. on Android, plugin may not forward USER_CANCELED
      // when user dismisses the dialog), the caller can clear state by leaving the
      // checkout page (dispose → clearPendingPurchase). We only use a long timeout
      // here to avoid the Future hanging forever on real hangs.
      Future.delayed(const Duration(minutes: 5), () {
        if (!completer.isCompleted) {
          completeAndClear(PurchaseResult.error('Purchase timeout. Please try again.'));
          _endSessionInternal(reason: 'purchase timeout');
        }
      });

      return completer.future;
    } catch (e, stack) {
      LogUtil.e(() => '''
        [PurchaseManager] Error in purchaseProduct:
        - productId: $productId
        - error: $e
        - stack: $stack
      ''');

      var message = 'Failed to initiate purchase. Please try again.';
      if (e is PlatformException) {
        message = e.message ?? message;
      }
      completeAndClear(PurchaseResult.error(message));
      return completer.future;
    }
  }

  /// Delay after platform restore to allow all [PurchaseStatus.restored] events to arrive.
  /// StoreKit can deliver events late (e.g. after user returns from Apple subscription UI),
  /// so we wait a bit before treating "no event" as "no purchase to restore".
  static const Duration _restoreSettlingDuration = Duration(seconds: 8);

  Future<List<PurchaseResult>> restorePurchases({
    Set<String>? productIds,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    LogUtil.d(() => '[PurchaseManager] restorePurchases() called');

    // If caller doesn't specify products, use all configured subscription productIds.
    productIds ??= SubscriptionRegistry.instance.allProductIds;
    if (productIds.isEmpty) return [];

    // One completer per productId we care about.
    final restoreCompleters = <String, Completer<PurchaseResult>>{};
    for (final productId in productIds) {
      restoreCompleters[productId] = Completer<PurchaseResult>();
    }

    // idleTimeout must be longer than our settling period, otherwise the session
    // would auto-end and completeError remaining completers before we mark them
    // as "no purchase to restore".
    final settling =
        timeout > _restoreSettlingDuration ? _restoreSettlingDuration : timeout;
    final idleTimeout = settling + const Duration(seconds: 2);

    _beginRestoreSession(
      restoreCompleters: restoreCompleters,
      idleTimeout: idleTimeout,
    );

    await _inAppPurchase.restorePurchases();

    // Wait for restored events to arrive. StoreKit only emits for products the user owns;
    // the rest never complete, so we must not wait for all completers.
    await Future.delayed(settling);

    // Complete any product that did not get a restored event (no purchase to restore)
    const noRestoreMessage = 'No purchase to restore for this product';
    for (final entry in restoreCompleters.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(PurchaseResult.error(noRestoreMessage));
        LogUtil.d(() => '[PurchaseManager] No restored event for product: ${entry.key}');
      }
    }

    final futures = restoreCompleters.values.map((c) => c.future).toList();
    List<PurchaseResult> results;
    try {
      results = await Future.wait(futures, eagerError: false)
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      results = [];
      for (final c in restoreCompleters.values) {
        try {
          results.add(await c.future);
        } catch (_) {
          results.add(PurchaseResult.error(e.toString()));
        }
      }
    } finally {
      _endSessionInternal(reason: 'restore completed');
    }

    return results;
  }

  /// --- Dedupe helpers -------------------------------------------------------

  String _buildTxKey(PurchaseDetails p) {
    // Prefer your idempotency manager output (often originalTransactionId / transactionId / purchaseID)
    final t = PurchaseIdempotencyManager.getTransactionId(p);
    if (t.isNotEmpty) return 'tx:$t:${p.productID}';

    final pid = p.purchaseID ?? '';
    if (pid.isNotEmpty) return 'pid:$pid:${p.productID}';

    final raw = p.verificationData.serverVerificationData;
    if (raw.isNotEmpty) return 'rcpt:${raw.hashCode}:${p.productID}';

    return 'fallback:${p.transactionDate ?? ''}:${p.productID}';
  }

  /// Returns true if first time seen in retention window (good for verbose log),
  /// false if duplicated.
  bool _markSeen(String txKey) {
    final now = DateTime.now();
    final last = _seenTxKeys[txKey];
    _seenTxKeys[txKey] = now;
    if (last == null) return true;
    return now.difference(last) > const Duration(seconds: 3);
  }

  void _evictSeenKeys() {
    final now = DateTime.now();
    final keys = _seenTxKeys.keys.toList(growable: false);
    for (final k in keys) {
      final t = _seenTxKeys[k];
      if (t == null) continue;
      if (now.difference(t) > _seenRetention) {
        _seenTxKeys.remove(k);
      }
    }
  }
}