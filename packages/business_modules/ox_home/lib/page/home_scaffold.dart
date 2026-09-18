import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_chat/page/session/lite_new_message_page.dart';
import 'package:ox_common/business_interface/ox_usercenter/interface.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_manager.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/widget_tool.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_theme/ox_theme.dart';
import 'package:ox_login/page/circle_selection_page.dart';
import 'package:ox_login/utils/circle_entry_helper.dart';

import 'home_header_components.dart';
import '../widgets/session_list_widget.dart';
import '../widgets/circle_empty_widget.dart';
import 'package:ox_common/utils/relay_latency_handler.dart';
import '../widgets/key_backup_banner.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({
    super.key,
  });

  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  final ValueNotifier<CircleItem?> selectedCircle$ = ValueNotifier(null);
  final ValueNotifier<bool> isShowExtendBody$ = ValueNotifier(false);

  HomeHeaderComponents? components;
  RelayLatencyHandler? _latencyHandler;

  Duration get extendBodyDuration => const Duration(milliseconds: 200);

  ValueNotifier<bool> isContrastedChild$ = ValueNotifier(false);
  ValueNotifier<ConnectStatus> relayStatus$ = ValueNotifier(ConnectStatus.open);
  bool isFirstJoin = false;

  @override
  void initState() {
    super.initState();
    // _latencyHandler = RelayLatencyHandler(isExpanded$: isShowExtendBody$);
    Connect.sharedInstance.addConnectStatusListener(_handleConnectStatusChanged);
  }

  @override
  void dispose() {
    Connect.sharedInstance.removeConnectStatusListener(_handleConnectStatusChanged);
    _latencyHandler?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: LoginManager.instance.state$,
      builder: (_, state, __) {
        final page = buildPage(state);
        if (state.hasCircle) {
          return page;
        }

        return _buildContrastedMask(
          notifier: isContrastedChild$,
          child: page,
        );
      },
    );
  }

  Widget buildPage(LoginState state) {
    final account = state.account;
    final circles = (account?.circles ?? []).map((e) => e.asViewModel()).toList();
    selectedCircle$.value = state.currentCircle?.asViewModel();

    components?.dispose();
    final headerComponents = HomeHeaderComponents(
      circles: circles,
      selectedCircle$: selectedCircle$,
      onCircleSelected: _onCircleSelected,
      avatarOnTap: _avatarOnTap,
      nameOnTap: null,
      addOnTap: _addOnTap,
      joinOnTap: _handleJoinCircle,
      paidOnTap: _paidOnTap,
      isShowExtendBody$: isShowExtendBody$,
      relayStatus$: relayStatus$,
      latencyHandler: _latencyHandler,
      extendBodyDuration: extendBodyDuration,
    );
    components = headerComponents;

    if (PlatformStyle.isUseMaterial) {
      return Scaffold(
        key: _scaffoldKey,
        appBar: headerComponents.buildAppBar(context),
        drawer: Drawer(
          width: 332.px,
          child: OXUserCenterInterface.settingSliderBuilder(context),
        ),
        drawerEdgeDragWidth: 50.px,
        resizeToAvoidBottomInset: false,
        body: buildBody(context, headerComponents),
      );
    }
    // Cupertino style: simplified, modal sidebar
    return Scaffold(
      appBar: headerComponents.buildAppBar(context),
      backgroundColor: CupertinoColors.systemBackground.resolveFrom(context),
      resizeToAvoidBottomInset: false,
      body: buildBody(context, headerComponents),
    );
  }

  Widget buildBody(BuildContext context, HomeHeaderComponents components) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: _buildContrastedMask(
            notifier: isShowExtendBody$,
            child: _buildMainContent(),
          )
        ),
        Positioned.fill(
          child: components.buildMask(),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder(
            valueListenable: isShowExtendBody$,
            builder: (context, isShowExtendBody, __) {
              return AnimatedSlide(
                offset: isShowExtendBody ? Offset.zero : const Offset(0, -1),
                duration: extendBodyDuration,
                child: components.buildCircleList(context),
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildContrastedMask({
    required ValueNotifier<bool> notifier,
    required Widget child,
  }) {
    // ref: CupertinoSheetTransition.delegateTransition
    return Stack(
      children: [
        child,
        IgnorePointer(
          child: ValueListenableBuilder(
            valueListenable: notifier,
            builder: (context, value, __) {
              return AnimatedOpacity(
                opacity: value ? 0.1: 0.0,
                duration: extendBodyDuration,
                curve: Curves.linearToEaseOut,
                child: ColoredBox(
                  color: ThemeManager.brightness() == Brightness.dark
                      ? const Color(0xFFc8c8c8)
                      : const Color(0xFF000000),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return ValueListenableBuilder<LoginState>(
      valueListenable: LoginManager.instance.state$,
      builder: (context, loginState, child) {
        final loginAccount = loginState.account;
        final loginCircle = loginState.currentCircle;
        
        if (loginAccount == null) {
          return Center(
            child: SafeArea(
              child: CLProgressIndicator.circular()
                  .setPaddingOnly(bottom: 32),
            ),
          );
        }

        Widget body = loginCircle != null ? SessionListWidget(
          ownerPubkey: loginAccount.pubkey,
          circle: loginCircle,
        ) : CircleEmptyWidget(
          onJoinCircle: _handleJoinCircle,
          onCreatePaidCircle: _handleCreatePaidCircle,
        );

        // Above the list rather than inside it, so it survives an empty circle
        // and does not scroll away from someone who has not read it yet.
        body = Column(
          children: [
            const KeyBackupBanner(),
            Expanded(child: body),
          ],
        );

        if (isFirstJoin) {
          body = AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeIn,
            switchOutCurve: Curves.easeOut,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: body,
          );
        }

        return body;
      },
    );
  }

  void _handleJoinCircle() async {
    isContrastedChild$.value = true;
    debugPrint('HomeScaffold: Join Circle button tapped');
    final didNavigateToRestore = await CircleEntryHelper.tryNavigateToCircleRestoreIfNeeded(
      context,
      type: OXPushPageType.present,
      fullscreenDialog: true,
    );
    if (!mounted) return;
    if (!didNavigateToRestore) {
      OXNavigator.pushPage(
        context,
        (context) => const CircleSelectionPage(controller: null),
        type: OXPushPageType.present,
        fullscreenDialog: true,
      );
    }
    isContrastedChild$.value = false;
    isShowExtendBody$.value = false;
  }

  void _handleCreatePaidCircle() {
    debugPrint('HomeScaffold: Create Paid Circle button tapped');
    // TODO: Navigate to create paid circle page
  }

  void _showSidebar(BuildContext context) {
    OXNavigator.pushPage(
      context,
      OXUserCenterInterface.settingSliderBuilder,
      type: OXPushPageType.present,
    );
  }

  void _avatarOnTap() {
    if (PlatformStyle.isUseMaterial) {
      _scaffoldKey.currentState?.openDrawer();
    } else {
      _showSidebar(context);
    }
  }

  void _nameOnTap() {
    isShowExtendBody$.value = !isShowExtendBody$.value;
  }

  void _addOnTap() {
    OXNavigator.pushPage(
      context,
      (context) => const CLNewMessagePage(),
      type: OXPushPageType.present,
    );
  }

  void _paidOnTap() {
  }

  void _onCircleSelected(CircleItem newSelected) async {
    final circles = (LoginManager.instance.currentState.account?.circles ?? []);
    final targetCircle = circles.where((e) => e.id == newSelected.id).firstOrNull;
    if (targetCircle == null) return;

    OXLoading.show();
    final failure = await LoginManager.instance.switchToCircle(targetCircle);
    OXLoading.dismiss();

    if (failure == null) {
      // Delay is needed because switching circles triggers heavy local operations
      // that consume performance. The delay ensures smooth window closing animation.
      await Future.delayed(const Duration(milliseconds: 100));
      isShowExtendBody$.value = false;
    } else {
      CommonToast.instance.show(context, failure.message);
    }
  }

  void _handleConnectStatusChanged(String relay, ConnectStatus status, List<RelayKind> relayKinds) {
    final currentRelay = selectedCircle$.value?.relayUrl;
    if (currentRelay == null) return;
    if (!relayKinds.contains(RelayKind.circleRelay)) return;
    if (relay != currentRelay) return;

    relayStatus$.value = status;
  }
}

extension _CircleEx on Circle {
  CircleItem asViewModel() {
    return CircleItem(
      id: id,
      name: name,
      relayUrl: relayUrl,
      type: type,
    );
  }
}
