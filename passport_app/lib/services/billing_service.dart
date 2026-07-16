import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One-time, non-consumable unlock via StoreKit / Play Billing only — never an
/// external payment (store compliance spec item 1). Exposes a Restore path
/// (required). The SKU must be created in both consoles before this returns
/// real products; until then `available` is false and the UI falls back to the
/// rewarded-video unlock.
class BillingService {
  static final BillingService instance = BillingService._();
  BillingService._();

  static const unlockProductId = 'unlock_all';
  static const _prefsKey = 'unlocked_v1';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  ProductDetails? _product;
  bool _available = false;
  bool _unlocked = false;

  bool get available => _available && _product != null;
  bool get unlocked => _unlocked;

  /// Human-readable price, or a sensible default before the SKU exists.
  String get price => _product?.price ?? r'$5.99';

  /// [onUnlockChanged] fires whenever entitlement changes (purchase/restore).
  Future<void> init(void Function(bool unlocked) onUnlockChanged) async {
    final prefs = await SharedPreferences.getInstance();
    _unlocked = prefs.getBool(_prefsKey) ?? false;
    onUnlockChanged(_unlocked);

    try {
      _available = await _iap.isAvailable();
      if (_available) {
        final resp =
            await _iap.queryProductDetails({unlockProductId});
        if (resp.productDetails.isNotEmpty) {
          _product = resp.productDetails.first;
        }
        _sub = _iap.purchaseStream.listen(
          (purchases) => _onPurchases(purchases, onUnlockChanged, prefs),
          onError: (e) => debugPrint('purchaseStream error: $e'),
        );
      }
    } catch (e) {
      debugPrint('Billing init failed (non-fatal): $e');
      _available = false;
    }
  }

  Future<void> _onPurchases(
    List<PurchaseDetails> purchases,
    void Function(bool) onUnlockChanged,
    SharedPreferences prefs,
  ) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        _unlocked = true;
        await prefs.setBool(_prefsKey, true);
        onUnlockChanged(true);
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  /// Kick off the store purchase sheet. Returns false if unavailable (caller
  /// should route the user to the rewarded-video unlock instead).
  Future<bool> buy() async {
    if (!available) return false;
    final param = PurchaseParam(productDetails: _product!);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Required Restore Purchases path.
  Future<void> restore() async {
    if (!_available) return;
    await _iap.restorePurchases();
  }

  void dispose() => _sub?.cancel();
}
