import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../data/notifications_provider.dart';

class NotificationsPage extends ConsumerStatefulWidget {
  const NotificationsPage({super.key});

  @override
  ConsumerState<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends ConsumerState<NotificationsPage> {
  final Set<String> _selected = {};
  bool _selectionMode = false;

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selectionMode = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterSelectionMode(String id) {
    HapticFeedback.mediumImpact();
    setState(() {
      _selectionMode = true;
      _selected.add(id);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
  }

  void _selectAll(List<NotificationModel> notifications) {
    setState(() {
      _selected.addAll(notifications.map((n) => n.id));
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;

    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Supprimer $count notification${count > 1 ? 's' : ''} ?',
        message: 'Cette action est irréversible.',
        confirmLabel: 'Supprimer',
        confirmColor: AppColors.error,
      ),
    );

    if (confirmed != true || !mounted) return;

    for (final id in _selected.toList()) {
      try {
        await ApiClient().dio.delete('/notifications/$id');
      } catch (_) {}
    }

    await ref.read(notificationsProvider.notifier).load();
    _exitSelectionMode();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count notification${count > 1 ? 's supprimées' : ' supprimée'}',
            style: const TextStyle(fontFamily: 'Nunito'),
          ),
          backgroundColor: AppColors.grey800,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _markSelectedAsRead() async {
    final unreadSelected = _selected.toList();
    for (final id in unreadSelected) {
      await ref.read(notificationsProvider.notifier).markRead(id);
    }
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    final notifState = ref.watch(notificationsProvider);
    final notifAsync = notifState.notifications;

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: _selectionMode
            ? _buildSelectionAppBar(notifAsync.asData?.value ?? [])
            : _buildNormalAppBar(),
        body: notifAsync.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => _buildError(),
          data: (notifications) => notifications.isEmpty
              ? _buildEmpty()
              : _buildList(notifications),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildNormalAppBar() {
    final unreadCount = ref.watch(unreadCountProvider);

    return AppBar(
      title: Row(
        children: [
          const Text('Notifications'),
          if (unreadCount > 0) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Nunito',
                ),
              ),
            ),
          ],
        ],
      ),
      backgroundColor: AppColors.white,
      actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (v) {
            switch (v) {
              case 'mark_all':
                ref.read(notificationsProvider.notifier).markAllRead();
                break;
              case 'select':
                final notifications =
                    ref.read(notificationsProvider).notifications.asData?.value ?? [];
                if (notifications.isNotEmpty) {
                  _enterSelectionMode(notifications.first.id);
                }
                break;
              case 'delete_read':
                _deleteReadNotifications();
                break;
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'mark_all',
              child: Row(children: [
                Icon(Icons.done_all_rounded, color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Text('Tout marquer comme lu',
                    style: TextStyle(fontFamily: 'Nunito')),
              ]),
            ),
            const PopupMenuItem(
              value: 'select',
              child: Row(children: [
                Icon(Icons.checklist_rounded, color: AppColors.grey600, size: 18),
                SizedBox(width: 10),
                Text('Sélectionner', style: TextStyle(fontFamily: 'Nunito')),
              ]),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'delete_read',
              child: Row(children: [
                Icon(Icons.delete_sweep_rounded, color: AppColors.error, size: 18),
                SizedBox(width: 10),
                Text('Supprimer les lues',
                    style: TextStyle(
                        fontFamily: 'Nunito', color: AppColors.error)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar(List<NotificationModel> all) {
    final allSelected = _selected.length == all.length;

    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _exitSelectionMode,
      ),
      title: Text(
        '${_selected.length} sélectionné${_selected.length > 1 ? 's' : ''}',
        style: const TextStyle(
            fontFamily: 'Nunito', fontWeight: FontWeight.w700, color: Colors.white),
      ),
      actions: [
        // Tout sélectionner / désélectionner
        TextButton(
          onPressed: allSelected ? _exitSelectionMode : () => _selectAll(all),
          child: Text(
            allSelected ? 'Désélectionner tout' : 'Tout',
            style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600),
          ),
        ),
        // Actions
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          onSelected: (v) {
            if (v == 'read') _markSelectedAsRead();
            if (v == 'delete') _deleteSelected();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'read',
              child: Row(children: [
                Icon(Icons.mark_email_read_rounded,
                    color: AppColors.primary, size: 18),
                SizedBox(width: 10),
                Text('Marquer comme lu',
                    style: TextStyle(fontFamily: 'Nunito')),
              ]),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 18),
                SizedBox(width: 10),
                Text('Supprimer',
                    style: TextStyle(
                        fontFamily: 'Nunito', color: AppColors.error)),
              ]),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildList(List<NotificationModel> notifications) {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => ref.read(notificationsProvider.notifier).load(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: notifications.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final notif = notifications[index];
          final isSelected = _selected.contains(notif.id);

          return _NotificationCard(
            notification: notif,
            isSelected: isSelected,
            selectionMode: _selectionMode,
            onTap: () {
              if (_selectionMode) {
                _toggleSelection(notif.id);
              } else {
                _handleTap(notif);
              }
            },
            onLongPress: () {
              if (!_selectionMode) {
                _enterSelectionMode(notif.id);
              }
            },
          );
        },
      ),
    );
  }

  void _handleTap(NotificationModel notification) {
    if (!notification.isRead) {
      ref.read(notificationsProvider.notifier).markRead(notification.id);
    }

    final data = notification.data;
    final type = data['type'] as String? ?? notification.type;

    final convIdRaw = data['conversation_id'];
    if (convIdRaw == null) return;

    // Gérer les deux formats : int ou String
    final convId = convIdRaw is int
        ? convIdRaw
        : int.tryParse(convIdRaw.toString());
    if (convId == null) return;

    context.push('/conversations/$convId');
  }

  Future<void> _deleteReadNotifications() async {
    final notifications =
        ref.read(notificationsProvider).notifications.asData?.value ?? [];
    final readIds = notifications
        .where((n) => n.isRead)
        .map((n) => n.id)
        .toList();

    if (readIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Aucune notification lue à supprimer',
              style: TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.grey600,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Supprimer ${readIds.length} notification${readIds.length > 1 ? 's' : ''} lue${readIds.length > 1 ? 's' : ''} ?',
        message: 'Seules les notifications déjà lues seront supprimées.',
        confirmLabel: 'Supprimer',
        confirmColor: AppColors.error,
      ),
    );

    if (confirmed != true || !mounted) return;

    for (final id in readIds) {
      try {
        await ApiClient().dio.delete('/notifications/$id');
      } catch (_) {}
    }

    await ref.read(notificationsProvider.notifier).load();
  }

  Widget _buildEmpty() {
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
          const Text(
            'Aucune notification',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.grey700,
              fontFamily: 'Nunito',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Vos notifications apparaîtront ici',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.grey400,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.grey300, size: 48),
          const SizedBox(height: 12),
          const Text('Impossible de charger les notifications',
              style: TextStyle(color: AppColors.grey500, fontFamily: 'Nunito')),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.read(notificationsProvider.notifier).load(),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}

// ─── Carte notification ───────────────────────────────────────
class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _NotificationCard({
    required this.notification,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primarySurface
              : notification.isRead
                  ? AppColors.white
                  : AppColors.primarySurface.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : notification.isRead
                    ? AppColors.grey200
                    : AppColors.primaryMid,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox en mode sélection, sinon icône
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: selectionMode
                  ? Container(
                      key: const ValueKey('checkbox'),
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.primary : AppColors.grey100,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.grey300,
                          width: 2,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(Icons.check_rounded,
                              color: Colors.white, size: 20)
                          : null,
                    )
                  : Container(
                      key: const ValueKey('icon'),
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
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
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
                      ),
                      Text(
                        timeago.format(notification.createdAt, locale: 'fr'),
                        style: TextStyle(
                          fontSize: 11,
                          color: notification.isRead
                              ? AppColors.grey400
                              : AppColors.primary,
                          fontFamily: 'Nunito',
                          fontWeight: notification.isRead
                              ? FontWeight.w400
                              : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  if (notification.body.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.grey500,
                        fontFamily: 'Nunito',
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  // Badge type
                  _TypeBadge(type: notification.data['type'] as String? ?? notification.type),
                ],
              ),
            ),
            if (!notification.isRead && !selectionMode)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4, left: 6),
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
    final type = notification.data['type'] as String? ?? notification.type;
    if (type.contains('message') || type.contains('Message')) {
      return Icons.chat_bubble_outline_rounded;
    }
    if (type.contains('call') || type.contains('Call')) {
      return Icons.call_outlined;
    }
    return Icons.notifications_outlined;
  }
}

// ─── Badge type ───────────────────────────────────────────────
class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isMessage = type.contains('message') || type.contains('Message');
    final isCall = type.contains('call') || type.contains('Call');

    final label = isMessage
        ? 'Message'
        : isCall
            ? 'Appel'
            : 'Notification';

    final color = isMessage
        ? AppColors.info
        : isCall
            ? AppColors.success
            : AppColors.grey400;

    final icon = isMessage
        ? Icons.chat_bubble_outline_rounded
        : isCall
            ? Icons.call_outlined
            : Icons.notifications_outlined;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ─── Dialog confirmation ──────────────────────────────────────
class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        title,
        style: const TextStyle(
            fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 16),
      ),
      content: Text(
        message,
        style: const TextStyle(
            fontFamily: 'Nunito', color: AppColors.grey500, fontSize: 14),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Annuler',
              style: TextStyle(fontFamily: 'Nunito', color: AppColors.grey600)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel,
              style: const TextStyle(
                  fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}