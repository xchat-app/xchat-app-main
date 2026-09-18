import 'package:flutter/foundation.dart';
import 'package:ox_cache_manager/ox_cache_manager.dart';

/// Whether an account has ever taken a copy of its private key.
///
/// The key on the device is the only copy of an account. Nothing on any server
/// can restore one, so a user who loses the phone loses the account outright.
/// People write to support months later having done exactly that, and the one
/// screen that explains the risk sits in Settings, where onboarding never sends
/// them. A prompt shown once at signup would be dismissed and forgotten by the
/// time it mattered, so the app keeps asking until the key has been copied.
class KeyBackupState {
  KeyBackupState._();

  static const String _suffix = '_private_key_backed_up';

  /// Scoped to the account: two people sharing a device must not answer for
  /// each other, and neither should an account the user later signs out of.
  static String _storageKey(String pubkey) => '$pubkey$_suffix';

  /// Bumped whenever the flag changes, so a banner can drop away immediately
  /// rather than waiting for whatever else happens to rebuild it.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<bool> isBackedUp(String pubkey) async {
    // With no account there is nothing to warn about, and saying "backed up"
    // keeps callers from showing a banner over a logged-out screen.
    if (pubkey.isEmpty) return true;
    final dynamic value = await OXCacheManager.defaultOXCacheManager
        .getForeverData(_storageKey(pubkey), defaultValue: false);
    return value == true;
  }

  static Future<void> markBackedUp(String pubkey) async {
    if (pubkey.isEmpty) return;
    await OXCacheManager.defaultOXCacheManager
        .saveForeverData(_storageKey(pubkey), true);
    revision.value++;
  }
}
