import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/circle_join_utils.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/utils/extension.dart';
import 'package:ox_common/utils/font_size_notifier.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_theme/ox_theme.dart';
import 'package:ox_usercenter/page/settings/language_settings_page.dart';
import 'package:ox_usercenter/page/settings/theme_settings_page.dart';
import 'package:ox_usercenter/page/settings/notification_settings_page.dart';
import 'package:ox_usercenter/page/settings/about_xchat_page.dart';

import 'keys_page.dart';
import 'circle_detail_page.dart';
import 'font_size_settings_page.dart';
import 'profile_settings_page.dart';
import 'qr_code_display_page.dart';

/// Logout options for user selection
enum LogoutOption {
  logout,
  deleteAccount,
}

class SettingSlider extends StatefulWidget {
  const SettingSlider({super.key});

  @override
  State<StatefulWidget> createState() => SettingSliderState();
}

class SettingSliderState extends State<SettingSlider> {

  String get title => Localized.text('ox_usercenter.str_settings');

  late ValueNotifier themeItemNty;
  late ValueNotifier languageItemNty;
  late ValueNotifier textSizeItemNty;

  late LoginUserNotifier userNotifier;
  late List<SectionListViewItem> pageData;

  @override
  void initState() {
    super.initState();

    prepareData();

    languageItemNty.addListener(() {
      // Update label notifier when language changed.
      themeItemNty.value = themeManager.themeStyle.text;
      prepareLiteData();
    });
  }

  void prepareData() {
    prepareNotifier();
    prepareLiteData();
    userNotifier = LoginUserNotifier.instance;
  }

  void prepareNotifier() {
    themeItemNty = themeManager.styleNty.map((style) => style.text);
    languageItemNty = Localized.localized.localeTypeNty.map((type) => type.languageText);
    textSizeItemNty = textScaleFactorNotifier.map((scale) => getFormattedTextSize(scale));
  }

  void prepareLiteData() {
    final hasCircle = LoginManager.instance.currentCircle != null;
    
    // Build first section items
    List<ListViewItem> firstSectionItems = [
      CustomItemModel(
        customWidgetBuilder: buildUserInfoWidget,
      ),
      // LabelItemModel(
      //   style: ListViewItemStyle.theme,
      //   icon: ListViewIcon(iconName: 'icon_setting_add.png', package: 'ox_usercenter'),
      //   title: 'My Circles',
      //   valueNty: ValueNotifier('Upgrade'),
      // ),
      LabelItemModel(
        icon: ListViewIcon(iconName: 'icon_setting_security.png', package: 'ox_usercenter'),
        title: Localized.text('ox_usercenter.keys'),
        onTap: keysItemOnTap,
      ),
      LabelItemModel(
        icon: ListViewIcon.data(Icons.share),
        title: Localized.text('ox_usercenter.invite'),
        onTap: inviteItemOnTap,
      ),
    ];
    
    // Only add circle settings when user has a circle
    if (hasCircle) {
      firstSectionItems.add(
        LabelItemModel(
          icon: ListViewIcon(iconName: 'icon_setting_circles.png', package: 'ox_usercenter'),
          title: Localized.text('ox_usercenter.circle_settings'),
          onTap: circleItemOnTap,
        ),
      );
    }
    
    pageData = [
      SectionListViewItem(data: firstSectionItems),
      // SectionListViewItem(data: [
      //   LabelItemModel(
      //     icon: ListViewIcon(iconName: 'icon_setting_contact.png', package: 'ox_usercenter'),
      //     title: 'Contact',
      //     valueNty: ValueNotifier('23'),
      //   ),
      //   LabelItemModel(
      //     icon: ListViewIcon(iconName: 'icon_setting_security.png', package: 'ox_usercenter'),
      //     title: 'Private and Security',
      //   ),
      // ]),
      SectionListViewItem(data: [
        LabelItemModel(
          icon: ListViewIcon(iconName: 'icon_setting_notification.png', package: 'ox_usercenter'),
          title: Localized.text('ox_usercenter.notification'),
          onTap: notificationItemOnTap,
        ),
        LabelItemModel(
          icon: ListViewIcon(iconName: 'icon_setting_theme.png', package: 'ox_usercenter'),
          title: Localized.text('ox_usercenter.theme'),
          value$: themeItemNty,
          onTap: themeItemOnTap,
        ),
        LabelItemModel(
          icon: ListViewIcon(iconName: 'icon_setting_lang.png', package: 'ox_usercenter'),
          title: Localized.text('ox_usercenter.language'),
          value$: languageItemNty,
          onTap: languageItemOnTap,
        ),
        LabelItemModel(
          icon: ListViewIcon(iconName: 'icon_setting_textsize.png', package: 'ox_usercenter'),
          title: Localized.text('ox_usercenter.text_size'),
          value$: textSizeItemNty,
          onTap: textSizeItemOnTap,
        ),
        // LabelItemModel(
        //   icon: ListViewIcon(iconName: 'icon_setting_sound.png', package: 'ox_usercenter'),
        //   title: 'Sound',
        //   valueNty: ValueNotifier('Default'),
        // ),
        LabelItemModel(
          icon: ListViewIcon.data(CupertinoIcons.info),
          title: Localized.text('ox_usercenter.about_xchat'),
          onTap: aboutXChatItemOnTap,
        ),
      ]),
      SectionListViewItem.button(
        text: Localized.text('ox_usercenter.Logout'),
        onTap: logoutItemOnTap,
        type: ButtonType.destructive,
      )
    ];
  }

  @override
  void dispose() {
    languageItemNty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: PlatformStyle.isUseMaterial ? null : CLAppBar(title: title),
      isSectionListPage: true,
      body: buildBody(),
    );
  }

  Widget buildBody() {
    return ValueListenableBuilder(
      valueListenable: LoginManager.instance.state$,
      builder: (context, loginState, _) {
        // Rebuild data when circle state changes
        prepareLiteData();
        return CLSectionListView(
          items: pageData,
        );
      },
    );
  }

  Widget buildUserInfoWidget(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LoginManager.instance.state$,
      builder: (context, loginState, _) {
        final circle = loginState.currentCircle;
        final hasCircle = circle != null;
        
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: profileItemOnTap,
          child: Container(
            height: 72.px,
            margin: EdgeInsets.symmetric(vertical: 12.px),
            child: Row(
              children: [
                // Avatar area
                Container(
                  width: 60.px,
                  height: 60.px,
                  margin: EdgeInsets.symmetric(horizontal: CLLayout.horizontalPadding),
                  child: hasCircle
                    ? ValueListenableBuilder(
                        valueListenable: userNotifier.avatarUrl$,
                        builder: (context, avatarUrl, _) {
                          return OXUserAvatar(
                            imageUrl: avatarUrl,
                            size: 60.px,
                          );
                        }
                      )
                    : CircleAvatar(
                        radius: 30.px,
                        backgroundColor: ColorToken.surfaceContainer.of(context),
                        child: Icon(
                          CupertinoIcons.person,
                          size: 30.px,
                          color: ColorToken.onSurfaceVariant.of(context),
                        ),
                      ),
                ),
                // Content area
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: hasCircle
                      ? [
                          // Show actual user info when logged in circle
                          ValueListenableBuilder(
                            valueListenable: userNotifier.name$,
                            builder: (context, name, _) {
                              return CLText.bodyLarge(name);
                            }
                          ),
                          ValueListenableBuilder(
                            valueListenable: userNotifier.encodedPubkey$,
                            builder: (context, encodedPubkey, _) {
                              return CLText.bodyMedium(encodedPubkey.truncate(20));
                            }
                          ),
                        ]
                      : [
                          // Show guide info when no circle
                          CLText.bodyLarge(
                            Localized.text('ox_usercenter.profile'),
                          ),
                          CLText.bodyMedium(
                            Localized.text('ox_home.join_or_create_circle_now'),
                          ),
                        ],
                  ),
                ),
                // Trailing
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: CLListTile.buildDefaultTrailing(profileItemOnTap),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void keysItemOnTap() {
    OXNavigator.pushPage(context, (_) => KeysPage(previousPageTitle: title,));
  }

  void inviteItemOnTap() {
    final circle = LoginManager.instance.currentCircle;
    if (circle == null) {
      CircleJoinUtils.showJoinCircleGuideDialog(context: OXNavigator.rootContext);
      return;
    }
    
    OXNavigator.pushPage(
      context, 
      (context) => QRCodeDisplayPage(previousPageTitle: title),
    );
  }

  void circleItemOnTap() {
    final circle = LoginManager.instance.currentCircle;
    if (circle == null) return;

    OXNavigator.pushPage(context, (_) => CircleDetailPage(
      previousPageTitle: title,
      circle: circle,
    ));
  }

  void profileItemOnTap() {
    final circle = LoginManager.instance.currentCircle;
    if (circle == null) {
      CircleJoinUtils.showJoinCircleGuideDialog(context: OXNavigator.rootContext);
      return;
    }
    
    OXNavigator.pushPage(context, (_) => ProfileSettingsPage(previousPageTitle: title,));
  }

  void themeItemOnTap() {
    OXNavigator.pushPage(context, (_) => ThemeSettingsPage(previousPageTitle: title,));
  }

  void notificationItemOnTap() {
    OXNavigator.pushPage(context, (_) => NotificationSettingsPage(previousPageTitle: title,));
  }

  void languageItemOnTap() {
    OXNavigator.pushPage(context, (_) => LanguageSettingsPage(previousPageTitle: title,));
  }

  void textSizeItemOnTap() {
    OXNavigator.pushPage(context, (_) => FontSizeSettingsPage(previousPageTitle: title,));
  }

  void aboutXChatItemOnTap() {
    OXNavigator.pushPage(context, (_) => AboutXChatPage(previousPageTitle: title,));
  }

  void logoutItemOnTap() async {
    // Show picker with logout options
    final logoutOption = await CLPicker.show<LogoutOption>(
      context: context,
      items: [
        CLPickerItem<LogoutOption>(
          label: Localized.text('ox_usercenter.Logout'),
          value: LogoutOption.logout,
        ),
        CLPickerItem<LogoutOption>(
          label: Localized.text('ox_usercenter.delete_account'),
          value: LogoutOption.deleteAccount,
          isDestructive: true,
        ),
      ],
    );

    if (logoutOption == null) return;

    switch (logoutOption) {
      case LogoutOption.logout:
        await _confirmLogout();
        break;
      case LogoutOption.deleteAccount:
        await _confirmDeleteAccount();
        break;
    }
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.warn_title'),
      content: Localized.text('ox_usercenter.sign_out_dialog_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_usercenter.Logout'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );

    if (shouldLogout == true) {
      try {
        await LoginManager.instance.logout();
        OXNavigator.popToRoot(context);
      } catch (e) {
        CommonToast.instance.show(context, e.toString());
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final shouldDelete = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.delete_account_confirm_title'),
      content: Localized.text('ox_usercenter.delete_account_confirm_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_usercenter.delete_account_confirm'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );

    if (shouldDelete == true) {
      OXLoading.show();
      try {
        final success = await LoginManager.instance.deleteAccount();
        OXLoading.dismiss();
        
        if (success) {
          OXNavigator.popToRoot(context);
        } else {
          CommonToast.instance.show(context, Localized.text('ox_usercenter.delete_account_failed'));
        }
      } catch (e) {
        OXLoading.dismiss();
        CommonToast.instance.show(context, '${Localized.text('ox_usercenter.delete_account_failed')}: $e');
      }
    }
  }
}
