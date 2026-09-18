import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/key_backup_state.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_module_service/ox_module_service.dart';

/// Sits above the chat list until the account's key has been copied somewhere.
///
/// It is deliberately not dismissible for good. Losing the key loses the
/// account, permanently and with no way back, and the people who write in
/// about it are always past the point where anything can be done. A banner
/// that waits is the only version of this warning that reaches someone on a
/// day when they have a password manager open.
class KeyBackupBanner extends StatefulWidget {
  const KeyBackupBanner({super.key});

  @override
  State<KeyBackupBanner> createState() => _KeyBackupBannerState();
}

class _KeyBackupBannerState extends State<KeyBackupBanner> {
  bool _backedUp = true;
  bool _hiddenForNow = false;
  String _pubkey = '';

  @override
  void initState() {
    super.initState();
    KeyBackupState.revision.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    KeyBackupState.revision.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _refresh() async {
    final pubkey = LoginManager.instance.currentState.account?.pubkey ?? '';
    final backedUp = await KeyBackupState.isBackedUp(pubkey);
    if (!mounted) return;
    final switchedAccount = pubkey != _pubkey;
    setState(() {
      _pubkey = pubkey;
      _backedUp = backedUp;
      // A different account starts its own conversation about this, so a
      // "later" tapped by the previous one does not carry over.
      if (switchedAccount) _hiddenForNow = false;
    });
  }

  Future<void> _openKeys() async {
    await OXModuleService.pushPage(context, 'ox_usercenter', 'KeysPage', {});
    // Copying the key from that page sets the flag; pick it up on the way back.
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_backedUp || _hiddenForNow || _pubkey.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.fromLTRB(16.px, 8.px, 16.px, 0),
      padding: EdgeInsets.all(12.px),
      decoration: BoxDecoration(
        color: ColorToken.secondaryContainer.of(context),
        borderRadius: BorderRadius.circular(12.px),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.vpn_key_rounded,
            size: 20.px,
            color: ColorToken.onSecondaryContainer.of(context),
          ),
          SizedBox(width: 12.px),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CLText.titleSmall(
                  Localized.text('ox_home.back_up_key_title'),
                  colorToken: ColorToken.onSecondaryContainer,
                ),
                SizedBox(height: 4.px),
                CLText.bodySmall(
                  Localized.text('ox_home.back_up_key_desc'),
                  colorToken: ColorToken.onSecondaryContainer,
                  maxLines: null,
                ),
                SizedBox(height: 10.px),
                Row(
                  children: [
                    GestureDetector(
                      onTap: _openKeys,
                      behavior: HitTestBehavior.opaque,
                      child: CLText.labelMedium(
                        Localized.text('ox_home.back_up_key_action'),
                        colorToken: ColorToken.primary,
                      ),
                    ),
                    SizedBox(width: 20.px),
                    GestureDetector(
                      // Hidden for this session only. The warning comes back,
                      // because the risk does not go away by being dismissed.
                      onTap: () => setState(() => _hiddenForNow = true),
                      behavior: HitTestBehavior.opaque,
                      child: CLText.labelMedium(
                        Localized.text('ox_home.back_up_key_later'),
                        colorToken: ColorToken.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
