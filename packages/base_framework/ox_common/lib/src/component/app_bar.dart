
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ox_localizable/ox_localizable.dart';

import 'platform_style.dart';
import 'text.dart';

enum MaterialBarType {
  small,
  medium,
  large,
}

class CLAppBar extends StatelessWidget {
  CLAppBar({
    super.key,
    dynamic title,
    this.leading,
    this.previousPageTitle,
    this.actions = const [],
    this.backgroundColor,
    this.barType,
    this.autoTrailing = true,
    this.bottom,
  }) : title = preferTitle(title);

  final Widget? title;
  final Widget? leading;
  final String? previousPageTitle;
  final List<Widget> actions;
  final Color? backgroundColor;
  final bool autoTrailing;
  final PreferredSizeWidget? bottom;

  final MaterialBarType? barType;

  static Widget? preferTitle(dynamic title) {
    if (title == null) return null;
    if (title is Widget) return title;
    return CLText(title.toString());
  }

  factory CLAppBar.sliver({
    required MaterialBarType barType,
    dynamic title,
    List<Widget> actions  = const [],
    Color? backgroundColor,
  }) {
    return CLAppBar(
      title: title,
      actions: actions,
      backgroundColor: backgroundColor,
      barType: barType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final barType = this.barType;
    if (barType != null) {
      return _buildSliverAppBar(context, barType);
    }
    return _buildAppBar(context);
  }

  Widget _buildAppBar(BuildContext context) {
    if (PlatformStyle.isUseMaterial) {
      return buildMaterialAppBar(context);
    }
    return buildCupertinoAppBar(context);
  }

  AppBar buildMaterialAppBar(BuildContext context) {
    return AppBar(
      title: title,
      leading: leading,
      leadingWidth: (leading != null && title == null) ? 250 : null,
      centerTitle: false,
      actions: actions,
      actionsPadding: EdgeInsetsDirectional.only(end: 16),
      backgroundColor: backgroundColor,
      bottom: bottom,
    );
  }

  CupertinoNavigationBar buildCupertinoAppBar(BuildContext context) {
    EdgeInsetsDirectional? padding;
    if (CupertinoSheetRoute.hasParentSheet(context)) {
      padding = const EdgeInsetsDirectional.only(
        start: 16,    // _kNavBarEdgePadding
        top: 0,
        bottom: 12,   // Adapt for CupertinoSheetRoute
        end: 16,      // _kNavBarEdgePadding
      );
    } else if (leading != null) {
      padding = EdgeInsetsDirectional.zero;
    }
    return CupertinoNavigationBar(
      middle: title,
      leading: leading,
      padding: padding,
      trailing: _buildCupertinoTrailing(context),
      bottom: bottom,
    );
  }

  Widget _buildSliverAppBar(BuildContext context, MaterialBarType barType) {
    if (PlatformStyle.isUseMaterial) {
      return _buildMaterialSliverAppBar(context, barType);
    }
    return _buildCupertinoSliverAppBar(context);
  }

  Widget _buildMaterialSliverAppBar(BuildContext context, MaterialBarType barType) {
    switch (barType) {
      case MaterialBarType.small:
        return SliverAppBar(
          title: title,
          centerTitle: false,
          actions: actions,
          backgroundColor: backgroundColor,
        );
      case MaterialBarType.medium:
        return SliverAppBar.medium(
          title: title,
          actions: actions,
          backgroundColor: backgroundColor,
        );
      case MaterialBarType.large:
        return SliverAppBar.large(
          title: title,
          actions: actions,
          backgroundColor: backgroundColor,
        );
    }
  }

  Widget _buildCupertinoSliverAppBar(BuildContext context) {
    return CupertinoSliverNavigationBar(
      largeTitle: title,
      trailing: _buildCupertinoTrailing(context),
      backgroundColor: backgroundColor,
    );
  }

  Widget _buildCupertinoTrailing(BuildContext context) {
    final actions = [...this.actions];
    if (actions.isEmpty && autoTrailing) {
      actions.add(_buildCupertinoDefaultCloseButton(context));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions,
    );
  }

  Widget _buildCupertinoDefaultCloseButton(BuildContext context) {
    final hasParentSheet = CupertinoSheetRoute.hasParentSheet(context);
    if (!hasParentSheet) return const SizedBox.shrink();

    return CupertinoButton(
      padding: EdgeInsets.zero,
      onPressed: () {
        CupertinoSheetRoute.popSheet(context);
      },
      child: Text(Localized.text('ox_common.complete')),
    );
  }
}