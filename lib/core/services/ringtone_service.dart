import 'package:flutter/foundation.dart';

// Conditional imports
import 'ringtone_service_stub.dart'
    if (dart.library.html) 'ringtone_service_web.dart'
    if (dart.library.io) 'ringtone_service_native.dart';

abstract class RingtoneService {
  static RingtoneService? _instance;
  static RingtoneService get instance => _instance ??= createRingtoneService();

  Future<void> startRinging();
  Future<void> stopRinging();
  Future<void> startDialingTone();
  bool get isRinging;
}