import 'package:flutter/foundation.dart' show kIsWeb;

import 'app_constants_web.dart' if (dart.library.io) 'app_constants_native.dart';

class AppConstants {
  AppConstants._();

  /// IP du serveur — priorité : dart-define > auto-détection
  static String get _serverIp {
    // Sur Web : on utilise le même host que la page
    if (kIsWeb) {
      return getWebHostname();
    }
    // Sur mobile/desktop : dart-define ou IP par défaut
    const defined = String.fromEnvironment('SERVER_IP', defaultValue: '');
    if (defined.isNotEmpty) return defined;
    return '192.168.100.195';
  }

  static String get baseUrl       => 'http://$_serverIp:8000/api';
  static String get storageBaseUrl => 'http://$_serverIp:8000';
  static String get reverbHost     => _serverIp;
  static const int reverbPort      = 8080;
  static const String reverbAppKey = 'xtsedffitwzc6vpwl7tz';
  static String get storageUrl     => 'http://$_serverIp:8000/storage';

  static const String reverbScheme  = 'http';
  static const String reverbCluster = 'mt1';

  // ── Auth ────────────────────────────────────────────────────────────────
  static const String tokenKey = 'auth_token';
  static const String userKey  = 'auth_user';

  // ── Pagination ─────────────────────────────────────────────────────────
  static const int messagesPerPage      = 50;
  static const int notificationsPerPage = 20;

  // ── Fichiers ───────────────────────────────────────────────────────────
  static const int maxFileSizeMB = 50;

  // ── App ───────────────────────────────────────────────────────────────
  static const String appName = 'Téléphonie CAP';
}
