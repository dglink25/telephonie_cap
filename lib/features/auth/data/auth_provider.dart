import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/auth_storage.dart';
import '../../../core/websocket/websocket_service.dart';
import '../../../shared/models/user_model.dart';

// ─── Parseur d'erreurs centralisé ─────────────────────────────
String parseDioError(Object e) {
  if (e is DioException) {
    final response = e.response;

    if (response == null) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Le serveur met trop de temps à répondre. Vérifiez votre connexion.';
        case DioExceptionType.connectionError:
          return 'Impossible de joindre le serveur. Vérifiez votre connexion.';
        default:
          return 'Erreur réseau. Vérifiez votre connexion internet.';
      }
    }

    final data = response.data;
    final status = response.statusCode ?? 0;

    if (status == 401) return 'Session expirée. Veuillez vous reconnecter.';

    if (status == 403) {
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Accès refusé. Contactez un administrateur.';
    }

    if (status == 422) {
      if (data is Map) {
        final errors = data['errors'];
        if (errors is Map && errors.isNotEmpty) {
          final firstList = errors.values.firstOrNull;
          if (firstList is List && firstList.isNotEmpty) {
            return firstList.first.toString();
          }
        }
        if (data['message'] is String) return data['message'] as String;
      }
      return 'Données invalides. Vérifiez les champs saisis.';
    }

    if (status == 429) {
      return 'Trop de tentatives. Réessayez dans quelques minutes.';
    }

    if (status >= 500) {
      return 'Erreur serveur ($status). Réessayez dans quelques instants.';
    }

    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
  }

  return 'Une erreur inattendue est survenue.';
}

// ─── State ────────────────────────────────────────────────────
class AuthState {
  final UserModel? user;
  final bool isLoading;
  final String? error;
  final bool isAuthenticated;

  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    UserModel? user,
    bool? isLoading,
    String? error,
    bool? isAuthenticated,
  }) =>
      AuthState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        error: error,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      );
}

// ─── Notifier ────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api = ApiClient();

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final loggedIn = await AuthStorage.isLoggedIn();
    if (loggedIn) {
      final userData = await AuthStorage.getUser();
      final token = await AuthStorage.getToken();
      if (userData != null) {
        state = state.copyWith(
          user: UserModel.fromJson(userData),
          isAuthenticated: true,
        );
        if (token != null) {
          try {
            await WebSocketService().init(token);
          } catch (_) {}
        }
      }
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.login(email, password);
      final data = response.data as Map<String, dynamic>;
      final token = data['token'] as String;
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

      await AuthStorage.saveToken(token);
      await AuthStorage.saveUser(user.toJson());

      try {
        await WebSocketService().init(token);
      } catch (_) {}

      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: parseDioError(e),
      );
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await _api.logout();
    } catch (_) {}
    try {
      await WebSocketService().disconnect();
    } catch (_) {}
    await AuthStorage.clear();
    state = const AuthState();
  }

  Future<bool> completeProfile(
    String token,
    String fullName,
    String password,
    String confirmation,
  ) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response =
          await _api.completeProfile(token, fullName, password, confirmation);
      final data = response.data as Map<String, dynamic>;
      final apiToken = data['token'] as String;
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

      await AuthStorage.saveToken(apiToken);
      await AuthStorage.saveUser(user.toJson());

      try {
        await WebSocketService().init(apiToken);
      } catch (_) {}

      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: parseDioError(e),
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});