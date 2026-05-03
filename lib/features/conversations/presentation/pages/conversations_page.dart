import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/data/auth_provider.dart';
import '../../data/conversations_provider.dart';

class ConversationsPage extends ConsumerWidget {
  const ConversationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final filter = ref.watch(conversationFilterProvider);
    final conversationsAsync = ref.watch(conversationsProvider);
    final allUsersAsync = ref.watch(allUsersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Messages'),
        backgroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Nouvelle conversation',
            onPressed: () => _showNewConversationSheet(context, ref),
          ),
          if (MediaQuery.of(context).size.width < 768)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (v) {
                if (v == 'logout') ref.read(authProvider.notifier).logout();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout_rounded,
                        color: AppColors.grey600, size: 18),
                    SizedBox(width: 8),
                    Text('Déconnexion',
                        style: TextStyle(fontFamily: 'Nunito')),
                  ]),
                ),
              ],
            ),
        ],
        // Filtres style WhatsApp
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterBar(
            current: filter,
            onChanged: (f) =>
                ref.read(conversationFilterProvider.notifier).state = f,
          ),
        ),
      ),
      body: conversationsAsync.when(
        loading: () => _buildShimmer(),
        error: (e, _) => _buildError(ref),
        data: (conversations) {
          return allUsersAsync.when(
            loading: () => _buildShimmer(),
            error: (_, __) => _buildList(
                context, ref, conversations, [], user?.id ?? 0, filter),
            data: (allUsers) => _buildList(
                context, ref, conversations, allUsers, user?.id ?? 0, filter),
          );
        },
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    WidgetRef ref,
    List<ConversationModel> conversations,
    List<UserModel> allUsers,
    int currentUserId,
    ConversationFilter filter,
  ) {
    // IDs des utilisateurs qui ont déjà une conversation directe
    final existingDirectUserIds = conversations
        .where((c) => !c.isGroup)
        .expand((c) => c.participants.map((p) => p.id))
        .where((id) => id != currentUserId)
        .toSet();

    // Utilisateurs sans conversation existante
    final usersWithoutConv = allUsers
        .where((u) => !existingDirectUserIds.contains(u.id))
        .toList();

    // Appliquer le filtre sur les conversations
    List<ConversationModel> filtered;
    switch (filter) {
      case ConversationFilter.unread:
        filtered = conversations.where((c) => c.hasUnread).toList();
        break;
      case ConversationFilter.groups:
        filtered = conversations.where((c) => c.isGroup).toList();
        break;
      case ConversationFilter.favorites:
        filtered =
            conversations.where((c) => c.isFavorite == true).toList();
        break;
      case ConversationFilter.all:
        filtered = conversations;
        break;
    }

    // En mode "Toutes" → on montre aussi les utilisateurs sans conv
    final showNewUsers =
        filter == ConversationFilter.all && usersWithoutConv.isNotEmpty;

    if (filtered.isEmpty && !showNewUsers) {
      return _buildEmpty(context, ref, filter);
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        ref.read(conversationsProvider.notifier).load();
        ref.invalidate(allUsersProvider);
      },
      child: ListView(
        children: [
          // Conversations existantes
          ...filtered.map((conv) => _ConversationTile(
                conversation: conv,
                currentUserId: currentUserId,
                onFavorite: () => ref
                    .read(conversationsProvider.notifier)
                    .toggleFavorite(conv.id),
              )),

          // Séparateur + utilisateurs sans conversation
          if (showNewUsers) ...[
            if (filtered.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Autres utilisateurs',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey400,
                    fontFamily: 'Nunito',
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ...usersWithoutConv.map((user) => _UserContactTile(
                  user: user,
                  onTap: () => _startAndNavigate(context, ref, user.id),
                )),
          ],
        ],
      ),
    );
  }

  Future<void> _startAndNavigate(
      BuildContext context, WidgetRef ref, int userId) async {
    final conv =
        await ref.read(conversationsProvider.notifier).startDirect(userId);
    if (conv != null && context.mounted) {
      context.push('/conversations/${conv.id}');
    }
  }

  void _showNewConversationSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewConversationSheet(),
    );
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
                decoration: const BoxDecoration(
                    color: AppColors.grey200, shape: BoxShape.circle)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: 140,
                      height: 14,
                      color: AppColors.grey200,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(
                      width: double.infinity,
                      height: 12,
                      color: AppColors.grey100),
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
          const Icon(Icons.wifi_off_rounded,
              color: AppColors.grey300, size: 48),
          const SizedBox(height: 12),
          const Text('Impossible de charger les messages',
              style: TextStyle(color: AppColors.grey500)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () =>
                ref.read(conversationsProvider.notifier).load(),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(
      BuildContext context, WidgetRef ref, ConversationFilter filter) {
    final messages = {
      ConversationFilter.unread: 'Aucun message non lu',
      ConversationFilter.groups: 'Aucun groupe',
      ConversationFilter.favorites: 'Aucun favori',
      ConversationFilter.all: 'Aucune conversation',
    };

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
                color: AppColors.primarySurface, shape: BoxShape.circle),
            child: const Icon(Icons.chat_bubble_outline_rounded,
                color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            messages[filter] ?? 'Aucune conversation',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.grey700,
              fontFamily: 'Nunito',
            ),
          ),
          if (filter == ConversationFilter.all) ...[
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Nouvelle conversation'),
              onPressed: () => _showNewConversationSheet(context, ref),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Barre de filtres ─────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final ConversationFilter current;
  final ValueChanged<ConversationFilter> onChanged;

  const _FilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (ConversationFilter.all, 'Toutes'),
      (ConversationFilter.unread, 'Non lues'),
      (ConversationFilter.groups, 'Groupes'),
      (ConversationFilter.favorites, 'Favoris'),
    ];

    return Container(
      height: 44,
      color: AppColors.white,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: filters.map((item) {
          final isSelected = current == item.$1;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(item.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.grey100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : AppColors.grey200,
                  ),
                ),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Nunito',
                    color: isSelected
                        ? Colors.white
                        : AppColors.grey600,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Tuile conversation existante ─────────────────────────────

class _ConversationTile extends StatelessWidget {
  final ConversationModel conversation;
  final int currentUserId;
  final VoidCallback onFavorite;

  const _ConversationTile({
    required this.conversation,
    required this.currentUserId,
    required this.onFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final name = conversation.getDisplayName(currentUserId);
    final other = conversation.getOtherParticipant(currentUserId);
    final hasUnread = conversation.hasUnread;
    final last = conversation.lastMessage;
    final isFav = conversation.isFavorite ?? false;

    return InkWell(
      onTap: () => context.push('/conversations/${conversation.id}'),
      onLongPress: () => _showOptions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Stack(
              children: [
                if (conversation.isGroup)
                  _GroupAvatar(group: conversation.group)
                else
                  AvatarWidget(name: other?.fullName ?? name, size: 52),
                if (!conversation.isGroup)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.online,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.white, width: 2),
                      ),
                    ),
                  ),
                if (isFav)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: Colors.amber,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.star_rounded,
                          color: Colors.white, size: 10),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
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
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: AppColors.grey800,
                            fontFamily: 'Nunito',
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.lastMessageAt != null)
                        Text(
                          timeago.format(conversation.lastMessageAt!,
                              locale: 'fr'),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread
                                ? AppColors.primary
                                : AppColors.grey400,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
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
                            color: hasUnread
                                ? AppColors.grey700
                                : AppColors.grey400,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
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
void _showOptions(BuildContext context) {
  final isFav = conversation.isFavorite ?? false;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),

          // ── Favori ──────────────────────────────────────
          ListTile(
            leading: Icon(
              isFav ? Icons.star_border_rounded : Icons.star_rounded,
              color: Colors.amber,
            ),
            title: Text(
              isFav ? 'Retirer des favoris' : 'Ajouter aux favoris',
              style: const TextStyle(fontFamily: 'Nunito'),
            ),
            onTap: () {
              Navigator.pop(context);
              onFavorite();
            },
          ),

          // ── Paramètres groupe ────────────────────────────
          if (conversation.isGroup) ...[
            const Divider(height: 1, color: AppColors.grey100),
            ListTile(
              leading: const Icon(
                Icons.settings_rounded,
                color: AppColors.primary,
              ),
              title: const Text(
                'Paramètres du groupe',
                style: TextStyle(fontFamily: 'Nunito'),
              ),
              onTap: () {
                Navigator.pop(context);
                // Récupérer l'id du groupe depuis group ou groupId
                final groupId =
                    conversation.group?.id ?? conversation.groupId;
                if (groupId != null) {
                  context.push('/groups/$groupId/settings');
                }
              },
            ),
          ],

          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

  String _getLastMessagePreview(MessageModel? msg) {
    if (msg == null) return 'Démarrer la conversation...';
    if (msg.isDeleted) return 'Message supprimé';
    if (msg.isImage) return 'to';
    if (msg.isFile) return ' ${msg.mediaName ?? 'Fichier'}';
    if (msg.isAudio) return 'Message vocal';
    if (msg.isVideo) return ' Vidéo';
    return msg.body ?? '';
  }
}

// ─── Tuile utilisateur sans conversation ──────────────────────

class _UserContactTile extends StatelessWidget {
  final UserModel user;
  final VoidCallback onTap;

  const _UserContactTile({required this.user, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            AvatarWidget(name: user.fullName, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.grey800,
                      fontFamily: 'Nunito',
                    ),
                  ),
                  Text(
                    'Appuyer pour démarrer une conversation',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontFamily: 'Nunito',
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chat_bubble_outline_rounded,
                color: AppColors.grey300, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Sheet nouvelle conversation ──────────────────────────────

class _NewConversationSheet extends ConsumerStatefulWidget {
  const _NewConversationSheet();

  @override
  ConsumerState<_NewConversationSheet> createState() =>
      _NewConversationSheetState();
}

class _NewConversationSheetState
    extends ConsumerState<_NewConversationSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _starting = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Nouvelle conversation',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'Nunito',
                        color: AppColors.grey800)),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    setState(() => _query = v.toLowerCase()),
                decoration: InputDecoration(
                  hintText: 'Rechercher par nom ou email...',
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.grey400, size: 20),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          })
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
                error: (e, _) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(allUsersProvider),
                    child: const Text('Réessayer'),
                  ),
                ),
                data: (users) {
                  final filtered = _query.isEmpty
                      ? users
                      : users
                          .where((u) =>
                              u.fullName.toLowerCase().contains(_query) ||
                              u.email.toLowerCase().contains(_query))
                          .toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Text(
                        _query.isEmpty
                            ? 'Aucun utilisateur disponible'
                            : 'Aucun résultat',
                        style: const TextStyle(
                            color: AppColors.grey400,
                            fontFamily: 'Nunito'),
                      ),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, color: AppColors.grey100),
                    itemBuilder: (_, index) {
                      final user = filtered[index];
                      return ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        leading:
                            AvatarWidget(name: user.fullName, size: 46),
                        title: Text(user.fullName,
                            style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.grey800)),
                        subtitle: Text(user.email,
                            style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 12,
                                color: AppColors.grey400)),
                        trailing: _starting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary))
                            : const Icon(Icons.chevron_right_rounded,
                                color: AppColors.grey300),
                        onTap: _starting
                            ? null
                            : () => _startConversation(user),
                      );
                    },
                  );
                },
              ),
            ),
            SizedBox(
                height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Future<void> _startConversation(UserModel user) async {
    if (_starting) return;
    setState(() => _starting = true);
    final conv = await ref
        .read(conversationsProvider.notifier)
        .startDirect(user.id);
    if (!mounted) return;
    setState(() => _starting = false);
    if (conv != null) {
      Navigator.pop(context);
      context.push('/conversations/${conv.id}');
    }
  }
}

// ─── Avatars ──────────────────────────────────────────────────

class _GroupAvatar extends StatelessWidget {
  final GroupModel? group;
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
        child: Text(group?.initials ?? 'G',
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: 'Nunito')),
      ),
    );
  }
}