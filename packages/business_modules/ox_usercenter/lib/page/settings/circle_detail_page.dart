import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';

import 'file_server_page.dart';
import 'profile_settings_page.dart';

enum _MenuAction { edit, delete }

class CircleDetailPage extends StatelessWidget {
  const CircleDetailPage({
    super.key,
    required this.circle,
    this.previousPageTitle,
    this.description = '',
  });

  final Circle circle;

  final String? previousPageTitle;

  final String description;

  String get title => Localized.text('ox_usercenter.circle_settings');

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        previousPageTitle: previousPageTitle,
        title: title,
        actions: [_buildMenuButton(context)],
        backgroundColor: ColorToken.primaryContainer.of(context),
      ),
      body: CLSectionListView(
        padding: EdgeInsets.zero,
        items: [
          SectionListViewItem(
            headerWidget: _buildHeader(context),
            data: _buildMainItems(context),
          ),
        ],
      ),
      isSectionListPage: true,
    );
  }

  Widget _buildMenuButton(BuildContext context) {
    return CLButton.icon(
      icon: CupertinoIcons.ellipsis,
      onTap: () async {
        final action = await CLPicker.show<_MenuAction>(
          context: context,
          items: [
            // CLPickerItem(label: Localized.text('ox_usercenter.edit_profile'), value: _MenuAction.edit),
            CLPickerItem(
              label: Localized.text('ox_usercenter.delete_circle'),
              value: _MenuAction.delete,
              isDestructive: true,
            ),
          ],
        );
        if (action != null) {
          _handleMenuAction(context, action);
        }
      },
    );
  }

  void _handleMenuAction(BuildContext context, _MenuAction action) {
    switch (action) {
      case _MenuAction.edit:
        OXNavigator.pushPage(context, (_) =>
            ProfileSettingsPage(previousPageTitle: title));
        break;
      case _MenuAction.delete:
        _confirmDelete(context);
        break;
    }
  }

  void _confirmDelete(BuildContext context) async {
    final bool? confirmed = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.delete_circle_confirm_title'),
      content: Localized.text('ox_usercenter.delete_circle_confirm_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_usercenter.delete_circle'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );

    if (confirmed == true) {
      try {
        await LoginManager.instance.deleteCircle(circle.id);
      } catch (e) {
        CommonToast.instance.show(context, e.toString());
      }
      OXNavigator.popToRoot(context);
    }
  }

  Widget _buildHeader(BuildContext context) {
    final description = this.description.orDefault(
        Localized.text('ox_usercenter.circle_description_placeholder'));
    return Container(
      color: PlatformStyle.isUseMaterial
          ? ColorToken.primaryContainer.of(context)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 8.px),
      
          CircleAvatar(
            radius: 40.px,
            backgroundColor: ColorToken.onPrimary.of(context),
            child: CLText.titleLarge(
              circle.name.isNotEmpty ? circle.name[0].toUpperCase() : '?',
            ),
          ),
      
          SizedBox(height: 12.px),

          CLText.titleLarge(circle.name, textAlign: TextAlign.center,),
      
          SizedBox(height: 12.px),
      
          // Padding(
          //   padding: EdgeInsets.symmetric(
          //     horizontal: PlatformStyle.isUseMaterial
          //         ? 24.px
          //         : 4.px,
          //     vertical: 12.px,
          //   ),
          //   child: Column(
          //     mainAxisSize: MainAxisSize.min,
          //     crossAxisAlignment: CrossAxisAlignment.stretch,
          //     children: [
          //       CLText.bodyLarge(Localized.text('ox_chat.description')),
          //       CLText.bodyMedium(description),
          //     ],
          //   ),
          // ),
        ],
      ),
    );
  }

  List<ListViewItem> _buildMainItems(BuildContext context) {
    return [
      // My Avatar in Circle
      // CustomItemModel(
      //   leading: const Icon(CupertinoIcons.person_crop_circle),
      //   titleWidget: CLText(Localized.text('ox_usercenter.my_avatar_in_circle')),
      //   trailing: OXUserAvatar(
      //     user: Account.sharedInstance.me,
      //     size: 32.px,
      //   ),
      //   onTap: () {
      //     OXNavigator.pushPage(context, (_) =>
      //         ProfileSettingsPage(previousPageTitle: title));
      //   },
      //   isCupertinoAutoTrailing: true,
      // ),
      // Relay Server
      LabelItemModel(
        icon: ListViewIcon.data(CupertinoIcons.antenna_radiowaves_left_right),
        title: Localized.text('ox_usercenter.relay_server'),
        value$: ValueNotifier(circle.relayUrl),
        onTap: null,
      ),
      // File Server Setting (Server Settings)
      CustomItemModel(
        leading: const Icon(CupertinoIcons.settings),
        titleWidget: CLText(Localized.text('ox_usercenter.file_server_setting')),
        onTap: () {
          OXNavigator.pushPage(context, (_) => FileServerPage(
            previousPageTitle: title,
          ));
        },
      ),
    ];
  }
}