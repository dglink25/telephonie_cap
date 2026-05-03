class AppConstants {
  AppConstants._();


  static const String _serverIp = '10.234.148.159';

  static const String baseUrl        = 'http://$_serverIp:8000/api';
  static const String storageBaseUrl = 'http://$_serverIp:8000';
  static const String storageUrl     = '$storageBaseUrl/storage';

  // ── Laravel Reverb ─────────────────────────────────────────────────────────
  static const String reverbHost   = _serverIp;
  static const int    reverbPort   = 8080;
  static const String reverbScheme = 'http';
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