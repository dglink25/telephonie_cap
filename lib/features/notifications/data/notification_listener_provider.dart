import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/auth_storage.dart';
import '../../../core/websocket/websocket_service.dart';
import '../../auth/data/auth_provider.dart';
import 'notifications_provider.dart';

final notificationListenerProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return;

  final ws = WebSocketService();

  Future<void> doSubscribe() async {
    // Attendre la connexion WS (max 5 secondes)
    for (int i = 0; i < 10; i++) {
      if (ws.isConnected) break;
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Si toujours pas connecté, forcer l'init
    if (!ws.isConnected) {
      final token = await AuthStorage.getToken();
      if (token == null) {
        debugPrint('[NotifListener] Pas de token, abandon');
        return;
      }
      try {
        await ws.init(token);
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        debugPrint('[NotifListener] WS init error: $e');
        return;
      }
    }

    if (!ws.isConnected) {
      debugPrint('[NotifListener] WS toujours déconnecté, abandon');
      return;
    }

    debugPrint('[NotifListener] ✓ Abonnement presence-user.${user.id}');

    // BUG #5 CORRIGÉ : subscribeToUserChannel existe maintenant dans le service unifié
    ws.subscribeToUserChannel(user.id, events: {
      'notification.new': (data) {
        debugPrint('[NotifListener] ✓ notification.new: $data');
        ref.read(notificationsProvider.notifier).addRealtimeNotification(data);
      },
    });
  }

  doSubscribe();

  ref.onDispose(() {
    ws.unsubscribeFromUserChannel(user.id);
  });
});
