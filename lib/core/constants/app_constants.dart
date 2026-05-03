import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;

class AppConstants {
  AppConstants._();



  static const String _serverIp = '10.217.221.159';

  static const String baseUrl        = 'http://$_serverIp:8000/api';
  static const String storageBaseUrl = 'http://$_serverIp:8000';
  static const String storageUrl     = '$storageBaseUrl/storage';

  // ── Laravel Reverb ─────────────────────────────────────────────────────────
  static const String reverbHost   = _serverIp;
  static const int    reverbPort   = 8080;
  static const String reverbScheme = 'http';

  static String get _serverIp {
    if (kIsWeb) {
      // Sur web, le serveur Laravel est sur le même host que la page
      return html.window.location.hostname ?? '192.168.100.195';
    }
    return const String.fromEnvironment('SERVER_IP', defaultValue: '192.168.100.195');
  }
  
  static String get baseUrl => 'http://$_serverIp:8000/api';
  static String get storageBaseUrl => 'http://$_serverIp:8000';
  static String get reverbHost => _serverIp;
  static const int reverbPort = 8080;

  static const String reverbAppKey = 'xtsedffitwzc6vpwl7tz';

  static String get storageUrl => 'http://$_serverIp:8000/storage'; 

  static const String reverbScheme = 'http';
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