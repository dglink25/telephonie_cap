import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../data/notifications_provider.dart';

class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifState = ref.watch(notificationsProvider);
    final notifAsync = notifState.notifications;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: AppColors.white,
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(notificationsProvider.notifier).markAllRead(),
            child: const Text('Tout lire',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
      body: notifAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () =>
                ref.read(notificationsProvider.notifier).load(),
            child: const Text('Réessayer'),
          ),
        ),
        data: (notifications) {
          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.notifications_outlined,
                        color: AppColors.primary, size: 36),
                  ),
                  const SizedBox(height: 16),
                  const Text('Aucune notification',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.grey700,
                        fontFamily: 'Nunito',
                      )),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () =>
                ref.read(notificationsProvider.notifier).load(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _NotificationCard(
                  notification: notifications[index]),
            ),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  final NotificationModel notification;
  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        if (!notification.isRead) {
          ref
              .read(notificationsProvider.notifier)
              .markRead(notification.id);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: notification.isRead
              ? AppColors.white
              : AppColors.primarySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.isRead
                ? AppColors.grey200
                : AppColors.primaryMid,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: notification.isRead
                    ? AppColors.grey100
                    : AppColors.primaryMid,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getIcon(),
                color: notification.isRead
                    ? AppColors.grey400
                    : AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: notification.isRead
                          ? FontWeight.w600
                          : FontWeight.w700,
                      color: AppColors.grey800,
                      fontFamily: 'Nunito',
                    ),
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.grey500,
                        fontFamily: 'Nunito',
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeago.format(notification.createdAt, locale: 'fr'),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.grey400,
                      fontFamily: 'Nunito',
                    ),
                  ),
                ],
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }

  IconData _getIcon() {
    if (notification.type.contains('Message')) {
      return Icons.chat_bubble_outline_rounded;
    }
    if (notification.type.contains('Call')) return Icons.call_outlined;
    return Icons.notifications_outlined;
  }
}