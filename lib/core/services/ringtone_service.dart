// lib/core/services/ringtone_service.dart
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

/// Gère la sonnerie et les vibrations lors d'un appel entrant.
class RingtoneService {
  static final RingtoneService _instance = RingtoneService._internal();
  factory RingtoneService() => _instance;
  RingtoneService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isRinging = false;

  /// Démarre la sonnerie + vibration pour un appel entrant.
  Future<void> startRinging() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      await _player.play(AssetSource('audio/ringtone.mp3'));
    } catch (e) {
      debugPrint('[Ringtone] Audio error: $e');
    }

    _startVibration();
  }

  void _startVibration() async {
    try {
      // BUG FIX: vibration ^2.0.0 API — use hasVibrator() properly
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) return;

      while (_isRinging) {
        await Vibration.vibrate(duration: 800);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } catch (e) {
      debugPrint('[Ringtone] Vibration error: $e');
    }
  }

  /// Arrête la sonnerie et la vibration.
  Future<void> stopRinging() async {
    if (!_isRinging) return;
    _isRinging = false;

    try {
      await _player.stop();
      Vibration.cancel();
    } catch (e) {
      debugPrint('[Ringtone] Stop error: $e');
    }
  }

  /// Son de tonalité lors d'un appel sortant (attente de réponse).
  Future<void> startDialingTone() async {
    if (_isRinging) return;
    _isRinging = true;

    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(0.6);
      await _player.play(AssetSource('audio/dialing.mp3'));
    } catch (e) {
      debugPrint('[Ringtone] Dialing error: $e');
    }
  }

  bool get isRinging => _isRinging;

  void dispose() {
    _player.dispose();
  }
}