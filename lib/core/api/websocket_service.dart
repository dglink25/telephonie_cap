import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pusher_client_socket/pusher_client_socket.dart';
import '../constants/app_constants.dart';
import '../api/auth_storage.dart';
import 'dart:js' as js;

typedef EventCallback = void Function(Map<String, dynamic> data);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  PusherClient? _pusher;
  bool _initialized = false;
  bool _connecting = false;
  String? _authToken;

  // channelName → { eventName → callback }
  final Map<String, Map<String, EventCallback>> _subscriptions = {};
  // channelName → Channel object
  final Map<String, Channel> _channels = {};

  // ─── Init ─────────────────────────────────────────────────
  Future<void> init(String authToken) async {
    _authToken = authToken;
    if (_initialized || _connecting) return;
    _connecting = true;

    try {
      final options = PusherOptions(
        key: AppConstants.reverbAppKey,
        host: AppConstants.reverbHost,       // '192.168.100.195'
        wsPort: AppConstants.reverbPort,     // 8080
        wssPort: AppConstants.reverbPort,
        encrypted: false,                    // HTTP/WS, pas HTTPS/WSS
        authOptions: PusherAuthOptions(
          endpoint:
              '${AppConstants.storageBaseUrl}/broadcasting/auth',
          headers: () async => {
            'Authorization': 'Bearer $_authToken',
            'Accept': 'application/json',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
        ),
        autoConnect: false,
      );

      _pusher = PusherClient(options);

      _pusher!.onConnectionEstablished((data) {
        debugPrint('[WS] Connecté — socket: ${_pusher!.socketId}');
        _initialized = true;
        _connecting = false;
        _resubscribeAll();
      });

      _pusher!.onConnectionError((error) {
        debugPrint('[WS] Erreur connexion: $error');
        _connecting = false;
      });

      _pusher!.onDisconnected((data) {
        debugPrint('[WS] Déconnecté');
        _initialized = false;
        _channels.clear();
        // Reconnexion automatique après 4 secondes
        Future.delayed(const Duration(seconds: 4), () {
          if (!_initialized && _authToken != null) {
            _connecting = false;
            init(_authToken!);
          }
        });
      });

      _pusher!.onError((error) {
        debugPrint('[WS] Erreur: $error');
      });

      _pusher!.connect();
    } catch (e) {
      _initialized = false;
      _connecting = false;
      debugPrint('[WS] Init error: $e');
      rethrow;
    }
  }

  // ─── Subscribe ─────────────────────────────────────────────
  Future<void> subscribeToConversation(
    int conversationId, {
    required Map<String, EventCallback> events,
  }) async {
    await _subscribePresence(
      'conversation.$conversationId',
      events: events,
    );
  }

  Future<void> _subscribePresence(
    String name, {
    required Map<String, EventCallback> events,
  }) async {
    final channelName = 'presence-$name';

    // Mémoriser / mettre à jour les handlers
    _subscriptions[channelName] ??= {};
    _subscriptions[channelName]!.addAll(events);

    if (!_initialized || _pusher == null) {
      debugPrint('[WS] Pas connecté — subscription en attente: $channelName');
      return;
    }

    if (_channels.containsKey(channelName)) {
      // Canal déjà abonné — juste mettre à jour les handlers
      return;
    }

    await _doSubscribe(channelName);
  }

  Future<void> _doSubscribe(String channelName) async {
    if (_pusher == null) return;
    try {
      final channel = _pusher!.subscribe(channelName);
      _channels[channelName] = channel;

      // Bind tous les events enregistrés pour ce canal
      final events = _subscriptions[channelName] ?? {};
      events.forEach((eventName, callback) {
        channel.bind(eventName, (data) {
          final parsed = _parseData(data);
          callback(parsed);
        });
      });

      debugPrint('[WS] Abonné → $channelName');
    } catch (e) {
      debugPrint('[WS] Subscribe error ($channelName): $e');
    }
  }

  void _notifyServiceWorker(String channelName, int conversationId) {
    if (!kIsWeb) return;
    try {
      final channel = js.context['navigator']['serviceWorker']['controller'];
      if (channel != null) {
        channel.callMethod('postMessage', [
          js.JsObject.jsify({
            'type': 'SUBSCRIBE_CONVERSATION',
            'conversationId': conversationId,
          })
        ]);
      }
    } catch (e) {
      debugPrint('[WS] SW notify error: $e');
    }
  }


  void _resubscribeAll() {
    final toResubscribe = Map<String, Map<String, EventCallback>>.from(
      _subscriptions,
    );
    for (final channelName in toResubscribe.keys) {
      _channels.remove(channelName);
      _doSubscribe(channelName);
    }
  }

  // ─── Unsubscribe ───────────────────────────────────────────
  Future<void> unsubscribeFromConversation(int conversationId) async {
    final channelName = 'presence-conversation.$conversationId';
    _subscriptions.remove(channelName);
    if (_channels.containsKey(channelName) && _pusher != null) {
      _pusher!.unsubscribe(channelName);
      _channels.remove(channelName);
    }
  }

  // ─── Disconnect ────────────────────────────────────────────
  Future<void> disconnect() async {
    _subscriptions.clear();
    _channels.clear();
    _pusher?.disconnect();
    _pusher = null;
    _initialized = false;
    _connecting = false;
  }

  // ─── Helpers ───────────────────────────────────────────────
  Map<String, dynamic> _parseData(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map<String, dynamic>) return d;
        if (d is Map) return Map<String, dynamic>.from(d);
      } catch (_) {}
    }
    return {};
  }

  bool get isConnected => _initialized;
  String? get socketId => _pusher?.socketId;
}