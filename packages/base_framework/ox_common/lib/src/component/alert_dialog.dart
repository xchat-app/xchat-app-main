import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:ox_common/component.dart';

/// Action model for alert dialog buttons.
class CLAlertAction<T> {
  const CLAlertAction({
    required this.label,
    this.value,
    this.isDefaultAction = false,
    this.isDestructiveAction = false,
  });

  /// Button label text.
  final String label;

  /// Value returned when this action is selected.
  final T? value;

  /// Whether this is the "default" affirmative action (Cupertino style).
  final bool isDefaultAction;

  /// Whether this action is destructive (highlighted in red on iOS / Material).
  final bool isDestructiveAction;

  /// Common OK / confirm action (value == true).
  static CLAlertAction<bool> ok() =>
      CLAlertAction<bool>(
        label: Localized.text('ox_common.ok'),
        value: true,
        isDefaultAction: true,
      );

  /// Common Cancel action (value == false).
  static CLAlertAction<bool> cancel() =>
      CLAlertAction<bool>(
        label: Localized.text('ox_common.cancel'),
        value: false,
        isDestructiveAction: false,
      );
}

/// Cross-platform Alert Dialog (Material & Cupertino).
class CLAlertDialog {
  /// Show alert dialog and return the [value] of the button tapped.
  /// If dismissed by other ways, returns null.
  static Future<T?> show<T>({
    required BuildContext context,
    String? title,
    String? content,
    required List<CLAlertAction<T>> actions,
    bool barrierDismissible = true,
  }) {
    final displayTitle = title ?? Localized.text('ox_common.alert');

    if (PlatformStyle.isUseMaterial) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (ctx) => AlertDialog(
          title: _buildTitle(displayTitle),
          content: content != null ? CLText.bodyMedium(content) : null,
          actions: _materialActions(ctx, actions),
        ),
      );
    }

    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => CupertinoAlertDialog(
        title: _buildTitle(displayTitle),
        content: content != null ? Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: CLText.bodyMedium(content),
        ) : null,
        actions: _cupertinoActions(ctx, actions),
      ),
    );
  }

  /// Show alert dialog with custom widget content and return the [value] of the button tapped.
  /// If dismissed by other ways, returns null.
  static Future<T?> showWithWidget<T>({
    required BuildContext context,
    String? title,
    required Widget content,
    required List<CLAlertAction<T>> actions,
    bool barrierDismissible = true,
  }) {
    final displayTitle = title ?? Localized.text('ox_common.alert');

    if (PlatformStyle.isUseMaterial) {
      return showDialog<T>(
        context: context,
        barrierDismissible: barrierDismissible,
        builder: (ctx) => AlertDialog(
          title: _buildTitle(displayTitle),
          content: content,
          actions: _materialActions(ctx, actions),
        ),
      );
    }

    return showCupertinoDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => CupertinoAlertDialog(
        title: _buildTitle(displayTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: content,
        ),
        actions: _cupertinoActions(ctx, actions),
      ),
    );
  }

  static Widget? _buildTitle(String title) {
    if (title.isEmpty) return null;
    if (PlatformStyle.isUseMaterial) {
      return CLText(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      return CLText(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
  }

  static List<Widget> _materialActions<T>(
    BuildContext ctx,
    List<CLAlertAction<T>> models,
  ) {
    return models
        .map((m) => TextButton(
              onPressed: () => Navigator.of(ctx).pop(m.value),
              style: m.isDestructiveAction
                  ? TextButton.styleFrom(foregroundColor: ColorToken.error.of(ctx))
                  : null,
              child: CLText(m.label),
            ))
        .toList();
  }

  static List<Widget> _cupertinoActions<T>(
    BuildContext ctx,
    List<CLAlertAction<T>> models,
  ) {
    return models
        .map((m) => CupertinoDialogAction(
              isDefaultAction: m.isDefaultAction,
              isDestructiveAction: m.isDestructiveAction,
              onPressed: () => Navigator.of(ctx).pop(m.value),
              child: CLText(m.label),
            ))
        .toList();
  }
}