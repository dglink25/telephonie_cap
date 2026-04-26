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
      // Jouer le son de sonnerie en boucle
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(1.0);
      // Fichier assets/audio/ringtone.mp3 à placer dans le projet
      await _player.play(AssetSource('audio/ringtone.mp3'));
    } catch (e) {
      debugPrint('[Ringtone] Audio error: $e');
    }

    // Vibration en pattern (appel entrant)
    _startVibration();
  }

  void _startVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator() ?? false;
      if (!hasVibrator) return;

      // Pattern : 500ms ON, 1000ms OFF, répété
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