class AppConstants {
  AppConstants._();

  static const String baseUrl        = 'http://192.168.10.126:8000/api';
  static const String storageBaseUrl = 'http://192.168.10.126:8000';
  static const String storageUrl     = '$storageBaseUrl/storage';

  // ── Laravel Reverb ─────────────────────────────────────────────────────────
  static const String reverbHost   = '192.168.10.126';
  static const int    reverbPort   = 8080;
  static const String reverbScheme = 'http';            // 'https' en production
  static const String reverbAppKey = 'xtsedffitwzc6vpwl7tz';

  static const String reverbCluster = 'mt1';

  // ── Auth ───────────────────────────────────────────────────────────────────
  static const String tokenKey = 'auth_token';
  static const String userKey  = 'auth_user';

  // ── Pagination ─────────────────────────────────────────────────────────────
  static const int messagesPerPage      = 50;
  static const int notificationsPerPage = 20;

  // ── Fichiers ───────────────────────────────────────────────────────────────
  static const int maxFileSizeMB = 50;

  // ── App ────────────────────────────────────────────────────────────────────
  static const String appName = 'Téléphonie CAP';
}