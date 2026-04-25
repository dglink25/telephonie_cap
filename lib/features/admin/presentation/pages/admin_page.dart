import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';

// ─── Providers ────────────────────────────────────────────────
final adminUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final response = await ApiClient().adminGetUsers();
  final list = response.data;
  if (list is! List) return [];
  return list.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
});

final adminInvitationsProvider = FutureProvider<List<InvitationModel>>((ref) async {
  final response = await ApiClient().adminGetInvitations();
  final list = response.data;
  if (list is! List) return [];
  return list
      .map((e) => InvitationModel.fromJson(e as Map<String, dynamic>))
      .toList();
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
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
          labelStyle: const TextStyle(
              fontFamily: 'Nunito', fontWeight: FontWeight.w700),
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
      loading: () =>
          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text('Erreur: $e',
                style: const TextStyle(
                    color: AppColors.grey500, fontFamily: 'Nunito')),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.invalidate(adminUsersProvider),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
      data: (users) => RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async => ref.invalidate(adminUsersProvider),
        child: users.isEmpty
            ? const Center(
                child: Text('Aucun utilisateur',
                    style: TextStyle(
                        color: AppColors.grey400, fontFamily: 'Nunito')),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: users.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _UserCard(
                  user: users[index],
                  onStatusChange: (status) async {
                    try {
                      await ApiClient()
                          .adminUpdateStatus(users[index].id, status);
                      ref.invalidate(adminUsersProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text('Statut mis à jour : $status')),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Erreur lors de la mise à jour')),
                        );
                      }
                    }
                  },
                  onDelete: () async {
                    try {
                      await ApiClient().adminDeleteUser(users[index].id);
                      ref.invalidate(adminUsersProvider);
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Erreur lors de la suppression')),
                        );
                      }
                    }
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
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
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.grey400, size: 20),
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
                        Icon(Icons.check_circle_outline,
                            color: AppColors.success, size: 18),
                        SizedBox(width: 8),
                        Text('Activer',
                            style: TextStyle(fontFamily: 'Nunito')),
                      ],
                    ),
                  ),
                if (user.status != 'suspended')
                  const PopupMenuItem(
                    value: 'suspended',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded,
                            color: AppColors.warning, size: 18),
                        SizedBox(width: 8),
                        Text('Suspendre',
                            style: TextStyle(fontFamily: 'Nunito')),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded,
                          color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text('Supprimer',
                          style: TextStyle(
                              color: AppColors.error, fontFamily: 'Nunito')),
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
        title: const Text(
          'Supprimer l\'utilisateur?',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Cette action est irréversible pour ${user.fullName}.',
          style: const TextStyle(fontFamily: 'Nunito'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.error),
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
class _InvitationsTab extends ConsumerStatefulWidget {
  const _InvitationsTab();

  @override
  ConsumerState<_InvitationsTab> createState() => _InvitationsTabState();
}

class _InvitationsTabState extends ConsumerState<_InvitationsTab> {
  bool _isSending = false;

  @override
  Widget build(BuildContext context) {
    final invitAsync = ref.watch(adminInvitationsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSending ? null : () => _showInviteDialog(context),
        icon: _isSending
            ? const SizedBox(
                width: 18,
                height: 18,
                child:
                    CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add),
        label: Text(
          _isSending ? 'Envoi...' : 'Inviter',
          style: const TextStyle(
              fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      body: invitAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text('Erreur: $e',
                  style: const TextStyle(
                      color: AppColors.grey500, fontFamily: 'Nunito')),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.invalidate(adminInvitationsProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (invitations) {
          if (invitations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.primarySurface,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mail_outline_rounded,
                        color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aucune invitation envoyée',
                    style: TextStyle(
                      color: AppColors.grey600,
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Appuyez sur + Inviter pour envoyer\nune invitation par email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.grey400,
                        fontFamily: 'Nunito',
                        fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(adminInvitationsProvider),
            child: ListView.separated(
              padding:
                  const EdgeInsets.fromLTRB(16, 16, 16, 88), // space for FAB
              itemCount: invitations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _InvitationCard(
                invitation: invitations[index],
                onDelete: () async {
                  try {
                    await ApiClient()
                        .adminDeleteInvitation(invitations[index].id);
                    ref.invalidate(adminInvitationsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invitation supprimée')),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text('Erreur lors de la suppression')),
                      );
                    }
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _showInviteDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Inviter un utilisateur',
          style: TextStyle(
              fontFamily: 'Nunito', fontWeight: FontWeight.w800),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Un email d\'invitation sera envoyé à cette adresse.',
                style: TextStyle(
                    color: AppColors.grey500,
                    fontSize: 13,
                    fontFamily: 'Nunito'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: ctrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'adresse@email.com',
                  prefixIcon: Icon(Icons.email_outlined,
                      color: AppColors.grey400, size: 20),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Email requis';
                  if (!v.contains('@') || !v.contains('.')) {
                    return 'Email invalide';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Envoyer'),
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(dialogCtx);

              setState(() => _isSending = true);
              try {
                await ApiClient()
                    .adminCreateInvitation(ctrl.text.trim());
                // ✅ Refresh immédiat de la liste
                ref.invalidate(adminInvitationsProvider);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text('Invitation envoyée à ${ctrl.text.trim()}'),
                        ],
                      ),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  // Parse error message from API if available
                  String errorMsg = 'Erreur lors de l\'envoi';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(errorMsg)),
                        ],
                      ),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              } finally {
                if (mounted) setState(() => _isSending = false);
              }
            },
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
    final statusColor = invitation.isUsed
        ? AppColors.primary
        : invitation.isExpired
            ? AppColors.error
            : AppColors.warning;

    final statusLabel = invitation.isUsed
        ? 'Compte créé'
        : invitation.isExpired
            ? 'Expirée'
            : 'En attente';

    final statusIcon = invitation.isUsed
        ? Icons.check_circle_rounded
        : invitation.isExpired
            ? Icons.timer_off_rounded
            : Icons.schedule_rounded;

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
                      : const Color(0xFFFFFBEB),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.email_outlined,
              color: invitation.isValid
                  ? AppColors.warning
                  : invitation.isUsed
                      ? AppColors.primary
                      : AppColors.error,
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
                    color: invitation.isValid
                        ? AppColors.grey800
                        : AppColors.grey400,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(statusIcon, size: 12, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                    if (!invitation.isUsed) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· expire ${_formatDate(invitation.expiresAt)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'Nunito',
                          color: AppColors.grey400,
                        ),
                      ),
                    ],
                  ],
                ),
                if (invitation.invitedBy != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Invité par ${invitation.invitedBy!.fullName}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: 'Nunito',
                      color: AppColors.grey400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!invitation.isUsed)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 20),
              tooltip: 'Supprimer',
              onPressed: () => _confirmDelete(context),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'expiré';
    if (diff.inHours < 24) return 'dans ${diff.inHours}h';
    return 'dans ${diff.inDays}j';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Supprimer l\'invitation ?',
          style:
              TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'L\'invitation pour ${invitation.email} sera supprimée.',
          style: const TextStyle(fontFamily: 'Nunito'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error),
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