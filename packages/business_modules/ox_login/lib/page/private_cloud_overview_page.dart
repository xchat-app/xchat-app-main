import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/purchase/purchase_manager.dart';
import 'package:ox_common/purchase/subscription_product_prices.dart';
import 'package:ox_login/utils/circle_entry_helper.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'circle_name_page.dart';
import 'private_circle_learn_more_page.dart';

class PrivateCloudOverviewPage extends StatefulWidget {
  const PrivateCloudOverviewPage({super.key, this.groupId});

  final String? groupId;

  @override
  State<PrivateCloudOverviewPage> createState() => _PrivateCloudOverviewPageState();
}

class _PrivateCloudOverviewPageState extends State<PrivateCloudOverviewPage> {
  @override
  void initState() {
    super.initState();
    PurchaseManager.instance.refreshAllPrices();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_login.overview'),
      ),
      body: _buildBody(context),
      bottomWidget: _buildConfigureButton(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: CLLayout.horizontalPadding,
        right: CLLayout.horizontalPadding,
        top: 24.px,
        bottom: 100.px,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeader(context),
          SizedBox(height: 48.px),
          _buildFeaturesList(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 80.px,
          height: 80.px,
          decoration: BoxDecoration(
            color: ColorToken.xChat.of(context),
            borderRadius: BorderRadius.circular(16.px),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: 8.px),
            child: Icon(
              Icons.diamond_rounded,
              color: Colors.white,
              size: 48.px,
            ),
          ),
        ),
        SizedBox(height: 24.px),
        CLText.titleLarge(
          Localized.text('ox_login.private_cloud'),
          colorToken: ColorToken.onSurface,
          isBold: true,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 12.px),
        CLText.bodyMedium(
          Localized.text('ox_login.private_cloud_overview_desc_1'),
          colorToken: ColorToken.onSurfaceVariant,
          textAlign: TextAlign.center,
          maxLines: null,
        ),
        ValueListenableBuilder<String?>(
          valueListenable: SubscriptionProductPrices.instance.lowestPriceNotifier,
          builder: (_, lowestPrice, __) {
            if (lowestPrice == null || lowestPrice.isEmpty) return const SizedBox.shrink();
            final part2 = Localized.text('ox_login.private_cloud_overview_desc_2').replaceAll('{price}', lowestPrice);
            return Padding(
              padding: EdgeInsets.only(top: 4.px),
              child: CLText.bodyMedium(
                part2,
                colorToken: ColorToken.onSurfaceVariant,
                textAlign: TextAlign.center,
                maxLines: null,
              ),
            );
          },
        ),
        SizedBox(height: 16.px),
        GestureDetector(
          onTap: () => _showLearnMoreDialog(context),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CLText.bodyMedium(
                Localized.text('ox_login.private_circle_learn_more'),
                colorToken: ColorToken.xChat,
              ),
              SizedBox(width: 4.px),
              Icon(
                Icons.arrow_forward,
                size: 16.px,
                color: ColorToken.xChat.of(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturesList() {
    final features = [
      _FeatureItem(
        icon: Icons.dns,
        title: Localized.text('ox_login.feature_private_relay'),
        description: Localized.text('ox_login.feature_private_relay_desc'),
        backgroundColor: const Color(0xFFE5E0FF), // Light purple
        iconColor: const Color(0xFF6B5CE6), // Dark purple
      ),
      _FeatureItem(
        icon: Icons.storage,
        title: Localized.text('ox_login.feature_media_file_server'),
        description: Localized.text('ox_login.feature_media_file_server_desc'),
        backgroundColor: const Color(0xFFE0F0FF), // Light blue
        iconColor: const Color(0xFF2196F3), // Dark blue
      ),
      _FeatureItem(
        icon: Icons.delete_outline,
        title: Localized.text('ox_login.feature_total_sovereignty'),
        description: Localized.text('ox_login.feature_total_sovereignty_desc'),
        backgroundColor: const Color(0xFFFFE5F1), // Light pink
        iconColor: const Color(0xFFE53935), // Red
      ),
    ];

    return Column(
      children: features.map((feature) => Padding(
        padding: EdgeInsets.only(bottom: 24.px),
        child: _buildFeatureItem(feature),
      )).toList(),
    );
  }

  Widget _buildFeatureItem(_FeatureItem feature) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48.px,
          height: 48.px,
          decoration: BoxDecoration(
            color: feature.backgroundColor,
            borderRadius: BorderRadius.circular(12.px),
          ),
          alignment: Alignment.center,
          child: Icon(
            feature.icon,
            color: feature.iconColor,
            size: 24.px,
          ),
        ),
        SizedBox(width: 16.px),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CLText.titleMedium(
                feature.title,
                colorToken: ColorToken.onSurface,
                isBold: true,
              ),
              SizedBox(height: 4.px),
              CLText.bodySmall(
                feature.description,
                colorToken: ColorToken.onSurfaceVariant,
                maxLines: null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfigureButton(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 16.px,
      ),
      child: CLButton.filled(
        text: Localized.text('ox_login.configure_plan'),
        onTap: () => _onConfigurePlan(context),
        expanded: true,
        height: 50.px,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CLText.titleMedium(
              Localized.text('ox_login.configure_plan'),
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
    );
  }

  Future<void> _onConfigurePlan(BuildContext context) async {
    final groupId = widget.groupId ?? await CircleEntryHelper.getCurrentInactiveGroupId();
    if (!context.mounted) return;
    if (groupId == null || groupId.isEmpty) {
      CommonToast.instance.show(
        context,
        Localized.text('ox_login.subscription_limit_reached'),
      );
      return;
    }
    OXNavigator.pushPage(
      context,
      (context) => CircleNamePage(groupId: groupId),
    );
  }

  void _showLearnMoreDialog(BuildContext context) {
    OXNavigator.pushPage(
      context,
      (context) => const PrivateCircleLearnMorePage(),
      type: OXPushPageType.present,
    );
  }
}

class _FeatureItem {
  final IconData icon;
  final String title;
  final String description;
  final Color backgroundColor;
  final Color iconColor;

  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.backgroundColor,
    required this.iconColor,
  });
}

