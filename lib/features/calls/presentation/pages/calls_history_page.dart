import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/data/auth_provider.dart';
import '../../../../core/services/call_service.dart';

// ─── Provider historique global ───────────────────────────────
final allCallsHistoryProvider = FutureProvider<List<CallModel>>((ref) async {
  try {
    // On récupère l'historique depuis toutes les conversations
    final convResponse = await ApiClient().getConversations();
    final convData = convResponse.data;
    List<dynamic> convList;
    if (convData is Map && convData.containsKey('data')) {
      convList = convData['data'] as List<dynamic>;
    } else if (convData is List) {
      convList = convData;
    } else {
      convList = [];
    }

    final List<CallModel> allCalls = [];

    for (final convJson in convList) {
      final convId = convJson['id'] as int?;
      if (convId == null) continue;
      try {
        final callsResponse = await ApiClient().getCallHistory(convId);
        final callsData = callsResponse.data;
        List<dynamic> callsList;
        if (callsData is Map && callsData.containsKey('data')) {
          callsList = callsData['data'] as List<dynamic>;
        } else if (callsData is List) {
          callsList = callsData;
        } else {
          callsList = [];
        }
        allCalls.addAll(
          callsList.map((e) => CallModel.fromJson(e as Map<String, dynamic>)),
        );
      } catch (_) {}
    }

    allCalls.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return allCalls;
  } catch (e) {
    return [];
  }
});

// ─── Filtre ───────────────────────────────────────────────────
enum CallFilter { all, outgoing, incoming, missed }

final callFilterProvider = StateProvider<CallFilter>((ref) => CallFilter.all);

// ─── Page principale ──────────────────────────────────────────
class CallsHistoryPage extends ConsumerWidget {
  const CallsHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callsAsync = ref.watch(allCallsHistoryProvider);
    final filter = ref.watch(callFilterProvider);
    final currentUser = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Appels'),
        backgroundColor: AppColors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(allCallsHistoryProvider),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _CallFilterBar(
            current: filter,
            onChanged: (f) =>
                ref.read(callFilterProvider.notifier).state = f,
          ),
        ),
      ),
      body: callsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (e, _) => _buildError(ref),
        data: (calls) {
          final filtered = _filterCalls(calls, filter, currentUser?.id ?? 0);
          if (filtered.isEmpty) return _buildEmpty(filter);

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () async => ref.invalidate(allCallsHistoryProvider),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filtered.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: AppColors.grey100, indent: 72),
              itemBuilder: (context, index) => _CallTile(
                call: filtered[index],
                currentUserId: currentUser?.id ?? 0,
                onTap: () => _handleCallTap(context, ref, filtered[index], currentUser),
              ),
            ),
          );
        },
      ),
    );
  }

  List<CallModel> _filterCalls(
      List<CallModel> calls, CallFilter filter, int currentUserId) {
    switch (filter) {
      case CallFilter.all:
        return calls;
      case CallFilter.outgoing:
        return calls.where((c) => c.callerId == currentUserId).toList();
      case CallFilter.incoming:
        
        return calls.where((c) => 
          c.callerId != currentUserId && 
          c.status != 'missed' && 
          c.status != 'rejected'
        ).toList();
      case CallFilter.missed:
        return calls
            .where((c) =>
                c.callerId != currentUserId && 
                (c.status == 'missed' || c.status == 'rejected'))
            .toList();
    }
  }

  void _handleCallTap(BuildContext context, WidgetRef ref, CallModel call, UserModel? currentUser) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _CallActionSheet(
        call: call, 
        currentUserId: currentUser?.id ?? 0,
        currentUser: currentUser,
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
          const Text('Impossible de charger les appels',
              style: TextStyle(color: AppColors.grey500, fontFamily: 'Nunito')),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => ref.invalidate(allCallsHistoryProvider),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(CallFilter filter) {
    final messages = {
      CallFilter.all: 'Aucun appel dans l\'historique',
      CallFilter.outgoing: 'Aucun appel sortant',
      CallFilter.incoming: 'Aucun appel entrant',
      CallFilter.missed: 'Aucun appel manqué',
    };

    final icons = {
      CallFilter.all: Icons.call_outlined,
      CallFilter.outgoing: Icons.call_made_rounded,
      CallFilter.incoming: Icons.call_received_rounded,
      CallFilter.missed: Icons.call_missed_rounded,
    };

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
            child: Icon(icons[filter]!, color: AppColors.primary, size: 36),
          ),
          const SizedBox(height: 16),
          Text(
            messages[filter]!,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.grey700,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }
}

class _CallActionSheet extends ConsumerWidget {
  final CallModel call;
  final int currentUserId;
  final UserModel? currentUser;

  const _CallActionSheet({
    required this.call, 
    required this.currentUserId,
    this.currentUser,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOutgoing = call.callerId == currentUserId;
    final contactName = isOutgoing
        ? (call.callee?.fullName ?? 'Correspondant')
        : (call.caller?.fullName ?? 'Inconnu');
    
    final callService = CallService();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                AvatarWidget(name: contactName, size: 48),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(contactName,
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            fontFamily: 'Nunito', color: AppColors.grey800,
                          )),
                      Text(timeago.format(call.createdAt, locale: 'fr'),
                          style: const TextStyle(
                            fontSize: 12, color: AppColors.grey400,
                            fontFamily: 'Nunito',
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(color: AppColors.grey100),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySurface, borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.call_rounded, color: AppColors.primary, size: 20),
            ),
            title: const Text('Appel audio',
                style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(context);
              
              // ✅ BUG FIX 2: Initier un vrai appel audio
              if (currentUser == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Utilisateur non authentifié')),
                  );
                }
                return;
              }
              
              if (callService.isBusy) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Un appel est déjà en cours')),
                  );
                }
                return;
              }
              
              // Afficher un indicateur de chargement
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => const _CallingDialog(),
              );
              
              try {
                final callData = await callService.initiateCall(
                  call.conversationId, 
                  'audio', 
                  currentUser!.id
                );
                
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop(); // Fermer le dialog
                  
                  if (callData != null) {
                    final newCall = CallModel.fromJson(callData);
                    // Naviguer vers la page d'appel
                    context.push('/calls/${newCall.id}', extra: newCall);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Impossible de démarrer l\'appel')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: ${e.toString()}')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.primarySurface, borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.videocam_rounded, color: AppColors.primary, size: 20),
            ),
            title: const Text('Appel vidéo',
                style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
            onTap: () async {
              Navigator.pop(context);
              
              // ✅ BUG FIX 2: Initier un vrai appel vidéo
              if (currentUser == null) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Utilisateur non authentifié')),
                  );
                }
                return;
              }
              
              if (callService.isBusy) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Un appel est déjà en cours')),
                  );
                }
                return;
              }
              
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (dialogContext) => const _CallingDialog(),
              );
              
              try {
                final callData = await callService.initiateCall(
                  call.conversationId, 
                  'video', 
                  currentUser!.id
                );
                
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                  
                  if (callData != null) {
                    final newCall = CallModel.fromJson(callData);
                    context.push('/calls/${newCall.id}', extra: newCall);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Impossible de démarrer l\'appel vidéo')),
                    );
                  }
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context, rootNavigator: true).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur: ${e.toString()}')),
                  );
                }
              }
            },
          ),
          ListTile(
            leading: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppColors.grey100, borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.grey500, size: 20),
            ),
            title: const Text('Envoyer un message',
                style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              // Celui-ci reste une navigation vers le chat (comportement attendu)
              context.push('/conversations/${call.conversationId}');
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// Dialog "En train d'appeler" (déjà existant dans ChatPage, à copier si nécessaire)
class _CallingDialog extends StatelessWidget {
  const _CallingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('Connexion en cours...',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey700)),
          ],
        ),
      ),
    );
  }
}

// ─── Barre de filtres ─────────────────────────────────────────
class _CallFilterBar extends StatelessWidget {
  final CallFilter current;
  final ValueChanged<CallFilter> onChanged;

  const _CallFilterBar({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final filters = [
      (CallFilter.all, 'Tous'),
      (CallFilter.outgoing, 'Sortants'),
      (CallFilter.incoming, 'Entrants'),
      (CallFilter.missed, 'Manqués'),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary : AppColors.grey100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.grey200,
                  ),
                ),
                child: Text(
                  item.$2,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Nunito',
                    color: isSelected ? Colors.white : AppColors.grey600,
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

// ─── Tuile d'appel ────────────────────────────────────────────
class _CallTile extends StatelessWidget {
  final CallModel call;
  final int currentUserId;
  final VoidCallback onTap;

  const _CallTile({
    required this.call,
    required this.currentUserId,
    required this.onTap,
  });

  bool get _isOutgoing => call.callerId == currentUserId;

  IconData get _statusIcon {
    if (_isOutgoing) return Icons.call_made_rounded;
    switch (call.status) {
      case 'missed':
        return Icons.call_missed_rounded;
      case 'rejected':
        return Icons.call_missed_rounded;
      case 'ended':
      case 'active':
        return Icons.call_received_rounded;
      default:
        return Icons.call_received_rounded;
    }
  }

  Color get _statusColor {
    if (_isOutgoing) {
      return call.status == 'ended' ? AppColors.primary : AppColors.grey400;
    }
    switch (call.status) {
      case 'missed':
      case 'rejected':
        return AppColors.error;
      case 'ended':
      case 'active':
        return AppColors.success;
      default:
        return AppColors.grey400;
    }
  }

  String get _statusLabel {
    if (_isOutgoing) {
      switch (call.status) {
        case 'ended':
          return 'Sortant';
        case 'rejected':
          return 'Refusé';
        case 'missed':
          return 'Sans réponse';
        default:
          return 'Sortant';
      }
    } else {
      switch (call.status) {
        case 'ended':
          return 'Entrant';
        case 'rejected':
          return 'Manqué';
        case 'missed':
          return 'Manqué';
        default:
          return 'Entrant';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final contactName = _isOutgoing
        ? (call.callee?.fullName ?? 'Correspondant')
        : (call.caller?.fullName ?? 'Inconnu');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            AvatarWidget(name: contactName, size: 52),
            const SizedBox(width: 14),
            // Infos
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contactName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: (_statusColor == AppColors.error && !_isOutgoing)
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: AppColors.grey800,
                      fontFamily: 'Nunito',
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(_statusIcon, size: 14, color: _statusColor),
                      const SizedBox(width: 4),
                      Text(
                        _statusLabel,
                        style: TextStyle(
                          fontSize: 13,
                          color: _statusColor,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Nunito',
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· ${call.isVideo ? 'Vidéo' : 'Audio'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.grey400,
                          fontFamily: 'Nunito',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Date + durée + rappel
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatDate(call.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.grey400,
                    fontFamily: 'Nunito',
                  ),
                ),
                if (call.duration != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    call.durationDisplay,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.grey500,
                      fontFamily: 'Nunito',
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Icon(
                  call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                  size: 20,
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return 'Hier';
    } else if (diff.inDays < 7) {
      const days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}/${dt.year % 100}';
    }
  }
}
