import 'package:flutter/foundation.dart';
import 'ringtone_service.dart';
import 'dart:js_interop';

@JS('_playWebNotificationSound')
external void _playWebNotificationSoundJS(String type);

@JS('_stopWebCallSound')
external void _stopWebCallSoundJS();

RingtoneService createRingtoneService() => WebRingtoneService();

class WebRingtoneService extends RingtoneService {
  bool _isRinging = false;

  @override
  bool get isRinging => _isRinging;

  @override
  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;
    try {
      _playWebNotificationSoundJS('call');
    } catch (e) {
      debugPrint('[WebRingtone] startRinging error: $e');
    }
  }

  @override
  Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      _stopWebCallSoundJS();
    } catch (e) {
      debugPrint('[WebRingtone] stopRinging error: $e');
    }
  }

  @override
  Future<void> startDialingTone() async {
    if (_isRinging) return;
    _isRinging = true;
    try {
      _playWebNotificationSoundJS('dialing');
    } catch (e) {
      debugPrint('[WebRingtone] startDialingTone error: $e');
    }
  }
}