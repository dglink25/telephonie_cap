import 'dart:async';
import 'package:dio/dio.dart';
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

  CallState _state = CallState.idle;
  int? _currentCallId;
  int? _currentConversationId;
  String _callType = 'audio';
  IncomingCallInfo? _incomingCallInfo;
  int? _currentUserId;

  final Set<int> _globalListenedConversations = {};

  // WebRTC (native only)
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  Function(MediaStream)? onLocalStream;
  Function(MediaStream)? onRemoteStream;
  Function(IncomingCallInfo)? onIncomingCall;
  Function(String status)? onCallStatusChanged;
  Function(String error)? onError;

  final List<RTCIceCandidate> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;

  Timer? _callTimeoutTimer;
  static const _callTimeoutSeconds = 60;

  // FIX: garde-fou pour ne pas déclencher endCall plusieurs fois en parallèle
  bool _isEndingCall = false;

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

  // ICE servers — STUN public + TURN gratuit (open-relay)
  static const Map<String, dynamic> _iceConfig = {
    'iceServers': [],   // LAN direct, pas besoin de STUN
    'sdpSemantics': 'unified-plan',
  };

  void setCurrentUser(int userId) {
    _currentUserId = userId;
    _log('Current user: $userId');
  }

  void listenGloballyToConversation(int conversationId) {
    if (_globalListenedConversations.contains(conversationId)) return;
    _globalListenedConversations.add(conversationId);

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

  // Compatibilité ChatPage
  void listenToConversation(int conversationId) {}
  void stopListening(int conversationId) {}

  // ─────────────────────────────────────────────────────────────
  // GESTION APPEL ENTRANT (WebSocket)
  // ─────────────────────────────────────────────────────────────

  void _handleGlobalCallInitiated(
      Map<String, dynamic> data, int conversationId) {
    _log('call.initiated: $data');

    int callerId = 0;
    final callerRaw = data['caller'];
    if (data['caller_id'] is int) {
      callerId = data['caller_id'] as int;
    } else if (callerRaw is Map) {
      callerId = (callerRaw['id'] as int?) ?? 0;
    }

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

    final info = IncomingCallInfo(
      callId: callId,
      conversationId: convId,
      callerName: callerName,
      callType: _callType,
      callerId: callerId,
      raw: data,
    );

    if (isBusy) {
      _log('Occupé — rejet automatique de $callId');
      _autoRejectBusy(callId);
      return;
    }

    _incomingCallInfo = info;
    _setState(CallState.ringing);

    if (!kIsWeb) {
      RingtoneService.instance.startRinging();
      NotificationService().showIncomingCallNotificationInApp(
        callerName: callerName,
        callType: _callType,
        callId: callId,
        conversationId: convId,
      );
    } else {
      RingtoneService.instance.startRinging();
    }

    onIncomingCall?.call(info);
  }

  void _handleGlobalCallStatus(Map<String, dynamic> data) {
    final status = data['status'] as String? ?? '';
    _log('call.status: $status');

    onCallStatusChanged?.call(status);

    switch (status) {
      case 'active':
        RingtoneService.instance.stopRinging();
        if (!kIsWeb) NotificationService().cancelAll();
        _callTimeoutTimer?.cancel();
        _setState(CallState.active);
        break;
      case 'rejected':
      case 'ended':
      case 'missed':
        RingtoneService.instance.stopRinging();
        if (!kIsWeb) NotificationService().cancelAll();
        _callTimeoutTimer?.cancel();
        _incomingCallInfo = null;
        // FIX: ne pas rappeler _cleanup() si on est l'initiateur de la fin
        // (évite la double-fin et la double-navigation)
        if (_state != CallState.idle && _state != CallState.ended) {
          _cleanupState();
        }
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
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  // SONNERIE
  // ─────────────────────────────────────────────────────────────

  void startIncomingRingtone() => RingtoneService.instance.startRinging();
  void stopIncomingRingtone() => RingtoneService.instance.stopRinging();

  // ─────────────────────────────────────────────────────────────
  // ACTIONS D'APPEL
  // ─────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> initiateCall(
    int conversationId,
    String type,
    int currentUserId,
  ) async {
    if (isBusy) {
      _log('Déjà occupé');
      onError?.call('Un appel est déjà en cours.');
      return null;
    }

    try {
      _callType = type;
      _currentUserId = currentUserId;
      _currentConversationId = conversationId;
      _pendingCandidates.clear();
      _remoteDescriptionSet = false;
      _isEndingCall = false;

      if (!kIsWeb) {
        await _setupLocalStream(video: type == 'video');
      }

      final response = await _api.initiateCall(conversationId, type);
      final callData = response.data as Map<String, dynamic>;
      _currentCallId = callData['id'] as int;
      _setState(CallState.calling);
      _log('Appel initié: id=$_currentCallId');

      // Tonalité d'appel sortant
      await RingtoneService.instance.startDialingTone();

      if (!kIsWeb) {
        await _setupPeerConnection(conversationId, currentUserId,
            isInitiator: true);
      }

      // Timeout 60s
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer =
          Timer(const Duration(seconds: _callTimeoutSeconds), () async {
        if (_state == CallState.calling) {
          _log('Timeout — pas de réponse');
          await endCall();
          onCallStatusChanged?.call('missed');
        }
      });

      return callData;
    } catch (e) {
      _log('initiateCall error: $e');
      final errMsg = _parseError(e);
      onError?.call(errMsg);
      await _cleanup();
      return null;
    }
  }

  Future<bool> answerCall(
      int callId, int conversationId, int currentUserId) async {
    if (_state == CallState.active || _state == CallState.calling) {
      _log('Déjà en appel');
      return false;
    }

    try {
      _currentCallId = callId;
      _currentUserId = currentUserId;
      _currentConversationId = conversationId;
      _pendingCandidates.clear();
      _remoteDescriptionSet = false;
      _isEndingCall = false;

      RingtoneService.instance.stopRinging();
      if (!kIsWeb) await NotificationService().cancelCallNotification(callId);

      if (!kIsWeb) {
        await _setupLocalStream(video: _callType == 'video');
      }

      await _api.answerCall(callId);
      _setState(CallState.active);
      _incomingCallInfo = null;

      if (!kIsWeb) {
        await _setupPeerConnection(conversationId, currentUserId,
            isInitiator: false);
      }

      _log('Appel répondu: $callId');
      return true;
    } catch (e) {
      _log('answerCall error: $e');
      onError?.call(_parseError(e));
      await _cleanup();
      return false;
    }
  }

  Future<void> rejectCall(int callId) async {
    try {
      RingtoneService.instance.stopRinging();
      if (!kIsWeb) await NotificationService().cancelCallNotification(callId);
      await _api.rejectCall(callId);
      _log('Appel rejeté: $callId');
    } catch (e) {
      _log('rejectCall error: $e');
    } finally {
      _incomingCallInfo = null;
      _setState(CallState.idle);
    }
  }

  Future<void> endCall() async {
    // FIX CRITIQUE: garde-fou contre les appels multiples simultanés
    if (_isEndingCall) {
      _log('endCall déjà en cours — ignoré');
      return;
    }
    _isEndingCall = true;

    try {
      RingtoneService.instance.stopRinging();
      if (!kIsWeb) NotificationService().cancelAll();
      _callTimeoutTimer?.cancel();

      if (_currentCallId != null) {
        try {
          await _api.endCall(_currentCallId!);
          _log('Appel terminé: $_currentCallId');
        } on DioException catch (e) {
          // FIX: 422 = appel déjà terminé côté serveur (missed/rejected/ended)
          // C'est normal si le job AutoMarkCallMissed a déjà agi → on ignore
          final statusCode = e.response?.statusCode;
          if (statusCode == 422) {
            _log(
                'endCall 422 ignoré — appel déjà terminé côté serveur (statut: ${e.response?.data})');
          } else {
            _log('endCall error: $e');
          }
        } catch (e) {
          _log('endCall error: $e');
        }
      }
    } finally {
      await _cleanup();
      _isEndingCall = false;
    }
  }

  void onCallSignalReceived(dynamic rawData) {
    final data = _toMap(rawData);
    if (data.isNotEmpty) _onCallSignal(data);
  }

  // ─────────────────────────────────────────────────────────────
  // WEBRTC (native uniquement)
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
      _log('Stream local OK');
    } catch (e) {
      _log('setupLocalStream error: $e');
      if (video) {
        try {
          _localStream = await navigator.mediaDevices
              .getUserMedia({'audio': true, 'video': false});
          onLocalStream?.call(_localStream!);
          _log('Stream local fallback audio-only');
        } catch (e2) {
          _log('setupLocalStream fallback error: $e2');
          onError?.call(
              'Impossible d\'accéder au microphone/caméra. Vérifiez les permissions.');
        }
      } else {
        onError?.call(
            'Impossible d\'accéder au microphone. Vérifiez les permissions.');
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
          _log('ICE disconnected/failed — fin d\'appel');
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
      onError?.call('Erreur WebRTC: $e');
    }
  }

  Future<void> _onCallSignal(Map<String, dynamic> data) async {
    if (_peerConnection == null) return;

    final signalType = data['signal_type'] as String? ?? '';
    final rawPayload = data['payload'];
    final payload = _toMap(rawPayload);

    if (payload.isEmpty) return;

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
          RingtoneService.instance.stopRinging();
          _setState(CallState.active);
          _log('Connexion WebRTC établie');
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

  // FIX: séparer le nettoyage des ressources WebRTC du changement d'état
  // _cleanupState() = juste mettre l'état à idle (appelé depuis _handleGlobalCallStatus)
  void _cleanupState() {
    _pendingCandidates.clear();
    _remoteDescriptionSet = false;
    _currentCallId = null;
    _incomingCallInfo = null;
    _callTimeoutTimer?.cancel();
    _setState(CallState.idle);
  }

  // _cleanup() = nettoyage complet (ressources + état)
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
    if (_state == newState) return; // FIX: éviter les rebuilds inutiles
    _state = newState;
    notifyListeners();
  }

  String _parseError(dynamic e) {
    // FIX: 422 avec message "appel déjà en cours" → message clair
    if (e is DioException) {
      final statusCode = e.response?.statusCode;
      final data = e.response?.data;
      if (statusCode == 422) {
        final msg = data is Map ? (data['message'] as String? ?? '') : '';
        if (msg.contains('en cours')) {
          return 'Un appel est déjà en cours dans cette conversation.';
        }
        return 'L\'appel n\'est plus disponible.';
      }
    }
    final msg = e.toString().toLowerCase();
    if (msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('socket')) {
      return 'Erreur réseau. Vérifiez votre connexion internet.';
    }
    if (msg.contains('permission') || msg.contains('denied')) {
      return 'Permission refusée. Autorisez l\'accès au microphone/caméra.';
    }
    if (msg.contains('busy') || msg.contains('active')) {
      return 'Un appel est déjà en cours.';
    }
    return 'Impossible de démarrer l\'appel. Réessayez.';
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}