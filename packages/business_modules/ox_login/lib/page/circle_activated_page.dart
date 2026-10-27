import 'package:chatcore/chat-core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_usercenter/page/settings/qr_code_display_page.dart';
import 'package:ox_usercenter/utils/invite_link_manager.dart';
import 'package:share_plus/share_plus.dart';

/// Shown right after a circle is bought. A circle is worth nothing until the
/// second person is in it, so this page is about inviting them: the link is
/// on screen as soon as the relay hands out a code, ready to copy, share or
/// show as a QR code. The circle's name was chosen before paying.
class CircleActivatedPage extends StatefulWidget {
  const CircleActivatedPage({
    super.key,
    this.maxUsers = 6,
  });

  final int maxUsers;

  @override
  State<CircleActivatedPage> createState() => _CircleActivatedPageState();
}

class _CircleActivatedPageState extends State<CircleActivatedPage> {
  final GlobalKey _shareButtonKey = GlobalKey();
  final int _currentMemberCount = 1; // The owner.
  late final Future<String> _inviteLink = _createInviteLink();

  Circle? get _circle => LoginManager.instance.currentCircle;

  /// Asks the relay for an invitation code and builds a link carrying both
  /// the code and the relay address; without them the recipient's app cannot
  /// resolve it.
  Future<String> _createInviteLink() async {
    final circle = _circle;
    if (circle == null) throw Localized.text('ox_common.operation_failed');
    final result = await InviteLinkManager.generateCircleInviteLink(circle: circle);
    return result['inviteLink'] as String;
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(),
      body: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: CLLayout.horizontalPadding,
          right: CLLayout.horizontalPadding,
          top: 32.px,
          bottom: 24.px,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            SizedBox(height: 32.px),
            _buildInviteLinkCard(),
            SizedBox(height: 12.px),
            _buildShareButton(),
            SizedBox(height: 12.px),
            CLButton.outlined(
              text: Localized.text('ox_login.show_qr_code'),
              onTap: _showQrCode,
              expanded: true,
              height: 50.px,
            ),
            SizedBox(height: 28.px),
            _buildMembers(),
          ],
        ),
      ),
      bottomWidget: CLButton.text(
        text: Localized.text('ox_login.enter_my_private_circle'),
        color: ColorToken.xChat.of(context),
        expanded: true,
        onTap: () => OXNavigator.popToRoot(context),
      ),
    );
  }

  Widget _buildHeader() {
    final name = _circle?.name ?? Localized.text('ox_login.my_private_circle');
    return Column(
      children: [
        Container(
          width: 76.px,
          height: 76.px,
          decoration: BoxDecoration(
            gradient: CLThemeData.themeGradientOf(context),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, color: Colors.white, size: 40.px),
        ),
        SizedBox(height: 24.px),
        CLText.titleLarge(
          Localized.text('ox_login.circle_is_ready').replaceAll('{name}', name),
          colorToken: ColorToken.onSurface,
          textAlign: TextAlign.center,
          isBold: true,
          maxLines: null,
        ),
        SizedBox(height: 8.px),
        CLText.bodyMedium(
          Localized.text('ox_login.invite_people_free')
              .replaceAll('{count}', '${widget.maxUsers - _currentMemberCount}'),
          colorToken: ColorToken.onSurfaceVariant,
          textAlign: TextAlign.center,
          maxLines: null,
        ),
      ],
    );
  }

  Widget _buildInviteLinkCard() {
    return Container(
      padding: EdgeInsets.fromLTRB(16.px, 6.px, 4.px, 6.px),
      decoration: BoxDecoration(
        color: ColorToken.cardContainer.of(context),
        borderRadius: BorderRadius.circular(16.px),
      ),
      child: FutureBuilder<String>(
        future: _inviteLink,
        builder: (context, snapshot) {
          final link = snapshot.data;
          final String shown;
          if (link != null) {
            shown = link;
          } else if (snapshot.hasError) {
            shown = snapshot.error.toString();
          } else {
            shown = '…';
          }
          return Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CLText.labelSmall(
                      Localized.text('ox_login.invite_link'),
                      colorToken: ColorToken.onSurfaceVariant,
                    ),
                    SizedBox(height: 2.px),
                    CLText.bodyMedium(
                      shown,
                      colorToken: ColorToken.onSurface,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: Localized.text('ox_login.copy_invite_link'),
                onPressed: link == null ? null : () => _copy(link),
                icon: Icon(Icons.copy_rounded, color: ColorToken.xChat.of(context)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildShareButton() {
    return KeyedSubtree(
      key: _shareButtonKey,
      child: CLButton.filled(
        onTap: _shareInviteLink,
        expanded: true,
        height: 50.px,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.ios_share_rounded, color: Colors.white, size: 20.px),
            SizedBox(width: 10.px),
            CLText.titleMedium(
              Localized.text('ox_login.share_invite_link'),
              customColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMembers() {
    final me = Account.sharedInstance.me;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: CLText.labelMedium(
                Localized.text('ox_login.members'),
                colorToken: ColorToken.onSurfaceVariant,
                isBold: true,
              ),
            ),
            CLText.labelMedium(
              '$_currentMemberCount / ${widget.maxUsers}',
              colorToken: ColorToken.onSurfaceVariant,
            ),
          ],
        ),
        SizedBox(height: 12.px),
        Row(
          children: [
            OXUserAvatar(user: me, size: 40.px),
            SizedBox(width: 12.px),
            Expanded(
              child: CLText.bodyLarge(
                Localized.text('ox_login.member_you').replaceAll('{name}', me?.name ?? ''),
                colorToken: ColorToken.onSurface,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    CommonToast.instance.show(context, Localized.text('ox_common.copied_to_clipboard'));
  }

  void _showQrCode() {
    final circle = _circle;
    if (circle == null) return;
    OXNavigator.pushPage(
      context,
      (context) => QRCodeDisplayPage(
        inviteType: InviteType.circle,
        circle: circle,
      ),
    );
  }

  Future<void> _shareInviteLink() async {
    // iOS/iPad needs a non-zero sharePositionOrigin for the share sheet
    // popover. Measured before the await, while the button is laid out.
    Rect sharePositionOrigin;
    final box = _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 0 && box.size.height > 0) {
      sharePositionOrigin = box.localToGlobal(Offset.zero) & box.size;
    } else {
      final media = MediaQuery.sizeOf(context);
      sharePositionOrigin = Rect.fromCenter(
        center: Offset(media.width / 2, media.height / 2),
        width: 1,
        height: 1,
      );
    }

    final String link;
    try {
      link = await _inviteLink;
    } catch (e) {
      if (!mounted) return;
      CommonToast.instance.show(context, e.toString());
      return;
    }

    try {
      await Share.share(link, sharePositionOrigin: sharePositionOrigin);
    } catch (e) {
      if (!mounted) return;
      CommonToast.instance.show(context, 'Failed to share: $e');
    }
  }
}
