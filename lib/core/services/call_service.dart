import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'
    if (dart.library.html) '../stubs/webrtc_stub.dart';
import '../api/api_client.dart';
import '../websocket/websocket_service.dart';
import 'ringtone_service.dart';
import 'notification_service.dart';

enum CallState { idle, calling, ringing, active, ended }

class IncomingCallInfo {
  final int callId;
  final int conversationId;
  final String callerName;
  final String callType;
  final int callerId;
  final Map<String, dynamic> raw;

  const IncomingCallInfo({
    required this.callId,
    required this.conversationId,
    required this.callerName,
    required this.callType,
    required this.callerId,
    required this.raw,
  });
}

class CallService extends ChangeNotifier {
  static final CallService _instance = CallService._internal();
  factory CallService() => _instance;
  CallService._internal();

  final ApiClient _api = ApiClient();
  final WebSocketService _ws = WebSocketService();
  final RingtoneService _ringtone = RingtoneService();

  CallState _state = CallState.idle;
  int? _currentCallId;
  int? _currentConversationId;
  String _callType = 'audio';
  IncomingCallInfo? _incomingCallInfo;
  int? _currentUserId;

  final Set<int> _globalListenedConversations = {};

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function(IncomingCallInfo)? onIncomingCall;
  Function(String status)? onCallStatusChanged;

  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  Timer? _callTimeoutTimer;
  static const _callTimeoutSeconds = 60;

  // ── Debug logger ─────────────────────────────────────────────
  void _log(String msg) => debugPrint('[CallService] $msg');

  CallState get state => _state;
  int? get currentCallId => _currentCallId;
  IncomingCallInfo? get incomingCallInfo => _incomingCallInfo;
  String get callType => _callType;
  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;
  bool get hasActiveCall => _state != CallState.idle;
  bool get isBusy =>
      _state == CallState.calling ||
      _state == CallState.active ||
      _state == CallState.ringing;

  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 10,
  };

  // ─────────────────────────────────────────────────────────────
  // CONFIGURATION
  // ─────────────────────────────────────────────────────────────
  void setCurrentUser(int userId) {
    _currentUserId = userId;
    _log('Current user set: $userId');
  }

  // ─────────────────────────────────────────────────────────────
  // ÉCOUTE GLOBALE DES CONVERSATIONS
  // ─────────────────────────────────────────────────────────────
  void listenGloballyToConversation(int conversationId) {
    if (_globalListenedConversations.contains(conversationId)) return;
    _globalListenedConversations.add(conversationId);
    _log('Écoute globale conversation $conversationId');

    _ws.subscribeToConversation(conversationId, events: {
      'call.initiated': (data) =>
          _handleGlobalCallInitiated(data, conversationId),
      'call.status': (data) => _handleGlobalCallStatus(data),
      'call.signal': (data) => _handleGlobalCallSignal(data),
    });
  }

  void stopListeningGlobally(int conversationId) {
    _globalListenedConversations.remove(conversationId);
  }

  // ─── Gestion appel entrant via WebSocket ──────────────────────
  void _handleGlobalCallInitiated(
      Map<String, dynamic> data, int conversationId) {
    _log('call.initiated reçu: $data');

    int callerId = 0;
    final callerRaw = data['caller'];
    if (data['caller_id'] is int) {
      callerId = data['caller_id'] as int;
    } else if (callerRaw is Map) {
      callerId = (callerRaw['id'] as int?) ?? 0;
    }

    // Ignorer si c'est MOI qui appelle
    if (_currentUserId != null && callerId == _currentUserId) {
      _log('Ignorer — appel initié par moi-même');
      return;
    }

    _callType = data['type'] as String? ?? 'audio';

    final callerName =
        (callerRaw is Map ? callerRaw['full_name'] : null) as String? ??
            data['caller_name'] as String? ??
            'Appel entrant';

    final callId = data['call_id'] as int? ?? data['id'] as int? ?? 0;
    final convId = data['conversation_id'] as int? ?? conversationId;

    _log('Appel entrant: id=$callId caller=$callerName type=$_callType');

    final info = IncomingCallInfo(
      callId: callId,
      conversationId: convId,
      callerName: callerName,
      callType: _callType,
      callerId: callerId,
      raw: data,
    );

    // Déjà occupé → rejeter automatiquement
    if (isBusy) {
      _log('Occupé — rejet automatique');
      _autoRejectBusy(callId);
      return;
    }

    _incomingCallInfo = info;
    _setState(CallState.ringing);

    if (!kIsWeb) {
      _ringtone.startRinging();
      NotificationService().showIncomingCallNotificationInApp(
        callerName: callerName,
        callType: _callType,
        callId: callId,
        conversationId: convId,
      );
    }

    onIncomingCall?.call(info);
  }

  void _handleGlobalCallStatus(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    _log('call.status: $status');

    onCallStatusChanged?.call(status);

    switch (status) {
      case 'active':
        if (!kIsWeb) _ringtone.stopRinging();
        if (!kIsWeb) NotificationService().cancelAll();
        _callTimeoutTimer?.cancel();
        _setState(CallState.active);
        break;
      case 'rejected':
      case 'ended':
      case 'missed':
        if (!kIsWeb) _ringtone.stopRinging();
        if (!kIsWeb) NotificationService().cancelAll();
        _callTimeoutTimer?.cancel();
        _incomingCallInfo = null;
        _cleanup();
        break;
    }
  }

  void _handleGlobalCallSignal(Map<String, dynamic> data) {
    final senderId = data['sender_id'] as int?;
    if (senderId != null && senderId == _currentUserId) return;
    _onCallSignal(data);
  }

  Future<void> _autoRejectBusy(int callId) async {
    try {
      await _api.rejectCall(callId);
    } catch (e) {
      _log('autoRejectBusy error: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // SONNERIE
  // ─────────────────────────────────────────────────────────────
  void startIncomingRingtone() {
    if (!kIsWeb) _ringtone.startRinging();
  }

  void stopIncomingRingtone() {
    if (!kIsWeb) _ringtone.stopRinging();
  }

  // ─────────────────────────────────────────────────────────────
  // COMPATIBILITÉ ChatPage
  // ─────────────────────────────────────────────────────────────
  void listenToConversation(int conversationId) {}
  void stopListening(int conversationId) {}

  // ─────────────────────────────────────────────────────────────
  // ACTIONS D'APPEL
  // ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> initiateCall(
    int conversationId,
    String type,
    int currentUserId,
  ) async {
    if (isBusy) {
      _log('Déjà occupé — initiateCall ignoré');
      return null;
    }

    try {
      _callType = type;
      _currentUserId = currentUserId;
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
      _log('Appel initié: id=$_currentCallId');

      if (!kIsWeb) {
        await _ringtone.startDialingTone();
        await _setupPeerConnection(
            conversationId, currentUserId, isInitiator: true);
      }

      // Timeout 60s
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer =
          Timer(const Duration(seconds: _callTimeoutSeconds), () async {
        if (_state == CallState.calling) {
          _log('Timeout — personne n\'a répondu');
          await endCall();
        }
      });

      return callData;
    } catch (e) {
      _log('initiateCall error: $e');
      await _cleanup();
      rethrow;
    }
  }

  Future<bool> answerCall(
      int callId, int conversationId, int currentUserId) async {
    if (_state == CallState.active || _state == CallState.calling) {
      _log('Déjà en appel actif — answerCall ignoré');
      return false;
    }

    try {
      _currentCallId = callId;
      _currentUserId = currentUserId;
      _currentConversationId = conversationId;
      _pendingCandidates.clear();
      _remoteDescriptionSet = false;

      if (!kIsWeb) {
        await _ringtone.stopRinging();
        await NotificationService().cancelCallNotification(callId);
        await _setupLocalStream(video: _callType == 'video');
      }

      await _api.answerCall(callId);
      _setState(CallState.active);
      _incomingCallInfo = null;

      if (!kIsWeb) {
        await _setupPeerConnection(
            conversationId, currentUserId, isInitiator: false);
      }

      _log('Appel répondu: id=$callId');
      return true;
    } catch (e) {
      _log('answerCall error: $e');
      await _cleanup();
      return false;
    }
  }

  Future<void> rejectCall(int callId) async {
    try {
      if (!kIsWeb) await _ringtone.stopRinging();
      if (!kIsWeb) await NotificationService().cancelCallNotification(callId);
      await _api.rejectCall(callId);
      _log('Appel rejeté: id=$callId');
    } catch (e) {
      _log('rejectCall error: $e');
    } finally {
      _incomingCallInfo = null;
      _setState(CallState.idle);
    }
  }

  Future<void> endCall() async {
    try {
      if (!kIsWeb) await _ringtone.stopRinging();
      if (!kIsWeb) await NotificationService().cancelAll();
      _callTimeoutTimer?.cancel();
      if (_currentCallId != null) {
        await _api.endCall(_currentCallId!);
        _log('Appel terminé: id=$_currentCallId');
      }
    } catch (e) {
      _log('endCall error: $e');
    } finally {
      await _cleanup();
    }
  }

  void onCallSignalReceived(dynamic rawData) {
    final data = _toMap(rawData);
    if (data.isNotEmpty) _onCallSignal(data);
  }

  // ─────────────────────────────────────────────────────────────
  // WEBRTC
  // ─────────────────────────────────────────────────────────────
  Future<void> _setupLocalStream({required bool video}) async {
    try {
      final constraints = <String, dynamic>{
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': video
            ? {
                'facingMode': 'user',
                'width': {'ideal': 1280},
                'height': {'ideal': 720},
                'frameRate': {'ideal': 30},
              }
            : false,
      };
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      onLocalStream?.call(_localStream!);
      _log('Stream local obtenu');
    } catch (e) {
      _log('setupLocalStream error: $e');
      // Fallback sans vidéo
      if (video) {
        try {
          _localStream = await navigator.mediaDevices
              .getUserMedia({'audio': true, 'video': false});
          onLocalStream?.call(_localStream!);
          _log('Stream local fallback (audio only)');
        } catch (e2) {
          _log('setupLocalStream fallback error: $e2');
        }
      }
    }
  }

  Future<void> _setupPeerConnection(
    int conversationId,
    int currentUserId, {
    required bool isInitiator,
  }) async {
    try {
      _peerConnection = await createPeerConnection(_iceConfig);

      _localStream?.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      _peerConnection!.onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          onRemoteStream?.call(_remoteStream!);
          _log('Stream distant reçu');
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
          _log('ICE send error: $e');
        }
      };

      _peerConnection!.onIceConnectionState = (state) {
        _log('ICE state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          endCall();
        }
      };

      if (isInitiator) {
        final offer = await _peerConnection!.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': _callType == 'video',
        });
        await _peerConnection!.setLocalDescription(offer);
        if (_currentCallId != null) {
          await _api.sendSignal(_currentCallId!, 'offer', {
            'sdp': offer.sdp,
            'type': offer.type,
          });
          _log('Offer envoyée');
        }
      }
    } catch (e) {
      _log('setupPeerConnection error: $e');
    }
  }

  Future<void> _onCallSignal(Map<String, dynamic> data) async {
    if (_peerConnection == null) {
      _log('peerConnection null — signal ignoré');
      return;
    }

    final signalType = data['signal_type'] as String? ?? '';
    final rawPayload = data['payload'];
    final payload = _toMap(rawPayload);

    if (payload.isEmpty) {
      _log('Payload vide pour: $signalType');
      return;
    }

    try {
      switch (signalType) {
        case 'offer':
          final sdp = payload['sdp'] as String?;
          final type = payload['type'] as String?;
          if (sdp == null || type == null) break;
          await _peerConnection!
              .setRemoteDescription(RTCSessionDescription(sdp, type));
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
            _log('Answer envoyée');
          }
          break;

        case 'answer':
          final sdp = payload['sdp'] as String?;
          final type = payload['type'] as String?;
          if (sdp == null || type == null) break;
          await _peerConnection!
              .setRemoteDescription(RTCSessionDescription(sdp, type));
          _remoteDescriptionSet = true;
          for (final c in _pendingCandidates) {
            await _peerConnection!.addCandidate(c);
          }
          _pendingCandidates.clear();
          if (!kIsWeb) _ringtone.stopRinging();
          _setState(CallState.active);
          _log('Connexion établie');
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

        default:
          _log('Signal inconnu: $signalType');
      }
    } catch (e) {
      _log('Signal error ($signalType): $e');
    }
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return {};
  }

  void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  void toggleCamera(bool cameraOff) {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !cameraOff);
  }

  Future<void> switchCamera() async {
    if (kIsWeb) return;
    final tracks = _localStream?.getVideoTracks();
    if (tracks != null && tracks.isNotEmpty) {
      await Helper.switchCamera(tracks.first);
    }
  }

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
      _log('Cleanup error: $e');
    }
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _currentCallId = null;
    _incomingCallInfo = null;
    _callTimeoutTimer?.cancel();
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