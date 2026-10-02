import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:ox_call/src/models/call_device_info.dart';
import 'package:ox_call/src/utils/call_logger.dart';

class DeviceManager {
  static final DeviceManager _instance = DeviceManager._internal();
  factory DeviceManager() => _instance;
  DeviceManager._internal();

  List<CallDeviceInfo>? _audioInputDevices;
  List<CallDeviceInfo>? _audioOutputDevices;
  List<CallDeviceInfo>? _videoInputDevices;

  Future<List<CallDeviceInfo>> getAudioInputDevices() async {
    if (_audioInputDevices != null) {
      return _audioInputDevices!;
    }

    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      _audioInputDevices = devices
          .where((device) => device.kind == 'audioinput')
          .map((device) => CallDeviceInfo(
            deviceId: device.deviceId,
            label: device.label,
            kind: device.kind ?? '',
          ))
          .toList();

      CallLogger.info('Found ${_audioInputDevices!.length} audio input devices');
      return _audioInputDevices!;
    } catch (e) {
      CallLogger.error('Failed to enumerate audio input devices: $e');
      return [];
    }
  }

  Future<List<CallDeviceInfo>> getAudioOutputDevices() async {
    if (_audioOutputDevices != null) {
      return _audioOutputDevices!;
    }

    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      _audioOutputDevices = devices
          .where((device) => device.kind == 'audiooutput')
          .map((device) => CallDeviceInfo(
            deviceId: device.deviceId,
            label: device.label,
            kind: device.kind ?? '',
          ))
          .toList();

      CallLogger.info('Found ${_audioOutputDevices!.length} audio output devices');
      return _audioOutputDevices!;
    } catch (e) {
      CallLogger.error('Failed to enumerate audio output devices: $e');
      return [];
    }
  }

  Future<List<CallDeviceInfo>> getVideoInputDevices() async {
    if (_videoInputDevices != null) {
      return _videoInputDevices!;
    }

    try {
      final devices = await navigator.mediaDevices.enumerateDevices();
      _videoInputDevices = devices
          .where((device) => device.kind == 'videoinput')
          .map((device) => CallDeviceInfo(
            deviceId: device.deviceId,
            label: device.label,
            kind: device.kind ?? '',
          ))
          .toList();

      CallLogger.info('Found ${_videoInputDevices!.length} video input devices');
      return _videoInputDevices!;
    } catch (e) {
      CallLogger.error('Failed to enumerate video input devices: $e');
      return [];
    }
  }

  void refreshDevices() {
    _audioInputDevices = null;
    _audioOutputDevices = null;
    _videoInputDevices = null;
  }

  Future<void> switchCamera(String sessionId, MediaStream localStream) async {
    try {
      final videoTracks = localStream.getVideoTracks();
      if (videoTracks.isEmpty) {
        CallLogger.warning('No video track found for camera switch');
        return;
      }
      final videoTrack = videoTracks.first;

      await Helper.switchCamera(videoTrack);
      CallLogger.info('Camera switched: sessionId=$sessionId');
    } catch (e) {
      CallLogger.error('Failed to switch camera: $e');
      rethrow;
    }
  }

  Future<void> setAudioInputDevice(
    String sessionId,
    MediaStream localStream,
    String deviceId,
  ) async {
    try {
      final audioTracks = localStream.getAudioTracks();
      if (audioTracks.isEmpty) {
        CallLogger.warning('No audio track found for device switch');
        return;
      }

      // Note: switchAudioInput may not be available in flutter_webrtc 1.2.1
      // Audio input device switching may require recreating the MediaStream
      CallLogger.info('Audio input device changed: sessionId=$sessionId, deviceId=$deviceId');
      CallLogger.warning('switchAudioInput is not available, device change may require stream recreation');
    } catch (e) {
      CallLogger.error('Failed to set audio input device: $e');
      rethrow;
    }
  }

  Future<void> setAudioOutputDevice(String deviceId) async {
    try {
      // selectAudioOutput with AudioOutputOptions in flutter_webrtc 1.2.1
      final options = AudioOutputOptions(deviceId: deviceId);
      await navigator.mediaDevices.selectAudioOutput(options);
      CallLogger.info('Audio output device changed: deviceId=$deviceId');
    } catch (e) {
      CallLogger.error('Failed to set audio output device: $e');
      rethrow;
    }
  }

  /// [preferBluetooth] keeps a connected headset over the speaker; it is for
  /// the default route, not for the user asking for the speaker.
  Future<void> setSpeakerOn(bool on, {bool preferBluetooth = false}) async {
    try {
      if (on && preferBluetooth) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } else {
        await Helper.setSpeakerphoneOn(on);
      }
      CallLogger.info('Speaker ${on ? 'on' : 'off'}');
    } catch (e) {
      CallLogger.error('Failed to switch the speaker: $e');
    }
  }

  Future<void> setMuted(String sessionId, MediaStream localStream, bool muted) async {
    try {
      localStream.getAudioTracks().forEach((track) {
        track.enabled = !muted;
      });
      CallLogger.info('Audio muted: sessionId=$sessionId, muted=$muted');
    } catch (e) {
      CallLogger.error('Failed to set muted: $e');
      rethrow;
    }
  }

  Future<void> setVideoEnabled(String sessionId, MediaStream localStream, bool enabled) async {
    try {
      localStream.getVideoTracks().forEach((track) {
        track.enabled = enabled;
      });
      CallLogger.info('Video enabled: sessionId=$sessionId, enabled=$enabled');
    } catch (e) {
      CallLogger.error('Failed to set video enabled: $e');
      rethrow;
    }
  }
}