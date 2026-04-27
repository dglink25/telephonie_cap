class AppConstants {
  AppConstants._();

  static const String baseUrl        = 'http://192.168.10.117:8000/api';
  static const String storageBaseUrl = 'http://192.168.10.117:8000';
  static const String storageUrl     = '$storageBaseUrl/storage';


  static const String reverbHost   = '192.168.10.117';
  static const int    reverbPort   = 8080;
  static const String reverbScheme = 'http';   // 'https' 
  static const String reverbAppKey = 'xtsedffitwzc6vpwl7tz'; 

  static const String tokenKey = 'auth_token';
  static const String userKey  = 'auth_user';

  static const int messagesPerPage      = 50;
  static const int notificationsPerPage = 20;

  static const int maxFileSizeMB = 50;

  // ─── App ───────────────────────────────────────────────────────────────────
  static const String appName = 'Téléphonie CAP';
}
