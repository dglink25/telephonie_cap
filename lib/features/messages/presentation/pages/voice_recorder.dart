// voice_recorder.dart - Nouveau composant réutilisable
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

class WhatsAppVoiceRecorder extends StatefulWidget {
  final Function(String path, Duration duration) onRecordingComplete;
  final VoidCallback? onCancel;
  final Color? primaryColor;

  const WhatsAppVoiceRecorder({
    super.key,
    required this.onRecordingComplete,
    this.onCancel,
    this.primaryColor,
  });

  @override
  State<WhatsAppVoiceRecorder> createState() => _WhatsAppVoiceRecorderState();
}

class _WhatsAppVoiceRecorderState extends State<WhatsAppVoiceRecorder>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();
  
  bool _isRecording = false;
  bool _isCanceling = false;
  Duration _duration = Duration.zero;
  Timer? _durationTimer;
  
  List<double> _amplitudes = List.filled(30, 0.0);
  Timer? _amplitudeTimer;
  
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;
  
  double _dragOffset = 0.0;
  bool _isDragging = false;
  
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
    
    _startRecording();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    _slideController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          Navigator.pop(context);
        }
        return;
      }

      final dir = Directory.systemTemp;
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordingPath = path;
      });

      _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _duration += const Duration(seconds: 1);
          });
        }
      });

      _startAmplitudeSimulation();
      
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('Erreur démarrage enregistrement: $e');
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _startAmplitudeSimulation() {
    final random = Random();
    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) return;
      
      setState(() {
        // Simulation d'amplitudes réalistes
        final newAmplitude = random.nextDouble() * (0.3 + random.nextDouble() * 0.7);
        _amplitudes.removeAt(0);
        _amplitudes.add(newAmplitude);
      });
    });
  }

  Future<void> _stopRecording({required bool cancel}) async {
    if (!_isRecording) return;
    
    _durationTimer?.cancel();
    _amplitudeTimer?.cancel();
    
    setState(() {
      _isRecording = false;
      if (cancel) _isCanceling = true;
    });

    final path = await _recorder.stop();
    
    if (cancel || _duration.inSeconds < 1) {
      if (path != null) {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
      if (mounted) {
        Navigator.pop(context);
        widget.onCancel?.call();
      }
      return;
    }

    if (path != null && mounted) {
      Navigator.pop(context);
      widget.onRecordingComplete(path, _duration);
    }
  }

  String _formatDuration() {
    final minutes = _duration.inMinutes;
    final seconds = _duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = widget.primaryColor ?? const Color(0xFF1B7F4A);
    
    return GestureDetector(
      onHorizontalDragStart: (details) {
        setState(() => _isDragging = true);
        _slideController.forward();
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _dragOffset = details.delta.dx;
          if (_dragOffset < -50) {
            _slideController.value = 1.0;
          }
        });
      },
      onHorizontalDragEnd: (details) {
        if (_dragOffset < -50) {
          _stopRecording(cancel: true);
        } else {
          setState(() => _isDragging = false);
          _slideController.reverse();
        }
        _dragOffset = 0;
      },
      child: Container(
        height: 80,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(40),
          child: Stack(
            children: [
              // Background avec effet de slide
              AnimatedBuilder(
                animation: _slideAnimation,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_slideAnimation.value.dx * 200, 0),
                    child: Container(
                      color: Colors.red.withOpacity(0.9),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_forever, color: Colors.white),
                            SizedBox(width: 8),
                            Text(
                              'Glisser pour annuler',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontFamily: 'Nunito',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              
              // Contenu principal
              Row(
                children: [
                  // Indicateur d'enregistrement
                  Container(
                    width: 60,
                    height: 60,
                    margin: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  
                  // Visualisation des fréquences
                  Expanded(
                    child: _buildWaveform(primaryColor),
                  ),
                  
                  // Durée
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _formatDuration(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Nunito',
                        color: Color(0xFF111B21),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform(Color color) {
    return SizedBox(
      height: 50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_amplitudes.length, (index) {
          final amplitude = _amplitudes[index];
          final height = 8.0 + (amplitude * 40).clamp(0.0, 42.0);
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.5 + amplitude * 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}