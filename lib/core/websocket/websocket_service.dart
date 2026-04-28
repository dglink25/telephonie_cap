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

  Future<void> init(String authToken) async {
    _authToken = authToken;
    if (_initialized) return;

    try {
      await _pusher.init(
        apiKey: AppConstants.reverbAppKey,

        // ✅ CORRECTION PRINCIPALE :
        //    pusher_channels_flutter ne supporte PAS les paramètres :
        //      ❌ host   → n'existe pas dans cette lib
        //      ❌ port   → n'existe pas dans cette lib
        //      ❌ encrypted → n'existe pas dans cette lib
        //
        //    Les paramètres corrects sont :
        //      ✅ cluster  → requis, 'mt1' si pas de cluster Pusher Cloud
        //      ✅ useTLS   → remplace 'encrypted'
        //
        //    Pour pointer vers Reverb local sur Android/iOS :
        //      → Le package mobile ne supporte pas de host custom nativement.
        //      → Solution : utiliser un tunnel HTTP (ex: ngrok) qui expose
        //        Reverb sur une URL publique, puis mettre cette URL dans reverbHost.
        //      → Pour le WEB : l'override se fait dans index.html (voir ce fichier).
        cluster: AppConstants.reverbCluster,
        useTLS: AppConstants.reverbScheme == 'https',

        authEndpoint:
            '${AppConstants.baseUrl.replaceAll('/api', '')}/broadcasting/auth',

        // ✅ Headers envoyés à authEndpoint pour valider le token
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
          if (currentState == 'DISCONNECTED' || currentState == 'FAILED') {
            _initialized = false;
          }
        },

        onError: (message, code, error) {
          debugPrint('[WS] Erreur $code: $message — $error');
        },
      );

      await _pusher.connect();
      _initialized = true;
      debugPrint('[WS] Connecté (cluster: ${AppConstants.reverbCluster})');
    } catch (e) {
      _initialized = false;
      debugPrint('[WS] Init error: $e');
      rethrow;
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
    if (_channels.containsKey(channelName)) return;

    if (!_initialized) {
      debugPrint("[WS] Non connecté — impossible de s'abonner à $channelName");
      return;
    }

    try {
      final channel = await _pusher.subscribe(
        channelName: channelName,
        onEvent: (event) {
          try {
            final handler = events[event.eventName];
            if (handler != null) {
              Map<String, dynamic> data;
              if (event.data is String) {
                final raw = event.data as String;
                data = raw.isEmpty
                    ? {}
                    : (jsonDecode(raw) as Map<String, dynamic>? ?? {});
              } else if (event.data is Map<String, dynamic>) {
                data = event.data as Map<String, dynamic>;
              } else {
                data = {};
              }
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

  Future<void> unsubscribeFromConversation(int conversationId) async {
    await _unsubscribe('presence-conversation.$conversationId');
  }

  Future<void> unsubscribeFromUserChannel(int userId) async {
    await _unsubscribe('presence-user.$userId');
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
      debugPrint('[WS] Déconnecté');
    }
  }

  bool get isConnected => _initialized;
}