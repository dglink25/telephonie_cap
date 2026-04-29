import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/data/auth_provider.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/complete_profile_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/conversations/presentation/pages/conversations_page.dart';
import '../../features/messages/presentation/pages/chat_page.dart';
import '../../features/groups/presentation/pages/groups_page.dart';
import '../../features/notifications/presentation/pages/notifications_page.dart';
import '../../features/admin/presentation/pages/admin_page.dart';
import '../../features/calls/presentation/pages/call_page.dart';
import '../../shared/models/models.dart';
import '../../shared/models/user_model.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/login',
    debugLogDiagnostics: false,

    redirect: (context, state) {
      final isLoggedIn = authState.isAuthenticated;
      final loc = state.matchedLocation;
      final isLoginRoute = loc == '/login';
      final isInviteRoute = loc.startsWith('/invite/');

      if (isInviteRoute) return null;
      if (!isLoggedIn && !isLoginRoute) return '/login';
      if (isLoggedIn && isLoginRoute) return '/home';
      return null;
    },

    routes: [
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginPage(),
      ),

      GoRoute(
        path: '/invite/:token',
        name: 'invite',
        builder: (context, state) => CompleteProfilePage(
          token: state.pathParameters['token']!,
        ),
      ),

      ShellRoute(
        builder: (context, state, child) => HomePage(child: child),
        routes: [
          GoRoute(
            path: '/home',
            name: 'home',
            builder: (context, state) => const ConversationsPage(),
          ),
          GoRoute(
            path: '/groups',
            name: 'groups',
            builder: (context, state) => const GroupsPage(),
          ),
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            builder: (context, state) => const NotificationsPage(),
          ),
          GoRoute(
            path: '/admin',
            name: 'admin',
            builder: (context, state) => const AdminPage(),
          ),
        ],
      ),

      GoRoute(
        path: '/conversations/:id',
        name: 'chat',
        builder: (context, state) => ChatPage(
          conversationId: int.parse(state.pathParameters['id']!),
        ),
      ),

      // CORRECTIF: extra est désormais un Map contenant 'call' et 'participants'
      GoRoute(
        path: '/calls/:id',
        name: 'call',
        builder: (context, state) {
          final callId =
              int.tryParse(state.pathParameters['id'] ?? '0') ?? 0;
          final extra = state.extra;

          CallModel call;
          List<UserModel> participants = [];

          if (extra is Map) {
            // Format depuis ChatPage: {'call': CallModel, 'participants': List<UserModel>}
            call = extra['call'] as CallModel? ??
                _placeholderCall(callId);
            participants =
                (extra['participants'] as List<UserModel>?) ?? [];
          } else if (extra is CallModel) {
            // Compatibilité ancien format
            call = extra;
          } else {
            call = _placeholderCall(callId);
          }

          return CallPage(call: call, participants: participants);
        },
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page introuvable : ${state.error}'),
      ),
    ),
  );
});

CallModel _placeholderCall(int callId) => CallModel(
      id: callId,
      conversationId: 0,
      callerId: 0,
      type: 'audio',
      status: 'pending',
      createdAt: DateTime.now(),
    );