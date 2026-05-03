import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:js' as js;
import '../../../../core/services/call_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/app_modal.dart';
import '../../../auth/data/auth_provider.dart';
import '../../../conversations/data/conversations_provider.dart';
import '../../../notifications/data/notifications_provider.dart';
import '../../../notifications/data/notification_listener_provider.dart';

class HomePage extends ConsumerStatefulWidget {
  final Widget child;
  const HomePage({super.key, required this.child});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  final CallService _callService = CallService();
  IncomingCallInfo? _globalIncomingCall;
  bool _callbacksSetup = false;

  @override
  void initState() {
    super.initState();
    _setupGlobalCallListener();
    _setupNotificationCallbacks();
    _checkNotificationPermission();
  }

  // ─── Méthodes de gestion des permissions de notification Web ───────────────
  Future<String> _getWebNotifPermission() async {
    if (!kIsWeb) return 'denied';
    try {
      final permission = js.context.callMethod('Notification', ['permission']);
      return permission?.toString() ?? 'default';
    } catch (e) {
      debugPrint('[Notification] Erreur get permission: $e');
      return 'denied';
    }
  }

  Future<void> _requestWebNotifPermission() async {
    if (!kIsWeb) return;
    try {
      final permission = await js.context.callMethod('Notification', ['requestPermission']);
      if (permission == 'granted') {
        debugPrint('[Notification] Permission accordée');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Notifications activées'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[Notification] Erreur demande permission: $e');
    }
  }

  void _checkNotificationPermission() async {
    if (!kIsWeb) return;
    // Vérifier via JS interop
    final permission = await _getWebNotifPermission();
    if (permission == 'default') {
      // Montrer un banner non-intrusif
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showNotificationPermissionBanner();
      });
    }
  }

  void _showNotificationPermissionBanner() {
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        content: const Text(
          'Activez les notifications pour recevoir les appels entrants',
          style: TextStyle(fontFamily: 'Nunito'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _requestWebNotifPermission();
            },
            child: const Text('Activer'),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Plus tard'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = ref.read(currentUserProvider);
    if (user != null && !_callbacksSetup) {
      _callService.setCurrentUser(user.id);
      _setupGlobalCallListener();
      _callbacksSetup = true;
    }
  }

  void _setupGlobalCallListener() {
    if (_callbacksSetup) return;
    _callbacksSetup = true;

    final user = ref.read(currentUserProvider);
    if (user != null) {
      _callService.setCurrentUser(user.id);
    }

    _callService.onIncomingCall = (IncomingCallInfo info) {
      if (!mounted) return;
      setState(() => _globalIncomingCall = info);
    };

    _callService.onCallStatusChanged = (String status) {
      if (!mounted) return;
      if (status == 'ended' || status == 'rejected' || status == 'missed') {
        _callService.stopIncomingRingtone();
        setState(() => _globalIncomingCall = null);
        if (!_isOnCallPage()) {
          NotificationService().cancelAll();
        }
      }
    };

    _callService.onError = (String error) {
      if (!mounted) return;
      AppModal.error(context, title: 'Erreur d\'appel', message: error);
    };
  }

  bool _isOnCallPage() {
    try {
      final location = GoRouterState.of(context).matchedLocation;
      return location.startsWith('/calls/');
    } catch (_) {
      return false;
    }
  }

  void _setupNotificationCallbacks() {
    NotificationService().onIncomingCallNotification = (data) {
      if (!mounted) return;
      final action = data['_action'] as String?;

      if (action == 'answer') {
        final callId = int.tryParse(data['call_id']?.toString() ?? '0') ?? 0;
        final convId =
            int.tryParse(data['conversation_id']?.toString() ?? '0') ?? 0;
        if (callId > 0 && convId > 0) {
          _acceptCallFromNotification(
            callId: callId,
            conversationId: convId,
            callerName: data['caller_name'] ?? 'Appel entrant',
            callType: data['call_type'] ?? 'audio',
          );
        }
        return;
      }

      if (action == 'reject') {
        final callId = int.tryParse(data['call_id']?.toString() ?? '0') ?? 0;
        if (callId > 0) {
          _callService.rejectCall(callId);
          setState(() => _globalIncomingCall = null);
        }
        return;
      }

      final callId = int.tryParse(data['call_id']?.toString() ?? '0') ?? 0;
      final convId =
          int.tryParse(data['conversation_id']?.toString() ?? '0') ?? 0;
      if (callId > 0 && _globalIncomingCall == null) {
        final info = IncomingCallInfo(
          callId: callId,
          conversationId: convId,
          callerName: data['caller_name'] ?? 'Appel entrant',
          callType: data['call_type'] ?? 'audio',
          callerId: 0,
          raw: data,
        );
        setState(() => _globalIncomingCall = info);
        _callService.startIncomingRingtone();
      }
    };

    NotificationService().onMessageTap = (data) {
      if (!mounted) return;
      final convId = data['conversation_id'];
      if (convId != null) {
        context.push('/conversations/$convId');
      }
    };
  }

  void _listenToAllConversations() {
    final conversationsAsync = ref.read(conversationsProvider);
    conversationsAsync.whenData((conversations) {
      for (final conv in conversations) {
        _callService.listenGloballyToConversation(conv.id);
      }
    });
  }

  Future<void> _acceptGlobalCall(IncomingCallInfo info) async {
    setState(() => _globalIncomingCall = null);
    _callService.stopIncomingRingtone();
    NotificationService().cancelCallNotification(info.callId);

    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      AppModal.error(context,
          title: 'Erreur', message: 'Utilisateur non authentifié.');
      return;
    }

    final success = await _callService.answerCall(
      info.callId,
      info.conversationId,
      currentUser.id,
    );

    if (!mounted) return;

    if (success) {
      final conversationsAsync = ref.read(conversationsProvider);
      List<UserModel> participants = [];
      conversationsAsync.whenData((conversations) {
        final conv =
            conversations.where((c) => c.id == info.conversationId).firstOrNull;
        participants = conv?.participants ?? [];
      });

      UserModel? caller;
      final callerData = info.raw['caller'];
      if (callerData is Map) {
        try {
          caller = UserModel.fromJson(Map<String, dynamic>.from(callerData));
        } catch (_) {}
      }

      final call = CallModel(
        id: info.callId,
        conversationId: info.conversationId,
        callerId: info.callerId,
        caller: caller,
        type: info.callType,
        status: 'active',
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      context.push('/calls/${info.callId}', extra: {
        'call': call,
        'participants': participants,
      });
    } else {
      if (mounted) {
        AppModal.error(context,
            title: 'Appel indisponible',
            message:
                'L\'appel n\'est plus disponible. Il a peut-être été annulé.');
      }
    }
  }

  Future<void> _acceptCallFromNotification({
    required int callId,
    required int conversationId,
    required String callerName,
    required String callType,
  }) async {
    final info = IncomingCallInfo(
      callId: callId,
      conversationId: conversationId,
      callerName: callerName,
      callType: callType,
      callerId: 0,
      raw: {'caller_name': callerName, 'call_type': callType},
    );
    await _acceptGlobalCall(info);
  }

  Future<void> _rejectGlobalCall(IncomingCallInfo info) async {
    setState(() => _globalIncomingCall = null);
    _callService.stopIncomingRingtone();
    NotificationService().cancelCallNotification(info.callId);
    await _callService.rejectCall(info.callId);
  }

  int _locationToIndex(String location) {
    if (location.startsWith('/calls-history')) return 1;
    if (location.startsWith('/groups')) return 2;
    if (location.startsWith('/notifications')) return 3;
    if (location.startsWith('/admin')) return 4;
    return 0;
  }

  void _onNavTap(BuildContext context, int index, bool isAdmin) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/calls-history');
        break;
      case 2:
        context.go('/groups');
        break;
      case 3:
        context.go('/notifications');
        break;
      case 4:
        if (isAdmin) context.go('/admin');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.isAdmin ?? false;
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);
    final isWide = MediaQuery.of(context).size.width > 768;

    // Active l'écoute Reverb pour les notifications en temps réel
    ref.watch(notificationListenerProvider);

    // Écouter les nouvelles conversations pour les abonnements WebSocket appels
    ref.listen(conversationsProvider, (_, next) {
      next.whenData((conversations) {
        for (final conv in conversations) {
          _callService.listenGloballyToConversation(conv.id);
        }
      });
    });

    Widget layout;
    if (isWide) {
      layout = _WebLayout(
        child: widget.child,
        currentIndex: currentIndex,
        isAdmin: isAdmin,
        user: user,
        onNavTap: (i) => _onNavTap(context, i, isAdmin),
        onLogout: () => ref.read(authProvider.notifier).logout(),
      );
    } else {
      layout = _MobileLayout(
        child: widget.child,
        currentIndex: currentIndex,
        isAdmin: isAdmin,
        onNavTap: (i) => _onNavTap(context, i, isAdmin),
      );
    }

    return Stack(
      children: [
        layout,
        if (_globalIncomingCall != null)
          Positioned(
            top: 0, left: 0, right: 0,
            child: _GlobalIncomingCallBanner(
              info: _globalIncomingCall!,
              onAccept: () => _acceptGlobalCall(_globalIncomingCall!),
              onReject: () => _rejectGlobalCall(_globalIncomingCall!),
            ),
          ),
      ],
    );
  }
}

// ─── Bannière appel entrant GLOBALE ──────────────────────────
class _GlobalIncomingCallBanner extends StatefulWidget {
  final IncomingCallInfo info;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _GlobalIncomingCallBanner({
    required this.info,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_GlobalIncomingCallBanner> createState() =>
      _GlobalIncomingCallBannerState();
}

class _GlobalIncomingCallBannerState extends State<_GlobalIncomingCallBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  bool _accepting = false;
  bool _rejecting = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleAccept() async {
    if (_accepting || _rejecting) return;
    setState(() => _accepting = true);
    widget.onAccept();
  }

  Future<void> _handleReject() async {
    if (_accepting || _rejecting) return;
    setState(() => _rejecting = true);
    widget.onReject();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: Material(
          elevation: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(children: [
                _PulsingIcon(
                  icon: widget.info.callType == 'video'
                      ? Icons.videocam_rounded
                      : Icons.call_rounded,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.info.callerName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Nunito',
                            fontSize: 16),
                      ),
                      Text(
                        widget.info.callType == 'video'
                            ? '📹 Appel vidéo entrant...'
                            : '📞 Appel audio entrant...',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.85),
                            fontSize: 13,
                            fontFamily: 'Nunito'),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _rejecting ? null : _handleReject,
                  child: Container(
                    width: 48,
                    height: 48,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: _rejecting
                          ? AppColors.error.withOpacity(0.6)
                          : AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: _rejecting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.call_end_rounded,
                            color: Colors.white, size: 22),
                  ),
                ),
                GestureDetector(
                  onTap: _accepting ? null : _handleAccept,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: _accepting
                          ? AppColors.success.withOpacity(0.6)
                          : AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: _accepting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Icon(
                            widget.info.callType == 'video'
                                ? Icons.videocam_rounded
                                : Icons.call_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingIcon extends StatefulWidget {
  final IconData icon;
  const _PulsingIcon({required this.icon});

  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
        ),
        child: Icon(widget.icon, color: Colors.white, size: 24),
      ),
    );
  }
}

// ─── Layout Mobile ────────────────────────────────────────────
class _MobileLayout extends ConsumerWidget {
  final Widget child;
  final int currentIndex;
  final bool isAdmin;
  final ValueChanged<int> onNavTap;

  const _MobileLayout({
    required this.child,
    required this.currentIndex,
    required this.isAdmin,
    required this.onNavTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.grey200, width: 1)),
          boxShadow: [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: NavigationBar(
            selectedIndex: currentIndex,
            onDestinationSelected: onNavTap,
            backgroundColor: AppColors.white,
            elevation: 0,
            height: 64,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline_rounded),
                selectedIcon: Icon(Icons.chat_bubble_rounded),
                label: 'Messages',
              ),
              const NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call_rounded),
                label: 'Appels',
              ),
              const NavigationDestination(
                icon: Icon(Icons.group_outlined),
                selectedIcon: Icon(Icons.group_rounded),
                label: 'Groupes',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 9 ? '9+' : '$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text(unread > 9 ? '9+' : '$unread'),
                  child: const Icon(Icons.notifications_rounded),
                ),
                label: 'Notifs',
              ),
              if (isAdmin)
                const NavigationDestination(
                  icon: Icon(Icons.admin_panel_settings_outlined),
                  selectedIcon: Icon(Icons.admin_panel_settings_rounded),
                  label: 'Admin',
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Layout Web ───────────────────────────────────────────────
class _WebLayout extends ConsumerWidget {
  final Widget child;
  final int currentIndex;
  final bool isAdmin;
  final dynamic user;
  final ValueChanged<int> onNavTap;
  final VoidCallback onLogout;

  const _WebLayout({
    required this.child,
    required this.currentIndex,
    required this.isAdmin,
    required this.user,
    required this.onNavTap,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 260,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    border:
                        Border(right: BorderSide(color: AppColors.grey200)),
                  ),
                  child: Column(
                    children: [
                      Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: const BoxDecoration(
                          border: Border(
                              bottom:
                                  BorderSide(color: AppColors.grey200)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primarySurface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.phone_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Téléphonie',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.grey800,
                                        fontFamily: 'Nunito')),
                                Text('CAP',
                                    style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.primary,
                                        letterSpacing: 2,
                                        fontFamily: 'Nunito')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          children: [
                            _SidebarItem(
                                icon: Icons.chat_bubble_outline_rounded,
                                selectedIcon: Icons.chat_bubble_rounded,
                                label: 'Messages',
                                selected: currentIndex == 0,
                                onTap: () => onNavTap(0)),
                            _SidebarItem(
                                icon: Icons.call_outlined,
                                selectedIcon: Icons.call_rounded,
                                label: 'Appels',
                                selected: currentIndex == 1,
                                onTap: () => onNavTap(1)),
                            _SidebarItem(
                                icon: Icons.group_outlined,
                                selectedIcon: Icons.group_rounded,
                                label: 'Groupes',
                                selected: currentIndex == 2,
                                onTap: () => onNavTap(2)),
                            _SidebarItem(
                                icon: Icons.notifications_outlined,
                                selectedIcon: Icons.notifications_rounded,
                                label: 'Notifications',
                                selected: currentIndex == 3,
                                onTap: () => onNavTap(3),
                                badge: unread > 0 ? unread : null),
                            if (isAdmin)
                              _SidebarItem(
                                  icon:
                                      Icons.admin_panel_settings_outlined,
                                  selectedIcon:
                                      Icons.admin_panel_settings_rounded,
                                  label: 'Administration',
                                  selected: currentIndex == 4,
                                  onTap: () => onNavTap(4)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppColors.grey200)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle),
                              child: Center(
                                child: Text(user?.initials ?? '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        fontFamily: 'Nunito')),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(user?.fullName ?? '',
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.grey800,
                                          fontFamily: 'Nunito'),
                                      overflow: TextOverflow.ellipsis),
                                  Text(user?.email ?? '',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.grey400,
                                          fontFamily: 'Nunito'),
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout_rounded,
                                  color: AppColors.grey400, size: 18),
                              tooltip: 'Déconnexion',
                              onPressed: onLogout,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: child),
              ],
            ),
          ),
          _WebFooter(),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon, selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AppColors.primarySurface : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(selected ? selectedIcon : icon,
                    color:
                        selected ? AppColors.primary : AppColors.grey500,
                    size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? AppColors.primary
                              : AppColors.grey600,
                          fontFamily: 'Nunito')),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badge! > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Nunito'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WebFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '© ${DateTime.now().year} Téléphonie CAP — Tous droits réservés',
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.grey400,
                fontFamily: 'Nunito'),
          ),
          const SizedBox(width: 16),
          const Text('•', style: TextStyle(color: AppColors.grey300)),
          const SizedBox(width: 16),
          const Text('Version 1.0.0',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.grey400,
                  fontFamily: 'Nunito')),
        ],
      ),
    );
  }
}