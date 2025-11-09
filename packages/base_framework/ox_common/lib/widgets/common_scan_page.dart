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
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'common_image.dart';

class CommonScanPage extends StatefulWidget {
  @override
  CommonScanPageState createState() => CommonScanPageState();
}

class CommonScanPageState extends State<CommonScanPage> {
  final GlobalKey qrKey = GlobalKey(debugLabel: 'QR');
  late final MobileScannerController _scannerController;
  late double _scanArea;
  bool _isProcessingScan = false;
  String? _lastErrorMessage;

  @override
  void initState() {
    super.initState();
    _scanArea = (Adapt.screenW < 375 ||
        Adapt.screenH < 400)
        ? Adapt.px(160)
        : Adapt.px(260);
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
      autoStart: true,
    );

  }

  @override
  void reassemble() {
    super.reassemble();
    if (Platform.isAndroid) {
      _scannerController.stop();
    }
    _scannerController.start();
  }

  @override
  void dispose() {
    _scannerController.dispose();
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
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          controller: _scannerController,
          fit: BoxFit.cover,
          onDetect: _handleBarcodeDetection,
          errorBuilder: (context, error, child) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleScannerError(error);
            });
            return child ?? Container(color: Colors.black);
          },
        ),
        _ScannerOverlay(
          cutOutSize: _scanArea,
        ),
      ],
    );
  }

  void _handleBarcodeDetection(BarcodeCapture capture) {
    if (_isProcessingScan) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue ?? barcode.displayValue;
      if (value != null && value.isNotEmpty) {
        _isProcessingScan = true;
        _scannerController.stop();
        OXNavigator.pop(context, value);
        return;
      }
    }
  }

  void _handleScannerError(MobileScannerException error) {
    final details = error.errorDetails?.toString();
    final message = (details != null && details.trim().isNotEmpty)
        ? details
        : error.errorCode.name;
    if (message.isEmpty) {
      return;
    }
    if (_lastErrorMessage == message) {
      return;
    }
    _lastErrorMessage = message;
    _showMessage(context, '${"str_error".commonLocalized()}: $message');
  }

  _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  final double cutOutSize;

  const _ScannerOverlay({
    required this.cutOutSize,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final left = (width - cutOutSize) / 2;
        final top = (height - cutOutSize) / 2 - 50;
        final cornerLength = Adapt.px(24);
        final strokeWidth = 4.px;

        return Stack(
          children: [
            CustomPaint(
              size: Size(width, height),
              painter: _ScannerOverlayBackgroundPainter(
                left: left,
                top: top,
                cutOutSize: cutOutSize,
              ),
            ),
            _CornerBorder(
              top: top,
              left: left,
              size: cornerLength,
              border: Border(
                top: BorderSide(color: Colors.white, width: strokeWidth),
                left: BorderSide(color: Colors.white, width: strokeWidth),
              ),
            ),
            _CornerBorder(
              top: top,
              right: left,
              size: cornerLength,
              border: Border(
                top: BorderSide(color: Colors.white, width: strokeWidth),
                right: BorderSide(color: Colors.white, width: strokeWidth),
              ),
            ),
            _CornerBorder(
              top: top + cutOutSize - cornerLength,
              left: left,
              size: cornerLength,
              border: Border(
                bottom: BorderSide(color: Colors.white, width: strokeWidth),
                left: BorderSide(color: Colors.white, width: strokeWidth),
              ),
            ),
            _CornerBorder(
              top: top + cutOutSize - cornerLength,
              right: left,
              size: cornerLength,
              border: Border(
                bottom: BorderSide(color: Colors.white, width: strokeWidth),
                right: BorderSide(color: Colors.white, width: strokeWidth),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CornerBorder extends StatelessWidget {
  final double size;
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final Border border;

  const _CornerBorder({
    required this.size,
    required this.border,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(border: border),
        ),
      ),
    );
  }
}

class _ScannerOverlayBackgroundPainter extends CustomPainter {
  final double left;
  final double top;
  final double cutOutSize;

  _ScannerOverlayBackgroundPainter({
    required this.left,
    required this.top,
    required this.cutOutSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRect(Rect.fromLTWH(left, top, cutOutSize, cutOutSize));

    final backgroundPaint = Paint()
      ..color = Colors.black45;

    canvas.drawPath(overlayPath, backgroundPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is! _ScannerOverlayBackgroundPainter) {
      return true;
    }
    return left != oldDelegate.left ||
        top != oldDelegate.top ||
        cutOutSize != oldDelegate.cutOutSize;
  }
}