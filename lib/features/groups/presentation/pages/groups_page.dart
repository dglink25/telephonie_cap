import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../auth/data/auth_provider.dart';
import '../../data/groups_provider.dart';

class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupsProvider);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Groupes'),
        backgroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showCreateGroup(context, ref),
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppColors.grey300, size: 48),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(groupsProvider.notifier).load(),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (groups) {
          if (groups.isEmpty) return _buildEmpty(context, ref);
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => ref.read(groupsProvider.notifier).load(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _GroupCard(
                group: groups[index],
                currentUserId: user?.id ?? 0,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, WidgetRef ref) {
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
            child: const Icon(Icons.group_outlined, color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Aucun groupe',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.grey700,
                fontFamily: 'Nunito',
              )),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _showCreateGroup(context, ref),
            child: const Text('Créer un groupe'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroup(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nouveau groupe',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Nunito',
                  )),
              const SizedBox(height: 20),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Nom du groupe',
                  prefixIcon: Icon(Icons.group_outlined, color: AppColors.grey400, size: 20),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  hintText: 'Description (optionnel)',
                  prefixIcon: Icon(Icons.description_outlined, color: AppColors.grey400, size: 20),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    if (nameCtrl.text.isEmpty) return;
                    Navigator.pop(context);
                    final group = await ref.read(groupsProvider.notifier).create(
                          nameCtrl.text.trim(),
                          description: descCtrl.text.trim().isEmpty
                              ? null
                              : descCtrl.text.trim(),
                        );
                    if (group?.conversation != null && context.mounted) {
                      context.push('/conversations/${group!.conversation!.id}');
                    }
                  },
                  child: const Text('Créer'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final GroupModel group;
  final int currentUserId;

  const _GroupCard({required this.group, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        if (group.conversation != null) {
          context.push('/conversations/${group.conversation!.id}');
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: group.isDefault ? AppColors.primary : AppColors.primarySurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  group.initials,
                  style: TextStyle(
                    color: group.isDefault ? Colors.white : AppColors.primary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'Nunito',
                  ),
                ),
              ),
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
                          group.name,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.grey800,
                            fontFamily: 'Nunito',
                          ),
                        ),
                      ),
                      if (group.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primarySurface,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Défaut',
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
                  const SizedBox(height: 4),
                  Text(
                    '${group.members.length} membre${group.members.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: AppColors.grey400,
                      fontSize: 13,
                      fontFamily: 'Nunito',
                    ),
                  ),
                ],
              ),
            ),
            // Modification ici : bouton paramètres + chevron
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.settings_rounded,
                      color: AppColors.grey400, size: 20),
                  tooltip: 'Paramètres',
                  onPressed: () => context.push('/groups/${group.id}/settings'),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppColors.grey300),
              ],
            ),
          ],
        ),
      ),
    );
  }
}