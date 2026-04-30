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

  // Timer pour annuler l'appel sortant si pas de réponse
  Timer? _callTimeoutTimer;
  static const _callTimeoutSeconds = 60;

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
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ─────────────────────────────────────────────────────────────
  // CONFIGURATION
  // ─────────────────────────────────────────────────────────────

  void setCurrentUser(int userId) {
    _currentUserId = userId;
    debugPrint('[Call] Current user set: $userId');
  }

  // ─────────────────────────────────────────────────────────────
  // ÉCOUTE GLOBALE DES CONVERSATIONS
  // ─────────────────────────────────────────────────────────────

  void listenGloballyToConversation(int conversationId) {
    if (_globalListenedConversations.contains(conversationId)) return;
    _globalListenedConversations.add(conversationId);

    debugPrint('[Call] Écoute globale conversation $conversationId');

    _ws.subscribeToConversation(conversationId, events: {
      'call.initiated': (data) =>
          _handleGlobalCallInitiated(data, conversationId),
      'call.status': (data) => _handleGlobalCallStatus(data),
      'call.signal': (data) => _handleGlobalCallSignal(data),
    });
  }

  void stopListeningGlobally(int conversationId) {
    _globalListenedConversations.remove(conversationId);
    // Ne pas désabonner — le WebSocket reste pour les messages
  }

  // ─── Gestion appel entrant via WebSocket ──────────────────────
  void _handleGlobalCallInitiated(
      Map<String, dynamic> data, int conversationId) {
    debugPrint('[Call] call.initiated reçu: $data');

    // Extraire caller_id
    int callerId = 0;
    final callerRaw = data['caller'];
    if (data['caller_id'] is int) {
      callerId = data['caller_id'] as int;
    } else if (callerRaw is Map) {
      callerId = (callerRaw['id'] as int?) ?? 0;
    }

    // Ignorer si c'est MOI qui appelle
    if (_currentUserId != null && callerId == _currentUserId) {
      debugPrint('[Call] Ignorer — appel initié par moi-même');
      return;
    }

    _callType = data['type'] as String? ?? 'audio';

    final callerName =
        (callerRaw is Map ? callerRaw['full_name'] : null) as String? ??
            data['caller_name'] as String? ??
            'Appel entrant';

    final callId =
        data['call_id'] as int? ?? data['id'] as int? ?? 0;

    final convId =
        data['conversation_id'] as int? ?? conversationId;

    debugPrint('[Call] Appel entrant: id=$callId caller=$callerName type=$_callType');

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
      debugPrint('[Call] Occupé — rejet automatique');
      _autoRejectBusy(callId);
      return;
    }

    _incomingCallInfo = info;
    _setState(CallState.ringing);

    // FIX: Sonnerie + notification locale système (pour écran veille)
    if (!kIsWeb) {
      _ringtone.startRinging();
      NotificationService().showIncomingCallNotificationInApp(
        callerName: callerName,
        callType: _callType,
        callId: callId,
        conversationId: convId,
      );
    }

    // Notifier l'UI (bannière in-app dans HomePage)
    onIncomingCall?.call(info);
  }

  void _handleGlobalCallStatus(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    debugPrint('[Call] call.status: $status');

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
    // Ignorer nos propres signaux
    if (senderId != null && senderId == _currentUserId) return;
    _onCallSignal(data);
  }

  Future<void> _autoRejectBusy(int callId) async {
    try {
      await _api.rejectCall(callId);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // SONNERIE — méthodes publiques
  // ─────────────────────────────────────────────────────────────

  void startIncomingRingtone() {
    if (!kIsWeb) _ringtone.startRinging();
  }

  void stopIncomingRingtone() {
    if (!kIsWeb) _ringtone.stopRinging();
  }

  // ─────────────────────────────────────────────────────────────
  // COMPATIBILITÉ ChatPage (no-op volontaire)
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
      debugPrint('[Call] Déjà occupé — initiateCall ignoré');
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

      debugPrint('[Call] Appel initié: id=$_currentCallId');

      if (!kIsWeb) {
        // Tonalité d'attente
        await _ringtone.startDialingTone();
        await _setupPeerConnection(
            conversationId, currentUserId, isInitiator: true);
      }

      // Timeout si pas de réponse après 60s
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer =
          Timer(const Duration(seconds: _callTimeoutSeconds), () async {
        if (_state == CallState.calling) {
          debugPrint('[Call] Timeout — personne n\'a répondu');
          await endCall();
        }
      });

      return callData;
    } catch (e) {
      debugPrint('[Call] initiateCall error: $e');
      await _cleanup();
      rethrow;
    }
  }

  Future<bool> answerCall(
      int callId, int conversationId, int currentUserId) async {
    if (_state == CallState.active || _state == CallState.calling) {
      debugPrint('[Call] Déjà en appel actif — answerCall ignoré');
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

      debugPrint('[Call] Appel répondu: id=$callId');
      return true;
    } catch (e) {
      debugPrint('[Call] answerCall error: $e');
      await _cleanup();
      return false;
    }
  }

  Future<void> rejectCall(int callId) async {
    try {
      if (!kIsWeb) await _ringtone.stopRinging();
      if (!kIsWeb) await NotificationService().cancelCallNotification(callId);
      await _api.rejectCall(callId);
      debugPrint('[Call] Appel rejeté: id=$callId');
    } catch (e) {
      debugPrint('[Call] rejectCall error: $e');
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
        debugPrint('[Call] Appel terminé: id=$_currentCallId');
      }
    } catch (e) {
      debugPrint('[Call] endCall error: $e');
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
    final constraints = <String, dynamic>{
      'audio': true,
      'video': video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
    _localStream = await navigator.mediaDevices.getUserMedia(constraints);
    onLocalStream?.call(_localStream!);
    debugPrint('[WebRTC] Stream local obtenu');
  }

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
        debugPrint('[WebRTC] Stream distant reçu');
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
        debugPrint('[WebRTC] Offer envoyée');
      }
    }
  }

  Future<void> _onCallSignal(Map<String, dynamic> data) async {
    if (_peerConnection == null) {
      debugPrint('[WebRTC] peerConnection null — signal ignoré');
      return;
    }

    final signalType = data['signal_type'] as String? ?? '';
    final rawPayload = data['payload'];
    final payload = _toMap(rawPayload);

    if (payload.isEmpty) {
      debugPrint('[WebRTC] Payload vide pour: $signalType');
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
            debugPrint('[WebRTC] Answer envoyée');
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
          debugPrint('[WebRTC] Connexion établie');
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
          debugPrint('[WebRTC] Signal inconnu: $signalType');
      }
    } catch (e) {
      debugPrint('[WebRTC] Signal error ($signalType): $e');
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
      debugPrint('[Call] Cleanup error: $e');
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