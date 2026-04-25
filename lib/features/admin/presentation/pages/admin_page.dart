import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';

// ─── Provider ─────────────────────────────────────────────────
final adminUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final response = await ApiClient().adminGetUsers();
  return (response.data as List).map((e) => UserModel.fromJson(e)).toList();
});

final adminInvitationsProvider = FutureProvider<List<InvitationModel>>((ref) async {
  final response = await ApiClient().adminGetInvitations();
  return (response.data as List).map((e) => InvitationModel.fromJson(e)).toList();
});

// ─── Page ─────────────────────────────────────────────────────
class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Administration'),
        backgroundColor: AppColors.white,
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.grey400,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Utilisateurs'),
            Tab(text: 'Invitations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _UsersTab(),
          _InvitationsTab(),
        ],
      ),
    );
  }
}

// ─── Users Tab ────────────────────────────────────────────────
class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
        child: TextButton(
          onPressed: () => ref.invalidate(adminUsersProvider),
          child: const Text('Réessayer'),
        ),
      ),
      data: (users) => RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => ref.invalidate(adminUsersProvider),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _UserCard(
            user: users[index],
            onStatusChange: (status) async {
              await ApiClient().adminUpdateStatus(users[index].id, status);
              ref.invalidate(adminUsersProvider);
            },
            onDelete: () async {
              await ApiClient().adminDeleteUser(users[index].id);
              ref.invalidate(adminUsersProvider);
            },
          ),
        ),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final Function(String) onStatusChange;
  final VoidCallback onDelete;

  const _UserCard({
    required this.user,
    required this.onStatusChange,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Row(
        children: [
          AvatarWidget(name: user.fullName, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.fullName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Nunito',
                          color: AppColors.grey800,
                        ),
                      ),
                    ),
                    if (user.isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Admin',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Nunito',
                          ),
                        ),
                      ),
                  ],
                ),
                Text(
                  user.email,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.grey400,
                    fontFamily: 'Nunito',
                  ),
                ),
                const SizedBox(height: 4),
                _StatusBadge(status: user.status),
              ],
            ),
          ),
          if (!user.isAdmin)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.grey400, size: 20),
              onSelected: (value) {
                if (value == 'delete') {
                  _confirmDelete(context);
                } else {
                  onStatusChange(value);
                }
              },
              itemBuilder: (_) => [
                if (user.status != 'active')
                  const PopupMenuItem(
                    value: 'active',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                        SizedBox(width: 8),
                        Text('Activer', style: TextStyle(fontFamily: 'Nunito')),
                      ],
                    ),
                  ),
                if (user.status != 'suspended')
                  const PopupMenuItem(
                    value: 'suspended',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, color: AppColors.warning, size: 18),
                        SizedBox(width: 8),
                        Text('Suspendre', style: TextStyle(fontFamily: 'Nunito')),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text('Supprimer', style: TextStyle(color: AppColors.error, fontFamily: 'Nunito')),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer l\'utilisateur?',
            style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
        content: Text('Cette action est irréversible pour ${user.fullName}.',
            style: const TextStyle(fontFamily: 'Nunito')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;

    switch (status) {
      case 'active':
        color = AppColors.success;
        label = 'Actif';
        break;
      case 'pending':
        color = AppColors.warning;
        label = 'En attente';
        break;
      case 'suspended':
        color = AppColors.error;
        label = 'Suspendu';
        break;
      default:
        color = AppColors.grey400;
        label = status;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
            fontFamily: 'Nunito',
          ),
        ),
      ],
    );
  }
}

// ─── Invitations Tab ──────────────────────────────────────────
class _InvitationsTab extends ConsumerWidget {
  const _InvitationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitAsync = ref.watch(adminInvitationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showInviteDialog(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Inviter', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
      ),
      body: invitAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(adminInvitationsProvider),
            child: const Text('Réessayer'),
          ),
        ),
        data: (invitations) {
          if (invitations.isEmpty) {
            return const Center(
              child: Text('Aucune invitation envoyée',
                  style: TextStyle(color: AppColors.grey400, fontFamily: 'Nunito')),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(adminInvitationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: invitations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _InvitationCard(
                invitation: invitations[index],
                onDelete: () async {
                  await ApiClient().adminDeleteInvitation(invitations[index].id);
                  ref.invalidate(adminInvitationsProvider);
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showInviteDialog(BuildContext context, WidgetRef ref) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Inviter un utilisateur',
            style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'adresse@email.com'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.isEmpty) return;
              Navigator.pop(context);
              try {
                await ApiClient().adminCreateInvitation(ctrl.text.trim());
                ref.invalidate(adminInvitationsProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Invitation envoyée !')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Erreur lors de l\'envoi')),
                  );
                }
              }
            },
            child: const Text('Inviter'),
          ),
        ],
      ),
    );
  }
}

class _InvitationCard extends StatelessWidget {
  final InvitationModel invitation;
  final VoidCallback onDelete;

  const _InvitationCard({required this.invitation, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: invitation.isValid ? AppColors.grey200 : AppColors.grey100,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: invitation.isUsed
                  ? AppColors.primarySurface
                  : invitation.isExpired
                      ? const Color(0xFFFEF2F2)
                      : AppColors.grey100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              invitation.isUsed
                  ? Icons.check_circle_rounded
                  : invitation.isExpired
                      ? Icons.timer_off_rounded
                      : Icons.email_outlined,
              color: invitation.isUsed
                  ? AppColors.primary
                  : invitation.isExpired
                      ? AppColors.error
                      : AppColors.grey400,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invitation.email,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Nunito',
                    color: invitation.isValid ? AppColors.grey800 : AppColors.grey400,
                  ),
                ),
                Text(
                  invitation.isUsed
                      ? '✓ Compte créé'
                      : invitation.isExpired
                          ? 'Expirée'
                          : 'En attente',
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'Nunito',
                    color: invitation.isUsed
                        ? AppColors.primary
                        : invitation.isExpired
                            ? AppColors.error
                            : AppColors.grey400,
                  ),
                ),
              ],
            ),
          ),
          if (!invitation.isUsed)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 20),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}