import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/page/circle_introduction_page.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/circle_join_utils.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_chat/page/session/find_people_page.dart';
import '../controller/onboarding_controller.dart';
import 'nostr_relay_introduction_page.dart';
import '../utils/circle_entry_helper.dart';
import 'circle_restore_page.dart';
import 'private_cloud_overview_page.dart';

enum CircleType { invite, public, private, custom }

class CircleSelectionPage extends StatefulWidget {
  const CircleSelectionPage({
    super.key,
    this.controller,
  });

  final OnboardingController? controller;

  @override
  State<CircleSelectionPage> createState() => _CircleSelectionPageState();
}

class _CircleSelectionPageState extends State<CircleSelectionPage> {
  bool _isProcessing = false;
  CircleType? _selectedCircleType;

  OnboardingController? get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(),
      body: _buildBody(),
      bottomWidget: _buildConnectButton(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: CLLayout.horizontalPadding,
        right: CLLayout.horizontalPadding,
        top: 24.px,
        bottom: 100.px, // Add bottom padding to avoid button overlap
      ),
      child: Column(
        children: [
          _buildHeader(),
          SizedBox(height: 32.px),
          _buildCircleOptions(),
          SizedBox(height: 24.px),
          _buildRestorePrivateRelaySection(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        CLText.titleLarge(
          Localized.text('ox_login.add_circle_title'),
          colorToken: ColorToken.onSurface,
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 12.px),
        CLText.bodyMedium(
          Localized.text('ox_login.join_circle_subtitle'),
          colorToken: ColorToken.onSurfaceVariant,
          textAlign: TextAlign.center,
          maxLines: null,
        ),
        SizedBox(height: 12.px),
        // This screen asks people to pick between an invite link, a hosted
        // circle and a relay address, in those words. "Can't work out how to
        // use it" is 23% of one- and two-star reviews outside the April
        // traffic spike — "что за круги? , что за реле?" — and this is where
        // they meet the words. The answer was already written, translated
        // into all 31 languages, and unreachable: nothing opened
        // NostrRelayIntroductionPage.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => OXNavigator.pushPage(
            context,
            (context) => NostrRelayIntroductionPage(
              previousPageTitle: Localized.text('ox_login.add_circle_title'),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 4.px),
            child: CLText.bodyMedium(
              Localized.text('ox_login.relay_intro_title'),
              colorToken: ColorToken.primary,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCircleOptions() {
    return Column(
      children: [
        _buildInviteOption(),
        SizedBox(height: 24.px),
        _buildSeparator(),
        SizedBox(height: 24.px),
        _buildPublicOption(),
        SizedBox(height: 16.px),
        _buildPrivateCloudOption(),
        SizedBox(height: 16.px),
        _buildCustomRelayOption(),
      ],
    );
  }

  /// Restore private relay: clickable text + button below Add Circle options
  Widget _buildRestorePrivateRelaySection() {
    return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _onRestorePrivateRelayTap,
            child: CLText.bodyMedium(
                Localized.text('ox_usercenter.restore_private_relay'),
                colorToken: ColorToken.primary,
            ),
          );
  }

  Future<void> _onRestorePrivateRelayTap() async {
    OXLoading.show();
    final fetched = await CircleEntryHelper.fetchCirclesToRestore();
    OXLoading.dismiss();
    if (!mounted) return;

    if (fetched == null || fetched.isEmpty) {
      CommonToast.instance.show(
        context,
        Localized.text('ox_usercenter.restore_private_relay_no_circles'),
      );
      return;
    }

    final currentRelayUrls = LoginManager.instance.currentState.account?.circles
            .map((c) => c.relayUrl)
            .toSet() ??
        {};
    final circlesToRestore = fetched
        .where((r) => !currentRelayUrls.contains(r.relayUrl))
        .toList();

    if (circlesToRestore.isEmpty) {
      CommonToast.instance.show(
        context,
        Localized.text('ox_usercenter.restore_private_relay_no_circles'),
      );
      return;
    }

    OXNavigator.pushPage(
      context,
      (_) => CircleRestorePage(circles: circlesToRestore, controller: _controller),
    );
  }

  Widget _buildInviteOption() {
    return _buildOptionCard(
      icon: Icons.link_rounded,
      iconColor: ColorToken.primary.of(context),
      title: Localized.text('ox_login.i_have_an_invite'),
      subtitle: Localized.text('ox_login.enter_invitation_code'),
      showArrow: true,
      isSelected: _selectedCircleType == CircleType.invite,
      onTap: () => setState(() => _selectedCircleType = CircleType.invite),
    );
  }

  Widget _buildSeparator() {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.2),
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.px),
          child: CLText.labelSmall(
            Localized.text('ox_login.or_connect_via'),
            colorToken: ColorToken.onSurfaceVariant,
          ),
        ),
        Expanded(
          child: Divider(
            color: ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }

  /// The only option here that costs nothing and needs nobody else. Without
  /// it a new arrival with no invite can either pay or leave, which is what
  /// the one-star reviews describe.
  Widget _buildPublicOption() {
    return _buildOptionCard(
      icon: Icons.public_rounded,
      iconColor: ColorToken.primary.of(context),
      title: Localized.text('ox_login.public_network'),
      subtitle: Localized.text('ox_login.public_network_desc'),
      showArrow: false,
      isSelected: _selectedCircleType == CircleType.public,
      onTap: () => setState(() => _selectedCircleType = CircleType.public),
    );
  }

  Widget _buildPrivateCloudOption() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildOptionCard(
          icon: Icons.diamond_rounded,
      iconColor: ColorToken.primary.of(context),
          title: Localized.text('ox_login.private_cloud'),
          subtitle: Localized.text('ox_login.private_cloud_desc'),
          showArrow: false,
          isSelected: _selectedCircleType == CircleType.private,
          isRecommended: true,
          onTap: () => setState(() => _selectedCircleType = CircleType.private),
        ),
        Positioned(
          top: -8.px,
          right: 8.px,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: 8.px,
              vertical: 4.px,
            ),
            decoration: BoxDecoration(
              color: ColorToken.xChat.of(context),
              borderRadius: BorderRadius.circular(6.px),
            ),
            child: CLText.labelSmall(
              Localized.text('ox_login.most_popular'),
              customColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomRelayOption() {
    return _buildOptionCard(
      icon: Icons.dns_rounded,
      iconColor: ColorToken.primary.of(context),
      title: Localized.text('ox_login.custom_relay'),
      subtitle: Localized.text('ox_login.custom_relay_desc'),
      showArrow: true,
      isSelected: _selectedCircleType == CircleType.custom,
      onTap: () => setState(() => _selectedCircleType = CircleType.custom),
    );
  }

  Widget _buildOptionCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool showArrow,
    required bool isSelected,
    bool isRecommended = false,
    List<Widget>? tags,
    required VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    final borderRadius = BorderRadius.circular(16.px);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isDisabled ? 0.5 : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: borderRadius,
              child: Container(
                color: ColorToken.cardContainer.of(context),
                padding: EdgeInsets.all(20.px),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 30.px,
                          height: 30.px,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12.px),
                          ),
                          child: Icon(
                            icon,
                            size: 28.px,
                            color: iconColor,
                          ),
                        ),
                        SizedBox(width: 16.px),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CLText.titleMedium(
                                title,
                                colorToken: ColorToken.onSurface,
                              ),
                              SizedBox(height: 4.px),
                              CLText.bodySmall(
                                subtitle,
                                colorToken: ColorToken.onSurfaceVariant,
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        if (showArrow) ...[
                          SizedBox(width: 8.px),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 16.px,
                            color: ColorToken.onSurfaceVariant.of(context),
                          ),
                        ],
                      ],
                    ),
                    if (tags != null && tags.isNotEmpty) ...[
                      SizedBox(height: 12.px),
                      Wrap(
                        spacing: 8.px,
                        runSpacing: 8.px,
                        children: tags,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: isSelected
                        ? ColorToken.primary.of(context)
                        : ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.2),
                    width: isSelected ? 2 : 1,
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCircleDialogDescription() {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: Localized.text('ox_login.add_relay_description'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: ColorToken.onSurfaceVariant.of(context),
            ),
          ),
          const TextSpan(text: ' '),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: GestureDetector(
              onTap: _showLearnMore,
              child: Text(
                Localized.text('ox_login.what_is_relay'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: ColorToken.xChat.of(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleHintWidget(BuildContext context, TextEditingController controller) {
    return Padding(
      padding: EdgeInsets.only(top: 8.px),
      child: CLText.bodySmall(
        Localized.text('ox_login.circle_url_hint'),
        colorToken: ColorToken.onSurfaceVariant,
        maxLines: null,
      ).highlighted(
        rules: [
          CLHighlightRule(
            pattern: RegExp(r'0xchat'),
            onTap: (match) {
              controller.text = '0xchat';
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            },
            cursor: SystemMouseCursors.click,
          ),
          CLHighlightRule(
            pattern: RegExp(r'damus'),
            onTap: (match) {
              controller.text = 'damus';
              controller.selection = TextSelection.fromPosition(
                TextPosition(offset: controller.text.length),
              );
            },
            cursor: SystemMouseCursors.click,
          ),
        ],
      ),
    );
  }

  void _showLearnMore() {
    OXNavigator.pushPage(
      context,
      (context) => const CircleIntroductionPage(),
      type: OXPushPageType.present,
    );
  }

  Widget _buildConnectButton() {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 16.px,
      ),
      child: CLButton.filled(
        text: Localized.text('ox_login.connect'),
        onTap: _selectedCircleType != null && !_isProcessing ? _onConnectTap : null,
        expanded: true,
        height: 48.px,
      ),
    );
  }

  Future<void> _onConnectTap() async {
    final type = _selectedCircleType;
    if (type == null) return;

    switch (type) {
      case CircleType.invite:
        await _onUseInvite();
        break;
      case CircleType.public:
        await _onUsePublicCircle();
        break;
      case CircleType.private:
        await _onUsePrivateCircle();
        break;
      case CircleType.custom:
        await _onUseCustomRelay();
        break;
    }
  }

  Future<void> _onUseInvite() async {
    OXNavigator.pushPage(
      context,
      (context) => const FindPeoplePage(joinCircleMode: true),
    );
  }

  Future<void> _onUsePublicCircle() async {
    setState(() => _isProcessing = true);
    OXLoading.show();
    try {
      if (_controller != null) {
        _handleOnboardingResult(await _controller!.joinPublicCircle());
      } else {
        await CircleJoinUtils.processJoinCircle(
          input: kPublicRelayUrl,
          context: context,
        );
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) CommonToast.instance.show(context, e.toString());
    } finally {
      OXLoading.dismiss();
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _onUsePrivateCircle() async {
    // Pre-check: if subscription slots are full, show toast and do not navigate
    final groupId = await CircleEntryHelper.getCurrentInactiveGroupId();
    if (!mounted) return;
    if (groupId == null || groupId.isEmpty) {
      CommonToast.instance.show(
        context,
        Localized.text('ox_login.subscription_limit_reached'),
      );
      return;
    }
    // Navigate to private cloud overview page
    OXNavigator.pushPage(
      context,
      (context) => const PrivateCloudOverviewPage(),
      type: OXPushPageType.present,
      fullscreenDialog: true,
    );
  }

  Future<void> _onUseCustomRelay() async {
    // Show dialog directly
    final relayUrl = await _showAddCircleDialog();
    if (relayUrl == null || relayUrl.isEmpty) return;

    setState(() => _isProcessing = true);
    OXLoading.show();

    try {
      if (_controller != null) {
        // Use onboarding controller for new users
        final result = await _controller!.joinPrivateCircle(
          relayUrl: relayUrl,
          context: context,
        );
        _handleOnboardingResult(result);
      } else {
        // Use CircleJoinUtils for existing users
        await CircleJoinUtils.processJoinCircle(
          input: relayUrl,
          context: context,
          supportInvite: true, // Enable invite link support
        );
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        CommonToast.instance.show(context, e.toString());
      }
    } finally {
      OXLoading.dismiss();
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _handleOnboardingResult(OnboardingResult result) {
    OXLoading.dismiss();

    if (result.success) {
      // Navigate to home
      if (mounted) {
        OXNavigator.popToRoot(context);
      }
    } else {
      // Show error
      if (mounted && result.errorMessage != null) {
        CommonToast.instance.show(context, result.errorMessage!);
      }
    }
  }

  Future<String?> _showAddCircleDialog() async {
    return await CLDialog.showInputDialog(
      context: context,
      title: Localized.text('ox_login.add_relay_title'),
      description: null,
      descriptionWidget: _buildCircleDialogDescription(),
      inputLabel: Localized.text('ox_login.relay_url_placeholder'),
      initialValue: 'damus',
      confirmText: Localized.text('ox_login.join'),
      onConfirm: (input) async {
        final trimmedInput = input.trim();
        if (trimmedInput.isEmpty) {
          CommonToast.instance.show(context, Localized.text('ox_login.relay_url_empty'));
          return false;
        }
        return true;
      },
      belowInputBuilder: (ctx, controller) => _buildCircleHintWidget(ctx, controller),
    );
  }
}
