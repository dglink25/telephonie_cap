import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_webrtc/flutter_webrtc.dart'
    if (dart.library.html) '../../../../core/stubs/webrtc_stub.dart';

import '../../../../core/api/api_client.dart';
import '../../../../core/services/call_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../../shared/widgets/app_modal.dart';
import '../../../auth/data/auth_provider.dart';

// ─── Provider historique appels par conversation ───────────────
final callHistoryProvider =
    FutureProvider.family<List<CallModel>, int>((ref, conversationId) async {
  final response = await ApiClient().getCallHistory(conversationId);
  final data = response.data;
  List<dynamic> list;
  if (data is Map && data.containsKey('data')) {
    list = data['data'] as List<dynamic>;
  } else if (data is List) {
    list = data;
  } else {
    list = [];
  }
  return list.map((e) => CallModel.fromJson(e as Map<String, dynamic>)).toList();
});

// ─── Page principale d'appel ──────────────────────────────────
class CallPage extends ConsumerStatefulWidget {
  final CallModel call;
  final List<UserModel> participants;

  const CallPage({
    super.key,
    required this.call,
    this.participants = const [],
  });

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage>
    with SingleTickerProviderStateMixin {
  late CallModel _call;
  final CallService _callService = CallService();

  bool _muted = false;
  bool _speakerOn = false;
  bool _cameraOff = false;
  bool _frontCamera = true;
  bool _isActionInProgress = false;

  Duration _duration = Duration.zero;
  Timer? _timer;

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

    // Si l'appel est déjà actif (répondu), démarrer le timer
    if (_call.isActive) _startTimer();
  }

  Future<void> _initRenderers() async {
    if (kIsWeb) return;
    await _localRenderer!.initialize();
    await _remoteRenderer!.initialize();

    if (_callService.localStream != null) {
      setState(() => _localRenderer!.srcObject = _callService.localStream);
    }
    if (_callService.remoteStream != null) {
      setState(() => _remoteRenderer!.srcObject = _callService.remoteStream);
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
      debugPrint('[CallPage] onCallStatusChanged: $status');

      switch (status) {
        case 'active':
          setState(() {
            _call = _call.copyWith(status: 'active', startedAt: DateTime.now());
          });
          _startTimer();
          break;
        case 'rejected':
          _timer?.cancel();
          if (mounted) {
            AppModal.show(
              context,
              type: ModalType.warning,
              title: 'Appel refusé',
              message: '${_remotePartyName} a refusé l\'appel.',
              onClose: () { if (mounted) context.pop(); },
            );
          }
          break;
        case 'ended':
          _timer?.cancel();
          if (mounted) context.pop();
          break;
        case 'missed':
          _timer?.cancel();
          if (mounted) {
            AppModal.show(
              context,
              type: ModalType.info,
              title: 'Appel sans réponse',
              message: 'Personne n\'a répondu à l\'appel.',
              onClose: () { if (mounted) context.pop(); },
            );
          }
          break;
      }
    };

    _callService.onError = (error) {
      if (!mounted) return;
      AppModal.error(context, title: 'Erreur d\'appel', message: error);
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
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    final currentUser = ref.read(authProvider).user;
    if (currentUser == null) {
      setState(() => _isActionInProgress = false);
      AppModal.error(context,
          title: 'Erreur', message: 'Utilisateur non authentifié.');
      return;
    }

    final success = await _callService.answerCall(
      _call.id,
      _call.conversationId,
      currentUser.id,
    );

    if (!mounted) return;
    setState(() => _isActionInProgress = false);

    if (success) {
      setState(() {
        _call = _call.copyWith(status: 'active', startedAt: DateTime.now());
      });
      _startTimer();
    } else {
      AppModal.error(context,
          title: 'Impossible de répondre',
          message: 'L\'appel n\'est plus disponible.',
          onClose: () { if (mounted) context.pop(); });
    }
  }

  Future<void> _reject() async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    await _callService.rejectCall(_call.id);

    if (mounted) {
      setState(() => _isActionInProgress = false);
      context.pop();
    }
  }

  Future<void> _end() async {
    if (_isActionInProgress) return;
    setState(() => _isActionInProgress = true);

    _timer?.cancel();
    await _callService.endCall();

    if (mounted) {
      setState(() => _isActionInProgress = false);
      context.pop();
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _callService.toggleMute(_muted);
  }

  void _toggleSpeaker() {
    setState(() => _speakerOn = !_speakerOn);
    // Sur Android, gérer le haut-parleur via le service natif si besoin
  }

  void _toggleCamera() {
    setState(() => _cameraOff = !_cameraOff);
    _callService.toggleCamera(_cameraOff);
  }

  Future<void> _switchCamera() async {
    setState(() => _frontCamera = !_frontCamera);
    if (!kIsWeb) await _callService.switchCamera();
  }

  void _showCallHistory() {
    if (_call.conversationId == 0) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CallHistorySheet(conversationId: _call.conversationId),
    );
  }

  String get _durationDisplay {
    final m = _duration.inMinutes;
    final s = _duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  int? get _currentUserId => ref.read(authProvider).user?.id;

  String get _remotePartyName {
    final myId = _currentUserId;
    final iAmCaller = _call.callerId == myId;
    if (iAmCaller) {
      if (_call.callee != null) return _call.callee!.fullName;
      final other = widget.participants.where((p) => p.id != myId).firstOrNull;
      return other?.fullName ?? 'Appel en cours...';
    } else {
      return _call.caller?.fullName ?? 'Appel entrant';
    }
  }

  String? get _remotePartyPhone {
    final myId = _currentUserId;
    if (_call.callerId == myId) {
      if (_call.callee != null) return _call.callee!.phoneNumber;
      final other = widget.participants.where((p) => p.id != myId).firstOrNull;
      return other?.phoneNumber;
    }
    return _call.caller?.phoneNumber;
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
    _callService.onError = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _call.isVideo;
    final size = MediaQuery.of(context).size;
    final isWide = size.width > 600;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          // Empêcher le retour arrière pendant un appel actif
          if (_call.isActive) {
            AppModal.warning(context,
                title: 'Appel en cours',
                message: 'Utilisez le bouton "Raccrocher" pour terminer l\'appel.');
          } else {
            await _end();
          }
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.primaryDark,
        body: Stack(
          children: [
            // ── Fond vidéo distant ───────────────────────────
            if (!kIsWeb && isVideo && _call.isActive && _remoteRenderer != null)
              Positioned.fill(
                child: RTCVideoView(
                  _remoteRenderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else
              _buildAudioBackground(),

            // ── Vidéo locale miniature ───────────────────────
            if (!kIsWeb && isVideo && _call.isActive && !_cameraOff && _localRenderer != null)
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

            // ── Web: vidéo non supportée ─────────────────────
            if (kIsWeb && isVideo)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_off_rounded, color: Colors.white54, size: 48),
                        SizedBox(height: 12),
                        Text(
                          'Vidéo WebRTC\nnon disponible sur ce navigateur',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontFamily: 'Nunito'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Overlay principal ────────────────────────────
            SafeArea(
              child: Column(
                children: [
                  // Barre supérieure
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        if (_call.isActive && _call.conversationId != 0)
                          IconButton(
                            icon: const Icon(Icons.history_rounded, color: Colors.white60),
                            tooltip: 'Historique',
                            onPressed: _showCallHistory,
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                  Expanded(
                    child: isWide
                        ? _buildWideLayout(isVideo)
                        : _buildNarrowLayout(isVideo),
                  ),
                ],
              ),
            ),

            // ── Indicateur d'action en cours ─────────────────
            if (_isActionInProgress)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWideLayout(bool isVideo) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_buildCallerInfo()],
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

  Widget _buildCallerInfo() {
    final myId = _currentUserId;
    final iAmCaller = _call.callerId == myId;

    String statusText;
    if (_call.isPending) {
      statusText = iAmCaller ? 'Appel en cours...' : 'Appel entrant...';
    } else if (_call.isActive) {
      statusText = _durationDisplay;
    } else {
      statusText = _call.status;
    }

    return Column(
      children: [
        _AnimatedAvatar(child: AvatarWidget(name: _remotePartyName, size: 110)),
        const SizedBox(height: 20),
        Text(
          _remotePartyName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            fontFamily: 'Nunito',
          ),
        ),
        const SizedBox(height: 4),
        if (_remotePartyPhone != null) ...[
          Text(
            _remotePartyPhone!,
            style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, fontFamily: 'Nunito'),
          ),
          const SizedBox(height: 4),
        ],
        Text(
          statusText,
          style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 16, fontFamily: 'Nunito'),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
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
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Nunito'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildControls(bool isVideo) {
    if (_call.isPending) {
      final isCaller = _call.callerId == _currentUserId;
      if (isCaller) {
        // Appelant: seulement "Annuler"
        return Center(
          child: _buildRoundButton(
            icon: Icons.call_end_rounded,
            color: AppColors.error,
            label: 'Annuler',
            onTap: _end,
            enabled: !_isActionInProgress,
          ),
        );
      } else {
        // Appelé: "Refuser" et "Répondre"
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
                enabled: !_isActionInProgress,
              ),
              _buildRoundButton(
                icon: _call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                color: AppColors.success,
                label: 'Répondre',
                onTap: _answer,
                enabled: !_isActionInProgress,
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
                icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                label: 'Enceinte',
                active: _speakerOn,
                onTap: _toggleSpeaker,
              ),
              if (isVideo && !kIsWeb) ...[
                _buildSmallButton(
                  icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
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
            enabled: !_isActionInProgress,
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
    bool enabled = true,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: enabled ? color : color.withOpacity(0.5),
              shape: BoxShape.circle,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [],
            ),
            child: enabled
                ? Icon(icon, color: Colors.white, size: 32)
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  ),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'Nunito')),
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
                color: active ? Colors.white : Colors.white.withOpacity(0.25),
                width: 1.5,
              ),
            ),
            child: Icon(icon,
                color: active ? AppColors.primaryDark : Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(
                  color: Colors.white.withOpacity(0.75),
                  fontSize: 11,
                  fontFamily: 'Nunito')),
        ],
      ),
    );
  }
}

// ─── Historique des appels (bottom sheet) ────────────────────
class _CallHistorySheet extends ConsumerWidget {
  final int conversationId;
  const _CallHistorySheet({required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(callHistoryProvider(conversationId));

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.grey200, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Text('Historique des appels',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Nunito')),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.grey400),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: historyAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator(color: AppColors.primary)),
              error: (e, _) => const Center(
                  child: Text('Impossible de charger l\'historique')),
              data: (calls) {
                if (calls.isEmpty) {
                  return const Center(
                    child: Text('Aucun appel dans l\'historique',
                        style: TextStyle(color: AppColors.grey400, fontFamily: 'Nunito')),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: calls.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _CallHistoryTile(call: calls[i]),
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final CallModel call;
  const _CallHistoryTile({required this.call});

  @override
  Widget build(BuildContext context) {
    final IconData statusIcon;
    final Color statusColor;

    switch (call.status) {
      case 'active':
      case 'ended':
        statusIcon = call.isVideo ? Icons.videocam_rounded : Icons.call_rounded;
        statusColor = AppColors.success;
        break;
      case 'rejected':
      case 'missed':
        statusIcon = Icons.call_missed_rounded;
        statusColor = AppColors.error;
        break;
      default:
        statusIcon = Icons.call_rounded;
        statusColor = AppColors.grey400;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(statusIcon, color: statusColor, size: 20),
      ),
      title: Text(
        call.caller?.fullName ?? 'Inconnu',
        style: const TextStyle(
            fontFamily: 'Nunito', fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${call.isVideo ? 'Vidéo' : 'Audio'} · ${_statusLabel(call.status)}',
        style: const TextStyle(
            fontFamily: 'Nunito', fontSize: 12, color: AppColors.grey400),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatDate(call.createdAt),
            style: const TextStyle(
                fontFamily: 'Nunito', fontSize: 11, color: AppColors.grey400),
          ),
          if (call.duration != null) ...[
            const SizedBox(height: 2),
            Text(
              call.durationDisplay,
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  color: AppColors.grey600,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ended': return 'Terminé';
      case 'rejected': return 'Refusé';
      case 'missed': return 'Manqué';
      case 'active': return 'En cours';
      case 'pending': return 'En attente';
      default: return status;
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Hier';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}/${dt.year}';
    }
  }
}

// ─── Avatar animé ─────────────────────────────────────────────
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
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 3),
          boxShadow: [
            BoxShadow(
                color: Colors.white.withOpacity(0.1),
                blurRadius: 20,
                spreadRadius: 4),
          ],
        ),
        child: ClipOval(child: widget.child),
      ),
    );
  }
}