import 'ringtone_service.dart';

RingtoneService createRingtoneService() => StubRingtoneService();

class StubRingtoneService extends RingtoneService {
  bool _isRinging = false;

  @override
  bool get isRinging => _isRinging;

  @override
  Future<void> startRinging() async { _isRinging = true; }

  @override
  Future<void> stopRinging() async { _isRinging = false; }

  @override
  Future<void> startDialingTone() async { _isRinging = true; }
}