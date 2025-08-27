import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:chatcore/chat-core.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';
import 'package:ox_common/utils/permission_utils.dart';
import 'package:ox_common/const/app_config.dart';
import 'package:ox_common/utils/compression_utils.dart';

enum QRCodeStyle {
  defaultStyle, // Default
  classic,      // Classic
  dots,         // Dots
  gradient,     // Gradient
}

enum InviteLinkType {
  oneTime,    // One-time invite link
  permanent,  // Permanent invite link
}

class QRCodeDisplayPage extends StatefulWidget {
  const QRCodeDisplayPage({
    super.key,
    this.previousPageTitle,
    this.otherUser,
  });

  final String? previousPageTitle;
  final UserDBISAR? otherUser;

  @override
  State<QRCodeDisplayPage> createState() => _QRCodeDisplayPageState();
}

class _QRCodeDisplayPageState extends State<QRCodeDisplayPage> {
  late final UserDBISAR userNotifier;
  late final String userName;
  String? currentInviteLink;
  String? currentQrCodeData;

  // QR Code style options
  QRCodeStyle currentStyle = QRCodeStyle.gradient;
  final GlobalKey qrWidgetKey = GlobalKey();

  double get horizontal => 32.px;

  QrCode? qrCode;
  QrImage? qrImage;
  late PrettyQrDecoration previousDecoration;
  late PrettyQrDecoration currentDecoration;

  // Invite link type
  InviteLinkType currentLinkType = InviteLinkType.oneTime;

  @override
  void initState() {
    super.initState();
    userNotifier = widget.otherUser ?? Account.sharedInstance.me!;
    userName = userNotifier.name ?? userNotifier.shortEncodedPubkey;
    
    currentDecoration = createDecoration(currentStyle);
    previousDecoration = currentDecoration;
    
    // Auto-generate permanent invite link when page loads (only for current user)
    if (widget.otherUser == null) {
      _generateInviteLink(InviteLinkType.permanent);
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _generateInviteLink(InviteLinkType linkType) async {
    if (widget.otherUser != null) return; // Only for current user
    
    try {
      OXLoading.show();
      
      KeyPackageEvent? keyPackageEvent;
      
      if (linkType == InviteLinkType.oneTime) {
        keyPackageEvent = await Groups.sharedInstance.createOneTimeKeyPackage();
      } else {
        keyPackageEvent = await Groups.sharedInstance.createPermanentKeyPackage(
          Account.sharedInstance.getCurrentCircleRelay(),
        );
      }
      
      if (keyPackageEvent == null) {
        await OXLoading.dismiss();
        CommonToast.instance.show(context, Localized.text('ox_usercenter.invite_link_generation_failed'));
        return;
      }

      // Get relay URL
      List<String> relays = Account.sharedInstance.getCurrentCircleRelay();
      String? relayUrl = relays.firstOrNull;
      if (relayUrl == null || relayUrl.isEmpty) {
        await OXLoading.dismiss();
        CommonToast.instance.show(context, 'Error circle info');
        OXNavigator.pop(context);
        return;
      }

      // Generate invite link with compression
      if (linkType == InviteLinkType.oneTime || linkType == InviteLinkType.permanent) {
        // For one-time invites, include sender's pubkey
        final senderPubkey = Account.sharedInstance.currentPubkey;
        
        // Try to compress the keypackage data
        String? compressedKeyPackage = await CompressionUtils.compressWithPrefix(keyPackageEvent.encoded_key_package);
        String keyPackageParam = compressedKeyPackage ?? keyPackageEvent.encoded_key_package;
        
        currentInviteLink = '${AppConfig.inviteBaseUrl}?keypackage=$keyPackageParam&pubkey=${Uri.encodeComponent(senderPubkey)}&relay=${Uri.encodeComponent(relayUrl)}';
        
        // Log compression results
        if (compressedKeyPackage != null) {
          double ratio = CompressionUtils.getCompressionRatio(keyPackageEvent.encoded_key_package, compressedKeyPackage);
          print('Keypackage compressed: ${(ratio * 100).toStringAsFixed(1)}% of original size');
        }
      } else {
        currentInviteLink = '${AppConfig.inviteBaseUrl}?eventid=${Uri.encodeComponent(keyPackageEvent.eventId)}&relay=${Uri.encodeComponent(relayUrl)}';
      }

      // Update QR code data and current link type
      currentQrCodeData = currentInviteLink;
      currentLinkType = linkType;
      
      // Initialize QR code and image with optimized settings for long URLs
      try {
        // Use lower error correction level for better readability with long URLs
        qrCode = QrCode.fromData(
          data: currentQrCodeData!,
          errorCorrectLevel: QrErrorCorrectLevel.L, // Use lowest error correction level
        );
        qrImage = QrImage(qrCode!);
      } catch (e) {
        print('QR code generation failed: $e');
        qrCode = null;
        qrImage = null;
        CommonToast.instance.show(context, Localized.text('ox_usercenter.qr_generation_failed'));
      }

      await OXLoading.dismiss();
      setState(() {});
    } catch (e) {
      await OXLoading.dismiss();
      CommonToast.instance.show(context, '${Localized.text('ox_usercenter.invite_link_generation_failed')}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: widget.otherUser != null 
            ? Localized.text('ox_usercenter.user_qr_code')
            : Localized.text('ox_usercenter.generate_invite_link'),
        previousPageTitle: widget.previousPageTitle,
        actions: widget.otherUser == null ? <Widget>[
          // Reload button with proper alignment
          CLButton.icon(
            onTap: currentInviteLink != null ? _showRegenerateConfirmDialog : null,
            tooltip: Localized.text('ox_usercenter.regenerate_invite_link'),
            icon: Icons.refresh
          ),
        ] : <Widget>[],
      ),
      isSectionListPage: true,
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // QR Code Card - Place at the top, following Signal's layout
          RepaintBoundary(
            key: qrWidgetKey,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontal,
                vertical: 20.px,
              ),
              child: _buildQRCodeCard(),
            ),
          ),
          
          // Action buttons (only for current user, only show when invite link is generated)
          if (widget.otherUser == null && currentInviteLink != null) ...[
            SizedBox(height: 24.px),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: CLButton.filled(
                text: Localized.text('ox_usercenter.share_invite_link'),
                onTap: _shareInvite,
                expanded: true,
              ),
            ),
            SizedBox(height: 12.px),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: horizontal),
              child: CLButton.outlined(
                text: Localized.text('ox_usercenter.save_qr_code'),
                onTap: _saveQRCode,
                expanded: true,
              ),
            ),
          ],
          
          SafeArea(child: SizedBox(height: 12.px))
        ],
      ),
    );
  }

  Widget _buildUserHeader() {
    return Row(
      children: [
        OXUserAvatar(
          imageUrl: userNotifier.picture ?? '',
          size: 56.px,
        ),
        SizedBox(width: 16.px),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CLText.titleMedium(
                userName,
                maxLines: 1,
                colorToken: ColorToken.onSurface,
                overflow: TextOverflow.ellipsis,
              ),
              SizedBox(height: 4.px),
              CLText.bodySmall(
                userNotifier.shortEncodedPubkey,
                colorToken: ColorToken.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQRCodeCard() {
    return Container(
      padding: EdgeInsets.all(24.px),
      decoration: BoxDecoration(
        color: ColorToken.surface.of(context).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16.px),
        border: Border.all(
          color: ColorToken.onSurfaceVariant.of(context).withValues(alpha: 0.1),
          width: 1.px,
        ),
      ),
      child: Column(
        children: [
          // User Header
          _buildUserHeader(),
          SizedBox(height: 24.px),
          
          // QR Code
          _buildQRCode(),

          SizedBox(height: 16.px),

          // Description text
          CLText.bodyMedium(
            Localized.text('ox_usercenter.scan_qr_to_find_me'),
            textAlign: TextAlign.center,
            colorToken: ColorToken.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _buildQRCode() {
    return Container(
      padding: EdgeInsets.all(16.px),
      decoration: BoxDecoration(
        color: qrImage == null
            ? ColorToken.surfaceContainer.of(context)
            : Colors.white,
        borderRadius: BorderRadius.circular(16.px),
      ),
      child: _buildStyledQRCode(),
    );
  }

  Widget _buildStyledQRCode() {
    if (qrImage == null) {
      return Container(
        width: 240.px,
        height: 240.px,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.qr_code_2,
              size: 64.px,
              color: ColorToken.onSurfaceVariant.of(context),
            ),
            SizedBox(height: 16.px),
            CLText.bodyMedium(
              currentInviteLink == null 
                  ? Localized.text('ox_usercenter.empty_invite_link')
                  : Localized.text('ox_usercenter.qr_generation_failed'),
              colorToken: ColorToken.onSurfaceVariant,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    
    return Container(
      width: 280.px,
      height: 280.px,
      padding: EdgeInsets.all(6.px),
      child: TweenAnimationBuilder<PrettyQrDecoration>(
        tween: PrettyQrDecorationTween(
          begin: previousDecoration,
          end: currentDecoration,
        ),
        curve: Curves.ease,
        duration: const Duration(milliseconds: 300),
        builder: (context, decoration, child) {
          return PrettyQrView(
            qrImage: qrImage!,
            decoration: decoration,
          );
        },
      ),
    );
  }

  void changeQrStyle(QRCodeStyle style) {
    setState(() {
      currentStyle = style;
      previousDecoration = currentDecoration;
      currentDecoration = createDecoration(style);
    });
  }

  PrettyQrDecoration createDecoration(QRCodeStyle style) {
    Color color = ColorToken.primary.of(
      OXNavigator.rootContext
    ).withValues(alpha: 0.8);
    double roundFactor = 1;
    PrettyQrShape shape;

    switch (style) {
      case QRCodeStyle.defaultStyle:
        shape = PrettyQrSmoothSymbol(
          color: color,
          roundFactor: roundFactor,
        );
        break;

      case QRCodeStyle.classic:
        shape = PrettyQrSmoothSymbol(
          color: color,
          roundFactor: 0,
        );
        break;

      case QRCodeStyle.dots:
        shape = PrettyQrRoundedSymbol(
          color: color,
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        );
        break;

      case QRCodeStyle.gradient:
        shape = PrettyQrSmoothSymbol(
          color: PrettyQrBrush.gradient(
            gradient: CLThemeData.themeGradientOf(OXNavigator.rootContext),
          ),
          roundFactor: roundFactor, // Rounded
        );
        break;
    }

    return PrettyQrDecoration(
      shape: shape,
    );
  }

  String _getStyleName(QRCodeStyle style) {
    switch (style) {
      case QRCodeStyle.defaultStyle:
        return Localized.text('ox_usercenter.default');
      case QRCodeStyle.classic:
        return Localized.text('ox_usercenter.classic');
      case QRCodeStyle.dots:
        return Localized.text('ox_usercenter.dots');
      case QRCodeStyle.gradient:
        return Localized.text('ox_usercenter.gradient');
    }
  }

  Future<void> _saveQRCode() async {
    try {
      // Request appropriate permissions using existing utility method
      bool permissionGranted = await PermissionUtils.getPhotosPermission(context, type: 1);

      if (!permissionGranted) {
        CommonToast.instance.show(
          context, 
          Localized.text('ox_usercenter.storage_permission_denied'),
        );
        return;
      }

      OXLoading.show();

      // Capture QR code widget as image
      final boundary = qrWidgetKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('Failed to capture QR code');
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('Failed to convert image to bytes');
      }

      final pngBytes = byteData.buffer.asUint8List();
      
      // Save to gallery
      final result = await ImageGallerySaverPlus.saveImage(
        pngBytes,
        name: 'QRCode_${DateTime.now().millisecondsSinceEpoch}',
        isReturnImagePathOfIOS: true,
      );

      await OXLoading.dismiss();

      if (result['isSuccess'] == true) {
        CommonToast.instance.show(
          context, 
          Localized.text('ox_usercenter.qr_code_saved'),
        );
      } else {
        throw Exception('Save failed');
      }
    } catch (e) {
      await OXLoading.dismiss();
      CommonToast.instance.show(
        context, 
        Localized.text('ox_usercenter.save_failed'),
      );
    }
  }

  void _showShareOptions() async {
    final result = await CLPicker.show<String>(
      context: context,
      title: Localized.text('ox_usercenter.select_operation'),
      items: [
        CLPickerItem(
          label: Localized.text('ox_usercenter.save_qr_code'),
          value: 'save_qr_code',
        ),
        CLPickerItem(
          label: Localized.text('ox_usercenter.share_invite_link'),
          value: 'share_invite_link',
        ),
      ],
    );

    if (result == 'save_qr_code') {
      _saveQRCode();
    } else if (result == 'share_invite_link') {
      _shareInvite();
    }
  }

  Future<void> _shareInvite() async {
    try {
      // Share invite link
      await Share.share(
        currentInviteLink!,
        subject: Localized.text('ox_usercenter.invite_to_chat'),
      );
    } catch (e) {
      CommonToast.instance.show(
        context, 
        '${Localized.text('ox_usercenter.share_failed')}: $e',
      );
    }
  }

  Future<void> _regenerateInviteLink() async {
    try {
      OXLoading.show();
      
      // Recreate permanent keypackage
      KeyPackageEvent? keyPackageEvent = await Groups.sharedInstance.recreatePermanentKeyPackage(
        Account.sharedInstance.getCurrentCircleRelay(),
      );
      
      if (keyPackageEvent == null) {
        await OXLoading.dismiss();
        CommonToast.instance.show(context, Localized.text('ox_usercenter.invite_link_generation_failed'));
        return;
      }

      // Get relay URL
      List<String> relays = Account.sharedInstance.getCurrentCircleRelay();
      String relayUrl = relays.isNotEmpty ? relays.first : 'wss://relay.0xchat.com';

      // Generate new invite link
      currentInviteLink = '${AppConfig.inviteBaseUrl}?eventid=${Uri.encodeComponent(keyPackageEvent.eventId)}&relay=${Uri.encodeComponent(relayUrl)}';

      // Update QR code data
      currentQrCodeData = currentInviteLink;
      
      // Initialize QR code and image with optimized settings for long URLs
      try {
        // Use lower error correction level for better readability with long URLs
        qrCode = QrCode.fromData(
          data: currentQrCodeData!,
          errorCorrectLevel: QrErrorCorrectLevel.L, // Use lowest error correction level
        );
        qrImage = QrImage(qrCode!);
      } catch (e) {
        print('QR code generation failed: $e');
        qrCode = null;
        qrImage = null;
        CommonToast.instance.show(context, Localized.text('ox_usercenter.qr_generation_failed'));
      }

      await OXLoading.dismiss();
      setState(() {});
      
      CommonToast.instance.show(context, Localized.text('ox_usercenter.invite_link_regenerated'));
    } catch (e) {
      await OXLoading.dismiss();
      CommonToast.instance.show(context, '${Localized.text('ox_usercenter.invite_link_generation_failed')}: $e');
    }
  }

  void _showOneTimeConfirmDialog() {
    CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.one_time_keypackage_confirm_title'),
      content: Localized.text('ox_usercenter.one_time_keypackage_confirm_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.confirm'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    ).then((value) {
      if (value == true) {
        _generateInviteLink(InviteLinkType.oneTime);
      }
    });
  }

  void _showPermanentConfirmDialog() {
    CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.permanent_keypackage_confirm_title'),
      content: Localized.text('ox_usercenter.permanent_keypackage_confirm_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.confirm'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    ).then((value) {
      if (value == true) {
        _generateInviteLink(InviteLinkType.permanent);
      }
    });
  }

  void _showRegenerateConfirmDialog() {
    CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.regenerate_invite_link'),
      content: Localized.text('ox_usercenter.regenerate_confirm_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_common.confirm'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    ).then((value) {
      if (value == true) {
        _regenerateInviteLink();
      }
    });
  }
} 