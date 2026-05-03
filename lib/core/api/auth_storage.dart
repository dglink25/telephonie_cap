import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class AuthStorage {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ─── Lecture ──────────────────────────────────────────────────
  static Future<String?> _read(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    return _secureStorage.read(key: key);
  }

  // ─── Écriture ─────────────────────────────────────────────────
  static Future<void> _write(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } else {
      await _secureStorage.write(key: key, value: value);
    }
  }

  // ─── Suppression totale ───────────────────────────────────────
  static Future<void> _clear() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(AppConstants.tokenKey);
      await prefs.remove(AppConstants.userKey);
    } else {
      await _secureStorage.deleteAll();
    }
  }

  // ─── API publique ─────────────────────────────────────────────
  static Future<void> saveToken(String token) => _write(AppConstants.tokenKey, token);

  static Future<String?> getToken() => _read(AppConstants.tokenKey);

  static Future<void> saveUser(Map<String, dynamic> user) =>
      _write(AppConstants.userKey, jsonEncode(user));

  static Future<Map<String, dynamic>?> getUser() async {
    final raw = await _read(AppConstants.userKey);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  static Future<void> clear() => _clear();

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}