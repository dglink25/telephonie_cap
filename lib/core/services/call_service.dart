import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    if (dart.library.html) '../stubs/webrtc_stub.dart';
import '../api/api_client.dart';
import '../websocket/websocket_service.dart';
import 'ringtone_service.dart';

/// État d'un appel WebRTC
enum CallState { idle, calling, ringing, active, ended }

class CallService extends ChangeNotifier {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final ApiClient _api = ApiClient();
  final WebSocketService _ws = WebSocketService();
  final RingtoneService _ringtone = RingtoneService();

  // ── État ─────────────────────────────────────────────────────
  CallState _state = CallState.idle;
  int? _currentCallId;
  int? _currentConversationId;
  String _callType = 'audio';
  Map<String, dynamic>? _incomingCallData;

  // ── WebRTC ───────────────────────────────────────────────────
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  // Callbacks UI
  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function(Map<String, dynamic>)? onIncomingCall;
  Function(String status)? onCallStatusChanged;

  // ICE candidate queue for race condition fix
  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  // ── Getters ──────────────────────────────────────────────────
  CallState get state => _state;
  int? get currentCallId => _currentCallId;
  Map<String, dynamic>? get incomingCallData => _incomingCallData;
  String get callType => _callType;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ── Écouter les événements WebSocket ─────────────────────────
  void listenToConversation(int conversationId) {
    _currentConversationId = conversationId;
    _ws.subscribeToConversation(conversationId, events: {
      'call.initiated': _onCallInitiated,
      'call.status': _onCallStatusUpdated,
      'call.signal': _onCallSignal,
    });
  }

  void stopListening(int conversationId) {
    _ws.unsubscribeFromConversation(conversationId);
  }

  // ── Appel sortant ─────────────────────────────────────────────
  Future<Map<String, dynamic>?> initiateCall(
    int conversationId,
    String type,
    int currentUserId,
  ) async {
    try {
      _callType = type;
      _currentConversationId = conversationId;
      _pendingCandidates.clear();
      _remoteDescriptionSet = false;

      if (!kIsWeb) {
        await _setupLocalStream(video: type == 'video');
      }

      final response = await _api.initiateCall(conversationId, type);
      final callData = response.data as Map<String, dynamic>;
      _currentCallId = callData['id'] as int;
      _setState(CallState.calling);

      if (!kIsWeb) {
        await _ringtone.startDialingTone();
        await _setupPeerConnection(
            conversationId, currentUserId, isInitiator: true);
      }

      return callData;
    } catch (e) {
      debugPrint('[Call] initiateCall error: $e');
      await _cleanup();
      return null;
    }
  }

  // ── Répondre à un appel ──────────────────────────────────────
  Future<bool> answerCall(
      int callId, int conversationId, int currentUserId) async {
    try {
      _currentCallId = callId;
      _currentConversationId = conversationId;
      _pendingCandidates.clear();
      _remoteDescriptionSet = false;

      if (!kIsWeb) {
        await _ringtone.stopRinging();
        await _setupLocalStream(video: _callType == 'video');
      }

      await _api.answerCall(callId);
      _setState(CallState.active);

      if (!kIsWeb) {
        await _setupPeerConnection(
            conversationId, currentUserId, isInitiator: false);
      }

      return true;
    } catch (e) {
      debugPrint('[Call] answerCall error: $e');
      await _cleanup();
      return false;
    }
  }

  // ── Rejeter un appel ─────────────────────────────────────────
  Future<void> rejectCall(int callId) async {
    try {
      if (!kIsWeb) await _ringtone.stopRinging();
      await _api.rejectCall(callId);
      _incomingCallData = null;
      _setState(CallState.idle);
    } catch (e) {
      debugPrint('[Call] rejectCall error: $e');
    }
  }

  // ── Terminer un appel ─────────────────────────────────────────
  Future<void> endCall() async {
    try {
      if (!kIsWeb) await _ringtone.stopRinging();
      if (_currentCallId != null) {
        await _api.endCall(_currentCallId!);
      }
    } catch (e) {
      debugPrint('[Call] endCall error: $e');
    } finally {
      await _cleanup();
    }
  }

  // ── BUG FIX: Public method for signal routing from chat_page ──
  void onCallSignalReceived(Map<String, dynamic> data) {
    _onCallSignal(data);
  }

  // ── Médias locaux ─────────────────────────────────────────────
  Future<void> _setupLocalStream({required bool video}) async {
    final constraints = <String, dynamic>{
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    onLocalStream?.call(_localStream!);
  }

  // ── Connexion WebRTC ─────────────────────────────────────────
  Future<void> _setupPeerConnection(
    int conversationId,
    int currentUserId, {
    required bool isInitiator,
  }) async {
    _peerConnection = await createPeerConnection(_iceConfig);

    _localStream?.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _peerConnection!.onIceCandidate = (candidate) async {
      if (_currentCallId == null) return;
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      try {
        await _api.sendSignal(_currentCallId!, 'ice-candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      } catch (e) {
        debugPrint('[WebRTC] ICE send error: $e');
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        endCall();
      }
    };

    if (isInitiator) {
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      if (_currentCallId != null) {
        await _api.sendSignal(_currentCallId!, 'offer', {
          'sdp': offer.sdp,
          'type': offer.type,
        });
      }
    }
  }

  // ── Gestionnaires d'événements WebSocket ─────────────────────
  void _onCallInitiated(Map<String, dynamic> data) {
    _callType = data['type'] as String? ?? 'audio';
    _incomingCallData = data;
    _setState(CallState.ringing);
    onIncomingCall?.call(data);
    if (!kIsWeb) _ringtone.startRinging();
  }

  void _onCallStatusUpdated(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    onCallStatusChanged?.call(status);

    switch (status) {
      case 'active':
        if (!kIsWeb) _ringtone.stopRinging();
        _setState(CallState.active);
        break;
      case 'rejected':
      case 'ended':
        if (!kIsWeb) _ringtone.stopRinging();
        _cleanup();
        break;
    }
  }

  Future<void> _onCallSignal(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;

    final signalType = data['signal_type'] as String? ?? '';
    final payload = data['payload'] as Map<String, dynamic>? ?? {};

    try {
      switch (signalType) {
        case 'offer':
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(
              payload['sdp'] as String,
              payload['type'] as String,
            ),
          );
          _remoteDescriptionSet = true;
          for (final c in _pendingCandidates) {
            await _peerConnection!.addCandidate(c);
          }
          _pendingCandidates.clear();

          final answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);
          if (_currentCallId != null) {
            await _api.sendSignal(_currentCallId!, 'answer', {
              'sdp': answer.sdp,
              'type': answer.type,
            });
          }
          break;

        case 'answer':
          await _peerConnection!.setRemoteDescription(
            RTCSessionDescription(
              payload['sdp'] as String,
              payload['type'] as String,
            ),
          );
          _remoteDescriptionSet = true;
          for (final c in _pendingCandidates) {
            await _peerConnection!.addCandidate(c);
          }
          _pendingCandidates.clear();
          if (!kIsWeb) _ringtone.stopRinging();
          _setState(CallState.active);
          break;

        case 'ice-candidate':
          final candidateStr = payload['candidate'] as String?;
          if (candidateStr == null || candidateStr.isEmpty) break;
          final candidate = RTCIceCandidate(
            candidateStr,
            payload['sdpMid'] as String?,
            payload['sdpMLineIndex'] as int?,
          );
          if (_remoteDescriptionSet) {
            await _peerConnection!.addCandidate(candidate);
          } else {
            _pendingCandidates.add(candidate);
          }
          break;
      }
    } catch (e) {
      debugPrint('[WebRTC] Signal handling error: $e');
    }
  }

  // ── Contrôles audio/vidéo ─────────────────────────────────────
  void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  void toggleCamera(bool cameraOff) {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !cameraOff);
  }

  Future<void> switchCamera() async {
    if (kIsWeb) return;
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks.first);
    }
  }

  // ── Nettoyage ─────────────────────────────────────────────────
  Future<void> _cleanup() async {
    try {
      _localStream?.getTracks().forEach((t) => t.stop());
      await _localStream?.dispose();
      _localStream = null;
      await _remoteStream?.dispose();
      _remoteStream = null;
      await _peerConnection?.close();
      _peerConnection = null;
    } catch (e) {
      debugPrint('[Call] Cleanup error: $e');
    }
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _currentCallId = null;
    _incomingCallData = null;
    _setState(CallState.idle);
  }

  void _setState(CallState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}
