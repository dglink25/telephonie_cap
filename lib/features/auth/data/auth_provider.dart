import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/auth_storage.dart';
import '../../../core/websocket/websocket_service.dart';
import '../../../shared/models/user_model.dart';

// ─── Parseur d'erreurs centralisé ─────────────────────────────────────────────
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

    // ✅ 401 = identifiants incorrects (Laravel Sanctum renvoie 401)
    if (status == 401) return 'Identifiants incorrects. Vérifiez votre email et mot de passe.';

    if (status == 403) {
      if (data is Map && data['message'] is String) {
        return data['message'] as String;
      }
      return 'Accès refusé. Contactez un administrateur.';
    }

    // ✅ 422 = validation Laravel (email format, champ vide, etc.)
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
      return 'Identifiants incorrects. Vérifiez les champs saisis.';
    }

    if (status == 429) return 'Trop de tentatives. Réessayez dans quelques minutes.';
    if (status >= 500) return 'Erreur serveur ($status). Réessayez dans quelques instants.';

    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }
  }


  debugPrint('╔══════════════════════════════════════════════');
  debugPrint('║ [AuthError] ERREUR INATTENDUE DÉTECTÉE');
  debugPrint('║ Type    : ${e.runtimeType}');
  debugPrint('║ Message : $e');
  debugPrint('╚══════════════════════════════════════════════');

  return 'Une erreur inattendue est survenue. Réessayez.';
}

// ─── Cast sécurisé Map ────────────────────────────────────────────────────────
Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException(
    'Réponse API invalide : attendu Map, reçu ${value.runtimeType} → $value',
  );
}

// ─── State ────────────────────────────────────────────────────────────────────
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

// ─── Notifier ─────────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  final ApiClient _api = ApiClient();

  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  Future<void> _init() async {
    final loggedIn = await AuthStorage.isLoggedIn();
    if (!loggedIn) return;

    final userData = await AuthStorage.getUser();
    final token = await AuthStorage.getToken();

    if (userData != null && token != null) {
      try {
        state = state.copyWith(
          user: UserModel.fromJson(_asMap(userData)),
          isAuthenticated: true,
        );
        await WebSocketService().init(token);
      } catch (e) {
        debugPrint('[Auth._init] Session corrompue : $e');
        await AuthStorage.clear();
        state = const AuthState();
      }
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _api.login(email, password);

      debugPrint('╔══════════════════════════════════════════════');
      debugPrint('║ [Auth.login] Réponse reçue');
      debugPrint('║ Status  : ${response.statusCode}');
      debugPrint('║ Type    : ${response.data.runtimeType}');
      debugPrint('║ Data    : ${response.data}');
      debugPrint('╚══════════════════════════════════════════════');

      final data = _asMap(response.data);

      final rawToken = data['token'];
      final rawUser  = data['user'];

      if (rawToken is! String || rawToken.isEmpty) {
        throw FormatException("Champ 'token' manquant ou invalide : $rawToken");
      }
      if (rawUser == null) {
        throw FormatException("Champ 'user' absent de la réponse");
      }

      final userMap = _asMap(rawUser);
      final user = UserModel.fromJson(userMap);

      await AuthStorage.saveToken(rawToken);
      await AuthStorage.saveUser(user.toJson());

      try {
        await WebSocketService().init(rawToken);
      } catch (wsError) {
        debugPrint('[Auth.login] WebSocket init ignoré : $wsError');
      }

      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } catch (e) {
      debugPrint('[Auth.login] Catch final : ${e.runtimeType} — $e');
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

      final data      = _asMap(response.data);
      final rawToken  = data['token'];
      final rawUser   = data['user'];

      if (rawToken is! String || rawToken.isEmpty) {
        throw FormatException("Champ 'token' manquant : $rawToken");
      }
      if (rawUser == null) {
        throw FormatException("Champ 'user' absent de la réponse");
      }

      final user = UserModel.fromJson(_asMap(rawUser));

      await AuthStorage.saveToken(rawToken);
      await AuthStorage.saveUser(user.toJson());

      try {
        await WebSocketService().init(rawToken);
      } catch (_) {}

      state = state.copyWith(
        user: user,
        isAuthenticated: true,
        isLoading: false,
      );
      return true;
    } catch (e) {
      debugPrint('[Auth.completeProfile] Catch : ${e.runtimeType} — $e');
      state = state.copyWith(
        isLoading: false,
        error: parseDioError(e),
      );
      return false;
    }
  }

  void clearError() => state = state.copyWith(error: null);
}

// ─── Providers ────────────────────────────────────────────────────────────────
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);

final currentUserProvider = Provider<UserModel?>((ref) {
  return ref.watch(authProvider).user;
});