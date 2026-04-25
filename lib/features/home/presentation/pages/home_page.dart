import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/data/auth_provider.dart';
import '../../../notifications/data/notifications_provider.dart';

class HomePage extends ConsumerWidget {
  final Widget child;

  const HomePage({super.key, required this.child});

  int _locationToIndex(String location) {
    if (location.startsWith('/groups')) return 1;
    if (location.startsWith('/notifications')) return 2;
    if (location.startsWith('/admin')) return 3;
    return 0;
  }

  void _onNavTap(BuildContext context, int index, bool isAdmin) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/groups');
        break;
      case 2:
        context.go('/notifications');
        break;
      case 3:
        if (isAdmin) context.go('/admin');
        break;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.isAdmin ?? false;
    final location = GoRouterState.of(context).matchedLocation;
    final currentIndex = _locationToIndex(location);
    final isWide = MediaQuery.of(context).size.width > 768;

    if (isWide) {
      return _WebLayout(
        child: child,
        currentIndex: currentIndex,
        isAdmin: isAdmin,
        user: user,
        onNavTap: (i) => _onNavTap(context, i, isAdmin),
        onLogout: () => ref.read(authProvider.notifier).logout(),
      );
    }

    return _MobileLayout(
      child: child,
      currentIndex: currentIndex,
      isAdmin: isAdmin,
      onNavTap: (i) => _onNavTap(context, i, isAdmin),
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
                icon: Icon(Icons.group_outlined),
                selectedIcon: Icon(Icons.group_rounded),
                label: 'Groupes',
              ),
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
                  child: const Icon(Icons.notifications_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: unread > 0,
                  label: Text('$unread'),
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
                // ─── Sidebar ──────────────────────────────────
                Container(
                  width: 260,
                  decoration: const BoxDecoration(
                    color: AppColors.white,
                    border: Border(
                      right: BorderSide(color: AppColors.grey200),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Header logo
                      Container(
                        height: 64,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.grey200),
                          ),
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
                                Text(
                                  'Téléphonie',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.grey800,
                                    fontFamily: 'Nunito',
                                  ),
                                ),
                                Text(
                                  'CAP',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                    letterSpacing: 2,
                                    fontFamily: 'Nunito',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Nav items
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
                              onTap: () => onNavTap(0),
                            ),
                            _SidebarItem(
                              icon: Icons.group_outlined,
                              selectedIcon: Icons.group_rounded,
                              label: 'Groupes',
                              selected: currentIndex == 1,
                              onTap: () => onNavTap(1),
                            ),
                            _SidebarItem(
                              icon: Icons.notifications_outlined,
                              selectedIcon: Icons.notifications_rounded,
                              label: 'Notifications',
                              selected: currentIndex == 2,
                              onTap: () => onNavTap(2),
                              badge: unread > 0 ? unread : null,
                            ),
                            if (isAdmin)
                              _SidebarItem(
                                icon: Icons.admin_panel_settings_outlined,
                                selectedIcon:
                                    Icons.admin_panel_settings_rounded,
                                label: 'Administration',
                                selected: currentIndex == 3,
                                onTap: () => onNavTap(3),
                              ),
                          ],
                        ),
                      ),

                      // User footer
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          border: Border(
                            top: BorderSide(color: AppColors.grey200),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  user?.initials ?? '?',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'Nunito',
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.fullName ?? '',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.grey800,
                                      fontFamily: 'Nunito',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    user?.email ?? '',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.grey400,
                                      fontFamily: 'Nunito',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
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

                // ─── Main content ─────────────────────────────
                Expanded(child: child),
              ],
            ),
          ),

          // ─── Footer Web ───────────────────────────────────
          _WebFooter(),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final IconData selectedIcon;
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected ? selectedIcon : icon,
                  color: selected ? AppColors.primary : AppColors.grey500,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? AppColors.primary : AppColors.grey600,
                      fontFamily: 'Nunito',
                    ),
                  ),
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
                      '$badge',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Nunito',
                      ),
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

// ─── Footer Web ───────────────────────────────────────────────
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
              fontFamily: 'Nunito',
            ),
          ),
          const SizedBox(width: 16),
          const Text(
            '•',
            style: TextStyle(color: AppColors.grey300),
          ),
          const SizedBox(width: 16),
          Text(
            'Version 1.0.0',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.grey400,
              fontFamily: 'Nunito',
            ),
          ),
        ],
      ),
    );
  }
}