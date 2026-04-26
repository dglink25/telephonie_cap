import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';

/// Gère les notifications push FCM et les notifications locales.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  // Callbacks
  Function(Map<String, dynamic> data)? onMessageTap;
  Function(Map<String, dynamic> data)? onIncomingCallNotification;

  // ── Initialisation ─────────────────────────────────────────────
  Future<void> init() async {
    // Demander les permissions iOS
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // Pour les appels (nécessite entitlement Apple)
    );

    // Configurer les canaux Android
    await _setupAndroidChannels();

    // Initialiser flutter_local_notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifs.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Écouter les messages FCM en premier plan
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Écouter les taps sur notifications en arrière-plan
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Envoyer le token FCM au serveur
    await _registerFcmToken();

    // Écouter les changements de token
    _fcm.onTokenRefresh.listen((token) async {
      try {
        await ApiClient().updateFcmToken(token);
      } catch (_) {}
    });
  }

  // ── Canaux Android ─────────────────────────────────────────────
  Future<void> _setupAndroidChannels() async {
    const messagesChannel = AndroidNotificationChannel(
      'messages',
      'Messages',
      description: 'Notifications de nouveaux messages',
      importance: Importance.high,
      sound: RawResourceAndroidNotificationSound('default'),
      enableVibration: true,
    );

    const callsChannel = AndroidNotificationChannel(
      'calls',
      'Appels entrants',
      description: 'Notifications d\'appels entrants',
      importance: Importance.max,
      sound: RawResourceAndroidNotificationSound('call_ringtone'),
      enableVibration: true,
      playSound: true,
    );

    final plugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await plugin?.createNotificationChannel(messagesChannel);
    await plugin?.createNotificationChannel(callsChannel);
  }

  // ── Enregistrement du token FCM ────────────────────────────────
  Future<void> _registerFcmToken() async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        await ApiClient().updateFcmToken(token);
        debugPrint('[FCM] Token enregistré');
      }
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  // ── Message en premier plan ────────────────────────────────────
  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'];

    if (type == 'incoming_call') {
      // Appel entrant → notification haute priorité
      _showCallNotification(
        callId:      data['call_id'] ?? '',
        callerName:  data['caller_name'] ?? 'Appel entrant',
        callerPhone: data['caller_phone'] ?? '',
        callType:    data['call_type'] ?? 'audio',
        convId:      data['conversation_id'] ?? '',
      );
      onIncomingCallNotification?.call(data);
    } else if (type == 'new_message') {
      _showMessageNotification(
        title: message.notification?.title ?? data['sender_name'] ?? 'Message',
        body:  message.notification?.body  ?? data['body'] ?? '',
        data:  data,
      );
    }
  }

  // ── Tap sur notification ───────────────────────────────────────
  void _handleNotificationTap(RemoteMessage message) {
    onMessageTap?.call(message.data);
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        onMessageTap?.call(data);
      } catch (_) {}
    }
  }

  // ── Afficher notification de message ──────────────────────────
  Future<void> _showMessageNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'messages',
      'Messages',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifs.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode(data),
    );
  }

  // ── Afficher notification d'appel ─────────────────────────────
  Future<void> _showCallNotification({
    required String callId,
    required String callerName,
    required String callerPhone,
    required String callType,
    required String convId,
  }) async {
    final callTypeLabel = callType == 'video' ? 'Appel vidéo' : 'Appel audio';

    final androidDetails = AndroidNotificationDetails(
      'calls',
      'Appels entrants',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,       // Afficher en plein écran
      ongoing: true,                // Non-dismissible tant que l'appel est actif
      icon: '@mipmap/ic_launcher',
      sound: const RawResourceAndroidNotificationSound('call_ringtone'),
      actions: [
        const AndroidNotificationAction(
          'reject_call',
          'Refuser',
          cancelNotification: true,
          showsUserInterface: false,
        ),
        const AndroidNotificationAction(
          'answer_call',
          'Répondre',
          cancelNotification: true,
          showsUserInterface: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
      categoryIdentifier: 'CALL_INVITE',
    );

    await _localNotifs.show(
      int.tryParse(callId) ?? 0,
      callerName,
      '$callTypeLabel entrant...',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode({
        'type':            'incoming_call',
        'call_id':         callId,
        'conversation_id': convId,
        'caller_name':     callerName,
        'caller_phone':    callerPhone,
        'call_type':       callType,
      }),
    );
  }


  Future<void> cancelCallNotification(int callId) async {
    await _localNotifs.cancel(callId);
  }

  /// Annuler toutes les notifications.
  Future<void> cancelAll() async {
    await _localNotifs.cancelAll();
  }
}