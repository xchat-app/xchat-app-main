import 'dart:io';

import 'package:chatcore/chat-core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_common/login/circle_service.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/purchase/purchase_manager.dart';
import 'package:ox_common/purchase/subscription_period.dart';
import 'package:ox_common/purchase/subscription_product_prices.dart';
import 'package:ox_common/purchase/subscription_registry.dart';
import 'package:ox_common/purchase/subscription_tier.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_module_service/ox_module_service.dart';

import '../component/onboarding_step_bar.dart';
import '../controller/onboarding_controller.dart';
import 'circle_activated_page.dart';
import 'circle_name_page.dart';

/// Last step of buying a circle: how often to pay, what it includes, and the
/// purchase itself. One page where there used to be two (billing period, then
/// an order review), with the price on the button that charges it.
class SubscribePage extends StatefulWidget {
  const SubscribePage({
    super.key,
    required this.subscriptionGroupId,
    required this.selectedTier,
    required this.circleName,
    this.controller,
  });

  final String subscriptionGroupId;
  final SubscriptionTier selectedTier;
  final String circleName;

  /// Set for a new account; see [CircleNamePage.controller].
  final OnboardingController? controller;

  @override
  State<SubscribePage> createState() => _SubscribePageState();
}

class _SubscribePageState extends State<SubscribePage> {
  SubscriptionPeriod _selectedPeriod = SubscriptionPeriod.yearly;
  bool _isProcessing = false;

  String _productIdFor(SubscriptionPeriod period) => SubscriptionRegistry.instance.productIdFor(
        widget.subscriptionGroupId,
        widget.selectedTier.id,
        period,
      );

  late final String _yearlyProductId = _productIdFor(SubscriptionPeriod.yearly);
  late final String _monthlyProductId = _productIdFor(SubscriptionPeriod.monthly);

  late final ValueNotifier<String?> _yearlyPrice =
      SubscriptionProductPrices.instance.getNotifier(_yearlyProductId);
  late final ValueNotifier<String?> _monthlyPrice =
      SubscriptionProductPrices.instance.getNotifier(_monthlyProductId);

  /// Yearly savings against twelve monthly payments, or null until both
  /// prices are known.
  int? get _yearlySavingsPercent {
    final monthly = SubscriptionProductPrices.instance.getRawPrice(_monthlyProductId);
    final yearly = SubscriptionProductPrices.instance.getRawPrice(_yearlyProductId);
    if (monthly == null || yearly == null || monthly <= 0) return null;
    final twelveMonthly = 12 * monthly;
    return ((twelveMonthly - yearly) / twelveMonthly * 100).clamp(0.0, 100.0).round();
  }

  @override
  void initState() {
    super.initState();
    PurchaseManager.instance.refreshAllPrices();
  }

  @override
  void dispose() {
    // Dismissing Play's purchase sheet sends no event, so a pending purchase
    // would otherwise stick and the next attempt report "already in progress".
    PurchaseManager.instance.clearPendingPurchase(_yearlyProductId);
    PurchaseManager.instance.clearPendingPurchase(_monthlyProductId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(),
      body: _buildBody(),
      bottomWidget: _buildBottom(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: CLLayout.horizontalPadding,
        right: CLLayout.horizontalPadding,
        top: 24.px,
        bottom: 24.px,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OnboardingStepBar(
            current: OnboardingStep.subscribe,
            includesProfile: widget.controller != null,
          ),
          SizedBox(height: 28.px),
          CLText.titleLarge(
            Localized.text('ox_login.start_your_circle'),
            colorToken: ColorToken.onSurface,
            isBold: true,
          ),
          SizedBox(height: 18.px),
          _buildCircleSummary(),
          SizedBox(height: 16.px),
          _buildPlans(),
          SizedBox(height: 24.px),
          _buildIncluded(),
        ],
      ),
    );
  }

  Widget _buildCircleSummary() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.px, 14.px, 8.px, 14.px),
      decoration: BoxDecoration(
        color: ColorToken.cardContainer.of(context),
        borderRadius: BorderRadius.circular(20.px),
      ),
      child: Row(
        children: [
          CircleNameAvatar(name: widget.circleName, size: 44.px),
          SizedBox(width: 14.px),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLText.titleMedium(
                  widget.circleName,
                  colorToken: ColorToken.onSurface,
                  isBold: true,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.px),
                CLText.bodySmall(
                  Localized.text('ox_login.up_to_members')
                      .replaceAll('{count}', '${widget.selectedTier.maxUsers}'),
                  colorToken: ColorToken.onSurfaceVariant,
                ),
              ],
            ),
          ),
          CLButton.text(
            text: Localized.text('ox_login.change'),
            color: ColorToken.xChat.of(context),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlans() {
    return ListenableBuilder(
      listenable: Listenable.merge([_yearlyPrice, _monthlyPrice]),
      builder: (_, __) {
        final percent = _yearlySavingsPercent;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _buildPlan(
                period: SubscriptionPeriod.yearly,
                label: Localized.text('ox_login.yearly'),
                price: _yearlyPrice.value,
                note: Localized.text('ox_login.billed_every_12_months'),
                tag: percent != null
                    ? Localized.text('ox_login.save_percent').replaceAll('{percent}', '$percent')
                    : Localized.text('ox_login.save_label'),
              ),
            ),
            SizedBox(width: 12.px),
            Expanded(
              child: _buildPlan(
                period: SubscriptionPeriod.monthly,
                label: Localized.text('ox_login.monthly'),
                price: _monthlyPrice.value,
                note: Localized.text('ox_login.billed_every_month'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlan({
    required SubscriptionPeriod period,
    required String label,
    required String? price,
    required String note,
    String? tag,
  }) {
    final isSelected = _selectedPeriod == period;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => setState(() => _selectedPeriod = period),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16.px, 18.px, 16.px, 14.px),
            decoration: BoxDecoration(
              color: ColorToken.cardContainer.of(context),
              borderRadius: BorderRadius.circular(20.px),
              border: Border.all(
                color: isSelected
                    ? ColorToken.xChat.of(context)
                    : ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLText.bodyMedium(label, colorToken: ColorToken.onSurfaceVariant),
                SizedBox(height: 4.px),
                SizedBox(
                  height: 30.px,
                  child: price == null
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 20.px,
                            height: 20.px,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ColorToken.xChat.of(context),
                            ),
                          ),
                        )
                      : CLText.titleLarge(
                          price,
                          colorToken: ColorToken.onSurface,
                          isBold: true,
                          maxLines: 1,
                        ),
                ),
                SizedBox(height: 4.px),
                CLText.bodySmall(note, colorToken: ColorToken.onSurfaceVariant, maxLines: null),
              ],
            ),
          ),
        ),
        if (tag != null)
          Positioned(
            top: -10.px,
            right: 12.px,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.px, vertical: 2.px),
              decoration: BoxDecoration(
                color: const Color(0xFF1B7F3B),
                borderRadius: BorderRadius.circular(6.px),
              ),
              child: CLText.labelSmall(tag, customColor: Colors.white, isBold: true),
            ),
          ),
      ],
    );
  }

  Widget _buildIncluded() {
    final items = [
      Localized.text('ox_login.included_relay'),
      Localized.text('ox_login.included_media'),
      Localized.text('ox_login.included_calls'),
      Localized.text('ox_login.included_wipe'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CLText.labelMedium(
          Localized.text('ox_login.included').toUpperCase(),
          colorToken: ColorToken.onSurfaceVariant,
          isBold: true,
        ),
        SizedBox(height: 12.px),
        for (final item in items)
          Padding(
            padding: EdgeInsets.only(bottom: 10.px),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_rounded, size: 20.px, color: ColorToken.xChat.of(context)),
                SizedBox(width: 12.px),
                Expanded(
                  child: CLText.bodyMedium(item, colorToken: ColorToken.onSurface, maxLines: null),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: EdgeInsets.only(top: 8.px, bottom: 8.px),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CLText.bodySmall(
            Platform.isIOS
                ? Localized.text('ox_login.private_circle_pricing_disclaimer')
                : Localized.text('ox_login.private_circle_pricing_disclaimer_android'),
            colorToken: ColorToken.onSurfaceVariant,
            textAlign: TextAlign.center,
            maxLines: null,
          ),
          SizedBox(height: 4.px),
          _buildTermsLinks(),
          SizedBox(height: 12.px),
          ValueListenableBuilder<String?>(
            valueListenable:
                _selectedPeriod == SubscriptionPeriod.yearly ? _yearlyPrice : _monthlyPrice,
            builder: (_, price, __) {
              final per = _selectedPeriod == SubscriptionPeriod.yearly
                  ? Localized.text('ox_login.per_year')
                  : Localized.text('ox_login.per_month');
              final subscribe = Localized.text('ox_login.subscribe');
              return CLButton.filled(
                text: _isProcessing
                    ? Localized.text('ox_usercenter.processing')
                    : (price == null ? subscribe : '$subscribe · $price$per'),
                onTap: _isProcessing ? null : _handlePay,
                expanded: true,
                height: 50.px,
              );
            },
          ),
          CLButton.text(
            text: Localized.text('ox_usercenter.restore_purchases'),
            color: ColorToken.xChat.of(context),
            expanded: true,
            onTap: _isProcessing ? null : _restorePurchases,
          ),
        ],
      ),
    );
  }

  /// Privacy Policy and Terms of Use, which store review requires next to a
  /// subscription. The sentence is a template so each language orders it.
  Widget _buildTermsLinks() {
    final linkColor = ColorToken.xChat.of(context);
    final mutedColor = ColorToken.onSurfaceVariant.of(context);
    final template = Localized.text('ox_login.checkout_agree_terms');
    final links = [
      _TermsLink('{privacy_policy}', Localized.text('ox_login.privacy_policy'), _openPrivacyPolicy),
      _TermsLink('{terms_of_service}', Localized.text('ox_login.terms_of_service'), _openTermsOfService),
    ]..sort((a, b) => template.indexOf(a.placeholder).compareTo(template.indexOf(b.placeholder)));

    final spans = <InlineSpan>[];
    var start = 0;
    for (final link in links) {
      final at = template.indexOf(link.placeholder, start);
      if (at == -1) continue;
      spans.add(TextSpan(text: template.substring(start, at)));
      spans.add(TextSpan(
        text: link.label,
        style: TextStyle(color: linkColor, decoration: TextDecoration.underline),
        recognizer: TapGestureRecognizer()..onTap = link.onTap,
      ));
      start = at + link.placeholder.length;
    }
    spans.add(TextSpan(text: template.substring(start)));

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(style: TextStyle(color: mutedColor, fontSize: 12.px), children: spans),
    );
  }

  void _openPrivacyPolicy() => _openWeb('https://0xchat.com/protocols/xchat-privacy-policy.html');

  void _openTermsOfService() => _openWeb('https://0xchat.com/protocols/xchat-terms-of-use.html');

  void _openWeb(String url) {
    OXModuleService.invoke('ox_common', 'gotoWebView', [context, url, null, null, null, null]);
  }

  Future<void> _handlePay() async {
    final productId = _productIdFor(_selectedPeriod);
    setState(() => _isProcessing = true);

    try {
      final result = await PurchaseManager.instance.purchaseProduct(productId);
      if (!mounted) return;

      if (result.success) {
        OXLoading.show();
        await _applyCircleName();
        await _waitForProfile();
        await OXLoading.dismiss();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        OXNavigator.pushPage(
          context,
          (context) => CircleActivatedPage(maxUsers: widget.selectedTier.maxUsers),
        );
        return;
      }

      setState(() => _isProcessing = false);
      final String message;
      if (result.isCanceled) {
        message = result.errorMessage ?? Localized.text('ox_login.purchase_canceled');
      } else if (result.isAlreadyRestored) {
        message = Localized.text('ox_login.already_purchased');
      } else if (result.isSubscriptionExpired) {
        message = result.errorMessage ?? 'Subscription has expired. Please tap again to renew.';
      } else {
        message = result.errorMessage ?? 'Purchase failed. Please try again.';
      }
      CommonToast.instance.show(context, message);
    } catch (e, stack) {
      LogUtil.e(() => '[SubscribePage] purchase of "$productId" failed: $e\n$stack');
      await OXLoading.dismiss();
      if (!mounted) return;
      setState(() => _isProcessing = false);
      CommonToast.instance.show(context, 'Failed to initiate purchase. Please try again.');
    }
  }

  /// The purchase joins the new circle under a name made from its relay
  /// address. Give it the one chosen at the start. If that fails the default
  /// stays, and it can still be renamed in the circle's settings.
  Future<void> _applyCircleName() async {
    final circle = LoginManager.instance.currentCircle;
    final name = widget.circleName;
    if (circle == null || circle.name == name) return;
    try {
      if (CircleApi.isPaidRelay(circle.relayUrl)) {
        await CircleMemberService.sharedInstance.updateTenant(name: name);
      }
      await CircleService.updateCircleName(circle.id, name);
    } catch (e) {
      LogUtil.e(() => '[SubscribePage] naming the new circle "$name" failed: $e');
    }
  }

  /// A new account's name goes out once its first circle connects
  /// ([OnboardingController.profilePublished]). Leaving before then would
  /// drop the controller with it, and the account would join as an npub.
  Future<void> _waitForProfile() async {
    final controller = widget.controller;
    if (controller == null) return;
    try {
      await controller.profilePublished.timeout(const Duration(seconds: 30));
    } catch (e) {
      LogUtil.e(() => '[SubscribePage] publishing the new account\'s profile failed: $e');
    }
  }

  Future<void> _restorePurchases() async {
    OXLoading.show(status: Localized.text('ox_usercenter.restoring_purchases'));
    try {
      final results = await PurchaseManager.instance.restorePurchases();
      await OXLoading.dismiss();
      if (!mounted) return;

      if (results.any((r) => r.success)) {
        CommonToast.instance.show(context, Localized.text('ox_usercenter.restore_purchases_success'));
        OXNavigator.popToRoot(context);
        return;
      }
      String? failure;
      for (final r in results) {
        final message = (r.errorMessage ?? '').trim();
        if (message.isNotEmpty && message != 'No purchase to restore for this product') {
          failure = message;
          break;
        }
      }
      CommonToast.instance.show(
        context,
        results.any((r) => r.isAlreadyRestored)
            ? Localized.text('ox_usercenter.restore_purchases_already_restored')
            : failure ?? Localized.text('ox_login.no_purchases_to_restore'),
      );
    } catch (e) {
      await OXLoading.dismiss();
      if (!mounted) return;
      CommonToast.instance.show(context, 'Failed to restore purchases: $e');
    }
  }
}

class _TermsLink {
  _TermsLink(this.placeholder, this.label, this.onTap);

  final String placeholder;
  final String label;
  final VoidCallback onTap;
}
