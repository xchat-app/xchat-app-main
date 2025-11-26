import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/widget_tool.dart';

import '../../../component.dart';

class CLListTile extends StatelessWidget {
  CLListTile({
    super.key,
    required this.model,
    this.isEditing = false,
    this.onDelete,
  });

  factory CLListTile.custom({
    Widget? leading,
    Widget? title,
    Widget? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool isEditing = false,
  }) {
    return CLListTile(
      model: CustomItemModel(
        leading: leading,
        titleWidget: title,
        subtitleWidget: subtitle,
        trailing: trailing,
        onTap: onTap,
      ),
      isEditing: isEditing,
    );
  }

  final ListViewItem model;
  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  Widget build(BuildContext context) {
    final model = this.model;
    if (model is LabelItemModel)
      return _ListViewLabelItemWidget(
        model: model,
        isEditing: isEditing,
        onDelete: onDelete,
      );
    if (model is SwitcherItemModel)
      return _ListViewSwitcherItemWidget(
        model: model,
        isEditing: isEditing,
        onDelete: onDelete,
      );
    if (model is SelectedItemModel)
      return _ListViewSelectedItemWidget(
        model: model,
        isEditing: isEditing,
        onDelete: onDelete,
      );
    if (model is MultiSelectItemModel)
      return _ListViewMultiSelectItemWidget(
        model: model,
        isEditing: isEditing,
        onDelete: onDelete,
      );
    if (model is CustomItemModel)
      return _ListViewCustomItemWidget(
        model: model,
        isEditing: isEditing,
        onDelete: onDelete,
      );
    throw Exception('Unknown item model type');
  }

  static Widget buildDefaultTrailing(GestureTapCallback? onTap) {
    if (PlatformStyle.isUseMaterial) return const SizedBox.shrink();;
    if (onTap == null) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(left: 10),
      child: CupertinoListTileChevron(),
    );
  }
}

class _ListViewItemBaseWidget extends StatefulWidget {
  const _ListViewItemBaseWidget({
    required this.model,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isEditing = false,
    this.onDelete,
  });

  final ListViewItem model;
  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final GestureTapCallback? onTap;

  bool get isThemeStyle => model.style == ListViewItemStyle.theme;

  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  State<StatefulWidget> createState() => _ListViewItemBaseWidgetState();
}

class _ListViewItemBaseWidgetState extends State<_ListViewItemBaseWidget>
    with SingleTickerProviderStateMixin {

  ListViewItem get model => widget.model;
  Widget? get leading => widget.leading;
  Widget? get title => widget.title;
  Widget? get subtitle => widget.subtitle;
  Widget? get trailing => widget.trailing;
  GestureTapCallback? get onTap => widget.isEditing ? null : widget.onTap;

  bool get isThemeStyle => widget.isThemeStyle;

  bool get isEditing => widget.isEditing;
  Function(ListViewItem item)? get onDelete => widget.onDelete;

  bool get isSupportDelete => onDelete != null;

  late AnimationController animationController;
  Duration get animationDuration => Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();

    animationController = AnimationController(
      duration: animationDuration,
      vsync: this,
    );
  }

  @override
  void didUpdateWidget(covariant _ListViewItemBaseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.isEditing != oldWidget.isEditing) {
      if (widget.isEditing) {
        animationController.forward();
      } else {
        animationController.reverse();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildListTile(context);
  }

  Widget _buildListTile(BuildContext context) {
    if (PlatformStyle.isUseMaterial || model.isUseMaterial == true) {
      return (_buildMaterialListTile(context));
    } else {
      return _buildCupertinoListTile();
    }
  }

  Widget _buildMaterialListTile(BuildContext context) {
    final isThemeStyle = model.style == ListViewItemStyle.theme;
    final labelLargeNoColor = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(color: null);
    Widget? effectiveTrailing = trailing;
    if (isEditing && onDelete != null) {
      effectiveTrailing = _buildDeleteIcon();
    }

    return ListTile(
      title: title ?? _buildTitle(),
      subtitle: subtitle ?? _buildSubtitle(),
      leading: leading ?? _buildLeading(),
      trailing: effectiveTrailing,
      onTap: onTap,
      tileColor: isThemeStyle ? ColorToken.primary.of(context) : null,
      textColor: isThemeStyle ? ColorToken.onPrimary.of(context) : null,
      iconColor: isThemeStyle ? ColorToken.onPrimary.of(context) : null,
      titleTextStyle: labelLargeNoColor,
      leadingAndTrailingTextStyle: labelLargeNoColor,
    );
  }

  Widget _buildCupertinoListTile() {
    return AnimatedBuilder(
      animation: animationController,
      builder: (_, __) {
        final originLeading = leading ?? _buildLeading();
        final originTrailing = Row(
          children: [
            trailing ?? const SizedBox.shrink(),
            if (model.isCupertinoAutoTrailing)
              CLListTile.buildDefaultTrailing(onTap),
          ],
        ).setPaddingOnly(left: 16.px);

        Widget? effectiveLeading = originLeading;
        Widget effectiveTrailing = originTrailing;
        if (isSupportDelete) {
          effectiveLeading = _cupertinoDeleteWrap(originLeading ?? SizedBox.shrink());
          effectiveTrailing = _cupertinoTrailingDismiss(originTrailing);
        }

        if (model.isCupertinoListTileBaseStyle) {
          final defaultLeadingSize = 28.0; // _kLeadingSize
          return CupertinoListTile(
            title: title ?? _buildTitle(),
            subtitle: subtitle ?? _buildSubtitle(),
            leading: effectiveLeading,
            leadingSize: isSupportDelete
                ? animationController.value * defaultLeadingSize
                : defaultLeadingSize,
            trailing: effectiveTrailing,
            onTap: onTap,
          );
        } else {
          final defaultLeadingSize = 30.0; // _kNotchedLeadingSize;
          return CupertinoListTile.notched(
            title: title ?? _buildTitle(),
            subtitle: subtitle ?? _buildSubtitle(),
            leading: effectiveLeading,
            leadingSize: isSupportDelete
                ? animationController.value * defaultLeadingSize
                : defaultLeadingSize,
            trailing: effectiveTrailing,
            padding: effectiveLeading != null
                ? CLLayout.kNotchedPadding
                : CLLayout.kNotchedPaddingWithoutLeading,
            onTap: onTap,
          );
        }
      },
    );
  }

  Widget _cupertinoDeleteWrap(Widget widget) {
    final dx = 20;
    final deleteWidget = Transform.translate(
      offset: Offset(-dx + dx * animationController.value, 0),
      child: Opacity(
        opacity: animationController.value,
        child: _buildDeleteIcon(),
      ),
    );
    return Stack(
      children: [
        OverflowBox(
          minWidth: 0,
          minHeight: 0,
          maxWidth: double.infinity,
          maxHeight: double.infinity,
          child: deleteWidget,
        ),
        widget,
      ],
    );
  }

  Widget _cupertinoTrailingDismiss(Widget widget) {
    return Opacity(
      opacity: 1- animationController.value,
      child: widget,
    );
  }

  Widget _buildDeleteIcon() {
    if (PlatformStyle.isUseMaterial) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => onDelete?.call(model),
        child: Padding(
          padding: EdgeInsets.all(11.px),
          child: Icon(
            Icons.indeterminate_check_box,
            color: ColorToken.error.of(context),
            size: 24.px,
          ),
        ),
      );
    } else {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => onDelete?.call(model),
        child: Icon(
          CupertinoIcons.minus_circle_fill,
          color: ColorToken.error.of(context),
          size: 22,
        ),
      );
    }
  }

  Widget? _buildLeading() {
    final icon = model.icon;
    if (icon == null) return null;
    return CLIcon(
      icon: icon.data,
      iconName: icon.iconName,
      package: icon.package ?? '',
      size: icon.size,
    );
  }

  Widget _buildTitle() =>
      CLText(model.title);

  Widget? _buildSubtitle() {
    final subtitle = model.subtitle;
    if (subtitle == null) {
      return null;
    }
    return CLText(subtitle);
  }
}

class _ListViewLabelItemWidget extends StatelessWidget {
  const _ListViewLabelItemWidget({
    required this.model,
    this.isEditing = false,
    this.onDelete,
  });

  final LabelItemModel model;

  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  Widget build(BuildContext context) => _ListViewItemBaseWidget(
    model: model,
    trailing: buildValueListenable(),
    onTap: model.onTap,
    isEditing: isEditing,
    onDelete: onDelete,
  );

  Widget? buildValueListenable() {
    final valueNty = model.value$;
    if (valueNty == null) {
      return null;
    }

    return ValueListenableBuilder(
      valueListenable: valueNty,
      builder: (_, value, child) {
        String label = model.getValueMapData(value);
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 200.px),
          child: CLText(
            label,
            maxLines: model.maxLines,
            overflow: model.overflow ?? TextOverflow.ellipsis,
          ),
        );
      },
    );
  }
}

class _ListViewSwitcherItemWidget extends StatelessWidget {
  const _ListViewSwitcherItemWidget({
    required this.model,
    this.isEditing = false,
    this.onDelete,
  });

  final SwitcherItemModel model;

  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  Widget build(BuildContext context) => _ListViewItemBaseWidget(
    model: model,
    trailing: buildValueListenable(),
    isEditing: isEditing,
    onDelete: onDelete,
  );

  Widget? buildValueListenable() {
    final valueNty = model.value$;
    return ValueListenableBuilder(
      valueListenable: valueNty,
      builder: (_, value, child) {
        return CLSwitch(
          value: value,
          onChanged: (newValue) {
            if (model.onChanged != null) {
              model.onChanged?.call(newValue);
            } else {
              model.value$.value = newValue;
            }
          },
        );
      },
    );
  }
}

class _ListViewSelectedItemWidget extends StatelessWidget {
  const _ListViewSelectedItemWidget({
    required this.model,
    this.isEditing = false,
    this.onDelete,
  });

  final SelectedItemModel model;

  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  Widget build(BuildContext context) {
    if (PlatformStyle.isUseMaterial && model.subtitle == null)
      return buildWithMaterial();

    return _ListViewItemBaseWidget(
      model: model,
      onTap: itemOnTap,
      trailing: buildValueListenable(),
      isEditing: isEditing,
      onDelete: onDelete,
    );
  }

  Widget buildWithMaterial() {
    return InkWell(
      onTap: itemOnTap,
      child: Container(
        height: 72.px,
        padding: EdgeInsets.symmetric(horizontal: 16.px),
        child: Row(
          children: [
            CLText.bodyLarge(model.title),
            Spacer(),
            buildValueListenable(),
          ],
        ),
      ),
    );
  }

  Widget buildValueListenable() {
    final valueNty = model.value$;
    return ValueListenableBuilder(
      valueListenable: valueNty,
      builder: (_, value, child) {
        if (value != model.value) return const SizedBox();
        return ImageIcon(
          AssetImage('assets/images/icon_selected.png', package: 'ox_common'),
        );
      },
    );
  }

  void itemOnTap() {
    model.selected$.value = model.value;
  }
}

class _ListViewMultiSelectItemWidget extends StatelessWidget {
  const _ListViewMultiSelectItemWidget({
    required this.model,
    this.isEditing = false,
    this.onDelete,
  });

  final MultiSelectItemModel model;

  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  Widget build(BuildContext context) => _ListViewItemBaseWidget(
    model: model,
    trailing: buildValueListenable(),
    onTap: _toggleSelect,
    isEditing: isEditing,
    onDelete: onDelete,
  );

  Widget buildValueListenable() {
    return ValueListenableBuilder<bool>(
      valueListenable: model.value$,
      builder: (_, selected, __) {
        return selected
            ? const Icon(Icons.check_circle, color: Colors.blue)
            : const Icon(Icons.circle_outlined, color: Colors.grey);
      },
    );
  }

  void _toggleSelect() {
    final onTap = model.onTap;
    if (onTap != null) {
      onTap();
    } else {
      model.value$.value = !model.value$.value;
    }
  }
}

class _ListViewCustomItemWidget extends StatelessWidget {
  const _ListViewCustomItemWidget({
    required this.model,
    this.isEditing = false,
    this.onDelete,
  });

  final CustomItemModel model;

  final bool isEditing;
  final Function(ListViewItem item)? onDelete;

  @override
  Widget build(BuildContext context) => model.customWidgetBuilder?.call(context) ??
      _ListViewItemBaseWidget(
        model: model,
        leading: model.leading,
        title: model.titleWidget,
        subtitle: model.subtitleWidget,
        trailing: model.trailing,
        onTap: model.onTap,
        isEditing: isEditing,
        onDelete: onDelete,
      );
}