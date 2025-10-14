import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/login/login_models.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

import '../page/archived_chats_page.dart';
import 'session_list_data_controller.dart';
import 'session_list_item_widget.dart';
import 'session_view_model.dart';

class SessionListWidget extends StatefulWidget {
  const SessionListWidget({
    super.key,
    required this.ownerPubkey,
    required this.circle,
  });

  final String ownerPubkey;
  final Circle circle;

  @override
  State<SessionListWidget> createState() => _SessionListWidgetState();
}

class _SessionListWidgetState extends State<SessionListWidget> {
  SessionListDataController? controller;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  @override
  void didUpdateWidget(SessionListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reinitialize controller if ownerPubkey or circle changed
    if (oldWidget.ownerPubkey != widget.ownerPubkey ||
        oldWidget.circle.id != widget.circle.id) {
      _initializeController();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _initializeController() {
    if (widget.ownerPubkey.isNotEmpty) {
      controller = SessionListDataController(widget.ownerPubkey, widget.circle);
      controller!.initialized();
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading if controller is not initialized or ownerPubkey is empty
    if (controller == null || widget.ownerPubkey.isEmpty) {
      return Center(
        child: CLProgressIndicator.circular(),
      );
    }

    return ValueListenableBuilder(
      valueListenable: controller!.sessionList$,
      builder: (context, sessionList, _) {
        // Show empty state when no sessions
        if (sessionList.isEmpty) {
          return _buildEmptyState(context);
        }

        return ValueListenableBuilder(
          valueListenable: controller!.hasArchivedChats$,
          builder: (context, hasArchived, _) {
            return ListView.separated(
              padding:
                  EdgeInsets.only(bottom: Adapt.bottomSafeAreaHeightByKeyboard),
              itemBuilder: (context, index) {
                if (hasArchived && index == sessionList.length) {
                  // This is the footer
                  return _buildArchivedChatsFooter(context);
                }
                return itemBuilder(context, sessionList[index]);
              },
              separatorBuilder: (context, index) {
                if (hasArchived && index == sessionList.length - 1) {
                  // No separator before footer
                  return const SizedBox.shrink();
                }
                return buildSeparator(context, index, sessionList);
              },
              itemCount: sessionList.length + (hasArchived ? 1 : 0),
            );
          },
        );
      },
    );
  }

  Widget? itemBuilder(BuildContext context, SessionListViewModel item) {
    return SessionListItemWidget(
      item: item,
      sessionListController: controller,
      showPinnedBackground: true,
    );
  }

  Widget buildSeparator(BuildContext context, int index, List<SessionListViewModel> sessionList) {
    if (PlatformStyle.isUseMaterial) return const SizedBox.shrink();

    // Is between pinned and unpinned items
    if (index < sessionList.length - 1) {
      final currentItem = sessionList[index];
      final nextItem = sessionList[index + 1];

      // No separator between pinned and unpinned items
      if (currentItem.isAlwaysTop && !nextItem.isAlwaysTop) {
        return const SizedBox.shrink();
      }
    }

    return Padding(
      padding: EdgeInsets.only(left: 72.px),
      child: Container(
        height: 0.5,
        color: CupertinoColors.separator,
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, -120.px),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.px),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Empty state icon using Material Icons
              Icon(
                Icons.forum_outlined,
                size: 120.px,
                color: PlatformStyle.isUseMaterial
                    ? ColorToken.primary.of(context)
                    : CupertinoTheme.of(context)
                        .textTheme
                        .actionSmallTextStyle
                        .color,
              ),

              SizedBox(height: 24.px),

              // Title
              CLText.titleMedium(
                Localized.text('ox_chat.no_sessions_title'),
                colorToken: ColorToken.onSurface,
                textAlign: TextAlign.center,
              ),

              SizedBox(height: 8.px),

              // Description
              CLText.bodyMedium(
                Localized.text('ox_chat.no_sessions_description'),
                colorToken: ColorToken.onSurfaceVariant,
                textAlign: TextAlign.center,
                maxLines: 3,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArchivedChatsFooter(BuildContext context) {
    return CupertinoButton(
      onPressed: () => _navigateToArchivedChats(context),
      padding: EdgeInsets.symmetric(vertical: 8.px),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CLText.bodyMedium(
            Localized.text('ox_chat.archived_chats'),
            customColor: ColorToken.primary.of(context),
          ),
          SizedBox(width: 4.px),
          Icon(
            CupertinoIcons.chevron_right,
            size: 16.px,
            color: ColorToken.primary.of(context),
          ),
        ],
      ),
    );
  }

  void _navigateToArchivedChats(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ArchivedChatsPage(
          ownerPubkey: widget.ownerPubkey,
          circle: widget.circle,
        ),
      ),
    );
  }
}
