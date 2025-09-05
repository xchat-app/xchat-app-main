
abstract class ConstantInterface {

  const ConstantInterface();

  String get baseUrl => 'https://www.0xchat.com';

  String get njumpURL =>  'https://njump.me/';

  String get APP_SCHEME => 'xchat';

  /// share app link domain
  String get SHARE_APP_LINK_DOMAIN => 'https://www.0xchat.com/link';

  /// Push Notifications
  int get NOTIFICATION_PUSH_NOTIFICATIONS => 0;
  /// Private Messages
  int get NOTIFICATION_PRIVATE_MESSAGES => 1;
  /// Channels
  int get NOTIFICATION_CHANNELS => 2;
  /// Zaps
  int get NOTIFICATION_ZAPS => 3;
  /// Sound
  int get NOTIFICATION_SOUND => 4;
  /// Vibrate
  int get NOTIFICATION_VIBRATE => 5;
  ///like
  int get NOTIFICATION_REACTIONS => 6;
  ///reply&repos
  int get NOTIFICATION_REPLIES => 7;
  ///groups
  int get NOTIFICATION_GROUPS => 8;

  String get serverPubkey;
  String get serverSignKey;

  /// ios Bundle id
  String get bundleId;

  /// Giphy API Key
  String get giphyApiKey;
}