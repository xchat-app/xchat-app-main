import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';

class ItemAction {
  final String id;
  final String label;
  final IconData? icon;
  final bool destructive;
  final Future<bool> Function(BuildContext context)? onTap;

  const ItemAction({
    required this.id,
    required this.label,
    this.icon,
    this.destructive = false,
    this.onTap,
  });
}

/// Attach actions to a list item.
/// - iOS: right-swipe (endActionPane) using flutter_slidable.
/// - Android: long-press BottomSheet (overridable by [onLongPress]).
class CLListItemActions extends StatelessWidget {
  const CLListItemActions({
    super.key,
    required this.child,
    required this.actions,
    this.semanticLabel,
    this.cupertinoExtentRatio = 0.44,
    this.cupertinoMotion = const ScrollMotion(),
  });

  final Widget child;
  final List<ItemAction> actions;
  final String? semanticLabel;

  /// iOS only: total action pane width ratio.
  final double cupertinoExtentRatio;

  /// iOS only: motion for the action pane.
  final ScrollMotion cupertinoMotion;

  Future<void> _showAndroidMenu(BuildContext context) async {
    showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final action in actions)
                ListTile(
                  leading: action.icon != null ? Icon(action.icon) : null,
                  title: Text(
                    action.label,
                    style: action.destructive
                        ? const TextStyle(fontWeight: FontWeight.w600)
                        : null,
                  ),
                  textColor: action.destructive ? Theme.of(ctx).colorScheme.error : null,
                  iconColor: action.destructive ? Theme.of(ctx).colorScheme.error : null,
                  onTap: () async {
                    final shouldClose = await action.onTap?.call(context) ?? true;
                    if (shouldClose) OXNavigator.pop(context);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCupertinoAction(BuildContext context, ItemAction action) {
    final tintColor = ColorToken.white.of(context);
    return CustomSlidableAction(
      padding: EdgeInsets.zero,
      backgroundColor: action.destructive
          ? ColorToken.error.of(context)
          : ColorToken.secondaryXChat.of(context),
      onPressed: (ctx) async {
        final shouldClose = await action.onTap?.call(ctx) ?? true;
        if (shouldClose) Slidable.of(ctx)?.close();
      },
      autoClose: false,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (action.icon != null) ...[
            CLIcon(
              icon: action.icon,
              size: 30,
              color: tintColor,
            ),
            const SizedBox(height: 6),
          ],
          CLText.bodySmall(
            action.label,
            customColor: tintColor,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return CLPopupMenu<String>(
        items: actions.map((action) => CLPopupMenuItem<String>(
          value: action.id,
          title: action.label,
          icon: action.icon,
          onTap: () {
            action.onTap?.call(context);
          },
        )).toList(),
        color: ColorToken.surface.of(context),
        trigger: CLPopupTrigger.longPress,
        child: child,
      );
    }

    return Slidable(
      endActionPane: ActionPane(
        extentRatio: cupertinoExtentRatio,
        motion: cupertinoMotion,
        children: [
          for (final a in actions) _buildCupertinoAction(context, a),
        ],
      ),
      child: child,
    );
  }
}