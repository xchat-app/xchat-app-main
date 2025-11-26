import 'package:flutter/foundation.dart';
import 'package:ox_cache_manager/ox_cache_manager.dart';
import 'package:ox_common/log_util.dart';

enum AppConfigKeys {
  showMessageInfoOption('app_config_show_message_info_option');

  const AppConfigKeys(this.value);
  final String value;
}

class AppConfigHelper {
  static final Map<AppConfigKeys, ValueNotifier> _notifierCache = {};

  static ValueNotifier<bool> showMessageInfoOptionNotifier() {
    return AppConfigKeys.showMessageInfoOption._getNotifier(defaultValue: false);
  }

  static Future<void> updateShowMessageInfoOption(bool value) async {
    await AppConfigKeys.showMessageInfoOption._updateNotifier(value);
  }
}

extension _AppConfigKeysExtension on AppConfigKeys {
  Future<T> _getValue<T>({required T defaultValue}) async {
    try {
      final value = await OXCacheManager.defaultOXCacheManager.getForeverData(
        this.value,
        defaultValue: defaultValue,
      );
      if (value is T) {
        return value;
      }
      return defaultValue;
    } catch (e) {
      LogUtil.e('Failed to get app config ${this.value}: $e');
      return defaultValue;
    }
  }

  ValueNotifier<T> _getNotifier<T>({required T defaultValue}) {
    ValueNotifier? notifier = AppConfigHelper._notifierCache[this];
    if (notifier is ValueNotifier<T>) return notifier;

    notifier = ValueNotifier<T>(defaultValue);
    AppConfigHelper._notifierCache[this] = notifier;

    // Load initial value
    _getValue(defaultValue: defaultValue).then((value) {
      notifier?.value = value;
    });

    return notifier;
  }

  Future<void> _updateNotifier<T>(T value) async {
    await OXCacheManager.defaultOXCacheManager.saveForeverData(this.value, value);
    // Update cached notifier if exists
    final notifier = AppConfigHelper._notifierCache[this];
    if (notifier is ValueNotifier<T>) {
      notifier.value = value;
    }
  }
}