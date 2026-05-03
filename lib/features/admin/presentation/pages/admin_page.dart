import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/data/auth_provider.dart' show parseDioError;


final adminUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final List<UserModel> allUsers = [];
  int page = 1;
  int lastPage = 1;

  do {
    final response = await ApiClient().adminGetUsers(page: page);
    final data = response.data;
    
    List<dynamic> list;
    if (data is Map && data.containsKey('data')) {
      list = data['data'] as List<dynamic>;
      lastPage = data['last_page'] as int? ?? 1;
    } else if (data is List) {
      list = data;
    } else {
      list = [];
    }

    allUsers.addAll(
      list.map((e) => UserModel.fromJson(e as Map<String, dynamic>)),
    );
    page++;
  } while (page <= lastPage);

  return allUsers;
});

final adminInvitationsProvider = FutureProvider<List<InvitationModel>>((ref) async {
  final response = await ApiClient().adminGetInvitations();
  final data = response.data;
  List<dynamic> list;
  if (data is Map && data.containsKey('data')) {
    list = data['data'] as List<dynamic>;
  } else if (data is List) {
    list = data;
  } else {
    list = [];
  }
  return list.map((e) => InvitationModel.fromJson(e as Map<String, dynamic>)).toList();
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
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
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
          labelStyle: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
          tabs: const [
            Tab(text: 'Utilisateurs'),
            Tab(text: 'Invitations'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UsersTab(
            searchQuery: _searchQuery,
            searchController: _searchController,
            onSearch: (q) => setState(() => _searchQuery = q),
          ),
          const _InvitationsTab(),
        ],
      ),
    );
  }
}

// ─── Users Tab ────────────────────────────────────────────────
class _UsersTab extends ConsumerWidget {
  final String searchQuery;
  final TextEditingController searchController;
  final ValueChanged<String> onSearch;

  const _UsersTab({
    required this.searchQuery,
    required this.searchController,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => _ErrorView(
        message: parseDioError(e),
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      data: (users) {
        // FIX: Filtrage côté client
        final filtered = searchQuery.isEmpty
            ? users
            : users.where((u) {
                final q = searchQuery.toLowerCase();
                return u.fullName.toLowerCase().contains(q) ||
                    u.email.toLowerCase().contains(q) ||
                    (u.phoneNumber?.contains(q) ?? false);
              }).toList();

        return Column(
          children: [
            // Barre de recherche
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: searchController,
                onChanged: onSearch,
                decoration: InputDecoration(
                  hintText: 'Rechercher par nom, email, téléphone...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.grey400, size: 20),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            searchController.clear();
                            onSearch('');
                          },
                        )
                      : null,
                ),
              ),
            ),

            // Compteur
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${filtered.length} utilisateur${filtered.length > 1 ? 's' : ''}',
                    style: const TextStyle(
                      color: AppColors.grey500,
                      fontFamily: 'Nunito',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Actualiser'),
                    onPressed: () => ref.invalidate(adminUsersProvider),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async => ref.invalidate(adminUsersProvider),
                child: filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'Aucun utilisateur trouvé',
                          style: TextStyle(color: AppColors.grey400, fontFamily: 'Nunito'),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          return _UserCard(
                            user: user,
                            onStatusChange: (status) =>
                                _updateStatus(context, ref, user, status),
                            onDelete: () =>
                                _confirmDeleteUser(context, ref, user),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
    String status,
  ) async {
    try {
      await ApiClient().adminUpdateStatus(user.id, status);
      ref.invalidate(adminUsersProvider);
      if (context.mounted) _showSuccess(context, 'Statut mis à jour : $status');
    } catch (e) {
      if (context.mounted) _showError(context, parseDioError(e));
    }
  }

  Future<void> _confirmDeleteUser(
    BuildContext context,
    WidgetRef ref,
    UserModel user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Supprimer l\'utilisateur ?',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Cette action est irréversible pour ${user.fullName}.',
          style: const TextStyle(fontFamily: 'Nunito'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ApiClient().adminDeleteUser(user.id);
      ref.invalidate(adminUsersProvider);
      if (context.mounted) _showSuccess(context, '${user.fullName} a été supprimé.');
    } catch (e) {
      if (context.mounted) _showError(context, parseDioError(e));
    }
  }
}

// ─── User Card ────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final UserModel user;
  final void Function(String) onStatusChange;
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
                  style: const TextStyle(fontSize: 12, color: AppColors.grey500, fontFamily: 'Nunito'),
                ),
                Text(
                  user.phoneNumber ?? 'Pas de numéro',
                  style: const TextStyle(fontSize: 12, color: AppColors.grey400, fontFamily: 'Nunito'),
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
                  onDelete();
                } else {
                  onStatusChange(value);
                }
              },
              itemBuilder: (_) => [
                if (user.status != 'active')
                  const PopupMenuItem(
                    value: 'active',
                    child: Row(children: [
                      Icon(Icons.check_circle_outline, color: AppColors.success, size: 18),
                      SizedBox(width: 8),
                      Text('Activer', style: TextStyle(fontFamily: 'Nunito')),
                    ]),
                  ),
                if (user.status != 'suspended')
                  const PopupMenuItem(
                    value: 'suspended',
                    child: Row(children: [
                      Icon(Icons.block_rounded, color: AppColors.warning, size: 18),
                      SizedBox(width: 8),
                      Text('Suspendre', style: TextStyle(fontFamily: 'Nunito')),
                    ]),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
                    SizedBox(width: 8),
                    Text('Supprimer', style: TextStyle(color: AppColors.error, fontFamily: 'Nunito')),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String? status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;

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
        label = status ?? 'Inconnu';
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
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.add),
        label: Text(
          _isSending ? 'Envoi...' : 'Inviter',
          style: const TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700),
        ),
      ),
      body: invitAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => _ErrorView(
          message: parseDioError(e),
          onRetry: () => ref.invalidate(adminInvitationsProvider),
        ),
        data: (invitations) {
          if (invitations.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.primarySurface, shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.mail_outline_rounded, color: AppColors.primary, size: 32),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Aucune invitation envoyée',
                    style: TextStyle(color: AppColors.grey600, fontFamily: 'Nunito', fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Appuyez sur + Inviter pour envoyer\nune invitation par email.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.grey400, fontFamily: 'Nunito', fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(adminInvitationsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
              itemCount: invitations.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _InvitationCard(
                invitation: invitations[index],
                onDelete: () => _confirmDeleteInvitation(context, invitations[index]),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteInvitation(BuildContext context, InvitationModel invitation) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Supprimer l\'invitation ?',
            style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w700)),
        content: Text('L\'invitation pour ${invitation.email} sera supprimée.',
            style: const TextStyle(fontFamily: 'Nunito')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ApiClient().adminDeleteInvitation(invitation.id);
      ref.invalidate(adminInvitationsProvider);
      if (mounted) _showSuccess(this.context, 'Invitation supprimée.');
    } catch (e) {
      if (mounted) _showError(this.context, parseDioError(e));
    }
  }

  void _showInviteDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => _InviteDialog(
        formKey: formKey,
        ctrl: ctrl,
        onConfirm: (email) => _sendInvitation(context, dialogCtx, email),
        onCancel: () => Navigator.pop(dialogCtx),
      ),
    );
  }

  Future<void> _sendInvitation(BuildContext pageContext, BuildContext dialogCtx, String email) async {
    setState(() => _isSending = true);
    try {
      await ApiClient().adminCreateInvitation(email);
      ref.invalidate(adminInvitationsProvider);
      if (dialogCtx.mounted) Navigator.pop(dialogCtx);
      if (pageContext.mounted) _showSuccess(pageContext, 'Invitation envoyée à $email');
    } on DioException catch (e) {
      if (dialogCtx.mounted) _showError(dialogCtx, parseDioError(e));
    } catch (e) {
      if (dialogCtx.mounted) _showError(dialogCtx, 'Erreur inattendue. Réessayez.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }
}

// ─── Dialog invitation ────────────────────────────────────────
class _InviteDialog extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController ctrl;
  final Future<void> Function(String email) onConfirm;
  final VoidCallback onCancel;

  const _InviteDialog({
    required this.formKey,
    required this.ctrl,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  bool _loading = false;
  String? _inlineError;

  Future<void> _submit() async {
    setState(() => _inlineError = null);
    if (!widget.formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await widget.onConfirm(widget.ctrl.text.trim());
    } on DioException catch (e) {
      if (mounted) setState(() { _loading = false; _inlineError = parseDioError(e); });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _inlineError = 'Erreur inattendue.'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Inviter un utilisateur',
          style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w800)),
      content: Form(
        key: widget.formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Un email d\'invitation sera envoyé à cette adresse.',
              style: TextStyle(color: AppColors.grey500, fontSize: 13, fontFamily: 'Nunito'),
            ),
            const SizedBox(height: 16),
            if (_inlineError != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_inlineError!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12, fontFamily: 'Nunito'))),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: widget.ctrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              enabled: !_loading,
              decoration: const InputDecoration(
                hintText: 'adresse@email.com',
                prefixIcon: Icon(Icons.email_outlined, color: AppColors.grey400, size: 20),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email requis';
                if (!v.trim().contains('@') || !v.trim().contains('.')) return 'Email invalide';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _loading ? null : widget.onCancel, child: const Text('Annuler')),
        ElevatedButton.icon(
          icon: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.send_rounded, size: 16),
          label: Text(_loading ? 'Envoi...' : 'Envoyer'),
          onPressed: _loading ? null : _submit,
        ),
      ],
    );
  }
}

// ─── Invitation Card ──────────────────────────────────────────
class _InvitationCard extends StatelessWidget {
  final InvitationModel invitation;
  final VoidCallback onDelete;

  const _InvitationCard({required this.invitation, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final statusColor = invitation.isUsed
        ? AppColors.primary
        : invitation.isExpired ? AppColors.error : AppColors.warning;
    final statusLabel = invitation.isUsed ? 'Compte créé' : invitation.isExpired ? 'Expirée' : 'En attente';
    final statusIcon = invitation.isUsed
        ? Icons.check_circle_rounded
        : invitation.isExpired ? Icons.timer_off_rounded : Icons.schedule_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: invitation.isValid ? AppColors.grey200 : AppColors.grey100),
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: invitation.isUsed
                  ? AppColors.primarySurface
                  : invitation.isExpired ? const Color(0xFFFEF2F2) : const Color(0xFFFFFBEB),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.email_outlined,
                color: invitation.isValid ? AppColors.warning : invitation.isUsed ? AppColors.primary : AppColors.error,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(invitation.email,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, fontFamily: 'Nunito',
                      color: invitation.isValid ? AppColors.grey800 : AppColors.grey400,
                    )),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(statusIcon, size: 12, color: statusColor),
                  const SizedBox(width: 4),
                  Text(statusLabel,
                      style: TextStyle(fontSize: 12, fontFamily: 'Nunito', fontWeight: FontWeight.w600, color: statusColor)),
                  if (!invitation.isUsed) ...[
                    const SizedBox(width: 8),
                    Text('· expire ${_formatDate(invitation.expiresAt)}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'Nunito', color: AppColors.grey400)),
                  ],
                ]),
                if (invitation.invitedBy != null) ...[
                  const SizedBox(height: 2),
                  Text('Invité par ${invitation.invitedBy!.fullName}',
                      style: const TextStyle(fontSize: 11, fontFamily: 'Nunito', color: AppColors.grey400)),
                ],
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

  String _formatDate(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'expiré';
    if (diff.inHours < 24) return 'dans ${diff.inHours}h';
    return 'dans ${diff.inDays}j';
  }
}

// ─── Widgets utilitaires ──────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 40),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.grey500, fontFamily: 'Nunito')),
            const SizedBox(height: 12),
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

void _showSuccess(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontFamily: 'Nunito'))),
    ]),
    backgroundColor: AppColors.primary,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Row(children: [
      const Icon(Icons.error_outline, color: Colors.white, size: 18),
      const SizedBox(width: 8),
      Expanded(child: Text(message, style: const TextStyle(fontFamily: 'Nunito'))),
    ]),
    backgroundColor: AppColors.error,
    behavior: SnackBarBehavior.floating,
    margin: const EdgeInsets.all(16),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));
}