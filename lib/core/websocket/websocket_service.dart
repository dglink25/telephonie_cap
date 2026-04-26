
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
  String? _authToken;

  final Map<String, PusherChannel> _channels = {};

  // ── Initialisation ────────────────────────────────────────────
  Future<void> init(String authToken) async {
    _authToken = authToken;
    if (_initialized) return;

    try {
      // pusher_channels_flutter >=2.1 ne supporte pas le paramètre nommé
      // `host` directement dans init() — on passe par wsHost / wssHost.
      await _pusher.init(
        apiKey: AppConstants.reverbAppKey,
        cluster: 'mt1',
        wsHost: AppConstants.reverbHost,
        wsPort: AppConstants.reverbPort,
        wssPort: AppConstants.reverbPort,
        useTLS: AppConstants.reverbScheme == 'https',
        authEndpoint:
            '${AppConstants.baseUrl.replaceAll('/api', '')}/broadcasting/auth',
        onAuthorizer: (channelName, socketId, options) async {
          return {
            'headers': {
              'Authorization': 'Bearer $_authToken',
              'Accept': 'application/json',
            },
          };
        },
        onConnectionStateChange: (currentState, previousState) {
          debugPrint('[WS] $previousState → $currentState');
        },
        onError: (message, code, error) {
          debugPrint('[WS] Error $code: $message');
        },
      );

      await _pusher.connect();
      _initialized = true;
      debugPrint('[WS] Connecté à Reverb (${AppConstants.reverbHost})');
    } catch (e) {
      debugPrint('[WS] Init error: $e');
      rethrow;
    }
  }

  // ── Canal de conversation privé ───────────────────────────────
  Future<void> subscribeToConversation(
    int conversationId, {
    required Map<String, EventCallback> events,
  }) async {
    await _subscribePrivate('conversation.$conversationId', events: events);
  }

  // ── Canal utilisateur personnel ───────────────────────────────
  Future<void> subscribeToUserChannel(
    int userId, {
    required Map<String, EventCallback> events,
  }) async {
    await _subscribePrivate('user.$userId', events: events);
  }

  // ── Abonnement générique à un canal privé ─────────────────────
  Future<void> _subscribePrivate(
    String name, {
    required Map<String, EventCallback> events,
  }) async {
    final channelName = 'private-$name';
    if (_channels.containsKey(channelName)) return;

    try {
      final channel = await _pusher.subscribe(
        channelName: channelName,
        onEvent: (event) {
          try {
            final handler = events[event.eventName];
            if (handler != null) {
              final data = event.data is String
                  ? jsonDecode(event.data as String) as Map<String, dynamic>
                  : event.data as Map<String, dynamic>;
              handler(data);
            }
          } catch (e) {
            debugPrint('[WS] Event parse error ($channelName): $e');
          }
        },
        onSubscriptionSucceeded: (ch, data) {
          debugPrint('[WS] Abonné → $ch');
        },
        onSubscriptionError: (message, e) {
          debugPrint('[WS] Erreur abonnement $channelName: $message');
        },
      );
      _channels[channelName] = channel;
    } catch (e) {
      debugPrint('[WS] Subscribe error ($channelName): $e');
    }
  }

  // ── Désabonnement ─────────────────────────────────────────────
  Future<void> unsubscribeFromConversation(int conversationId) async {
    await _unsubscribe('private-conversation.$conversationId');
  }

  Future<void> unsubscribeFromUserChannel(int userId) async {
    await _unsubscribe('private-user.$userId');
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

  // ── Déconnexion ───────────────────────────────────────────────
  Future<void> disconnect() async {
    try {
      for (final name in _channels.keys.toList()) {
        await _pusher.unsubscribe(channelName: name);
      }
      _channels.clear();
      await _pusher.disconnect();
      _initialized = false;
      debugPrint('[WS] Déconnecté');
    } catch (e) {
      debugPrint('[WS] Disconnect error: $e');
    }
  }

  bool get isConnected => _initialized;
}