import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/navigator/navigator.dart';
import 'package:ox_common/ox_common.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_common/utils/image_picker_utils.dart';
import 'package:ox_common/utils/permission_utils.dart';
import 'package:ox_common/utils/platform_utils.dart';
import 'package:ox_common/utils/file_utils.dart';
import 'package:ox_common/utils/string_utils.dart';
import 'package:ox_common/widgets/avatar.dart';
import 'package:ox_common/widgets/common_loading.dart';
import 'package:ox_common/widgets/common_toast.dart';
import 'package:ox_localizable/ox_localizable.dart';
import 'package:nostr_core_dart/nostr.dart';
import 'package:permission_handler/permission_handler.dart';
import '../component/onboarding_step_bar.dart';
import '../controller/onboarding_controller.dart';
import 'circle_name_page.dart';

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({
    super.key,
    this.initialKeychain,
    this.initialFirstName,
    this.initialLastName,
  });

  /// When set (e.g. from Apple login), onboarding uses this keychain instead of generating a new one.
  final Keychain? initialKeychain;

  /// Pre-fill first name (e.g. from Apple givenName). Editable.
  final String? initialFirstName;

  /// Pre-fill last name (e.g. from Apple familyName). Editable.
  final String? initialLastName;

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

enum _AvatarAction { gallery, camera }

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  final TextEditingController _nameController = TextEditingController();

  late final OnboardingController _onboardingController = OnboardingController(
    isCreateNewAccount: true,
    initialKeychain: widget.initialKeychain,
  );
  
  bool _hasValidInput = false;
  File? _avatarFile;

  @override
  void initState() {
    super.initState();
    _nameController.text = [widget.initialFirstName, widget.initialLastName]
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' ');
    _nameController.addListener(_onInputChanged);
    _onInputChanged();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _onboardingController.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    // One field for the whole name: people type it the way they want it shown.
    _onboardingController.setFirstName(_nameController.text);
    _onboardingController.setLastName('');

    // Update button state
    final hasValidInput = _onboardingController.hasValidProfile;
    if (hasValidInput != _hasValidInput) {
      setState(() {
        _hasValidInput = hasValidInput;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LoseFocusWrap(
      child: CLScaffold(
        appBar: CLAppBar(),
        body: _buildBody(),
        bottomWidget: _buildNextButton(),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: EdgeInsets.symmetric(
        vertical: 24.px,
        horizontal: CLLayout.horizontalPadding,
      ),
      children: [
        const OnboardingStepBar(current: OnboardingStep.profile),
        SizedBox(height: 28.px),
        CLText.titleLarge(
          Localized.text('ox_login.whats_your_name'),
          colorToken: ColorToken.onSurface,
          isBold: true,
        ),
        SizedBox(height: 32.px),
        _buildAvatarPreview(),
        SizedBox(height: 32.px),
        _buildNameInput(),
        SizedBox(height: 24.px),
        _buildKeyNote(),
      ],
    );
  }

  /// The one thing a new user should know before going further: there is no
  /// phone number or email behind this account, only a key on this phone.
  Widget _buildKeyNote() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.px, vertical: 14.px),
      decoration: BoxDecoration(
        color: ColorToken.cardContainer.of(context),
        borderRadius: BorderRadius.circular(16.px),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.key_rounded,
            size: 20.px,
            color: ColorToken.xChat.of(context),
          ),
          SizedBox(width: 12.px),
          Expanded(
            child: CLText.bodySmall(
              Localized.text('ox_login.account_key_note'),
              colorToken: ColorToken.onSurfaceVariant,
              maxLines: null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarPreview() {
    return Center(
      child: GestureDetector(
        onTap: _showAvatarPicker,
        child: Container(
          width: 80.px,
          height: 80.px,
          child: Stack(
            children: [
              OXUserAvatar(
                imageUrl: _avatarFile?.path,
                size: 80.px,
                isFile: true,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24.px,
                  height: 24.px,
                  decoration: BoxDecoration(
                    color: ColorToken.primary.of(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ColorToken.surface.of(context),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    Icons.camera_alt,
                    size: 14.px,
                    color: ColorToken.onPrimary.of(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAvatarPicker() async {
    final result = await CLPicker.show<_AvatarAction>(
      context: context,
      title: Localized.text('ox_login.select_avatar'),
      items: [
        CLPickerItem(
          label: 'str_album'.commonLocalized(),
          value: _AvatarAction.gallery,
        ),
        if (PlatformUtils.isMobile)
          CLPickerItem(
            label: Localized.text('ox_login.camera'),
            value: _AvatarAction.camera,
          ),
      ],
    );

    if (result != null) {
      await _handleAvatarAction(result);
    }
  }

  Future<void> _handleAvatarAction(_AvatarAction action) async {
    File? imgFile;
    switch (action) {
      case _AvatarAction.gallery:
        imgFile = await _openGallery();
        break;
      case _AvatarAction.camera:
        imgFile = await _openCamera();
        break;
    }

    if (imgFile != null) {
      setState(() {
        _avatarFile = imgFile;
      });
      _onboardingController.setAvatarFile(imgFile);
    }
  }

  Future<File?> _openGallery() async {
    File? imgFile;
    DeviceInfoPlugin plugin = DeviceInfoPlugin();
    bool storagePermission = false;

    if (Platform.isAndroid && (await plugin.androidInfo).version.sdkInt >= 34) {
      Map<String, bool> result = await OXCommon.request34MediaPermission(1);
      bool readMediaImagesGranted = result['READ_MEDIA_IMAGES'] ?? false;
      bool readMediaVisualUserSelectedGranted = result['READ_MEDIA_VISUAL_USER_SELECTED'] ?? false;

      if (readMediaImagesGranted) {
        storagePermission = true;
      } else if (readMediaVisualUserSelectedGranted) {
        final filePaths = await OXCommon.select34MediaFilePaths(1);
        if (filePaths.isNotEmpty) {
          return File(filePaths[0]);
        }
        return null;
      }
    } else {
      storagePermission = await PermissionUtils.getPhotosPermission(context);
    }

    if (!storagePermission) return null;

    try {
      if (PlatformUtils.isDesktop) {
        List<Media>? list = await FileUtils.importClientFile(1);
        if (list != null && list.isNotEmpty) {
          imgFile = File(list[0].path ?? '');
        }
      } else {
        final res = await ImagePickerUtils.pickerPaths(
          galleryMode: GalleryMode.image,
          selectCount: 1,
          showGif: false,
          compressSize: 2048,
        );
        if (res.isNotEmpty) {
          imgFile = (res[0].path == null) ? null : File(res[0].path ?? '');
        }
      }
    } catch (e) {
      CommonToast.instance.show(context, 'Failed to select image: $e');
    }

    return imgFile;
  }

  Future<File?> _openCamera() async {
    File? imgFile;
    Map<Permission, PermissionStatus> statuses = await [Permission.camera].request();

    if (statuses[Permission.camera]?.isGranted ?? false) {
      try {
        Media? res = await ImagePickerUtils.openCamera(
          cameraMimeType: CameraMimeType.photo,
          compressSize: 1024,
        );
        if (res != null) {
          imgFile = File(res.path ?? '');
        }
      } catch (e) {
        CommonToast.instance.show(context, 'Failed to take photo: $e');
      }
    } else {
      PermissionUtils.showPermission(context, statuses);
    }

    return imgFile;
  }

  Widget _buildNameInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CLTextField(
          controller: _nameController,
          placeholder: Localized.text('ox_login.your_name'),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (_hasValidInput) _onNextTap();
          },
        ),
        SizedBox(height: 8.px),
        CLDescription(Localized.text('ox_login.profile_setup_name_hint')),
      ],
    );
  }

  Widget _buildNextButton() {
    return CLButton.filled(
      text: Localized.text('ox_common.next'),
      onTap: _hasValidInput ? _onNextTap : null,
      expanded: true,
      height: 48.px,
    );
  }

  void _onNextTap() async {
    OXLoading.show();
    final result = await _onboardingController.invokeLoginAction();
    final errorMessage = result.errorMessage;
    OXLoading.dismiss();
    if (errorMessage != null && errorMessage.isNotEmpty) {
      CommonToast.instance.show(context, errorMessage);
      return;
    }
    if (!mounted) return;
    OXNavigator.pushPage(
      context,
      (context) => CircleNamePage(controller: _onboardingController),
    );
  }
}
