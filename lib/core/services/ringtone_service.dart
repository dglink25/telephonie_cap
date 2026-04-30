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

  // ─── Appel entrant ───────────────────────────────────────────
  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      // FIX: utilise ringtone.mp3 qui existe — dialing.mp3 absent
      await _player.play(AssetSource('audio/ringtone.mp3'));
    } catch (e) {
      debugPrint('[Ringtone] Audio error: $e');
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
      while (_isRinging && _isVibrating) {
        await Vibration.vibrate(duration: 800);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      debugPrint('[Ringtone] Vibration error: $e');
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
    } catch (e) {
      debugPrint('[Ringtone] Stop error: $e');
    }
  }

  // ─── Tonalité appel sortant ──────────────────────────────────
  /// FIX: dialing.mp3 n'existe pas — on utilise notification.mp3 en fallback
  /// ou silence si même ça échoue. On ne bloque PAS l'appel.
  Future<void> startDialingTone() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.4);
      
      await _player.play(AssetSource('audio/notification.mp3'));
    } catch (e) {
      // Echec silencieux — l'appel continue quand même
      debugPrint('[Ringtone] Dialing tone error (ignored): $e');
      _isRinging = false;
    }
  }

  bool get isRinging => _isRinging;

  void dispose() {
    _player.dispose();
  }
}