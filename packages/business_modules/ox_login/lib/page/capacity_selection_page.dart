import 'package:flutter/material.dart';
import 'package:ox_chat/page/session/find_people_page.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/purchase/purchase_manager.dart';
import 'package:ox_common/purchase/subscription_period.dart';
import 'package:ox_common/purchase/subscription_product_prices.dart';
import 'package:ox_common/purchase/subscription_registry.dart';
import 'package:ox_common/purchase/subscription_tier.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

import '../component/onboarding_step_bar.dart';
import '../controller/onboarding_controller.dart';
import 'subscribe_page.dart';

/// How many people the circle is for. Each size shows its monthly price, so
/// the choice is made knowing what it costs rather than on the next page.
class CapacitySelectionPage extends StatefulWidget {
  const CapacitySelectionPage({
    super.key,
    required this.subscriptionGroupId,
    required this.circleName,
    this.controller,
  });

  final String subscriptionGroupId;

  /// Chosen on the previous page; applied to the circle once it is bought.
  final String circleName;

  /// Set for a new account; see [CircleNamePage.controller].
  final OnboardingController? controller;

  @override
  State<CapacitySelectionPage> createState() => _CapacitySelectionPageState();
}

class _CapacitySelectionPageState extends State<CapacitySelectionPage> {
  SubscriptionTier? _selectedTier;

  late List<SubscriptionTier> _tiers;

  @override
  void initState() {
    super.initState();
    PurchaseManager.instance.refreshAllPrices();
    _tiers = SubscriptionRegistry.instance.tiersForGroup(widget.subscriptionGroupId);
    _selectedTier = _tiers.isEmpty
        ? null
        : (_tiers.length > 1 ? _tiers[1] : _tiers[0]);
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
            current: OnboardingStep.members,
            includesProfile: widget.controller != null,
          ),
          SizedBox(height: 28.px),
          CLText.titleLarge(
            Localized.text('ox_login.capacity_selection_title'),
            colorToken: ColorToken.onSurface,
            isBold: true,
          ),
          SizedBox(height: 8.px),
          CLText.bodyMedium(
            Localized.text('ox_login.capacity_selection_desc'),
            colorToken: ColorToken.onSurfaceVariant,
            maxLines: null,
          ),
          SizedBox(height: 28.px),
          _buildCapacityOptions(),
        ],
      ),
    );
  }

  static Color _colorForTier(SubscriptionTier t) {
    switch (t.id) {
      case SubscriptionTierIds.lovers:
        return const Color(0xFFFFE5F1);
      case SubscriptionTierIds.family:
        return const Color(0xFFE5F0FF);
      case SubscriptionTierIds.community:
        return const Color(0xFFF0E5FF);
      default:
        return const Color(0xFFE5E5E5);
    }
  }

  Widget _buildCapacityOptions() {
    return Column(
      children: [
        for (int i = 0; i < _tiers.length; i++) ...[
          if (i > 0) SizedBox(height: 14.px),
          _buildCapacityOption(
            tier: _tiers[i],
            isPopular: _tiers[i].id == SubscriptionTierIds.family,
          ),
        ],
      ],
    );
  }

  Widget _buildCapacityOption({
    required SubscriptionTier tier,
    bool isPopular = false,
  }) {
    final isSelected = _selectedTier?.id == tier.id;
    String title;
    String desc;
    switch (tier.id) {
      case SubscriptionTierIds.lovers:
        title = Localized.text('ox_login.capacity_2_members');
        desc = Localized.text('ox_login.capacity_2_members_desc');
        break;
      case SubscriptionTierIds.family:
        title = Localized.text('ox_login.capacity_6_members');
        desc = Localized.text('ox_login.capacity_6_members_desc');
        break;
      case SubscriptionTierIds.community:
        title = Localized.text('ox_login.capacity_50_members');
        desc = Localized.text('ox_login.capacity_50_members_desc');
        break;
      default:
        title = '';
        desc = '';
    }
    final monthlyPrice = SubscriptionProductPrices.instance.getNotifier(
      SubscriptionRegistry.instance.productIdFor(
        widget.subscriptionGroupId,
        tier.id,
        SubscriptionPeriod.monthly,
      ),
    );

    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: () => setState(() => _selectedTier = tier),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 18.px, vertical: 18.px),
            decoration: BoxDecoration(
              color: ColorToken.cardContainer.of(context),
              borderRadius: BorderRadius.circular(24.px),
              border: Border.all(
                color: isSelected
                    ? ColorToken.xChat.of(context)
                    : ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.2),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44.px,
                  height: 44.px,
                  decoration: BoxDecoration(
                    color: _colorForTier(tier),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.people_rounded,
                    color: ColorToken.xChat.of(context),
                    size: 24.px,
                  ),
                ),
                SizedBox(width: 14.px),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CLText.titleMedium(
                        title,
                        colorToken: ColorToken.onSurface,
                        isBold: true,
                      ),
                      SizedBox(height: 4.px),
                      CLText.bodySmall(
                        desc,
                        colorToken: ColorToken.onSurfaceVariant,
                        maxLines: null,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.px),
                ValueListenableBuilder<String?>(
                  valueListenable: monthlyPrice,
                  builder: (_, price, __) {
                    if (price == null) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CLText.titleMedium(
                          price,
                          colorToken: ColorToken.onSurface,
                          isBold: true,
                        ),
                        CLText.labelSmall(
                          Localized.text('ox_login.per_month'),
                          colorToken: ColorToken.onSurfaceVariant,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        if (isPopular)
          Positioned(
            top: -10.px,
            right: 18.px,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 8.px, vertical: 2.px),
              decoration: BoxDecoration(
                color: ColorToken.xChat.of(context),
                borderRadius: BorderRadius.circular(6.px),
              ),
              child: CLText.labelSmall(
                Localized.text('ox_login.most_popular'),
                customColor: Colors.white,
                isBold: true,
              ),
            ),
          ),
      ],
    );
  }

  /// The way in for someone who was invited: they join a circle somebody
  /// else pays for, so they must not be stopped at the price.
  Widget _buildInviteLink() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => OXNavigator.pushPage(
        context,
        (context) => const FindPeoplePage(joinCircleMode: true),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 12.px),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_rounded, size: 18.px, color: ColorToken.xChat.of(context)),
            SizedBox(width: 6.px),
            CLText.bodyMedium(
              Localized.text('ox_login.have_invite_join_circle'),
              colorToken: ColorToken.xChat,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottom() {
    return Padding(
      padding: EdgeInsets.only(bottom: 16.px),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInviteLink(),
          SizedBox(height: 4.px),
          CLButton.filled(
            onTap: _selectedTier != null ? _onContinue : null,
            expanded: true,
            height: 50.px,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CLText.titleMedium(
                  Localized.text('ox_login.connect'),
                  customColor: Colors.white,
                ),
                SizedBox(width: 8.px),
                Icon(
                  Icons.arrow_forward,
                  color: Colors.white,
                  size: 20.px,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onContinue() {
    if (_selectedTier == null) return;
    OXNavigator.pushPage(
      context,
      (context) => SubscribePage(
        subscriptionGroupId: widget.subscriptionGroupId,
        selectedTier: _selectedTier!,
        circleName: widget.circleName,
        controller: widget.controller,
      ),
    );
  }
}
