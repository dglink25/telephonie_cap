class AppConstants {
  AppConstants._();

  // ─── API ───────────────────────────────────────────────────
  static const String baseUrl = 'http://127.0.0.1:8000/api';
  static const String storageUrl = 'http://127.0.0.1:8000/storage';

  // ─── Reverb WebSocket ──────────────────────────────────────
  static const String reverbHost = '127.0.0.1';
  static const int reverbPort = 8080;
  static const String reverbScheme = 'http';
  static const String reverbAppKey = 'xtsedffitwzc6vpwl7tz';

  // ─── Storage Keys ──────────────────────────────────────────
  static const String tokenKey = 'auth_token';
  static const String userKey = 'auth_user';
  
  //static const String userKey  = 'current_user';

  // ─── Pagination ────────────────────────────────────────────
  static const int messagesPerPage = 50;
  static const int notificationsPerPage = 20;

  // ─── Upload ────────────────────────────────────────────────
  static const int maxFileSizeMB = 50;

  // ─── App ───────────────────────────────────────────────────
  static const String appName = 'Téléphonie CAP';
}