part of 'call_manager.dart';

/// Extension for managing device controls (camera, microphone, audio devices).
extension CallManagerDevice on CallManager {
  Future<void> switchCamera(String sessionId) async {
    if (_localStream == null) {
      CallLogger.warning('Local stream not found for camera switch: sessionId=$sessionId');
      return;
    }

    await DeviceManager().switchCamera(sessionId, _localStream!);
  }

  Future<void> setMuted(String sessionId, bool muted) async {
    if (_localStream == null) {
      CallLogger.warning('Local stream not found for mute: sessionId=$sessionId');
      return;
    }

    await DeviceManager().setMuted(sessionId, _localStream!, muted);
  }

  Future<void> setVideoEnabled(String sessionId, bool enabled) async {
    if (_localStream == null) {
      CallLogger.warning('Local stream not found for video toggle: sessionId=$sessionId');
      return;
    }

    await DeviceManager().setVideoEnabled(sessionId, _localStream!, enabled);
  }

  Future<void> setAudioInputDevice(String sessionId, String deviceId) async {
    if (_localStream == null) {
      CallLogger.warning('Local stream not found for audio input device: sessionId=$sessionId');
      return;
    }

    await DeviceManager().setAudioInputDevice(sessionId, _localStream!, deviceId);
  }

  Future<void> setSpeakerOn(bool on, {bool preferBluetooth = false}) async {
    await DeviceManager().setSpeakerOn(on, preferBluetooth: preferBluetooth);
  }

  Future<void> setAudioOutputDevice(String deviceId) async {
    await DeviceManager().setAudioOutputDevice(deviceId);
  }

  Future<List<CallDeviceInfo>> getAudioInputDevices() async {
    return await DeviceManager().getAudioInputDevices();
  }

  Future<List<CallDeviceInfo>> getAudioOutputDevices() async {
    return await DeviceManager().getAudioOutputDevices();
  }

  Future<List<CallDeviceInfo>> getVideoInputDevices() async {
    return await DeviceManager().getVideoInputDevices();
  }
}