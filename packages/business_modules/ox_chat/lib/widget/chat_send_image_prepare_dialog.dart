import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:ox_common/component.dart';
import 'package:ox_common/utils/adapt.dart';
import 'package:ox_localizable/ox_localizable.dart';

class ChatSendImagePrepareDialog {
  static Future<bool> show(BuildContext context, File imageFile) async {
    final result = await CLAlertDialog.showWithWidget<bool>(
      context: context,
      title: '',
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: 355.px,
        ),
        child: IntrinsicHeight(
          child: Image.file(
            imageFile,
            width: double.infinity,
            fit: BoxFit.contain,
          ),
        ),
      ),
      actions: [
        CLAlertAction.cancel(),
        CLAlertAction<bool>(
          label: Localized.text('ox_chat.send'),
          value: true,
          isDefaultAction: true,
        ),
      ],
    );
    return result ?? false;
  }
}