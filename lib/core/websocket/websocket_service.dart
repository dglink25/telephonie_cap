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

  final Map<String, PusherChannel> _channels = {};
  final Map<String, Map<String, EventCallback>> _pendingSubscriptions = {};

  Future<void> init(String authToken) async {
    _authToken = authToken;

    if (_connecting) {
      debugPrint('[WS] Init déjà en cours — attente');
      return;
    }
    if (_initialized) {
      debugPrint('[WS] Déjà connecté');
      return;
    }

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
            _resubscribeAll();
          } else if (currentState == 'DISCONNECTED' ||
              currentState == 'FAILED') {
            _initialized = false;
            _connecting = false;
            _channels.clear();
          }
        },

        onError: (message, code, error) {
          debugPrint('[WS] Erreur $code: $message — $error');
          _connecting = false;
        },

        // onEvent global: route chaque événement vers le bon handler
        // enregistré dans _pendingSubscriptions[channelName]
        onEvent: (PusherEvent event) {
          try {
            final channelName = event.channelName;
            if (channelName == null) return;
            final currentEvents = _pendingSubscriptions[channelName];
            if (currentEvents == null) return;
            final handler = currentEvents[event.eventName];
            if (handler != null) {
              final data = _parseEventData(event.data);
              handler(data);
            }
          } catch (e) {
            debugPrint('[WS] onEvent global error: $e');
          }
        },

        // Signature globale correcte: (String channelName, dynamic data)
        onSubscriptionSucceeded: (String channelName, dynamic data) {
          debugPrint('[WS] ✓ Abonné → $channelName');
        },

        // Signature globale correcte: (String message, dynamic e)
        onSubscriptionError: (String message, dynamic e) {
          debugPrint('[WS] ✗ Erreur abonnement: $message — $e');
        },

        // Signature globale correcte: (String channelName, PusherMember member)
        onMemberAdded: (String channelName, PusherMember member) {
          debugPrint('[WS] 👤 Rejoint $channelName: ${member.userId}');
        },

        onMemberRemoved: (String channelName, PusherMember member) {
          debugPrint('[WS] 👤 Parti $channelName: ${member.userId}');
        },
      );

      await _pusher.connect();
    } catch (e) {
      _initialized = false;
      _connecting = false;
      debugPrint('[WS] Init error: $e');
      rethrow;
    }
  }

  Future<void> _resubscribeAll() async {
    final toResubscribe = Map<String, Map<String, EventCallback>>.from(_pendingSubscriptions);
    debugPrint('[WS] Re-abonnement de ${toResubscribe.length} channels');

    for (final channelName in toResubscribe.keys) {
      _channels.remove(channelName);
      await _doSubscribe(channelName);
      await Future.delayed(const Duration(milliseconds: 100));
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

    // Enregistrer / mettre à jour les handlers
    if (_pendingSubscriptions.containsKey(channelName)) {
      _pendingSubscriptions[channelName]!.addAll(events);
    } else {
      _pendingSubscriptions[channelName] = Map.from(events);
    }

    if (_channels.containsKey(channelName)) {
      debugPrint('[WS] Channel $channelName déjà abonné');
      return;
    }

    if (!_initialized) {
      debugPrint('[WS] Non connecté — subscription en attente: $channelName');
      return;
    }

    await _doSubscribe(channelName);
  }

  Future<void> _doSubscribe(String channelName) async {
    if (!_initialized || _pusher == null) {
      debugPrint('[WS] _doSubscribe ignoré — pas connecté: $channelName');
      return;
    }
    try {
      final channel = await _pusher.subscribe(channelName: channelName);
      _channels[channelName] = channel;
      debugPrint('[WS] Subscribe OK → $channelName');
    } catch (e) {
      debugPrint('[WS] Subscribe FAILED ($channelName): $e');
      _channels.remove(channelName);
    }
  }


  Map<String, dynamic> _parseEventData(dynamic rawData) {
    if (rawData is Map<String, dynamic>) return rawData;
    if (rawData is Map) return Map<String, dynamic>.from(rawData);
    if (rawData is String && rawData.isNotEmpty) {
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

  // ─────────────────────────────────────────────────────────────
  // DÉCONNEXION
  // ─────────────────────────────────────────────────────────────

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
      debugPrint('[WS] Déconnecté proprement');
    }
  }

  bool get isConnected => _initialized;
}