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
    // Retry jusqu'à 10 fois (5 secondes max) pour attendre la connexion WS
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
        // Laisser le temps à la connexion de s'établir
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        debugPrint('[NotifListener] WS init error: $e');
        return;
      }
    }

    if (!ws.isConnected) {
      debugPrint('[NotifListener] WS toujours déconnecté après init, abandon');
      return;
    }

    debugPrint('[NotifListener] ✓ Abonnement canal presence-user.${user.id}');
    ws.subscribeToUserChannel(user.id, events: {
      'notification.new': (data) {
        debugPrint('[NotifListener] ✓ notification.new reçue: $data');
        ref
            .read(notificationsProvider.notifier)
            .addRealtimeNotification(data);
      },
    });
  }

  doSubscribe();

  ref.onDispose(() {
    ws.unsubscribeFromUserChannel(user.id);
  });
});