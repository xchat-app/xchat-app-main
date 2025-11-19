import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:ox_common/component.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_usercenter/utils/app_config_helper.dart';

class AdvancedSettingsPage extends StatefulWidget {
  const AdvancedSettingsPage({
    super.key,
    this.previousPageTitle,
  });

  final String? previousPageTitle;

  @override
  State<AdvancedSettingsPage> createState() => _AdvancedSettingsPageState();
}

class _AdvancedSettingsPageState extends State<AdvancedSettingsPage> {
  late ValueNotifier<bool> showMessageInfoOption$;

  @override
  void initState() {
    super.initState();
    // Notifier is cached in AppConfigHelper, no need to dispose
    showMessageInfoOption$ = AppConfigHelper.showMessageInfoOptionNotifier();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_usercenter.advanced_settings'),
        previousPageTitle: widget.previousPageTitle,
      ),
      isSectionListPage: true,
      body: CLSectionListView(
        items: [
          SectionListViewItem(
            data: [
              SwitcherItemModel(
                icon: ListViewIcon.data(CupertinoIcons.info),
                title: Localized.text('ox_usercenter.show_message_info_option'),
                value$: showMessageInfoOption$,
                onChanged: (value) async {
                  await AppConfigHelper.updateShowMessageInfoOption(value);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}