// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Envoie le token auth + URLs au Service Worker
/// pour qu'il se connecte à Reverb et reçoive les événements.
void setupServiceWorkerConnection({
  required String authToken,
  required String apiBaseUrl,
  required String reverbHost,
  required int reverbPort,
}) {
  if (!kIsWeb) return;
  try {
    final sw = html.window.navigator.serviceWorker?.controller;
    if (sw == null) {
      debugPrint('[SW] Pas de Service Worker actif');
      return;
    }
    sw.postMessage({
      'type':        'SET_AUTH_TOKEN',
      'token':       authToken,
      'apiBaseUrl':  apiBaseUrl,
      'reverbWsUrl': 'ws://$reverbHost:$reverbPort/app/xtsedffitwzc6vpwl7tz?protocol=7&client=sw&version=8.3.0',
    });
    debugPrint('[SW] Token envoyé au Service Worker');
  } catch (e) {
    debugPrint('[SW] setupServiceWorkerConnection error: $e');
  }
}

/// Abonne le Service Worker à une conversation (appels + messages)
void subscribeSwToConversation(int conversationId) {
  if (!kIsWeb) return;
  try {
    final sw = html.window.navigator.serviceWorker?.controller;
    sw?.postMessage({
      'type':           'SUBSCRIBE_CONVERSATION',
      'conversationId': conversationId,
    });
  } catch (e) {
    debugPrint('[SW] subscribeConversation error: $e');
  }
}

/// Abonne le Service Worker au canal utilisateur (notifications)
void subscribeSwToUser(int userId) {
  if (!kIsWeb) return;
  try {
    final sw = html.window.navigator.serviceWorker?.controller;
    sw?.postMessage({'type': 'SUBSCRIBE_USER', 'userId': userId});
    debugPrint('[SW] Abonnement user.$userId envoyé');
  } catch (e) {
    debugPrint('[SW] subscribeUser error: $e');
  }
}
