// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/foundation.dart';
import 'ringtone_service.dart';

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
      js.context.callMethod('_playWebNotificationSound', ['call']);
    } catch (e) {
      debugPrint('[WebRingtone] startRinging error: $e');
    }
  }

  @override
  Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;
    try {
      js.context.callMethod('_stopWebCallSound', []);
    } catch (e) {
      debugPrint('[WebRingtone] stopRinging error: $e');
    }
  }

  @override
  Future<void> startDialingTone() async {
    if (_isRinging) return;
    _isRinging = true;
    try {
      js.context.callMethod('_playWebNotificationSound', ['dialing']);
    } catch (e) {
      debugPrint('[WebRingtone] startDialingTone error: $e');
    }
  }
}