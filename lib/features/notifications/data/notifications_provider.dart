import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class NotificationsNotifier extends StateNotifier<AsyncValue<List<NotificationModel>>> {
  final ApiClient _api = ApiClient();
  int _unreadCount = 0;

  NotificationsNotifier() : super(const AsyncLoading()) {
    load();
  }

  int get unreadCount => _unreadCount;

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final response = await _api.getNotifications();
      final data = response.data as Map<String, dynamic>;
      final list = (data['data'] as List)
          .map((e) => NotificationModel.fromJson(e))
          .toList();
      _unreadCount = list.where((n) => !n.isRead).length;
      state = AsyncData(list);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<void> markRead(String id) async {
    try {
      await _api.readNotification(id);
      state.whenData((notifs) {
        final updated = notifs.map((n) {
          if (n.id == id) {
            return NotificationModel(
              id: n.id,
              type: n.type,
              data: n.data,
              readAt: DateTime.now(),
              createdAt: n.createdAt,
            );
          }
          return n;
        }).toList();
        _unreadCount = updated.where((n) => !n.isRead).length;
        state = AsyncData(updated);
      });
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _api.readAllNotifications();
      state.whenData((notifs) {
        final updated = notifs.map((n) => NotificationModel(
              id: n.id,
              type: n.type,
              data: n.data,
              readAt: DateTime.now(),
              createdAt: n.createdAt,
            )).toList();
        _unreadCount = 0;
        state = AsyncData(updated);
      });
    } catch (_) {}
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, AsyncValue<List<NotificationModel>>>(
  (ref) => NotificationsNotifier(),
);

final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider.notifier).unreadCount;
});