import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/login/circle_service.dart';
import 'package:ox_common/login/circle_repository.dart';
import 'package:ox_common/circle/page/circle_expired_prompt_dialog.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/widgets/common_loading.dart' as Loading;
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_common/utils/file_server_helper.dart';
import 'package:ox_common/repository/file_server_repository.dart';
import 'package:ox_common/log_util.dart';
import 'package:ox_module_service/ox_module_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:ox_login/ox_login.dart';

import 'file_server_page.dart';
import 'call_server_page.dart';
import 'profile_settings_page.dart';
import 'qr_code_display_page.dart';
import '../../utils/invite_link_manager.dart';

enum _MenuAction { edit, delete }
enum _PlanAction { changePlan, cancelSubscription, renewPlan }
enum _StorageAction { clearAllStorage }

/// Placeholder when subscription status is loading or unknown. Avoids showing
/// optimistic "renews on" which would flash to "expired" after server response.
const String _kSubscriptionUnknownPlaceholder = '—';

/// Display data derived from TenantInfo or cache map. Single source: state$ or cache.
class _TenantDisplayData {
  const _TenantDisplayData({
    required this.isOwner,
    required this.renewDateText,
    required this.subscriptionStatus,
    required this.currentMembers,
    required this.maxMembers,
    required this.memberPubkeys,
  });

  final bool isOwner;
  final String renewDateText;
  final String? subscriptionStatus;
  final int currentMembers;
  final int maxMembers;
  final List<String> memberPubkeys;

  static _TenantDisplayData fromTenantInfo(TenantInfo info, String currentPubkey) {
    final isOwner = info.tenantAdminPubkey.toLowerCase() == currentPubkey.toLowerCase();
    String renewDateText = _kSubscriptionUnknownPlaceholder;
    if (info.expiresAt != null && info.expiresAt! > 0) {
      try {
        final date = DateTime.fromMillisecondsSinceEpoch(info.expiresAt! * 1000);
        renewDateText = DateFormat('MMM d, yyyy').format(date);
      } catch (_) {}
    }
    String? status = info.status.isNotEmpty ? info.status : null;
    if (status == null && info.expiresAt != null && info.expiresAt! > 0) {
      try {
        final expiresDate = DateTime.fromMillisecondsSinceEpoch(info.expiresAt! * 1000);
        status = expiresDate.isBefore(DateTime.now()) ? 'expired' : 'active';
      } catch (_) {}
    }
    final pubkeys = info.members.map((m) => m.pubkey).where((p) => p.isNotEmpty).toList();
    return _TenantDisplayData(
      isOwner: isOwner,
      renewDateText: renewDateText,
      subscriptionStatus: status,
      currentMembers: info.currentMembers,
      maxMembers: info.maxMembers,
      memberPubkeys: pubkeys,
    );
  }

  static _TenantDisplayData? fromMap(Map<String, dynamic> map, String currentPubkey, {bool fromCache = false}) {
    final tenantAdminPubkey = map['tenant_admin_pubkey'] as String?;
    final isOwner = tenantAdminPubkey != null && tenantAdminPubkey.isNotEmpty
        ? tenantAdminPubkey.toLowerCase() == currentPubkey.toLowerCase()
        : false;
    String renewDateText = _kSubscriptionUnknownPlaceholder;
    final expiresAt = map['expires_at'] as int?;
    if (expiresAt != null && expiresAt > 0) {
      try {
        final date = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
        renewDateText = DateFormat('MMM d, yyyy').format(date);
      } catch (_) {}
    }
    String? subscriptionStatus = map['subscription_status'] as String? ?? map['status'] as String?;
    if (subscriptionStatus == null || subscriptionStatus.isEmpty) {
      if (expiresAt != null && expiresAt > 0) {
        try {
          final expiresDate = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
          subscriptionStatus = expiresDate.isBefore(DateTime.now()) ? 'expired' : 'active';
          if (fromCache && subscriptionStatus == 'expired') subscriptionStatus = null;
        } catch (_) {}
      }
    } else if (fromCache && subscriptionStatus == 'expired') {
      subscriptionStatus = null;
    }
    final currentMembers = map['current_members'] as int? ?? 0;
    final maxMembers = map['max_members'] as int? ?? 100;
    final membersData = map['members'] as List<dynamic>? ?? [];
    final pubkeys = <String>[];
    for (final m in membersData) {
      if (m is Map<String, dynamic>) {
        final p = m['pubkey'] as String?;
        if (p != null && p.isNotEmpty) pubkeys.add(p);
      }
    }
    return _TenantDisplayData(
      isOwner: isOwner,
      renewDateText: renewDateText,
      subscriptionStatus: subscriptionStatus,
      currentMembers: currentMembers,
      maxMembers: maxMembers,
      memberPubkeys: pubkeys,
    );
  }
}

class CircleDetailPage extends StatefulWidget {
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
  State<CircleDetailPage> createState() => _CircleDetailPageState();
}

class _CircleDetailPageState extends State<CircleDetailPage>
    with WidgetsBindingObserver {
  /// Display name: from state$ when this is current circle, else widget.circle.name.
  String get _displayCircleName {
    final state = LoginManager.instance.currentState;
    if (state.currentCircle?.id == widget.circle.id && state.currentCircle != null) {
      return state.currentCircle!.name;
    }
    return widget.circle.name;
  }

  late ValueNotifier<String> _fileServerName$;
  /// Cache for first-paint when state.currentCircle.tenantInfo not yet loaded. Loaded once.
  late Future<Map<String, dynamic>?> _cachedTenantInfoFuture;
  /// Whether current user is admin for this circle (resolved async; default false to avoid showing edit to non-admins on first frame).
  bool _isCircleAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fileServerName$ = ValueNotifier<String>('');
    _cachedTenantInfoFuture = _loadCachedTenantInfo();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadLocalData();
      _loadSubscriptionInfo();
      _loadFileServerInfo();
      CircleExpiredPromptDialog.resolveIsAdmin(widget.circle).then((isAdmin) {
        if (mounted) setState(() => _isCircleAdmin = isAdmin);
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fileServerName$.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshCircleInfo();
    }
  }

  /// Refresh circle info when app returns from background.
  Future<void> _refreshCircleInfo() async {
    _loadLocalData();
    await _loadSubscriptionInfo();
    _loadFileServerInfo();
  }

  /// Check if this circle is a paid relay (based on relayUrl matching privateRelayApiBaseUrl)
  bool _isPaidRelay() {
    return CircleApi.isPaidRelay(widget.circle.relayUrl);
  }

  /// Load local data first (for paid relays, UI comes from _loadSubscriptionInfo only)
  Future<void> _loadLocalData() async {}

  /// Load cached tenant info: mem (state) when current circle, else store; via LoginManager.
  Future<Map<String, dynamic>?> _loadCachedTenantInfo() async {
    try {
      return await LoginManager.instance.getCachedTenantInfoForCircle(widget.circle.id);
    } catch (e) {
      LogUtil.w(() => 'Failed to load cached tenant info: $e');
      return null;
    }
  }

  Future<void> _loadSubscriptionInfo() async {
    if (!_isPaidRelay()) return;

    if (widget.circle.category != CircleCategory.paid) {
      await _updateCircleCategory(CircleCategory.paid);
    }

    if (LoginManager.instance.currentCircle?.id == widget.circle.id) {
      try {
        await LoginManager.instance.refreshCircleFromRemote();
      } catch (e) {
        LogUtil.w(() => 'Failed to refresh circle info: $e');
      }
    }
  }

  /// Update circle category in account-level database
  Future<void> _updateCircleCategory(CircleCategory category) async {
    try {
      final loginManager = LoginManager.instance;
      final account = loginManager.currentState.account;
      if (account == null) return;

      // Find the circle in account circles
      final circleIndex = account.circles.indexWhere((c) => c.id == widget.circle.id);
      if (circleIndex == -1) return;

      // Update category
      account.circles[circleIndex].category = category;

      // Save to account database
      final accountDb = account.db;
      final success = await CircleRepository.update(accountDb, account.circles[circleIndex]);
      if (success) {
        LogUtil.v(() => 'Updated circle category to $category for circle: ${widget.circle.id}');
        // Update LoginManager state to reflect the change
        loginManager.updateStateAccount(account);
      }
    } catch (e) {
      LogUtil.w(() => 'Failed to update circle category: $e');
    }
  }
  
  Future<void> _loadFileServerInfo() async {
    final selectedUrl = widget.circle.selectedFileServerUrl;
    String displayName = '';
    
    if (FileServerHelper.isDefaultFileServerGroupSelected(selectedUrl)) {
      displayName = Localized.text('ox_usercenter.default_file_server_group');
    } else {
      try {
        final repo = FileServerRepository(DBISAR.sharedInstance.isar);
        final servers = repo.fetch();
        final matched = servers.firstWhere((e) => e.url == selectedUrl);
        displayName = matched.name.isNotEmpty ? matched.name : matched.url;
      } catch (e) {
        displayName = selectedUrl;
      }
    }
    
    _fileServerName$.value = displayName;
  }

  /// Derive display data from state$ (when current circle) or cache (first-paint / non-current).
  _TenantDisplayData? _tenantDisplayData(LoginState state, Map<String, dynamic>? cache) {
    final currentPubkey = LoginManager.instance.currentPubkey;
    final isCurrentCircle = state.currentCircle?.id == widget.circle.id;
    if (isCurrentCircle && state.currentCircle?.tenantInfo != null) {
      return _TenantDisplayData.fromTenantInfo(state.currentCircle!.tenantInfo!, currentPubkey);
    }
    if (cache != null) {
      return _TenantDisplayData.fromMap(cache, currentPubkey, fromCache: true);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        previousPageTitle: widget.previousPageTitle,
        title: widget.title,
        actions: [_buildMenuButton(context)],
        backgroundColor: ColorToken.primaryContainer.of(context),
      ),
      body: ValueListenableBuilder<LoginState>(
        valueListenable: LoginManager.instance.state$,
        builder: (context, state, _) {
          return FutureBuilder<Map<String, dynamic>?>(
            future: _cachedTenantInfoFuture,
            builder: (context, cacheSnap) {
              final displayData = _tenantDisplayData(state, cacheSnap.data);
              return _CircleDetailBody(
                displayData: displayData,
                circle: widget.circle,
                parent: this,
              );
            },
          );
        },
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
            ProfileSettingsPage(previousPageTitle: widget.title));
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
        await LoginManager.instance.deleteCircle(widget.circle.id);
      } catch (e) {
        CommonToast.instance.show(context, e.toString());
      }
      OXNavigator.popToRoot(context);
    }
  }

  Widget _buildHeader(BuildContext context) {
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
              _displayCircleName.isNotEmpty ? _displayCircleName[0].toUpperCase() : '?',
            ),
          ),
      
          SizedBox(height: 12.px),

          _isCircleAdmin
              ? GestureDetector(
                  onTap: () => _editCircleName(context),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: CLText.titleLarge(
                          _displayCircleName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 8.px),
                      Icon(
                        CupertinoIcons.create_solid,
                        size: 18.px,
                        color: ColorToken.onSurfaceVariant.of(context),
                      ),
                    ],
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: CLText.titleLarge(
                        _displayCircleName,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

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

  Future<void> _editCircleName(BuildContext context) async {
    await CLDialog.showInputDialog(
      context: context,
      title: Localized.text('ox_usercenter.edit_circle_name'),
      inputLabel: Localized.text('ox_usercenter.circle_name'),
      initialValue: _displayCircleName,
      onConfirm: (newName) async {
        if (newName.trim().isEmpty) {
          CommonToast.instance.show(context, Localized.text('ox_common.input_cannot_be_empty'));
          return false;
        }
        
        if (newName.trim() == _displayCircleName) {
          return true; // No change needed
        }

        try {
          Loading.OXLoading.show();
          
          final trimmedName = newName.trim();
          
          // If this is a paid relay, update tenant name on server first
          if (_isPaidRelay()) {
            try {
              await CircleMemberService.sharedInstance.updateTenant(
                name: trimmedName,
              );
              // After successful server update, reload tenant info to sync local cache
              // This will update CircleDBISAR and UI
              await _loadSubscriptionInfo();
            } catch (e) {
              Loading.OXLoading.dismiss();
              LogUtil.e(() => 'Failed to update tenant name on server: $e');
              final errorMessage = e.toString().replaceFirst('Exception: ', '');
              CommonToast.instance.show(
                context,
                errorMessage.isNotEmpty 
                    ? errorMessage 
                    : Localized.text('ox_common.operation_failed'),
              );
              return false;
            }
          }
          
          // Update account-level Circle object in local database
          final updatedCircle = await CircleService.updateCircleName(
            widget.circle.id,
            trimmedName,
          );

          if (updatedCircle == null) {
            Loading.OXLoading.dismiss();
            CommonToast.instance.show(context, Localized.text('ox_common.operation_failed'));
            return false;
          }

          Loading.OXLoading.dismiss();
          setState(() {}); // Rebuild so _displayCircleName reflects state / updated circle.

          return true;
        } catch (e) {
          Loading.OXLoading.dismiss();
          // Show detailed error message
          final errorMessage = e.toString().replaceFirst('Exception: ', '');
          CommonToast.instance.show(context, errorMessage.isNotEmpty ? errorMessage : Localized.text('ox_common.operation_failed'));
          return false;
        }
      },
    );
  }

  List<SectionListViewItem> _buildMainItems(
    BuildContext context,
    _TenantDisplayData? displayData,
    List<UserDBISAR>? resolvedMembers,
  ) {
    final items = <SectionListViewItem>[];
    
    if (!_isPaidRelay()) {
      items.add(
        SectionListViewItem(
          footer: Localized.text('ox_usercenter.relay_server_description'),
          data: [
            LabelItemModel(
              icon: ListViewIcon.data(CupertinoIcons.antenna_radiowaves_left_right),
              title: Localized.text('ox_usercenter.relay_server'),
              subtitle: widget.circle.relayUrl,
              onTap: null,
            ),
            LabelItemModel(
              icon: ListViewIcon.data(CupertinoIcons.settings),
              title: Localized.text('ox_usercenter.file_server_setting'),
              onTap: () {
                OXNavigator.pushPage(context, (_) => FileServerPage(
                  previousPageTitle: widget.title,
                  readOnlyForPaidCircle: _isPaidRelay(),
                )).then((_) {
                  _loadFileServerInfo();
                });
              },
            ),
            LabelItemModel(
              icon: ListViewIcon.data(CupertinoIcons.phone),
              title: Localized.text('ox_usercenter.call_server'),
              onTap: () {
                OXNavigator.pushPage(context, (_) => CallServerPage(
                  previousPageTitle: widget.title,
                ));
              },
            ),
          ],
        ),
      );
    }

    // Subscription section: owner only
    if (displayData != null && displayData.isOwner) {
      items.add(_buildSubscriptionSection(context, displayData));
    }
    // Members section: all members for paid relay (invite/remove only when owner)
    if (_isPaidRelay() && displayData != null) {
      items.add(_buildMembersSection(context, displayData, resolvedMembers ?? []));
    }

    return items;
  }

  SectionListViewItem _buildSubscriptionSection(BuildContext context, _TenantDisplayData displayData) {
    final status = displayData.subscriptionStatus;
    final renewDate = displayData.renewDateText;
    return SectionListViewItem(
      header: Localized.text('ox_usercenter.subscription_and_usage'),
      data: [
        CustomItemModel(
          icon: ListViewIcon.data(Icons.diamond_rounded),
          title: Localized.text('ox_usercenter.plan'),
          subtitleWidget: Builder(
            builder: (context) {
              if (status == 'active') {
                return Row(
                  children: [
                    Expanded(
                      child: CLText.bodySmall(
                        Localized.text('ox_usercenter.renews_on').replaceAll('{date}', renewDate),
                        colorToken: ColorToken.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              } else if (status == 'expired') {
                return Row(
                  children: [
                    Expanded(
                      child: CLText.bodySmall(
                        Localized.text('ox_usercenter.subscription_expired_on').replaceAll('{date}', renewDate),
                        colorToken: ColorToken.error,
                      ),
                    ),
                  ],
                );
              }
              return CLText.bodySmall(
                _kSubscriptionUnknownPlaceholder,
                colorToken: ColorToken.onSurfaceVariant,
              );
            },
          ),
          onTap: () => _showPlanOptions(context),
        ),
        LabelItemModel(
          icon: ListViewIcon.data(Icons.storage),
          title: Localized.text('ox_usercenter.storage'),
          onTap: () => _showStorageOptions(context),
        ),
      ],
    );
  }

  SectionListViewItem _buildMembersSection(
    BuildContext context,
    _TenantDisplayData displayData,
    List<UserDBISAR> members,
  ) {
    final currentPubkey = LoginManager.instance.currentPubkey;
    final memberItems = <ListViewItem>[];

    UserDBISAR? ownerUser;
    try {
      ownerUser = members.firstWhere((user) => user.pubKey == currentPubkey);
    } catch (e) {
      if (members.isNotEmpty) ownerUser = members.first;
    }
    final isOwner = displayData.isOwner;
    if (ownerUser != null) {
      memberItems.add(
        LabelItemModel(
          icon: ListViewIcon.data(Icons.person),
          title: isOwner
              ? Localized.text('ox_usercenter.you_owner')
              : Localized.text('ox_chat.you'),
          subtitle: isOwner
              ? Localized.text('ox_usercenter.owner')
              : Localized.text('ox_usercenter.member'),
          onTap: null,
        ),
      );
    }

    for (final member in members) {
      if (member.pubKey != currentPubkey) {
        final memberName = member.name ?? '';
        final displayName = memberName.isNotEmpty
            ? memberName
            : (member.pubKey.length >= 8 ? member.pubKey.substring(0, 8) : member.pubKey);
        memberItems.add(
          CustomItemModel(
            icon: ListViewIcon.data(Icons.person),
            title: displayName,
            subtitle: Localized.text('ox_usercenter.member'),
            trailing: isOwner
                ? CLButton.text(
                    text: Localized.text('ox_usercenter.remove'),
                    color: ColorToken.error.of(context),
                    onTap: () => _removeMember(member),
                  )
                : null,
            onTap: () {
              OXModuleService.pushPage(
                context,
                'ox_chat',
                'ContactUserInfoPage',
                {'pubkey': member.pubKey},
              );
            },
          ),
        );
      }
    }

    // Add member entry: owner only
    if (isOwner && displayData.currentMembers < displayData.maxMembers) {
      memberItems.add(
        LabelItemModel(
          icon: ListViewIcon.data(Icons.person_add),
          title: Localized.text('ox_usercenter.add_member'),
          onTap: () => _addMember(displayData),
        ),
      );
    }

    return SectionListViewItem(
      header: '${Localized.text('ox_usercenter.members')}(${displayData.currentMembers}/${displayData.maxMembers})',
      data: memberItems,
    );
  }

  Future<void> _removeMember(UserDBISAR member) async {
    final memberName = member.name ?? '';
    final displayName = memberName.isNotEmpty 
        ? memberName 
        : (member.pubKey.length >= 8 
            ? member.pubKey.substring(0, 8) 
            : member.pubKey);
    
    final confirmed = await CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.remove_member_title'),
      content: Localized.text('ox_usercenter.remove_member_content').replaceAll('{name}', displayName),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_usercenter.remove'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    );

    if (confirmed == true) {
      Loading.OXLoading.show();
      try {
        await CircleMemberService.sharedInstance.removeMember(
          memberPubkey: member.pubKey,
        );
        
        if (mounted) {
          CommonToast.instance.show(context, Localized.text('ox_common.operation_success'));
          await _loadSubscriptionInfo();
        }
      } catch (e) {
        if (mounted) {
          CommonToast.instance.show(context, e.toString());
        }
      } finally {
        Loading.OXLoading.dismiss();
      }
    }
  }

  Future<void> _addMember(_TenantDisplayData displayData) async {
    if (displayData.currentMembers >= displayData.maxMembers) {
      CommonToast.instance.show(
        context,
        Localized.text('ox_usercenter.member_limit_reached'),
      );
      return;
    }
    if (mounted) {
      await OXNavigator.pushPage(
        context,
        (context) => QRCodeDisplayPage(
          inviteType: InviteType.circle,
          circle: widget.circle,
        ),
      );
    }
  }

  /// Subscription status at tap time from state$ (for plan options dialog).
  String? get _currentSubscriptionStatus {
    final state = LoginManager.instance.currentState;
    if (state.currentCircle?.id != widget.circle.id || state.currentCircle?.tenantInfo == null) {
      return null;
    }
    final info = state.currentCircle!.tenantInfo!;
    final status = info.status;
    if (status.isNotEmpty) return status.toLowerCase();
    if (info.expiresAt != null && info.expiresAt! > 0) {
      final expiresDate = DateTime.fromMillisecondsSinceEpoch(info.expiresAt! * 1000);
      return expiresDate.isBefore(DateTime.now()) ? 'expired' : 'active';
    }
    return null;
  }

  void _showPlanOptions(BuildContext context) async {
    final status = _currentSubscriptionStatus;
    final items = <CLPickerItem<_PlanAction>>[];
    if (status == 'active') {
      // Active subscription: show change plan and cancel subscription
      items.addAll([
        CLPickerItem(
          label: Localized.text('ox_usercenter.change_plan'),
          value: _PlanAction.changePlan,
        ),
        CLPickerItem(
          label: Localized.text('ox_usercenter.cancel_subscription'),
          value: _PlanAction.cancelSubscription,
          isDestructive: true,
        ),
      ]);
    } else if (status == 'expired') {
      // Expired subscription: show renew plan
      items.addAll([
        CLPickerItem(
          label: Localized.text('ox_usercenter.change_plan'),
          value: _PlanAction.changePlan,
        ),
        CLPickerItem(
          label: Localized.text('ox_usercenter.renew'),
          value: _PlanAction.renewPlan,
        ),
      ]);
    } else {
      // Default: show all options
      items.addAll([
        CLPickerItem(
          label: Localized.text('ox_usercenter.change_plan'),
          value: _PlanAction.changePlan,
        ),
        CLPickerItem(
          label: Localized.text('ox_usercenter.renew'),
          value: _PlanAction.renewPlan,
        ),
        CLPickerItem(
          label: Localized.text('ox_usercenter.cancel_subscription'),
          value: _PlanAction.cancelSubscription,
          isDestructive: true,
        ),
      ]);
    }

    final action = await CLPicker.show<_PlanAction>(
      context: context,
      items: items,
    );

    if (action == null) return;

    switch (action) {
      case _PlanAction.changePlan:
        _handleChangePlan(context);
        break;
      case _PlanAction.cancelSubscription:
        _handleCancelSubscription(context);
        break;
      case _PlanAction.renewPlan:
        _handleRenewPlan(context);
        break;
    }
  }

  void _showStorageOptions(BuildContext context) async {
    final action = await CLPicker.show<_StorageAction>(
      context: context,
      items: [
        CLPickerItem(
          label: Localized.text('ox_usercenter.clear_all_storage'),
          value: _StorageAction.clearAllStorage,
          isDestructive: true,
        ),
      ],
    );

    if (action == null) return;

    switch (action) {
      case _StorageAction.clearAllStorage:
        _showClearStorageDialog(context);
        break;
    }
  }

  void _handleChangePlan(BuildContext context) {
    OXNavigator.pushPage(
      context,
      (context) => PrivateCloudOverviewPage(groupId: widget.circle.groupId,),
      type: OXPushPageType.present,
      fullscreenDialog: true,
    );
  }

  Future<void> _handleCancelSubscription(BuildContext context) async {
    await _openSubscriptionManagement(context);
  }

  Future<void> _handleRenewPlan(BuildContext context) async {
    await _openSubscriptionManagement(context);
  }

  Future<void> _openSubscriptionManagement(BuildContext context) async {
    String url;
    if (Platform.isIOS) {
      url = 'https://apps.apple.com/account/subscriptions';
    } else if (Platform.isAndroid) {
      url = 'https://play.google.com/store/account/subscriptions?package=com.oxchat.lite';
    } else {
      CommonToast.instance.show(
        context,
        Localized.text('ox_common.unsupported_platform'),
      );
      return;
    }

    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      CommonToast.instance.show(
        context,
        Localized.text('ox_common.failed_to_open_url'),
      );
    }
  }

  void _showCancelSubscriptionDialog(BuildContext context) {
    CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.cancel_subscription_title'),
      content: Localized.text('ox_usercenter.cancel_subscription_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_usercenter.cancel_subscription'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    ).then((confirmed) {
      if (confirmed == true) {
        // TODO: Implement cancel subscription logic
        CommonToast.instance.show(context, Localized.text('ox_common.operation_success'));
      }
    });
  }

  void _showClearStorageDialog(BuildContext context) {
    CLAlertDialog.show<bool>(
      context: context,
      title: Localized.text('ox_usercenter.clear_all_storage_title'),
      content: Localized.text('ox_usercenter.clear_all_storage_content'),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_usercenter.clear_all_storage'),
          value: true,
          isDestructiveAction: true,
        ),
      ],
    ).then((confirmed) async {
      if (confirmed == true) {
        await _handleClearAllStorage(context);
      }
    });
  }

  /// Handle clear all storage operation
  Future<void> _handleClearAllStorage(BuildContext context) async {
    // Only allow for paid relays
    if (!_isPaidRelay()) {
      CommonToast.instance.show(context, Localized.text('ox_common.operation_failed'));
      return;
    }

    // Get account credentials
    final pubkey = LoginManager.instance.currentPubkey;
    final privkey = Account.sharedInstance.currentPrivkey;
    
    if (pubkey.isEmpty || privkey.isEmpty) {
      CommonToast.instance.show(context, Localized.text('ox_common.operation_failed'));
      return;
    }

    // Get tenantId from CircleDBISAR, fallback to circle.id if not available
    String tenantId = widget.circle.id;
    try {
      final circleDB = await Account.sharedInstance.getCircleById(widget.circle.id);
      if (circleDB?.tenantId != null && circleDB!.tenantId!.isNotEmpty) {
        tenantId = circleDB.tenantId!;
      }
    } catch (e) {
      LogUtil.w(() => 'Failed to get tenantId from CircleDBISAR: $e');
      // Use circle.id as fallback
    }

    // Show loading
    Loading.OXLoading.show();

    try {
      // Call API to delete tenant files
      final result = await CircleApi.deleteTenantFiles(
        pubkey: pubkey,
        privkey: privkey,
        tenantId: tenantId,
      );

      // Hide loading
      Loading.OXLoading.dismiss();

      // Show success message
      CommonToast.instance.show(
        context,
        Localized.text('ox_common.operation_success'),
      );

      LogUtil.v(() => 'Successfully deleted ${result.deletedCount}/${result.totalCount} files for tenant $tenantId');
    } catch (e) {
      // Hide loading
      Loading.OXLoading.dismiss();

      // Show error message
      final errorMessage = e.toString().replaceFirst('Exception: ', '');
      CommonToast.instance.show(context, errorMessage);

      LogUtil.e(() => 'Failed to delete tenant files: $e');
    }
  }
}

/// Body that builds section list from [displayData] (from state$ / cache).
/// Holds only page-specific async state: resolved members for list.
class _CircleDetailBody extends StatefulWidget {
  const _CircleDetailBody({
    required this.displayData,
    required this.circle,
    required this.parent,
  });

  final _TenantDisplayData? displayData;
  final Circle circle;
  final _CircleDetailPageState parent;

  @override
  State<_CircleDetailBody> createState() => _CircleDetailBodyState();
}

class _CircleDetailBodyState extends State<_CircleDetailBody> {
  List<UserDBISAR>? _resolvedMembers;
  List<String>? _lastMemberPubkeys;

  Future<void> _resolveMembers(List<String> pubkeys) async {
    if (pubkeys.isEmpty) {
      if (mounted) setState(() => _resolvedMembers = []);
      return;
    }
    final userMap = await Account.sharedInstance.getUserInfos(pubkeys);
    final list = <UserDBISAR>[];
    for (final p in pubkeys) {
      final user = userMap[p];
      if (user != null) list.add(user);
    }
    if (mounted) setState(() => _resolvedMembers = list);
  }

  bool _listEquals(List<String> a, List<String>? b) {
    if (b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    final pubkeys = widget.displayData?.memberPubkeys ?? [];
    if (pubkeys.isNotEmpty) {
      _lastMemberPubkeys = List.from(pubkeys);
      _resolveMembers(pubkeys);
    }
  }

  @override
  void didUpdateWidget(covariant _CircleDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pubkeys = widget.displayData?.memberPubkeys ?? [];
    if (pubkeys.isEmpty) {
      if (_lastMemberPubkeys != null && mounted) {
        setState(() {
          _resolvedMembers = null;
          _lastMemberPubkeys = null;
        });
      }
      return;
    }
    if (_listEquals(pubkeys, _lastMemberPubkeys) == false) {
      _lastMemberPubkeys = List.from(pubkeys);
      _resolveMembers(pubkeys);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parent = widget.parent;
    return CLSectionListView(
      padding: EdgeInsets.only(bottom: 40.px),
      items: [
        SectionListViewItem(
          headerWidget: parent._buildHeader(context),
          data: [],
        ),
        ...parent._buildMainItems(context, widget.displayData, _resolvedMembers),
      ],
    );
  }
}