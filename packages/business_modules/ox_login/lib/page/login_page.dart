import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ox_common/component.dart';
// ox_common
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/widget_tool.dart';
import 'package:ox_common/widgets/common_image.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_module_service/ox_module_service.dart';
// ox_login
import 'package:ox_login/component/welcome_carousel.dart';
import 'package:ox_login/page/account_key_login_page.dart';
import 'package:ox_login/page/apple_password_page.dart';
import 'package:ox_login/page/profile_setup_page.dart';
import 'package:ox_login/utils/apple_nostr_login_helper.dart';
import 'package:nostr_core_dart/src/channel/core_method_channel.dart';
import 'package:nostr_core_dart/src/signer/signer_config.dart';

/// Set to true to show "Sign in with Apple" on iOS again.
const bool kEnableAppleLogin = false;

class LoginPage extends StatefulWidget {
  const LoginPage();

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  /// Near-black with a trace of the brand violet; the carousel photos fade
  /// into it, so it has to match their darkest tone.
  static const Color _background = Color(0xFF0E0C16);

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: CLScaffold(
        body: Container(
          color: _background,
          child: _body(),
        ),
      ),
    );
  }

  Widget _body() {
    return Column(
      children: <Widget>[
        const Expanded(child: WelcomeCarousel(background: _background)),
        SizedBox(height: 22.py),
        SafeArea(
          top: false,
          child: Column(
          children: [
            // Primary: Get Started (all platforms)
            _buildQuickStartButton().setPaddingOnly(bottom: 6.px),
            // iOS only: Sign in with Apple below Get Started (gated by kEnableAppleLogin)
            if (Platform.isIOS && kEnableAppleLogin)
              _buildAppleLoginButton().setPaddingOnly(bottom: 8.px),
            // Secondary button: For existing Nostr users
            _buildExistingAccountButton().setPaddingOnly(bottom: 8.px),
            // Privacy policy and terms links
            _buildPrivacyAndTermsLinks().setPaddingOnly(bottom: 12.px),
            // Signer login for Android
            if(Platform.isAndroid) buildAmberLoginWidget(),
          ],
          ).setPadding(EdgeInsets.symmetric(horizontal: 24.px)),
        ),
        SizedBox(height: 12.py,),
      ],
    );
  }

  /// Primary action: Quick start for new users
  Widget _buildQuickStartButton() => CLButton.filled(
    onTap: _quickStart,
    height: 54.px,
    expanded: true,
    text: Localized.text('ox_login.get_started'),
  );

  /// Sign in with Apple (iOS): fully transparent, white outline (same size/radius as Get Started).
  Widget _buildAppleLoginButton() {
    final white = Colors.white;
    // Same height as Get Started (48.py)
    final buttonHeight = 54.py;
    // Match Get Started: Cupertino large = 12, Material stadium = half height
    final radius = Platform.isIOS ? 12.0 : 24.0;
    final borderRadius = BorderRadius.circular(radius.px);
    return SizedBox(
      height: buttonHeight,
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _appleLogin,
          borderRadius: borderRadius,
          child: Container(
            height: buttonHeight,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.transparent,
              border: Border.all(color: white, width: 1),
              borderRadius: borderRadius,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.apple, color: white, size: 22.px),
                SizedBox(width: 10.px),
                Text(
                  Localized.text('ox_login.sign_in_with_apple'),
                  style: TextStyle(
                    color: white,
                    fontSize: 17.px,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Secondary action: For users with existing Nostr account
  Widget _buildExistingAccountButton() => CLButton.text(
    onTap: _login,
    height: 48.py,
    expanded: true,
    color: ColorToken.white.of(context),
    text: Localized.text('ox_login.have_account'),
  );

  /// Privacy policy and terms of service links
  Widget _buildPrivacyAndTermsLinks() {
    final linkColor = ColorToken.white.of(context).withOpacity(0.7);
    final privacyPolicyText = Localized.text('ox_login.privacy_policy');
    final termsOfServiceText = Localized.text('ox_login.terms_of_service');
    final agreeText = Localized.text('ox_login.agree_to_terms');
    
    // Parse the agree text and replace placeholders with actual links
    final privacyPlaceholder = '{privacy_policy}';
    final termsPlaceholder = '{terms_of_service}';
    
    final List<TextSpan> spans = [];
    int startIndex = 0;
    
    // Find privacy policy placeholder
    final privacyIndex = agreeText.indexOf(privacyPlaceholder);
    if (privacyIndex != -1) {
      // Add text before privacy policy
      if (privacyIndex > startIndex) {
        spans.add(TextSpan(
          text: agreeText.substring(startIndex, privacyIndex),
          style: TextStyle(color: linkColor, fontSize: 12.px),
        ));
      }
      // Add clickable privacy policy link
      spans.add(TextSpan(
        text: privacyPolicyText,
        style: TextStyle(
          color: linkColor,
          fontSize: 12.px,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = _openPrivacyPolicy,
      ));
      startIndex = privacyIndex + privacyPlaceholder.length;
    }
    
    // Find terms of service placeholder
    final termsIndex = agreeText.indexOf(termsPlaceholder, startIndex);
    if (termsIndex != -1) {
      // Add text between privacy and terms
      if (termsIndex > startIndex) {
        spans.add(TextSpan(
          text: agreeText.substring(startIndex, termsIndex),
          style: TextStyle(color: linkColor, fontSize: 12.px),
        ));
      }
      // Add clickable terms of service link
      spans.add(TextSpan(
        text: termsOfServiceText,
        style: TextStyle(
          color: linkColor,
          fontSize: 12.px,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()..onTap = _openTermsOfService,
      ));
      startIndex = termsIndex + termsPlaceholder.length;
    }
    
    // Add remaining text
    if (startIndex < agreeText.length) {
      spans.add(TextSpan(
        text: agreeText.substring(startIndex),
        style: TextStyle(color: linkColor, fontSize: 12.px),
      ));
    }
    
    // If no placeholders found, show plain text
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: agreeText,
        style: TextStyle(color: linkColor, fontSize: 12.px),
      ));
    }
    
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 32.px),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Checkbox (always checked)
          Padding(
            padding: EdgeInsets.only(top: 2.px),
            child: CLCheckbox(
              value: true,
              onChanged: null, // Disabled, always checked
              size: 32.px,
            ),
          ),
          SizedBox(width: 8.px),
          // Agreement text
          Expanded(
            child: RichText(
              textAlign: TextAlign.left,
              text: TextSpan(children: spans),
            ),
          ),
        ],
      ),
    );
  }

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
                color: Colors.white.withValues(alpha: 0.15),
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
              child: CLText.labelSmall(text, customColor: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  // ========== Event Handlers ==========

  void _quickStart() {
    OXNavigator.pushPage(context, (context) => const ProfileSetupPage());
  }

  void _login() {
    OXNavigator.pushPage(context, (context) => AccountKeyLoginPage());
  }

  Future<void> _appleLogin() async {
    // If already logged in (e.g. no circle), logout first so new Apple login uses a clean state and avoids Isar/account mix.
    if (LoginManager.instance.currentState.account != null) {
      await LoginManager.instance.logoutAccount();
      if (!mounted) return;
    }
    final credential = await AppleNostrLoginHelper.signInWithApple();
    if (!mounted) return;
    if (credential == null) return;
    final sub = AppleNostrLoginHelper.parseSubFromAppleIdentityToken(credential.identityToken);
    if (sub == null || sub.isEmpty) {
      CommonToast.instance.show(context, 'Invalid Apple credential');
      return;
    }
    // Push ApplePasswordPage (full page) to collect recovery password
    final password = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (ctx) => ApplePasswordPage()),
    );
    if (!mounted) return;
    if (password == null) return;
    try {
      final keychain = AppleNostrLoginHelper.generateKeychainFromApple(sub, password);
      if (!mounted) return;
      OXNavigator.pushPage(
        context,
        (context) => ProfileSetupPage(
          initialKeychain: keychain,
          initialFirstName: credential.givenName,
          initialLastName: credential.familyName,
        ),
      );
    } catch (e) {
      if (mounted) CommonToast.instance.show(context, 'Failed to derive key: $e');
    }
  }

  void _openPrivacyPolicy() {
    try {
      OXModuleService.invoke('ox_common', 'gotoWebView', [
        context,
        'https://0xchat.com/protocols/xchat-privacy-policy.html',
        null,
        null,
        null,
        null
      ]);
    } catch (e) {
      CommonToast.instance.show(context, 'Failed to open privacy policy: $e');
    }
  }

  void _openTermsOfService() {
    try {
      OXModuleService.invoke('ox_common', 'gotoWebView', [
        context,
        'https://0xchat.com/protocols/xchat-terms-of-use.html',
        null,
        null,
        null,
        null
      ]);
    } catch (e) {
      CommonToast.instance.show(context, 'Failed to open terms of service: $e');
    }
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
      contentPadding: EdgeInsets.zero, // Remove default padding to align left
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
