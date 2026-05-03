import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';
import 'ringtone_service.dart';

RingtoneService createRingtoneService() => NativeRingtoneService();

class NativeRingtoneService extends RingtoneService {
  final AudioPlayer _player = AudioPlayer();
  bool _isRinging = false;
  bool _isVibrating = false;

  void _log(String msg) => debugPrint('[RingtoneService] $msg');

  @override
  bool get isRinging => _isRinging;

  @override
  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;

    final assets = ['audio/ringtone.mp3', 'audio/notification.mp3'];
    bool played = false;

    for (final asset in assets) {
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(1.0);
        await _player.play(AssetSource(asset));
        _log('Sonnerie démarrée: $asset');
        played = true;
        break;
      } catch (e) {
        _log('Erreur audio $asset: $e');
      }
    }

    if (!played) _log('Aucun fichier audio — vibration seule');
    _startVibration();
  }

  void _startVibration() async {
    if (_isVibrating) return;
    _isVibrating = true;
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) { _isVibrating = false; return; }
      while (_isRinging && _isVibrating) {
        await Vibration.vibrate(duration: 1000);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      _log('Vibration error: $e');
    } finally {
      _isVibrating = false;
    }
  }

  @override
  Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;
    _isVibrating = false;
    try {
      await _player.stop();
      await Vibration.cancel();
      _log('Sonnerie stoppée');
    } catch (e) {
      _log('Stop error: $e');
    }
  }

  @override
  Future<void> startDialingTone() async {
    if (_isRinging) return;
    _isRinging = true;

    final assets = ['audio/dialing.mp3', 'audio/notification.mp3', 'audio/ringtone.mp3'];

    for (final asset in assets) {
      try {
        await _player.setReleaseMode(ReleaseMode.loop);
        await _player.setVolume(0.4);
        await _player.play(AssetSource(asset));
        _log('Tonalité sortante: $asset');
        return;
      } catch (e) {
        _log('Erreur audio sortant $asset: $e');
      }
    }
    _isRinging = false;
    _log('Aucune tonalité sortante (ignoré)');
  }
}