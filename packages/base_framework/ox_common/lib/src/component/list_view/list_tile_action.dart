import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:ox_common/component.dart';

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
/// - iOS: left-swipe (startActionPane) and right-swipe (endActionPane) using flutter_slidable.
/// - Android: long-press BottomSheet (overridable by [onLongPress]).
class CLListTileActions extends StatelessWidget {
  const CLListTileActions({
    super.key,
    required this.child,
    this.actions,
    this.startActions,
    this.endActions,
    this.semanticLabel,
    this.cupertinoExtentRatio = 0.44,
    this.cupertinoMotion = const ScrollMotion(),
  });

  final Widget child;

  /// Actions for Android long-press menu or iOS if startActions/endActions are not provided
  final List<ItemAction>? actions;

  /// Actions for iOS left-swipe (startActionPane)
  final List<ItemAction>? startActions;

  /// Actions for iOS right-swipe (endActionPane)
  final List<ItemAction>? endActions;

  final String? semanticLabel;

  /// iOS only: total action pane width ratio.
  final double cupertinoExtentRatio;

  /// iOS only: motion for the action pane.
  final ScrollMotion cupertinoMotion;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      final allActions = actions ?? [...?startActions, ...?endActions];
      return CLPopupMenu<String>(
        items: allActions.map((action) => CLPopupMenuItem<String>(
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

    final start = startActions;
    final end = endActions ?? actions;

    return Slidable(
      startActionPane: start != null && start.isNotEmpty
          ? ActionPane(
              extentRatio: cupertinoExtentRatio,
              motion: cupertinoMotion,
              children: [
                for (final action in start) _buildCupertinoAction(context, action),
              ],
            )
          : null,
      endActionPane: end != null && end.isNotEmpty
          ? ActionPane(
              extentRatio: cupertinoExtentRatio,
              motion: cupertinoMotion,
              children: [
                for (final action in end) _buildCupertinoAction(context, action),
              ],
            )
          : null,
      child: child,
    );
  }

  Widget _buildCupertinoAction(BuildContext context, ItemAction action) {
    final tintColor = ColorToken.white.of(context);
    final backgroundColor = action.destructive
        ? ColorToken.error.of(context)
        : ColorToken.xChat.of(context);
    return CustomSlidableAction(
      padding: EdgeInsets.zero,
      foregroundColor: backgroundColor,
      backgroundColor: backgroundColor,
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
}