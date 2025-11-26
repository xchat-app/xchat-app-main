import 'package:flutter/painting.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';

class CLLayout {
  static double get horizontalPadding => PlatformStyle.isUseMaterial
      ? 16.px
      : 20; // list_section.dart._kDefaultInsetGroupedRowsMargin

  // source: cupertino/list_tile.dart - _kNotchedPadding
  static EdgeInsets get kNotchedPadding =>
      EdgeInsets.symmetric(
        horizontal: 14.0,
        vertical: 10.0,
      );

  // source: cupertino/list_tile.dart - _kNotchedPaddingWithoutLeading
  static EdgeInsetsDirectional get kNotchedPaddingWithoutLeading =>
      EdgeInsetsDirectional.fromSTEB(
        28.0,
        10.0,
        14.0,
        10.0,
      );

  static double get avatarRadius => 5.0;
}