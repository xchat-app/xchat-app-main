import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
// ox_common
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/widget_tool.dart';
import 'package:ox_common/widgets/common_image.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_localizable/ox_localizable.dart';
// ox_login
import 'package:ox_login/page/account_key_login_page.dart';
import 'package:ox_login/page/create_account_page.dart';
import 'package:nostr_core_dart/src/channel/core_method_channel.dart';
import 'package:nostr_core_dart/src/signer/signer_config.dart';

class LoginPage extends StatefulWidget {
  const LoginPage();

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    return Column(
      children: <Widget>[
        const Spacer(),
        BannerCarousel(
          items: [
            BannerItem(
              image: CommonImage(
                iconName: 'image_guide_1.png',
                size: 280.px,
                package: 'ox_login',
                isPlatformStyle: true,
              ),
              title: Localized.text('ox_login.carousel_title_1'),
              text: Localized.text('ox_login.carousel_text_1'),
            ),
            BannerItem(
              image: CommonImage(
                iconName: 'image_guide_2.png',
                size: 280.px,
                package: 'ox_login',
                isPlatformStyle: true,
              ),
              title: Localized.text('ox_login.carousel_title_2'),
              text: Localized.text('ox_login.carousel_text_2'),
            ),
            BannerItem(
              image: CommonImage(
                iconName: 'image_guide_3.png',
                size: 280.px,
                package: 'ox_login',
                isPlatformStyle: true,
              ),
              title: Localized.text('ox_login.carousel_title_3'),
              text: Localized.text('ox_login.carousel_text_3'),
            ),
            BannerItem(
              image: CommonImage(
                iconName: 'image_guide_4.png',
                size: 280.px,
                package: 'ox_login',
                isPlatformStyle: true,
              ),
              title: Localized.text('ox_login.carousel_title_4'),
              text: Localized.text('ox_login.carousel_text_4'),
            ),
          ],
          height: 460.py,
          interval: const Duration(seconds: 3),
          padding: EdgeInsets.symmetric(horizontal: 32.px),
        ),
        const Spacer(),
        Column(
          children: [
            buildCreateAccountButton().setPaddingOnly(bottom: 18.px),
            buildLoginButton().setPaddingOnly(bottom: 18.px),
            // buildQrCodeLoginWidget().setPaddingOnly(bottom: 18.px),
            // buildPrivacyWidget().setPaddingOnly(bottom: 18.px),
            if(Platform.isAndroid) buildAmberLoginWidget(),
          ],
        ).setPadding(EdgeInsets.symmetric(horizontal: 32.px)),
        SizedBox(height: 12.py,),
      ],
    );
  }

  Widget buildCreateAccountButton() => CLButton.filled(
    onTap: _createAccount,
    height: 48.py,
    expanded: true,
    text: Localized.text('ox_login.create_account'),
  );

  Widget buildLoginButton() => CLButton.tonal(
    onTap: _login,
    height: 48.py,
    expanded: true,
    text: Localized.text('ox_login.login_button'),
  );

  Widget buildAmberLoginWidget() {
    String text = Localized.text('ox_login.login_with_signer');
    GestureTapCallback? onTap = _showSignerSelectionDialog;
    String iconName = "icon_login_amber.png";
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: onTap,
      child: Container(
        height: 70.px,
        child: Stack(
          children: [
            Positioned(
              top: 24.px,
              left: 0,
              right: 0,
              child: Container(
                width: double.infinity,
                height: 0.5.px,
                color: ColorToken.secondaryContainer.of(context),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: CommonImage(
                iconName: iconName,
                width: 48.px,
                height: 48.px,
                package: 'ox_login',
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: CLText.labelSmall(text),
            ),
          ],
        ),
      ),
    );
  }

  // ========== Event Handlers ==========

  void _createAccount() {
    OXNavigator.pushPage(context, (context) => CreateAccountPage());
  }

  void _login() {
    OXNavigator.pushPage(context, (context) => AccountKeyLoginPage());
  }


  void _showSignerSelectionDialog() async {
    // Check which signers are installed
    final availableSigners = await _getAvailableSigners();
    
    if (availableSigners.isEmpty) {
      // No signers installed, show error message
      if (mounted) {
        CommonToast.instance.show(context, Localized.text('ox_login.no_signer_installed'));
      }
      return;
    }
    
    // Check if we should use the last used signer
    final lastSigner = await _getLastUsedSigner();
    if (lastSigner != null) {
      final lastSignerAvailable = availableSigners.any((signer) => signer['key'] == lastSigner);
      if (lastSignerAvailable) {
        // Last used signer is still available, use it directly
        _loginWithSelectedSigner(lastSigner);
        return;
      }
    }
    
    if (availableSigners.length == 1) {
      // Only one signer installed, use it directly
      final signer = availableSigners.first;
      _loginWithSelectedSigner(signer['key']!);
      return;
    }
    
    // Multiple signers available, show selection dialog
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(Localized.text('ox_login.select_signer')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: availableSigners.map((signer) {
              return Column(
                children: [
                  _buildSignerOption(signer['key']!, signer['displayName']!, signer['packageName']!, signer['icon']!),
                  if (signer != availableSigners.last) SizedBox(height: 12.px),
                ],
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<List<Map<String, String>>> _getAvailableSigners() async {
    final availableSigners = <Map<String, String>>[];
    
    // Get all signer configurations from SignerConfigs
    final signerKeys = SignerConfigs.getAvailableSigners();
    
    // Check which signers are installed
    for (final signerKey in signerKeys) {
      try {
        final config = SignerConfigs.getConfig(signerKey);
        if (config != null) {
          final isInstalled = await CoreMethodChannel.isAppInstalled(config.packageName);
          if (isInstalled) {
            availableSigners.add({
              'key': signerKey,
              'displayName': config.displayName,
              'packageName': config.packageName,
              'icon': config.iconName,
            });
          }
        }
      } catch (e) {
        debugPrint('Error checking if $signerKey is installed: $e');
      }
    }
    
    return availableSigners;
  }

  Future<String?> _getLastUsedSigner() async {
    try {
      // Get current pubkey from LoginManager
      final currentPubkey = LoginManager.instance.currentState.account?.pubkey;
      if (currentPubkey == null) return null;
      
      // Get signer for this specific pubkey
      return await LoginManager.instance.getSignerForPubkey(currentPubkey);
    } catch (e) {
      debugPrint('Error getting last used signer: $e');
      return null;
    }
  }

  Widget _buildSignerOption(String signerKey, String displayName, String packageName, String iconName) {
    return ListTile(
      leading: Container(
        width: 40.px,
        height: 40.px,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ColorToken.surfaceContainer.of(context),
        ),
        child: ClipOval(
          child: CommonImage(
            iconName: iconName,
            width: 32.px,
            height: 32.px,
            package: 'ox_login',
          ),
        ),
      ),
      title: Text(displayName),
      subtitle: Text(packageName),
      onTap: () {
        Navigator.of(context).pop();
        _loginWithSelectedSigner(signerKey);
      },
    );
  }

  void _loginWithSelectedSigner(String signerKey) async {
    try {
      debugPrint('Starting login with signer: $signerKey');
      
      // Use LoginManager for signer login
      final result = await LoginManager.instance.loginWithSigner(signerKey);
      debugPrint('Signer login result: $result');
    } catch (e) {
      debugPrint('Signer login failed: $e');
      if (mounted) {
        CommonToast.instance.show(context, 'Login failed: ${e.toString()}');
      }
    }
  }

}
