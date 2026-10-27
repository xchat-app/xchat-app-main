import 'package:flutter/widgets.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';

class SectionListViewItem {
  /// Creates a section with optional header and footer
  /// 
  /// [data] - List of ListViewItem to display in this section
  /// [header] - Optional string title for the section header (will be styled automatically)
  /// [headerWidget] - Optional custom widget for the section header (overrides [header] if provided)
  /// [footer] - Optional string description for the section footer (will be styled automatically)
  /// [footerWidget] - Optional custom widget for the section footer (overrides [footer] if provided)
  /// [margin] - Optional margin around the entire section
  /// [additionalDividerMargin] - Optional additional margin for dividers in CupertinoListSection.insetGrouped
  /// [isEditing] - Whether the list is in editing mode
  /// [onDelete] - Callback when an item is deleted in editing mode
  SectionListViewItem({
    required this.data,
    String? header,
    Widget? headerWidget,
    String? footer,
    Widget? footerWidget,
    this.margin,
    this.additionalDividerMargin,
    this.isEditing = false,
    this.onDelete,
  }) : headerWidget = headerWidget
      ?? (header != null ? _buildSectionHeader(header) : null),
       footerWidget = footerWidget
      ?? (footer != null ? _buildSectionFooter(footer) : null),
       _isButtonSection = false,
       _buttonOnTap = null,
       _buttonType = null,
       _buttonText = null;

  /// Constructor for a section that displays a single button
  /// Similar to the "Sign Out" button in iPhone's Apple ID settings
  SectionListViewItem.button({
    required String text,
    required VoidCallback onTap,
    ButtonType type = ButtonType.secondary,
  }) : data = [],
       headerWidget = null,
       footerWidget = null,
       isEditing = false,
       onDelete = null,
       _isButtonSection = true,
       _buttonOnTap = onTap,
       _buttonType = type,
       _buttonText = text,
       margin = null,
       additionalDividerMargin = null;

  /// List of items to display in this section
  final List<ListViewItem> data;
  
  /// Optional header widget for the section
  final Widget? headerWidget;
  
  /// Optional footer widget for the section
  final Widget? footerWidget;
  
  /// Optional margin around the entire section
  final EdgeInsetsGeometry? margin;

  /// Optional additional margin for dividers in CupertinoListSection.insetGrouped
  final double? additionalDividerMargin;

  /// Whether the CLListView inside this section is in editing mode.
  final bool isEditing;

  /// Callback when an item is deleted in editing mode.
  final Function(ListViewItem item)? onDelete;

  /// Whether this section is a button section
  final bool _isButtonSection;

  /// The onTap callback for button sections
  final VoidCallback? _buttonOnTap;

  /// The button type for styling
  final ButtonType? _buttonType;

  /// The button text
  final String? _buttonText;

  /// Getter to check if this is a button section
  bool get isButtonSection => _isButtonSection;

  /// Getter to get the button onTap callback
  VoidCallback? get buttonOnTap => _buttonOnTap;

  /// Getter to get the button type
  ButtonType? get buttonType => _buttonType;

  /// Getter to get the button text
  String? get buttonText => _buttonText;

  /// Builds a styled section header widget
  /// 
  /// Uses CLText.titleSmall with appropriate padding for Material Design
  static Widget _buildSectionHeader(String title) {
    Widget widget = CLText.titleSmall(title);
    if (PlatformStyle.isUseMaterial) {
      widget = Padding(
        padding: EdgeInsetsDirectional.only(
          start: 20.px,
          top: 16.px,
        ),
        child: widget,
      );
    }
    return widget;
  }

  /// Builds a styled section footer widget
  /// 
  /// Uses `CLDescription.forSectionFooter` to ensure consistent spacing and style.
  static Widget _buildSectionFooter(String title) {
    return CLDescription.forSectionFooter(title);
  }
}

/// Button types for styling
enum ButtonType {
  /// Primary action (positive, highlighted)
  primary,
  
  /// Secondary action (neutral)
  secondary,
  
  /// Destructive action (dangerous, highlighted in red)
  destructive,
}