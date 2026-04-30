import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';
import '../constants/app_constants.dart';

typedef EventCallback = void Function(Map<String, dynamic> data);

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal();

  final PusherChannelsFlutter _pusher = PusherChannelsFlutter.getInstance();
  bool _initialized = false;
  bool _connecting = false;
  String? _authToken;

  // Stocker les subscriptions pour re-abonnement après reconnexion
  final Map<String, PusherChannel> _channels = {};
  final Map<String, Map<String, EventCallback>> _pendingSubscriptions = {};

  Future<void> init(String authToken) async {
    _authToken = authToken;

    // CORRECTION: Eviter double init simultané
    if (_connecting) return;
    if (_initialized) return;

    _connecting = true;

    try {
      await _pusher.init(
        apiKey: AppConstants.reverbAppKey,
        cluster: AppConstants.reverbCluster,
        useTLS: AppConstants.reverbScheme == 'https',

        authEndpoint:
            '${AppConstants.baseUrl.replaceAll('/api', '')}/broadcasting/auth',

        onAuthorizer: (channelName, socketId, options) async {
          return {
            'headers': {
              'Authorization': 'Bearer $_authToken',
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
          };
        },

        onConnectionStateChange: (currentState, previousState) {
          debugPrint('[WS] $previousState → $currentState');

          if (currentState == 'CONNECTED') {
            _initialized = true;
            _connecting = false;
            // CORRECTION: Re-abonner aux channels après reconnexion
            _resubscribeAll();
          }

          if (currentState == 'DISCONNECTED' || currentState == 'FAILED') {
            _initialized = false;
            _connecting = false;
            _channels.clear();
          }
        },

        onError: (message, code, error) {
          debugPrint('[WS] Erreur $code: $message — $error');
          _connecting = false;
        },
      );

      await _pusher.connect();
      // Ne pas mettre _initialized = true ici, attendre onConnectionStateChange CONNECTED
    } catch (e) {
      _initialized = false;
      _connecting = false;
      debugPrint('[WS] Init error: $e');
      rethrow;
    }
  }

  // CORRECTION: Re-abonnement automatique après reconnexion
  Future<void> _resubscribeAll() async {
    final pending = Map<String, Map<String, EventCallback>>.from(
        _pendingSubscriptions);
    for (final entry in pending.entries) {
      await _subscribePresence(entry.key.replaceFirst('presence-', ''),
          events: entry.value);
    }
  }

  Future<void> subscribeToConversation(
    int conversationId, {
    required Map<String, EventCallback> events,
  }) async {
    await _subscribePresence('conversation.$conversationId', events: events);
  }

  Future<void> subscribeToUserChannel(
    int userId, {
    required Map<String, EventCallback> events,
  }) async {
    await _subscribePresence('user.$userId', events: events);
  }

  Future<void> _subscribePresence(
    String name, {
    required Map<String, EventCallback> events,
  }) async {
    final channelName = 'presence-$name';

    // Stocker pour re-abonnement
    _pendingSubscriptions[channelName] = events;

    if (_channels.containsKey(channelName)) return;

    if (!_initialized) {
      debugPrint("[WS] Non connecté — subscription en attente: $channelName");
      return;
    }

    try {
      final channel = await _pusher.subscribe(
        channelName: channelName,
        onEvent: (event) {
          try {
            final handler = events[event.eventName];
            if (handler != null) {
              final data = _parseEventData(event.data);
              handler(data);
            }
          } catch (e) {
            debugPrint(
                '[WS] Parse error ($channelName / ${event.eventName}): $e');
          }
        },
        onSubscriptionSucceeded: (ch, data) =>
            debugPrint('[WS] ✓ Abonné → $ch'),
        onSubscriptionError: (message, e) =>
            debugPrint('[WS] ✗ Erreur abonnement $channelName: $message — $e'),
        onMemberAdded: (ch, member) =>
            debugPrint('[WS] 👤 Rejoint $ch: ${member.userId}'),
        onMemberRemoved: (ch, member) =>
            debugPrint('[WS] 👤 Parti $ch: ${member.userId}'),
      );
      _channels[channelName] = channel;
    } catch (e) {
      debugPrint('[WS] Subscribe error ($channelName): $e');
    }
  }

  // CORRECTION: Parse robuste des données d'événement
  Map<String, dynamic> _parseEventData(dynamic rawData) {
    if (rawData is Map<String, dynamic>) return rawData;
    if (rawData is Map) return Map<String, dynamic>.from(rawData);
    if (rawData is String) {
      if (rawData.isEmpty) return {};
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return {};
  }

  Future<void> unsubscribeFromConversation(int conversationId) async {
    final channelName = 'presence-conversation.$conversationId';
    _pendingSubscriptions.remove(channelName);
    await _unsubscribe(channelName);
  }

  Future<void> unsubscribeFromUserChannel(int userId) async {
    final channelName = 'presence-user.$userId';
    _pendingSubscriptions.remove(channelName);
    await _unsubscribe(channelName);
  }

  Future<void> _unsubscribe(String channelName) async {
    if (!_channels.containsKey(channelName)) return;
    try {
      await _pusher.unsubscribe(channelName: channelName);
      _channels.remove(channelName);
      debugPrint('[WS] Désabonné → $channelName');
    } catch (e) {
      debugPrint('[WS] Unsubscribe error: $e');
    }
  }

  Future<void> disconnect() async {
    _pendingSubscriptions.clear();
    try {
      for (final name in _channels.keys.toList()) {
        try {
          await _pusher.unsubscribe(channelName: name);
        } catch (_) {}
      }
      _channels.clear();
      await _pusher.disconnect();
    } catch (e) {
      debugPrint('[WS] Disconnect error: $e');
    } finally {
      _initialized = false;
      _connecting = false;
      debugPrint('[WS] Déconnecté');
    }
  }

  bool get isConnected => _initialized;
}