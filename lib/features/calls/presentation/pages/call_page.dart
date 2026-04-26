import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// WebRTC uniquement sur les plateformes natives
import 'package:flutter_webrtc/flutter_webrtc.dart'
    if (dart.library.html) '../../../../core/stubs/webrtc_stub.dart';

import '../../../../core/services/call_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/widgets/avatar_widget.dart';
// Provider de l'utilisateur courant (défini dans auth_provider.dart)
import '../../../auth/data/auth_provider.dart';

class CallPage extends ConsumerStatefulWidget {
  final CallModel call;

  const CallPage({super.key, required this.call});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage> {
  late CallModel _call;
  final CallService _callService = CallService();

  bool _muted = false;
  bool _speakerOn = false;
  bool _cameraOff = false;
  bool _frontCamera = true;

  Duration _duration = Duration.zero;
  Timer? _timer;

  // Renderers WebRTC – instanciés uniquement sur native
  RTCVideoRenderer? _localRenderer;
  RTCVideoRenderer? _remoteRenderer;

  @override
  void initState() {
    super.initState();
    _call = widget.call;

    if (!kIsWeb) {
      _localRenderer = RTCVideoRenderer();
      _remoteRenderer = RTCVideoRenderer();
      _initRenderers();
    }

    _setupCallServiceCallbacks();

    if (_call.isActive) _startTimer();
  }

  Future<void> _initRenderers() async {
    if (kIsWeb) return;
    await _localRenderer!.initialize();
    await _remoteRenderer!.initialize();

    if (_callService.localStream != null) {
      _localRenderer!.srcObject = _callService.localStream;
    }
    if (_callService.remoteStream != null) {
      _remoteRenderer!.srcObject = _callService.remoteStream;
    }
  }

  void _setupCallServiceCallbacks() {
    if (!kIsWeb) {
      _callService.onLocalStream = (stream) {
        if (mounted) setState(() => _localRenderer!.srcObject = stream);
      };

      _callService.onRemoteStream = (stream) {
        if (mounted) setState(() => _remoteRenderer!.srcObject = stream);
      };
    }

    _callService.onCallStatusChanged = (status) {
      if (!mounted) return;
      switch (status) {
        case 'active':
          setState(() {
            _call = _call.copyWith(
              status: 'active',
              startedAt: DateTime.now(),
            );
          });
          _startTimer();
          break;
        case 'rejected':
        case 'ended':
          _timer?.cancel();
          if (mounted) context.pop();
          break;
      }
    };
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _duration += const Duration(seconds: 1));
    });
  }

  // ── Actions ──────────────────────────────────────────────────
  Future<void> _answer() async {
    final authState = ref.read(authProvider);
    final currentUser = authState.user;
    final success = await _callService.answerCall(
      _call.id,
      _call.conversationId,
      currentUser?.id ?? 0,
    );

    if (success && mounted) {
      setState(() {
        _call = _call.copyWith(
          status: 'active',
          startedAt: DateTime.now(),
        );
      });
      _startTimer();
    }
  }

  Future<void> _reject() async {
    await _callService.rejectCall(_call.id);
    if (mounted) context.pop();
  }

  Future<void> _end() async {
    _timer?.cancel();
    await _callService.endCall();
    if (mounted) context.pop();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _callService.toggleMute(_muted);
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    _callService.toggleCamera(_cameraOff);
  }

  Future<void> _switchCamera() async {
    setState(() => _frontCamera = !_frontCamera);
    if (!kIsWeb) await _callService.switchCamera();
  }

  // ── Helpers ──────────────────────────────────────────────────
  String get _durationDisplay {
    final m = _duration.inMinutes;
    final s = _duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  int? get _currentUserId {
    return ref.read(authProvider).user?.id;
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (!kIsWeb) {
      _localRenderer?.dispose();
      _remoteRenderer?.dispose();
    }
    _callService.onLocalStream = null;
    _callService.onRemoteStream = null;
    _callService.onCallStatusChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _call.isVideo;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.primaryDark,
      body: Stack(
        children: [
          // ── Fond vidéo distant ─────────────────────────────────
          if (!kIsWeb && isVideo && _call.isActive && _remoteRenderer != null)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer!,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            )
          else
            _buildAudioBackground(),

          // ── Vidéo locale (miniature) ──────────────────────────
          if (!kIsWeb &&
              isVideo &&
              _call.isActive &&
              !_cameraOff &&
              _localRenderer != null)
            Positioned(
              top: isWide ? 80 : 60,
              right: 16,
              width: isWide ? 160 : 100,
              height: isWide ? 220 : 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: RTCVideoView(
                  _localRenderer!,
                  mirror: _frontCamera,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

          // ── Message Web (WebRTC non supporté dans le navigateur) ──
          if (kIsWeb && isVideo)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.videocam_off_rounded,
                          color: Colors.white54, size: 48),
                      SizedBox(height: 12),
                      Text(
                        'Vidéo non disponible sur navigateur',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Overlay principal ───────────────────────────────────
          SafeArea(
            child: isWide
                ? _buildWideLayout(isVideo)
                : _buildNarrowLayout(isVideo),
          ),
        ],
      ),
    );
  }

  // Layout large (web / tablette)
  Widget _buildWideLayout(bool isVideo) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildCallerInfo(),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControls(isVideo),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ],
    );
  }

  // Layout étroit (mobile)
  Widget _buildNarrowLayout(bool isVideo) {
    return Column(
      children: [
        const SizedBox(height: 20),
        _buildCallerInfo(),
        const Spacer(),
        _buildControls(isVideo),
        const SizedBox(height: 48),
      ],
    );
  }

  // ── Fond dégradé audio ────────────────────────────────────────
  Widget _buildAudioBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryDark, Color(0xFF0A3520)],
        ),
      ),
    );
  }

  // ── Informations sur l'appelant ───────────────────────────────
  Widget _buildCallerInfo() {
    final statusText = _call.isPending
        ? (_call.callerId == _currentUserId
            ? 'Appel en cours...'
            : 'Appel entrant...')
        : _call.isActive
            ? _durationDisplay
            : _call.status;

    return Column(
      children: [
        // Avatar animé
        _AnimatedAvatar(
          child: AvatarWidget(
            name: _call.caller?.fullName ?? 'Appel',
            size: 110,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _call.caller?.fullName ?? 'Appel entrant',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            fontFamily: 'Nunito',
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 4),
        if (_call.caller?.phoneNumber != null) ...[
          Text(
            _call.caller!.phoneNumber!,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 14,
              fontFamily: 'Nunito',
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          statusText,
          style: TextStyle(
            color: Colors.white.withOpacity(0.75),
            fontSize: 16,
            fontFamily: 'Nunito',
          ),
        ),
        const SizedBox(height: 10),
        // Badge type d'appel
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withOpacity(0.2), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _call.isAudio
                    ? Icons.call_rounded
                    : Icons.videocam_rounded,
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
    );
  }

  // ── Contrôles d'appel ─────────────────────────────────────────
  Widget _buildControls(bool isVideo) {
    if (_call.isPending) {
      final isCaller = _call.callerId == _currentUserId;
      if (isCaller) {
        return Center(
          child: _buildRoundButton(
            icon: Icons.call_end_rounded,
            color: AppColors.error,
            label: 'Annuler',
            onTap: _end,
          ),
        );
      } else {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildRoundButton(
                icon: Icons.call_end_rounded,
                color: AppColors.error,
                label: 'Refuser',
                onTap: _reject,
              ),
              _buildRoundButton(
                icon: _call.isVideo
                    ? Icons.videocam_rounded
                    : Icons.call_rounded,
                color: AppColors.success,
                label: 'Répondre',
                onTap: _answer,
              ),
            ],
          ),
        );
      }
    }

    if (_call.isActive) {
      return Column(
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              _buildSmallButton(
                icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                label: _muted ? 'Micro off' : 'Micro',
                active: _muted,
                onTap: _toggleMute,
              ),
              _buildSmallButton(
                icon: _speakerOn
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded,
                label: 'Enceinte',
                active: _speakerOn,
                onTap: () => setState(() => _speakerOn = !_speakerOn),
              ),
              if (isVideo && !kIsWeb) ...[
                _buildSmallButton(
                  icon: _cameraOff
                      ? Icons.videocam_off_rounded
                      : Icons.videocam_rounded,
                  label: 'Caméra',
                  active: _cameraOff,
                  onTap: _toggleCamera,
                ),
                _buildSmallButton(
                  icon: Icons.flip_camera_ios_rounded,
                  label: 'Changer',
                  active: false,
                  onTap: _switchCamera,
                ),
              ],
            ],
          ),
          const SizedBox(height: 32),
          _buildRoundButton(
            icon: Icons.call_end_rounded,
            color: AppColors.error,
            label: 'Raccrocher',
            onTap: _end,
          ),
        ],
      );
    }

    return const SizedBox.shrink();
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 32),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: active ? Colors.white : Colors.white.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: active
                    ? Colors.white
                    : Colors.white.withOpacity(0.25),
                width: 1.5,
              ),
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
              color: Colors.white.withOpacity(0.75),
              fontSize: 11,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }
}

// ── Avatar avec animation de pulsation ────────────────────────
class _AnimatedAvatar extends StatefulWidget {
  final Widget child;
  const _AnimatedAvatar({required this.child});

  @override
  State<_AnimatedAvatar> createState() => _AnimatedAvatarState();
}

class _AnimatedAvatarState extends State<_AnimatedAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.35),
            width: 3,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withOpacity(0.1),
              blurRadius: 20,
              spreadRadius: 4,
            ),
          ],
        ),
        child: ClipOval(child: widget.child),
      ),
    );
  }
}