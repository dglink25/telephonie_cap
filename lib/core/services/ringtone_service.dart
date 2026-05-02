import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Gère la sonnerie et les vibrations lors d'un appel entrant ou sortant.
class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isRinging = false;
  bool _isVibrating = false;

  void _log(String msg) => debugPrint('[RingtoneService] $msg');

  // ─── Appel entrant ───────────────────────────────────────────
  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;

    // Essayer ringtone.mp3, puis notification.mp3, puis silence
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
        _log('Erreur audio $asset: $e (essai suivant)');
      }
    }

    if (!played) {
      _log('Aucun fichier audio disponible — vibration seule');
    }

    _startVibration();
  }

  void _startVibration() async {
    if (_isVibrating) return;
    _isVibrating = true;
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) {
        _isVibrating = false;
        return;
      }
      // Pattern: vibrer 1s, pause 1s
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

  // ─── Tonalité appel sortant ──────────────────────────────────
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

    // Échec silencieux — l'appel continue
    _isRinging = false;
    _log('Aucune tonalité sortante disponible (ignoré)');
  }

  bool get isRinging => _isRinging;

  void dispose() {
    _player.dispose();
  }
}