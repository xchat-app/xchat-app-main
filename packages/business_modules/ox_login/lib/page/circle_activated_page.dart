import 'package:chatcore/chat-core.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/circle_service.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/color_extension.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_usercenter/utils/invite_link_manager.dart';
import 'package:share_plus/share_plus.dart';

class CircleActivatedPage extends StatefulWidget {
  const CircleActivatedPage({
    super.key,
    this.maxUsers = 6,
    this.planName = 'Family Plan',
  });

  final int maxUsers;
  final String planName;

  @override
  State<CircleActivatedPage> createState() => _CircleActivatedPageState();
}

class _CircleActivatedPageState extends State<CircleActivatedPage> {
  late TextEditingController _nameController;
  late String _circleName;
  int _currentMemberCount = 1; // Start with 1 (the current user)
  final GlobalKey _shareButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final circle = LoginManager.instance.currentCircle;
    _circleName = circle?.name ?? Localized.text('ox_login.my_private_circle');
    _nameController = TextEditingController(text: _circleName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: CLLayout.horizontalPadding,
          right: CLLayout.horizontalPadding,
          top: 24.px,
          bottom: 100.px,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSuccessHeader(),
            SizedBox(height: 32.px),
            _buildStep1(),
            SizedBox(height: 24.px),
            _buildStep2(),
          ],
        ),
      ),
      bottomWidget: _buildEnterButton(),
    );
  }

  Widget _buildSuccessHeader() {
    return Column(
      children: [
        // Success icon
        Container(
          width: 64.px,
          height: 64.px,
          decoration: BoxDecoration(
            color: ColorToken.green.of(context).lighten(0.4),
            borderRadius: BorderRadius.circular(16.px),
          ),
          child: Icon(
            Icons.check_circle,
            color: ColorToken.green.of(context),
            size: 40.px,
          ),
        ),
        SizedBox(height: 16.px),
        // Title
        CLText.titleLarge(
          Localized.text('ox_login.circle_activated'),
          colorToken: ColorToken.onSurface,
          textAlign: TextAlign.center,
          isBold: true,
        ),
        SizedBox(height: 8.px),
        // Description
        CLText.bodyMedium(
          Localized.text('ox_login.circle_activated_desc'),
          colorToken: ColorToken.onSurfaceVariant,
          textAlign: TextAlign.center,
          maxLines: null,
        ),
      ],
    );
  }

  Widget _buildStepHeader(int stepNumber, String title) {
    return Row(
      children: [
        Container(
          width: 24.px,
          height: 24.px,
          decoration: BoxDecoration(
            color: ColorToken.onSurface.of(context),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: CLText.labelMedium(
              stepNumber.toString(),
              colorToken: ColorToken.surface,
            ),
          ),
        ),
        SizedBox(width: 8.px),
        CLText.titleMedium(
          title,
          colorToken: ColorToken.onSurface,
        ),
      ],
    );
  }

  Widget _buildCardContainer({
    required Widget child,
    EdgeInsets? padding,
    VoidCallback? onTap,
  }) {
    final container = Container(
      padding: padding ?? EdgeInsets.all(16.px),
      decoration: BoxDecoration(
        color: ColorToken.cardContainer.of(context),
        borderRadius: BorderRadius.circular(12.px),
      ),
      child: child,
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: container,
      );
    }

    return container;
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(1, Localized.text('ox_login.name_your_circle')),
        SizedBox(height: 12.px),
        _buildCardContainer(
          padding: EdgeInsets.symmetric(
            horizontal: 16.px,
            vertical: 14.px,
          ),
          onTap: _editCircleName,
          child: Row(
            children: [
              Expanded(
                child: CLText.titleMedium(
                  _circleName,
                  colorToken: ColorToken.onSurface,
                  isBold: true,
                ),
              ),
              SizedBox(width: 8.px),
              Icon(
                Icons.edit_outlined,
                size: 18.px,
                color: ColorToken.onSurfaceVariant.of(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStepHeader(2, Localized.text('ox_login.invite_members')),
        SizedBox(height: 12.px),
        _buildCardContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.diamond_rounded,
                    size: 20.px,
                    color: const Color(0xFFFFC107), // Yellow crown icon
                  ),
                  SizedBox(width: 8.px),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CLText.titleMedium(
                          widget.planName,
                          colorToken: ColorToken.onSurface,
                          isBold: true,
                        ),
                        SizedBox(height: 2.px),
                        CLText.bodySmall(
                          Localized.text('ox_login.unlimited_secure_storage'),
                          colorToken: ColorToken.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      CLText.titleMedium(
                        '$_currentMemberCount/${widget.maxUsers}',
                        colorToken: ColorToken.onSurface,
                        isBold: true,
                      ),
                      CLText.labelSmall(
                        Localized.text('ox_login.members'),
                        colorToken: ColorToken.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 12.px),
              // Progress bar
              Container(
                height: 4.px,
                decoration: BoxDecoration(
                  color: ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2.px),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _currentMemberCount / widget.maxUsers,
                  child: Container(
                    decoration: BoxDecoration(
                      color: ColorToken.xChat.of(context),
                      borderRadius: BorderRadius.circular(2.px),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16.px),
              // Share invite link button
              GestureDetector(
                key: _shareButtonKey,
                onTap: _shareInviteLink,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16.px,
                    vertical: 12.px,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.3),
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12.px),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.share_outlined,
                        size: 18.px,
                        color: ColorToken.onSurface.of(context),
                      ),
                      SizedBox(width: 8.px),
                      CLText.titleSmall(
                        Localized.text('ox_login.share_invite_link'),
                        colorToken: ColorToken.onSurface,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 8.px),
              CLText.bodySmall(
                Localized.text('ox_login.invite_more_people').replaceAll('{count}', '${widget.maxUsers - _currentMemberCount}'),
                colorToken: ColorToken.onSurfaceVariant,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEnterButton() {
    return CLButton.filled(
      onTap: _onEnterCircle,
      expanded: true,
      height: 48.px,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CLText.titleMedium(
            Localized.text('ox_login.enter_my_private_circle'),
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
    );
  }

  Future<void> _editCircleName() async {
    await CLDialog.showInputDialog(
      context: context,
      title: Localized.text('ox_login.name_your_circle'),
      inputLabel: Localized.text('ox_usercenter.circle_name'),
      initialValue: _circleName,
      onConfirm: (newName) async {
        if (newName.trim().isEmpty) {
          CommonToast.instance.show(context, Localized.text('ox_common.input_cannot_be_empty'));
          return false;
        }
        
        if (newName.trim() == _circleName) {
          return true; // No change needed
        }

        try {
          OXLoading.show();

          final circle = LoginManager.instance.currentCircle;
          if (circle == null) {
            OXLoading.dismiss();
            CommonToast.instance.show(context, Localized.text('ox_common.operation_failed'));
            return false;
          }

          final trimmedName = newName.trim();

          // If this is a paid relay, update tenant name on server first (same as circle_detail_page)
          if (CircleApi.isPaidRelay(circle.relayUrl)) {
            try {
              await CircleMemberService.sharedInstance.updateTenant(
                name: trimmedName,
              );
            } catch (e) {
              OXLoading.dismiss();
              LogUtil.e(() => 'Failed to update tenant name on server: $e');
              final errorMessage = e.toString().replaceFirst('Exception: ', '');
              CommonToast.instance.show(
                context,
                errorMessage.isNotEmpty
                    ? errorMessage
                    : Localized.text('ox_common.operation_failed'),
              );
              return false;
            }
          }

          final updatedCircle = await CircleService.updateCircleName(
            circle.id,
            trimmedName,
          );

          if (updatedCircle == null) {
            OXLoading.dismiss();
            CommonToast.instance.show(context, Localized.text('ox_common.operation_failed'));
            return false;
          }

          OXLoading.dismiss();

          setState(() {
            _circleName = trimmedName;
            _nameController.text = trimmedName;
          });

          return true;
        } catch (e) {
          OXLoading.dismiss();
          CommonToast.instance.show(context, e.toString());
          return false;
        }
      },
    );
  }

  Future<void> _shareInviteLink() async {
    final circle = LoginManager.instance.currentCircle;
    if (circle == null) {
      CommonToast.instance.show(context, Localized.text('ox_common.operation_failed'));
      return;
    }

    // iOS/iPad requires a non-zero sharePositionOrigin for the share sheet popover.
    // Measured before the await below, while the button is certainly laid out.
    Rect sharePositionOrigin;
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final rect = box.localToGlobal(Offset.zero) & box.size;
      sharePositionOrigin = rect.size.width > 0 && rect.size.height > 0
          ? rect
          : Rect.fromCenter(
              center: box.localToGlobal(Offset(box.size.width / 2, box.size.height / 2)),
              width: 1,
              height: 1,
            );
    } else {
      final media = MediaQuery.sizeOf(context);
      sharePositionOrigin = Rect.fromCenter(
        center: Offset(media.width / 2, media.height / 2),
        width: 1,
        height: 1,
      );
    }

    // Ask the relay for an invitation code and build a link that carries both
    // the code and the relay address. A link without them cannot be resolved
    // by the recipient's app, which is what the previous placeholder produced.
    String inviteLink;
    OXLoading.show();
    try {
      final result = await InviteLinkManager.generateCircleInviteLink(circle: circle);
      inviteLink = result['inviteLink'] as String;
    } catch (e) {
      OXLoading.dismiss();
      if (!mounted) return;
      CommonToast.instance.show(context, e.toString());
      return;
    }
    OXLoading.dismiss();
    if (!mounted) return;

    try {
      await Share.share(
        inviteLink,
        sharePositionOrigin: sharePositionOrigin,
      );
    } catch (e) {
      if (!mounted) return;
      CommonToast.instance.show(context, 'Failed to share: $e');
    }
  }

  void _onEnterCircle() {
    // Navigate to home/main screen
    OXNavigator.popToRoot(context);
  }
}

