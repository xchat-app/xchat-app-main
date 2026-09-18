import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/account_models.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/took_kit.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_common/utils/key_backup_state.dart';

class KeysPage extends StatefulWidget {

  const KeysPage({
    super.key,
    this.previousPageTitle,
  });

  final String? previousPageTitle;

  @override
  State<StatefulWidget> createState() {
    return _KeysPageState();
  }

}

class _KeysPageState extends State<KeysPage> {

  ValueNotifier<bool> isShowPriv$ = ValueNotifier(false);
  ValueNotifier<bool> isLoading$ = ValueNotifier(true);
  ValueNotifier<String> encodedPubkey$ = ValueNotifier('');
  ValueNotifier<String> encodedPrivkey$ = ValueNotifier('');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prepareData();
    });
  }

  Future prepareData() async {
    try {
      final account = LoginManager.instance.currentState.account;
      if (account == null) return;
      
      final pubkey = account.getEncodedPubkey();
      encodedPubkey$.value = pubkey;
      
      final privkey = await account.getEncodedPrivkey();
      encodedPrivkey$.value = privkey;
      isLoading$.value = false;
    } catch (e) {
      print('Error loading keys: $e');
      isLoading$.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_usercenter.keys'),
        previousPageTitle: widget.previousPageTitle,
      ),
      isSectionListPage: true,
      body: _body(),
    );
  }

  Widget _body() {
    return ValueListenableBuilder(
      valueListenable: isShowPriv$,
      builder: (context, isShowPriv, _) {
        return ValueListenableBuilder(
          valueListenable: isLoading$,
          builder: (context, isLoading, _) {
            return ValueListenableBuilder(
              valueListenable: encodedPubkey$,
              builder: (context, encodedPubkey, _) {
                return ValueListenableBuilder(
                  valueListenable: encodedPrivkey$,
                  builder: (context, encodedPrivkey, _) {
                    return CLSectionListView(
                      items: [
                        SectionListViewItem(
                          footer: Localized.text('ox_usercenter.public_key_description'),
                          data: [
                            CustomItemModel(
                              title: Localized.text('ox_login.public_key'),
                              subtitleWidget: CLText(
                                encodedPubkey.isNotEmpty ? encodedPubkey : 'Loading...',
                                maxLines: 2,
                              ),
                              trailing: encodedPubkey.isNotEmpty ? Icon(
                                Icons.copy_rounded,
                                color: ColorToken.onSecondaryContainer.of(context),
                              ) : CLProgressIndicator.circular(size: 16),
                              onTap: encodedPubkey.isNotEmpty ? pubkeyItemOnTap : null,
                            ),
                          ],
                        ),
                        SectionListViewItem(
                          footer: Localized.text('ox_usercenter.private_key_description'),
                          data: [
                            CustomItemModel(
                              title: Localized.text('ox_login.private_key'),
                              subtitleWidget: isLoading 
                                ? CLText(Localized.text('ox_common.loading'), maxLines: 2)
                                : CLText(
                                    isShowPriv ? encodedPrivkey
                                        : List.filled(encodedPrivkey.length, '*').join(),
                                    maxLines: 2,
                                  ),
                              trailing: isLoading 
                                ? CLProgressIndicator.circular(size: 16)
                                : Icon(
                                    Icons.copy_rounded,
                                    color: ColorToken.onSecondaryContainer.of(context),
                                  ),
                              onTap: !isLoading ? privkeyItemOnTap : null,
                            ),
                          ],
                        ),
                      ],
                      footer: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16.px, vertical: 16.px),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildShowButton(),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget buildShowButton() {
    return ValueListenableBuilder(
      valueListenable: isLoading$,
      builder: (context, isLoading, _) {
        return CLButton.tonal(
          height: 48,
          padding: EdgeInsets.symmetric(
            horizontal: 12.px,
            vertical: 12.px,
          ),
          expanded: true,
          text: Localized.text('ox_common.show_private_key'),
          onTap: isLoading ? null : () => isShowPriv$.value = true,
        );
      },
    );
  }

  void pubkeyItemOnTap () async {
    await TookKit.copyKey(
      context,
      encodedPubkey$.value,
    );
  }

  void privkeyItemOnTap() async {
    await TookKit.copyKey(
      context,
      encodedPrivkey$.value,
    );
    // Taking a copy is the only thing that makes an account recoverable, so
    // it is also what stops the home banner asking.
    await KeyBackupState.markBackedUp(
      LoginManager.instance.currentState.account?.pubkey ?? '',
    );
  }
}