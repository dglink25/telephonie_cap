class AppConstants {
  AppConstants._();

  // ─── API REST ──────────────────────────────────────────────
  // BUG FIX: Le backend Laravel tourne sur le port 8000.
  // L'URL était 'http://192.168.100.201/api' (port 80 → WRONG)
  // Corrigé en 'http://192.168.100.201:8000/api' (port 8000 → OK)
  static const String baseUrl         = 'http://10.234.148.159:8000/api';
  static const String storageBaseUrl  = 'http://10.234.148.159:8000';
  static const String storageUrl      = '$storageBaseUrl/storage';

  // ─── Reverb WebSocket ──────────────────────────────────────
  // BUG FIX: Reverb écoute sur 127.0.0.1:8080 côté serveur.
  // Depuis le navigateur/appareil, il faut l'IP LAN : 192.168.100.201:8080
  static const String reverbHost      = '10.234.148.159';
  static const int    reverbPort      = 8080;
  static const String reverbScheme    = 'http';
  static const String reverbAppKey    = 'xtsedffitwzc6vpwl7tz';

  // ─── Storage Keys ──────────────────────────────────────────
  static const String tokenKey = 'auth_token';
  static const String userKey  = 'auth_user';

  // ─── Pagination ────────────────────────────────────────────
  static const int messagesPerPage       = 50;
  static const int notificationsPerPage  = 20;

  // ─── Upload ────────────────────────────────────────────────
  static const int maxFileSizeMB = 50;

  // ─── App ───────────────────────────────────────────────────
  static const String appName = 'Téléphonie CAP';
}