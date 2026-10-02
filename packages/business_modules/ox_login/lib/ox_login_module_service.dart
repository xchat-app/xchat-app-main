import 'package:flutter/material.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_module_service/ox_module_service.dart';
import 'page/private_cloud_overview_page.dart';
import 'utils/circle_entry_helper.dart';

/// OXLogin module service interface
///
/// Provides access to LoginFlowManager and other login-related services
class OXLoginModuleService extends OXFlutterModule {
  @override
  String get moduleName => 'ox_login';

  @override
  Future<void> setup() async {
    await super.setup();
  }

  @override
  Map<String, Function> get interfaces => {};

  @override
  Future<T?>? navigateToPage<T>(BuildContext context, String pageName, Map<String, dynamic>? params) {
    switch (pageName) {
      case 'PrivateCloudOverviewPage':
        return _openPrivateCloud<T>(context);
      default:
        return null;
    }
  }

  /// The Private Circle purchase flow, for modules that cannot import this one
  /// (ox_chat, when a call is tried in a free circle). Same pre-check as the
  /// Add Circle page.
  Future<T?> _openPrivateCloud<T>(BuildContext context) async {
    final groupId = await CircleEntryHelper.getCurrentInactiveGroupId();
    if (!context.mounted) return null;
    if (groupId == null || groupId.isEmpty) {
      CommonToast.instance.show(context, Localized.text('ox_login.subscription_limit_reached'));
      return null;
    }
    return OXNavigator.pushPage<T>(
      context,
      (context) => const PrivateCloudOverviewPage(),
      type: OXPushPageType.present,
      fullscreenDialog: true,
    );
  }
}
