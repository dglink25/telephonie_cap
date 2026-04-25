
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/auth_storage.dart';
import '../../../shared/models/user_model.dart';

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
  }) => AuthState(
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
      if (userData != null) {
        state = state.copyWith(
          user: UserModel.fromJson(userData),
          isAuthenticated: true,
        );
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

      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } catch (e) {
      String message = 'Identifiants incorrects.';
      state = state.copyWith(isLoading: false, error: message);
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    try {
      await _api.logout();
    } catch (_) {}
    await AuthStorage.clear();
    state = const AuthState();
  }

  Future<bool> completeProfile(
      String token, String fullName, String password, String confirmation) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.completeProfile(token, fullName, password, confirmation);
      final data = response.data as Map<String, dynamic>;
      final apiToken = data['token'] as String;
      final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);

      await AuthStorage.saveToken(apiToken);
      await AuthStorage.saveUser(user.toJson());

      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Erreur lors de la création du compte.');
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

// ─── Provider ────────────────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});