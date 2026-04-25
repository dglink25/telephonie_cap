import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/data/auth_provider.dart';
import '../../data/conversations_provider.dart';
import '../../../../shared/widgets/avatar_widget.dart';

class ConversationsPage extends ConsumerWidget {
  const ConversationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _showNewConversation(context, ref),
          ),
        ],
      ),
      body: conversationsAsync.when(
        loading: () => _buildShimmer(),
        error: (e, _) => _buildError(ref),
        data: (conversations) {
          if (conversations.isEmpty) return _buildEmpty();
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.read(conversationsProvider.notifier).load(),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: conversations.length,
              itemBuilder: (context, index) => _ConversationTile(
                conversation: conversations[index],
                currentUserId: user?.id ?? 0,
              ),
            ),
          );
        },
      ),
    );
  }

  void _showNewConversation(BuildContext context, WidgetRef ref) {
    // Navigate to user list to start conversation
    context.push('/users/select');
  }

  Widget _buildShimmer() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.grey200,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 140, height: 14, color: AppColors.grey200,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(width: double.infinity, height: 12, color: AppColors.grey100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: AppColors.grey300, size: 48),
          const SizedBox(height: 12),
          const Text('Impossible de charger les conversations',
              style: TextStyle(color: AppColors.grey500)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.read(conversationsProvider.notifier).load(),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
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
            child: const Icon(Icons.chat_bubble_outline_rounded,
                color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Aucune conversation',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.grey700,
                fontFamily: 'Nunito',
              )),
          const SizedBox(height: 6),
          const Text('Commencez une nouvelle conversation',
              style: TextStyle(color: AppColors.grey400, fontFamily: 'Nunito')),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final int currentUserId;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context) {
    final name = conversation.getDisplayName(currentUserId);
    final other = conversation.getOtherParticipant(currentUserId);
    final hasUnread = conversation.hasUnread;
    final last = conversation.lastMessage;

    return InkWell(
      onTap: () => context.push('/conversations/${conversation.id}'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                if (conversation.isGroup)
                  _GroupAvatar(group: conversation.group)
                else
                  AvatarWidget(
                    name: other?.fullName ?? name,
                    size: 52,
                  ),
                if (!conversation.isGroup && other != null)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                            color: AppColors.grey800,
                            fontFamily: 'Nunito',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.lastMessageAt != null)
                        Text(
                          timeago.format(conversation.lastMessageAt!, locale: 'fr'),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread ? AppColors.primary : AppColors.grey400,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                            fontFamily: 'Nunito',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _getLastMessagePreview(last),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: hasUnread ? AppColors.grey700 : AppColors.grey400,
                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w400,
                            fontFamily: 'Nunito',
                          ),
                        ),
                      ),
                      if (hasUnread)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getLastMessagePreview(MessageModel? msg) {
    if (msg == null) return 'Démarrer la conversation...';
    if (msg.isDeleted) return '🗑 Message supprimé';
    if (msg.isImage) return '📷 Photo';
    if (msg.isFile) return '📄 ${msg.mediaName ?? 'Fichier'}';
    if (msg.isAudio) return '🎵 Message vocal';
    if (msg.isVideo) return '🎥 Vidéo';
    return msg.body ?? '';
  }
}

class _GroupAvatar extends StatelessWidget {
  final dynamic group;
  const _GroupAvatar({this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.primaryMid, width: 1.5),
      ),
      child: Center(
        child: Text(
          group?.initials ?? 'G',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFamily: 'Nunito',
          ),
        ),
      ),
    );
  }
}