import 'package:flutter/material.dart';
import 'package:ox_chat/utils/chat_session_utils.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/model/chat_type.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';

import '../contact_group_member_page.dart';
import 'group_add_members_page.dart';
import 'group_name_settings_page.dart';
import 'group_remove_members_page.dart';

import 'package:chatcore/chat-core.dart';

class GroupInfoPage extends StatefulWidget {
  final String groupId;

  GroupInfoPage({Key? key, required this.groupId}) : super(key: key);

  @override
  _GroupInfoPageState createState() => new _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  bool _isMute = false;
  List<UserDBISAR> groupMember = [];
  late ValueNotifier<GroupDBISAR> _groupNotifier;

  @override
  void initState() {
    super.initState();
    _groupNotifier = Groups.sharedInstance.getPrivateGroupNotifier(widget.groupId);
    _groupInfoInit();
    
    // Listen to group changes and update member list
    _groupNotifier.addListener(_onGroupChanged);
  }

  void _groupInfoInit() async {
    String groupId = widget.groupId;
    List<UserDBISAR>? groupList =
    await Groups.sharedInstance.getAllGroupMembers(groupId);

    setState(() {
      groupMember = groupList;
      _isMute = _groupNotifier.value.mute;
    });
  }

  void _onGroupChanged() {
    // Reload member list when group changes
    _groupInfoInit();
  }

  @override
  void dispose() {
    _groupNotifier.removeListener(_onGroupChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: Localized.text('ox_chat.group_info'),
      ),
      isSectionListPage: true,
      body: ValueListenableBuilder<GroupDBISAR>(
        valueListenable: _groupNotifier,
        builder: (context, groupInfo, child) {
          return CLSectionListView(
            header: _buildHeaderWidget(),
            items: [
              _buildGroupInfoSection(),
              _buildSettingsSection(),
              _buildDangerSection(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderWidget() {
    return ValueListenableBuilder<GroupDBISAR>(
      valueListenable: _groupNotifier,
      builder: (context, groupInfo, child) {
        return Column(
          children: [
            SizedBox(height: 16.px),
            // Group avatar or member avatars
            SmartGroupAvatar(
              group: groupInfo,
              size: 80.px,
            ),
            SizedBox(height: 6.px),
            // Group name
            CLText.titleLarge(
              groupInfo.name.isEmpty ? '--' : groupInfo.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            SizedBox(height: 16.px),
            // Action buttons
            _buildActionButtons(),
            SizedBox(height: 8.px),
          ],
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_isGroupOwner) ...[
          _buildActionButton(
            icon: Icons.person_add,
            label: Localized.text('ox_chat.add_member_title'),
            onTap: _addMembersFn,
          ),
          SizedBox(width: 24.px),
          _buildActionButton(
            icon: Icons.person_remove,
            label: Localized.text('ox_chat.remove_member_title'),
            onTap: _removeMembersFn,
          ),
        ],
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48.px,
            height: 48.px,
            decoration: BoxDecoration(
              color: ColorToken.surfaceContainer.of(context),
              borderRadius: BorderRadius.circular(24.px),
            ),
            child: CLIcon(
              icon: icon,
              size: 24.px,
              color: ColorToken.onSurface.of(context),
            ),
          ),
          SizedBox(height: 4.px),
          CLText.labelSmall(
            label,
            colorToken: ColorToken.onSurfaceVariant,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  SectionListViewItem _buildGroupInfoSection() {
    return SectionListViewItem(
      data: [
        LabelItemModel(
          title: Localized.text('ox_chat.group_name'),
          value$: ValueNotifier(_groupNotifier.value.name.isEmpty ? '--' : _groupNotifier.value.name),
          onTap: _isGroupOwner ? _updateGroupNameFn : null,
        ),
        CustomItemModel(
          title: Localized.text('ox_chat.group_member'),
          titleWidget: CLText.bodyLarge(Localized.text('ox_chat.group_member')),
          trailing: FutureBuilder<List<UserDBISAR>>(
            future: Groups.sharedInstance.getAllGroupMembers(_groupNotifier.value.privateGroupId),
            builder: (context, snapshot) {
              final memberCount = snapshot.data?.length ?? groupMember.length;
              return CLText.bodyMedium(
                '$memberCount',
                colorToken: ColorToken.onSurfaceVariant,
              );
            },
          ),
          isCupertinoAutoTrailing: true,
          onTap: () => _memberItemOnTap(),
        ),
      ],
    );
  }

  SectionListViewItem _buildSettingsSection() {
    final muteNotifier = ValueNotifier(_isMute);
    muteNotifier.addListener(() {
      _changeMuteFn(muteNotifier.value);
    });
    
    return SectionListViewItem(
      data: [
        SwitcherItemModel(
          title: Localized.text('ox_chat.mute_item'),
          value$: muteNotifier,
        ),
      ],
    );
  }

  SectionListViewItem _buildDangerSection() {
    String buttonText = _isGroupOwner 
        ? Localized.text('ox_chat.delete_and_leave_item')
        : Localized.text('ox_chat.str_leave_group');
    
    return SectionListViewItem(
      data: [
        CustomItemModel(
          customWidgetBuilder: (context) => GestureDetector(
            onTap: () {
              ChatSessionUtils.leaveConfirmWidget(
                context, 
                ChatType.chatGroup, 
                widget.groupId, 
                isGroupOwner: _isGroupOwner,
              );
            },
            child: Container(
              width: double.infinity,
              height: 48.px,
              decoration: BoxDecoration(
                color: ColorToken.surface.of(context),
                borderRadius: BorderRadius.circular(12.px),
              ),
              alignment: Alignment.center,
              child: CLText.bodyLarge(
                buttonText,
                colorToken: ColorToken.error,
              ),
            ),
          ),
        ),
      ],
    );
  }

  bool get _isGroupOwner {
    UserDBISAR? userInfo = Account.sharedInstance.me;
    if (userInfo == null) return false;

    return userInfo.pubKey == _groupNotifier.value.owner;
  }

  bool get _isGroupMember {
    UserDBISAR? userInfo = Account.sharedInstance.me;
    if (userInfo == null || groupMember.length == 0) return false;
    bool hasMember =
        groupMember.any((userDB) => userDB.pubKey == userInfo.pubKey);
    return hasMember;
  }

  void _updateGroupNameFn() async {
    if (!_isGroupOwner) return;

    OXNavigator.pushPage(
      context,
      (context) => GroupNameSettingsPage(
        groupInfo: _groupNotifier.value,
        previousPageTitle: Localized.text('ox_chat.group_info'),
      ),
    );
  }

  void _addMembersFn() async {
    if (!_isGroupOwner) return;
    
    OXNavigator.pushPage(
      context,
      (context) => GroupAddMembersPage(
        groupInfo: _groupNotifier.value,
        previousPageTitle: Localized.text('ox_chat.group_info'),
      ),
    );
  }

  void _removeMembersFn() async {
    if (!_isGroupOwner) return;
    
    OXNavigator.pushPage(
      context,
      (context) => GroupRemoveMembersPage(
        groupInfo: _groupNotifier.value,
        previousPageTitle: Localized.text('ox_chat.group_info'),
      ),
    );
  }

  void _memberItemOnTap() async {
    if (!_isGroupMember) return;
    OXNavigator.pushPage(
      context, (context) => ContactGroupMemberPage(
        groupId: widget.groupId,
      ),
    );
  }

  void _changeMuteFn(bool value) async {
    if (!_isGroupMember) {
      CommonToast.instance.show(context, Localized.text('ox_chat.group_mute_no_member_toast'));
      return;
    }
    if (value) {
      await Groups.sharedInstance.muteGroup(widget.groupId);
      CommonToast.instance.show(context, Localized.text('ox_chat.group_mute_operate_success_toast'));
    } else {
      await Groups.sharedInstance.unMuteGroup(widget.groupId);
      CommonToast.instance.show(context, Localized.text('ox_chat.group_mute_operate_success_toast'));
    }
    setState(() {
      _isMute = value;
    });
  }
}
