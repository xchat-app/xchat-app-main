import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:chatcore/chat-core.dart';
import 'package:ox_common/utils/storage_key_tool.dart';
import 'package:ox_common/utils/throttle_utils.dart';
import 'package:ox_common/utils/user_config_tool.dart';
import 'package:ox_localizable/ox_localizable.dart';

import 'ox_userinfo_manager.dart';

enum SoundType { Message_Received, Message_Sent, Zap_Received, Zap_Sent }

enum SoundTheme {
  classic(1, 'classic', 'str_default'),
  ostrich(2, 'ostrich', 'str_ostrich');

  final int id;
  final String name;
  final String symbol;

  const SoundTheme(this.id, this.name, this.symbol);
  
  String get localizedSymbol => Localized.text('ox_common.$symbol');
}

class PromptToneManager {
  bool Function(String chatId, String messageId)? isCurrencyChatPage;
  bool isAppPaused = false;

  static final PromptToneManager sharedInstance = PromptToneManager._internal();

  final AudioPlayer _player;
  /// The call ringtone has a player of its own. On Android, audioplayers
  /// writes the system audio mode and speakerphone whenever a player changes
  /// context, so with one player shared by ringtone and message sounds every
  /// call began by putting the phone back in normal mode with the speaker off,
  /// right after WebRTC had set it up for the call.
  final AudioPlayer _callPlayer;
  final _throttle = ThrottleUtils(delay: Duration(milliseconds: 3000));

  PromptToneManager._internal()
      : _player = AudioPlayer(),
        _callPlayer = AudioPlayer();

  SoundTheme _currentSoundTheme = SoundTheme.classic;

  SoundTheme get currentSoundTheme => _currentSoundTheme;

  set currentSoundTheme(SoundTheme theme) {
    _currentSoundTheme = theme;
  }

  static AudioContext get _defaultAudioContext => AudioContextConfig(
        respectSilence: Platform.isIOS ? true : false,
        stayAwake: false,
        focus:
            Platform.isIOS ? AudioContextConfigFocus.gain : AudioContextConfigFocus.mixWithOthers,
      ).build();

  Future setup() async {
    await AudioPlayer.global.setAudioContext(_defaultAudioContext);
    // Each player gets its context once, here, before any call, so a later
    // play() never changes it.
    await _player.setAudioContext(_defaultAudioContext);
    await _callPlayer.setAudioContext(_callingAudioContext);
  }

  initSoundTheme() {
    int index = UserConfigTool.getSetting(StorageSettingKey.KEY_SOUND_THEME.name, defaultValue: 1);
    currentSoundTheme = index == SoundTheme.classic.id
        ? SoundTheme.classic
        : SoundTheme.ostrich;
  }

  void playMessageReceived() async {
    _playSound(SoundType.Message_Received);
  }

  void playMessageSent() async {
    _playSound(SoundType.Message_Sent);
  }

  void playZapReceived() async {
    _playSound(SoundType.Zap_Received);
  }

  void playZapSent() async {
    _playSound(SoundType.Zap_Sent);
  }

  void _playSound(SoundType type) async {
    if (isAppPaused || !OXUserInfoManager.sharedInstance.canSound) return;
    _throttle(() async {
      String source = '';
      switch (type) {
        case SoundType.Message_Received:
          source = 'sounds/${_currentSoundTheme.name}/message-receive.mp3';
        case SoundType.Message_Sent:
          source = 'sounds/${_currentSoundTheme.name}/message-send.mp3';
        case SoundType.Zap_Received:
          source = 'sounds/${_currentSoundTheme.name}/zap-receive.mp3';
        case SoundType.Zap_Sent:
          source = 'sounds/${_currentSoundTheme.name}/zap-send.mp3';
      }
      if (_player.state != PlayerState.playing) {
        _player.setReleaseMode(ReleaseMode.release);
        await _setGlobalAudioContext(_defaultAudioContext);
        _player.play(
          AssetSource(source),
          ctx: _defaultAudioContext,
        );
      }
    });
  }

  /// AudioContext for call ringtone: follows system mute switch (respectSilence).
  static AudioContext get _callingAudioContext => AudioContextConfig(
        respectSilence: true,
        stayAwake: false,
        focus: Platform.isIOS
            ? AudioContextConfigFocus.gain
            : AudioContextConfigFocus.mixWithOthers,
      ).build();

  Future<void> playCalling() async {
    if (!OXUserInfoManager.sharedInstance.canSound) return;
    await _callPlayer.stop();
    _callPlayer.setReleaseMode(ReleaseMode.loop);
    await _setGlobalAudioContext(_callingAudioContext);
    await _callPlayer.play(
      AssetSource('sounds/${_currentSoundTheme.name}/calling.mp3'),
      ctx: _callingAudioContext,
    );
  }

  Future<void> stopPlay() async {
    await _callPlayer.stop();
    await _player.stop();
    await _setGlobalAudioContext(_defaultAudioContext);
  }

  /// On Android the global context writes the system audio mode and the
  /// speakerphone. stopPlay() runs as a call connects, so it took the live
  /// call out of communication mode and switched its speaker off; a message
  /// sound mid-call did the same. Each play passes its own context, which is
  /// all Android needs, and setup() sets the global one once at start.
  Future<void> _setGlobalAudioContext(AudioContext context) async {
    if (Platform.isAndroid) return;
    await AudioPlayer.global.setAudioContext(context);
  }
}
