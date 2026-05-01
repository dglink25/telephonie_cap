import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/data/auth_provider.dart';
import '../../../conversations/data/conversations_provider.dart';
import '../../data/groups_provider.dart';

final groupDetailProvider =
    FutureProvider.family<GroupModel, int>((ref, groupId) async {
  final response = await ApiClient().getGroup(groupId);
  return GroupModel.fromJson(response.data as Map<String, dynamic>);
});

class GroupSettingsPage extends ConsumerStatefulWidget {
  final int groupId;
  const GroupSettingsPage({super.key, required this.groupId});

  @override
  ConsumerState<GroupSettingsPage> createState() => _GroupSettingsPageState();
}

class _GroupSettingsPageState extends ConsumerState<GroupSettingsPage> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _editing = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        title: const Text('Paramètres du groupe'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.grey700, size: 20),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (_editing)
            TextButton(
              onPressed: _saving ? null : () => _saveGroup(groupAsync.value),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : const Text('Enregistrer',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontFamily: 'Nunito',
                          fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: groupAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(groupDetailProvider(widget.groupId)),
            child: const Text('Réessayer'),
          ),
        ),
        data: (group) {
          final isAdmin = group.isAdmin(currentUser?.id ?? 0);

          if (!_editing) {
            _nameCtrl.text = group.name;
            _descCtrl.text = group.description ?? '';
          }

          return ListView(
            children: [
              // ── Avatar + nom ──────────────────────────────
              Container(
                color: AppColors.white,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: group.isDefault
                            ? AppColors.primary
                            : AppColors.primarySurface,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          group.initials,
                          style: TextStyle(
                            color: group.isDefault
                                ? Colors.white
                                : AppColors.primary,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Nunito',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_editing) ...[
                      TextField(
                        controller: _nameCtrl,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Nunito',
                          color: AppColors.grey800,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Nom du groupe',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _descCtrl,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'Nunito',
                            color: AppColors.grey500),
                        decoration: const InputDecoration(
                          hintText: 'Description (optionnel)',
                        ),
                      ),
                    ] else ...[
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Nunito',
                          color: AppColors.grey800,
                        ),
                      ),
                      if (group.description != null &&
                          group.description!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          group.description!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.grey500,
                              fontFamily: 'Nunito'),
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    if (group.isDefault)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primarySurface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Groupe par défaut',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Nunito')),
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ── Actions admin ─────────────────────────────
              if (isAdmin && !group.isDefault) ...[
                _SectionHeader(title: 'Administration'),
                _ActionTile(
                  icon: Icons.edit_rounded,
                  color: AppColors.primary,
                  title: _editing ? 'Annuler la modification' : 'Modifier le groupe',
                  onTap: () => setState(() => _editing = !_editing),
                ),
                _ActionTile(
                  icon: Icons.person_add_rounded,
                  color: AppColors.info,
                  title: 'Ajouter un membre',
                  onTap: () => _showAddMemberSheet(context, group),
                ),
                const SizedBox(height: 12),
              ],

              // ── Membres ───────────────────────────────────
              _SectionHeader(
                  title: 'Membres (${group.members.length})'),
              ...group.members.map((member) => _MemberTile(
                    member: member,
                    group: group,
                    currentUser: currentUser,
                    isCurrentUserAdmin: isAdmin,
                    onRemove: () =>
                        _removeMember(context, group, member),
                    onPromote: () =>
                        _promoteMember(context, group, member),
                  )),

              const SizedBox(height: 12),

              // ── Zone de danger ────────────────────────────
              _SectionHeader(title: 'Zone de danger'),
              if (!group.isDefault)
                _ActionTile(
                  icon: Icons.exit_to_app_rounded,
                  color: AppColors.warning,
                  title: 'Quitter le groupe',
                  onTap: () => _leaveGroup(context, group),
                ),
              if (isAdmin && !group.isDefault)
                _ActionTile(
                  icon: Icons.delete_rounded,
                  color: AppColors.error,
                  title: 'Supprimer le groupe',
                  onTap: () => _deleteGroup(context, group),
                ),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveGroup(GroupModel? group) async {
    if (group == null) return;
    setState(() => _saving = true);
    try {
      await ApiClient().updateGroup(
        group.id,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      ref.invalidate(groupDetailProvider(widget.groupId));
      ref.read(groupsProvider.notifier).load();
      setState(() {
        _editing = false;
        _saving = false;
      });
      _showSuccess('Groupe mis à jour.');
    } catch (_) {
      setState(() => _saving = false);
      _showError('Impossible de modifier le groupe.');
    }
  }

  void _showAddMemberSheet(BuildContext context, GroupModel group) {
    final existingIds = group.members.map((m) => m.id).toSet();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMemberSheet(
        groupId: group.id,
        existingMemberIds: existingIds,
        onAdded: () =>
            ref.invalidate(groupDetailProvider(widget.groupId)),
      ),
    );
  }

  Future<void> _removeMember(
      BuildContext context, GroupModel group, UserModel member) async {
    final confirmed = await _confirm(
      context,
      title: 'Retirer ${member.fullName} ?',
      body: 'Ce membre sera retiré du groupe.',
      confirmLabel: 'Retirer',
      danger: true,
    );
    if (!confirmed) return;

    try {
      await ApiClient().removeMember(group.id, member.id);
      ref.invalidate(groupDetailProvider(widget.groupId));
      _showSuccess('${member.fullName} a été retiré.');
    } catch (_) {
      _showError('Impossible de retirer ce membre.');
    }
  }

  Future<void> _promoteMember(
      BuildContext context, GroupModel group, UserModel member) async {
    final confirmed = await _confirm(
      context,
      title: 'Promouvoir ${member.fullName} ?',
      body: 'Ce membre deviendra administrateur du groupe.',
      confirmLabel: 'Promouvoir',
    );
    if (!confirmed) return;

    try {
      await ApiClient().dio.patch(
        '/groups/${group.id}/members/${member.id}/promote',
      );
      ref.invalidate(groupDetailProvider(widget.groupId));
      _showSuccess('${member.fullName} est maintenant admin.');
    } catch (_) {
      _showError('Impossible de promouvoir ce membre.');
    }
  }

  Future<void> _leaveGroup(BuildContext context, GroupModel group) async {
    final confirmed = await _confirm(
      context,
      title: 'Quitter ${group.name} ?',
      body: 'Vous ne pourrez plus voir les messages de ce groupe.',
      confirmLabel: 'Quitter',
      danger: true,
    );
    if (!confirmed) return;

    try {
      await ApiClient().leaveGroup(group.id);
      ref.read(groupsProvider.notifier).load();
      if (mounted) context.go('/home');
    } catch (_) {
      _showError('Impossible de quitter le groupe.');
    }
  }

  Future<void> _deleteGroup(BuildContext context, GroupModel group) async {
    final confirmed = await _confirm(
      context,
      title: 'Supprimer ${group.name} ?',
      body: 'Cette action est irréversible. Tous les messages seront perdus.',
      confirmLabel: 'Supprimer',
      danger: true,
    );
    if (!confirmed) return;

    try {
      await ApiClient().deleteGroup(group.id);
      ref.read(groupsProvider.notifier).load();
      if (mounted) context.go('/home');
    } catch (_) {
      _showError('Impossible de supprimer le groupe.');
    }
  }

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
    bool danger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title,
            style: const TextStyle(
                fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
        content: Text(body,
            style: const TextStyle(fontFamily: 'Nunito')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
            style: danger
                ? ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error)
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
      backgroundColor: AppColors.primary,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ─── Widgets internes ─────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.grey400,
          letterSpacing: 0.8,
          fontFamily: 'Nunito',
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      child: ListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title,
            style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600,
                color: color == AppColors.error ? AppColors.error : AppColors.grey800)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppColors.grey300),
        onTap: onTap,
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final UserModel member;
  final GroupModel group;
  final UserModel? currentUser;
  final bool isCurrentUserAdmin;
  final VoidCallback onRemove;
  final VoidCallback onPromote;

  const _MemberTile({
    required this.member,
    required this.group,
    required this.currentUser,
    required this.isCurrentUserAdmin,
    required this.onRemove,
    required this.onPromote,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = member.id == currentUser?.id;
    final isCreator = member.id == group.createdBy;
    final isMemberAdmin = group.isAdmin(member.id);

    return Container(
      color: AppColors.white,
      child: ListTile(
        leading: AvatarWidget(name: member.fullName, size: 44),
        title: Row(
          children: [
            Expanded(
              child: Text(
                member.fullName + (isMe ? ' (Moi)' : ''),
                style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.grey800),
              ),
            ),
            if (isCreator)
              _RoleBadge(label: 'Créateur', color: AppColors.primary)
            else if (isMemberAdmin)
              _RoleBadge(label: 'Admin', color: AppColors.info),
          ],
        ),
        subtitle: Text(
          member.email,
          style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              color: AppColors.grey400),
        ),
        trailing: isCurrentUserAdmin && !isMe && !isCreator
            ? PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    color: AppColors.grey400, size: 20),
                onSelected: (v) {
                  if (v == 'remove') onRemove();
                  if (v == 'promote') onPromote();
                },
                itemBuilder: (_) => [
                  if (!isMemberAdmin)
                    const PopupMenuItem(
                      value: 'promote',
                      child: Row(children: [
                        Icon(Icons.admin_panel_settings_outlined,
                            color: AppColors.info, size: 18),
                        SizedBox(width: 8),
                        Text('Promouvoir admin',
                            style: TextStyle(fontFamily: 'Nunito')),
                      ]),
                    ),
                  const PopupMenuItem(
                    value: 'remove',
                    child: Row(children: [
                      Icon(Icons.remove_circle_outline_rounded,
                          color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text('Retirer du groupe',
                          style: TextStyle(
                              color: AppColors.error,
                              fontFamily: 'Nunito')),
                    ]),
                  ),
                ],
              )
            : null,
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _RoleBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              fontFamily: 'Nunito')),
    );
  }
}

// ─── Sheet ajout de membre ────────────────────────────────────

class _AddMemberSheet extends ConsumerStatefulWidget {
  final int groupId;
  final Set<int> existingMemberIds;
  final VoidCallback onAdded;

  const _AddMemberSheet({
    required this.groupId,
    required this.existingMemberIds,
    required this.onAdded,
  });

  @override
  ConsumerState<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends ConsumerState<_AddMemberSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _adding = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
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
                child: Text('Ajouter un membre',
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
                decoration: const InputDecoration(
                  hintText: 'Rechercher...',
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.grey400, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: usersAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary)),
                error: (_, __) => const Center(
                    child: Text('Erreur de chargement')),
                data: (users) {
                  final available = users
                      .where((u) =>
                          !widget.existingMemberIds.contains(u.id))
                      .where((u) =>
                          _query.isEmpty ||
                          u.fullName.toLowerCase().contains(_query) ||
                          u.email.toLowerCase().contains(_query))
                      .toList();

                  if (available.isEmpty) {
                    return const Center(
                      child: Text('Tous les utilisateurs sont déjà membres.',
                          style: TextStyle(
                              color: AppColors.grey400,
                              fontFamily: 'Nunito')),
                    );
                  }

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    itemCount: available.length,
                    separatorBuilder: (_, __) => const Divider(
                        height: 1, color: AppColors.grey100),
                    itemBuilder: (_, i) {
                      final user = available[i];
                      return ListTile(
                        leading:
                            AvatarWidget(name: user.fullName, size: 44),
                        title: Text(user.fullName,
                            style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontWeight: FontWeight.w600,
                                fontSize: 14)),
                        subtitle: Text(user.email,
                            style: const TextStyle(
                                fontFamily: 'Nunito',
                                fontSize: 12,
                                color: AppColors.grey400)),
                        trailing: _adding
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary))
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 6),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () =>
                                    _addMember(user),
                                child: const Text('Ajouter',
                                    style: TextStyle(
                                        fontFamily: 'Nunito',
                                        fontSize: 12)),
                              ),
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

  Future<void> _addMember(UserModel user) async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      await ApiClient().addMember(widget.groupId, user.id);
      widget.onAdded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${user.fullName} a été ajouté.',
              style: const TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible d\'ajouter ce membre.',
              style: TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }
}