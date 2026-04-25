import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/widgets/avatar_widget.dart';

class CallPage extends ConsumerStatefulWidget {
  final CallModel call;

  const CallPage({super.key, required this.call});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  late CallModel _call;
  bool _muted = false;
  bool _speakerOn = false;
  bool _cameraOff = false;
  Duration _duration = Duration.zero;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _call = widget.call;
    if (_call.isActive) _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
    });
  }

  Future<void> _answer() async {
    try {
      await ApiClient().answerCall(_call.id);
      setState(() => _call = CallModel(
            id: _call.id,
            conversationId: _call.conversationId,
            callerId: _call.callerId,
            caller: _call.caller,
            type: _call.type,
            status: 'active',
            startedAt: DateTime.now(),
            createdAt: _call.createdAt,
          ));
      _startTimer();
    } catch (_) {}
  }

  Future<void> _reject() async {
    try {
      await ApiClient().rejectCall(_call.id);
    } catch (_) {}
    if (mounted) context.pop();
  }

  Future<void> _end() async {
    try {
      await ApiClient().endCall(_call.id);
    } catch (_) {}
    _timer?.cancel();
    if (mounted) context.pop();
  }

  String get _durationDisplay {
    final m = _duration.inMinutes;
    final s = _duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            // ─── Caller info ───────────────────────────────────
            Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.3), width: 3),
                  ),
                  child: ClipOval(
                    child: AvatarWidget(
                      name: _call.caller?.fullName ?? 'Appel',
                      size: 100,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _call.caller?.fullName ?? 'Appel entrant',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Nunito',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _call.isPending
                      ? 'Appel entrant...'
                      : _call.isActive
                          ? _durationDisplay
                          : _call.status,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontFamily: 'Nunito',
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _call.isAudio ? Icons.call_rounded : Icons.videocam_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _call.isAudio ? 'Appel audio' : 'Appel vidéo',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontFamily: 'Nunito',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const Spacer(),

            // ─── Controls ──────────────────────────────────────
            if (_call.isPending) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRoundButton(
                    icon: Icons.call_end_rounded,
                    color: AppColors.error,
                    label: 'Refuser',
                    onTap: _reject,
                  ),
                  _buildRoundButton(
                    icon: Icons.call_rounded,
                    color: AppColors.success,
                    label: 'Répondre',
                    onTap: _answer,
                  ),
                ],
              ),
            ] else if (_call.isActive) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSmallButton(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _muted ? 'Micro off' : 'Micro',
                    active: _muted,
                    onTap: () => setState(() => _muted = !_muted),
                  ),
                  _buildSmallButton(
                    icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: 'Haut-parleur',
                    active: _speakerOn,
                    onTap: () => setState(() => _speakerOn = !_speakerOn),
                  ),
                  if (_call.isVideo)
                    _buildSmallButton(
                      icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                      label: 'Caméra',
                      active: _cameraOff,
                      onTap: () => setState(() => _cameraOff = !_cameraOff),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              Center(
                child: _buildRoundButton(
                  icon: Icons.call_end_rounded,
                  color: AppColors.error,
                  label: 'Raccrocher',
                  onTap: _end,
                ),
              ),
            ],

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildRoundButton({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: active ? AppColors.primaryDark : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 11,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }
}