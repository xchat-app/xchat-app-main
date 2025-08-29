import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ox_common/business_interface/ox_usercenter/interface.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/ox_common.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/image_picker_utils.dart';
import 'package:ox_common/utils/permission_utils.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:flutter_zxing/flutter_zxing.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'common_image.dart';

class CommonScanPage extends StatefulWidget {
  @override
  CommonScanPageState createState() => CommonScanPageState();
}

class CommonScanPageState extends State<CommonScanPage> with SingleTickerProviderStateMixin{
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  late AnimationController _controller;
  late double _scanArea;

  @override
  void initState() {
    super.initState();
    _scanArea = (Adapt.screenW < 375 ||
        Adapt.screenH < 400)
        ? Adapt.px(160)
        : Adapt.px(260);
    _controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: 3),
    )..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
        _controller.forward();
      }
    });
    _controller.forward();

  }

  @override
  void reassemble() {
    super.reassemble();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CLScaffold(
      appBar: CLAppBar(
        title: 'str_scan'.commonLocalized(),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(top: 1, child: _buildQrView(context)),
          Positioned(
            width: MediaQuery.of(context).size.width,
            bottom: Adapt.px(56),
            child: Container(
              margin: EdgeInsets.only(left: Adapt.px(24), right: Adapt.px(24), top: Adapt.px(16)),
              // height: Adapt.px(105),
              width: double.infinity,
              child: Row(
                children: [
                  Expanded(
                      child: GestureDetector(
                    child: Container(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          SizedBox(
                            height: Adapt.px(20),
                          ),
                          _itemView('icon_business_card.png'),
                          SizedBox(
                            height: Adapt.px(7),
                          ),
                          CLText.labelSmall(
                            'str_my_idcard'.commonLocalized(),
                            colorToken: ColorToken.white,
                          ),
                        ],
                      ),
                    ),
                    onTap: () {
                      OXUserCenterInterface.pushQRCodeDisplayPage(context);
                    },
                  )),
                  Container(
                    width: 0.5,
                    height: 80.px,
                    color: ColorToken.white.of(context),
                  ),
                  Expanded(
                      child: GestureDetector(
                    child: Container(
                      color: Colors.transparent,
                      child: Column(
                        children: [
                          SizedBox(
                            height: Adapt.px(20),
                          ),
                          _itemView('icon_scan_qr.png'),
                          SizedBox(
                            height: Adapt.px(7),
                          ),
                          CLText.labelSmall(
                            'str_album'.commonLocalized(),
                            colorToken: ColorToken.white,
                          ),
                        ],
                      ),
                    ),
                    onTap: _onPicTap,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _itemView(String iconName) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Center(
          child: CLIcon(
            iconName: 'icon_btn_bg.png',
            package: 'ox_common',
            size: 54.px,
            color: ColorToken.white.of(context),
          ),
        ),
        Center(
          child: CommonImage(
            iconName: iconName,
            size: 24.px,
            color: ColorToken.black.of(context),
          ),
        ),
      ],
    );
  }

  void _onPicTap() async {
    DeviceInfoPlugin plugin = DeviceInfoPlugin();
    bool storagePermission = false;
    File? _imgFile;
    if (Platform.isAndroid && (await plugin.androidInfo).version.sdkInt >= 34) {
      Map<String, bool> result = await OXCommon.request34MediaPermission(1);
      bool readMediaImagesGranted = result['READ_MEDIA_IMAGES'] ?? false;
      bool readMediaVisualUserSelectedGranted = result['READ_MEDIA_VISUAL_USER_SELECTED'] ?? false;
      if (readMediaImagesGranted) {
        storagePermission = true;
      } else if (readMediaVisualUserSelectedGranted) {
        final filePaths = await OXCommon.select34MediaFilePaths(1);
        _imgFile = File(filePaths[0]);
      }
    } else {
      storagePermission = await PermissionUtils.getPhotosPermission(context);
    }
    if (storagePermission) {
      final res = await ImagePickerUtils.pickerPaths(
        galleryMode: GalleryMode.image,
        selectCount: 1,
        showGif: false,
        compressSize: 5120,
      );
      if (res.isEmpty) return;

      _imgFile = (res[0].path == null) ? null : File(res[0].path ?? '');
    } else {
      final result = await CLAlertDialog.show<bool>(
        context: context,
        title: Localized.text('ox_common.tips'),
        content: Localized.text('ox_common.str_grant_permission_photo_hint'),
        actions: [
          CLAlertAction.cancel(),
          CLAlertAction<bool>(
            label: Localized.text('ox_common.str_go_to_settings'),
            value: true,
            isDefaultAction: true,
          ),
        ],
      );

      if (result == true) {
        await openAppSettings();
      }
      return;
    }
    try {
      String qrcode = await OXCommon.scanPath(_imgFile?.path ?? '');
      OXNavigator.pop(context, qrcode);
    } catch (e) {
      CommonToast.instance.show(context, "str_invalid_qr_code".commonLocalized());
    }
  }

  Widget _buildQrView(BuildContext context) {
    return ReaderWidget(
      onScan: _onScanSuccess,
      onScanFailure: _onScanFailure,
      scanDelay: Duration(milliseconds: 500),
      resolution: ResolutionPreset.high,
      lensDirection: CameraLensDirection.back,
      scannerOverlay: FixedScannerOverlay(
        borderColor: Colors.white,
        overlayColor: Colors.black45,
        borderRadius: 1,
        borderLength: 20,
        borderWidth: 4.px,
        cutOutSize: _scanArea,
      ),
      showFlashlight: false,
      showGallery: false,
      showToggleCamera: false,
    );
  }

  _onScanSuccess(Code? code) {
    if (code != null) {
      OXNavigator.pop(context, code.text);
    } else {
      CommonToast.instance.show(context, "str_invalid_qr_code".commonLocalized());
    }
  }

  _onScanFailure(Code? code) {
    if (code?.error?.isNotEmpty == true) {
      _showMessage(context, '${"str_error".commonLocalized()}: ${code?.error}');
    }
  }

  _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

}
