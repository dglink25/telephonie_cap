import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class NotificationsState {
  final AsyncValue<List<NotificationModel>> notifications;
  final int unreadCount;

  const NotificationsState({
    required this.notifications,
    required this.unreadCount,
  });

  NotificationsState copyWith({
    AsyncValue<List<NotificationModel>>? notifications,
    int? unreadCount,
  }) =>
      NotificationsState(
        notifications: notifications ?? this.notifications,
        unreadCount: unreadCount ?? this.unreadCount,
      );
}

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  final ApiClient _api = ApiClient();

  NotificationsNotifier()
      : super(NotificationsState(
          notifications: const AsyncLoading(),
          unreadCount: 0,
        )) {
    load();
  }

  Future<void> load() async {
    state = state.copyWith(notifications: const AsyncLoading());
    try {
      final response = await _api.getNotifications();
      final data = response.data as Map<String, dynamic>;
      final list = (data['data'] as List)
          .map((e) => NotificationModel.fromJson(e))
          .toList();
      final unread = list.where((n) => !n.isRead).length;
      state = state.copyWith(
        notifications: AsyncData(list),
        unreadCount: unread,
      );
    } catch (e, s) {
      state = state.copyWith(notifications: AsyncError(e, s));
    }
  }

  /// Ajoute une notification reçue en temps réel via Reverb.
  void addRealtimeNotification(Map<String, dynamic> data) {
    try {
      final notif = NotificationModel.fromJson(data);
      final current = state.notifications.asData?.value;
      if (current == null) return;
      if (current.any((n) => n.id == notif.id)) return;

      final updated = List<NotificationModel>.from([notif, ...current]);
      state = state.copyWith(
        notifications: AsyncData(updated),
        unreadCount: state.unreadCount + 1,
      );
    } catch (_) {}
  }

  Future<void> markRead(String id) async {
    try {
      await _api.readNotification(id);
      final current = state.notifications.asData?.value ?? [];
      final updated = current.map((n) {
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
      final unread = updated.where((n) => !n.isRead).length;
      state = state.copyWith(
        notifications: AsyncData(updated),
        unreadCount: unread,
      );
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _api.readAllNotifications();
      final current = state.notifications.asData?.value ?? [];
      final updated = current
          .map((n) => NotificationModel(
                id: n.id,
                type: n.type,
                data: n.data,
                readAt: DateTime.now(),
                createdAt: n.createdAt,
              ))
          .toList();
      state = state.copyWith(
        notifications: AsyncData(updated),
        unreadCount: 0,
      );
    } catch (_) {}
  }
}

final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>(
  (ref) => NotificationsNotifier(),
);

final unreadCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).unreadCount;
});