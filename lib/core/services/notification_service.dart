import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';
import 'dart:ui' show Color;


@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {

  debugPrint('[FCM Background] type=${message.data['type']} id=${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  Function(Map<String, dynamic> data)? onMessageTap;
  Function(Map<String, dynamic> data)? onIncomingCallNotification;

  bool _initialized = false;

  // ── Initialisation ─────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Handler background AVANT tout
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Permissions — demander TOUTES les permissions critiques
    final settings = await _fcm.requestPermission(
      alert: true,
      announcement: true,
      badge: true,
      carPlay: false,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

    // Présentation des notifications FCM en premier plan (iOS)
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Créer les canaux Android AVANT d'initialiser le plugin
    await _setupAndroidChannels();

    // Init plugin local notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifs.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    // Écoute messages FCM en premier plan
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Tap sur notification quand app en arrière-plan (pas tuée)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Notification initiale (app tuée, relancée depuis notif)
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      // Délai pour laisser l'app s'initialiser
      await Future.delayed(const Duration(milliseconds: 500));
      _handleNotificationTap(initialMessage);
    }

    await _registerFcmToken();

    _fcm.onTokenRefresh.listen((token) async {
      debugPrint('[FCM] Token refreshed');
      try {
        await ApiClient().updateFcmToken(token);
      } catch (_) {}
    });
  }

  // ── Canaux Android ─────────────────────────────────────────────
  Future<void> _setupAndroidChannels() async {
    final plugin = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (plugin == null) return;

    // Canal messages
    await plugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Notifications de nouveaux messages',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      ),
    );

    // Canal appels — importance MAX + fullScreenIntent pour sonner même en veille
    await plugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'calls',
        'Appels entrants',
        description: "Notifications d'appels entrants",
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
        // FIX: enableLights pour visibilité écran veille
        enableLights: true,
        ledColor: const Color(0xFF1B7F4A),
      ),
    );
  }

  // ── Enregistrement token FCM ───────────────────────────────────
  Future<void> _registerFcmToken() async {
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null && token.isNotEmpty) {
        await ApiClient().updateFcmToken(token);
        debugPrint('[FCM] Token enregistré: ${token.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  Future<void> refreshFcmToken() => _registerFcmToken();

  // ── Message FCM en premier plan ────────────────────────────────
  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String? ?? '';

    debugPrint('[FCM Foreground] type=$type data=$data');

    if (type == 'incoming_call') {
      // Déclencher la sonnerie + notification locale visuelle
      _showCallNotification(
        callId: data['call_id'] ?? '0',
        callerName: data['caller_name'] ?? 'Appel entrant',
        callerPhone: data['caller_phone'] ?? '',
        callType: data['call_type'] ?? 'audio',
        convId: data['conversation_id'] ?? '0',
      );
      // Notifier le CallService pour déclencher la sonnerie inApp
      onIncomingCallNotification?.call(data);
    } else if (type == 'new_message') {
      _showMessageNotification(
        title: message.notification?.title ??
            data['sender_name'] as String? ??
            'Nouveau message',
        body: message.notification?.body ?? data['body'] as String? ?? '',
        data: data,
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    onMessageTap?.call(message.data);
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;

      // FIX: gérer le tap "Répondre" vs tap normal
      if (response.actionId == 'answer_call') {
        onIncomingCallNotification?.call({...data, '_action': 'answer'});
      } else if (response.actionId == 'reject_call') {
        onIncomingCallNotification?.call({...data, '_action': 'reject'});
      } else {
        onMessageTap?.call(data);
      }
    } catch (e) {
      debugPrint('[Notif] Tap parse error: $e');
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(NotificationResponse response) {
    debugPrint('[Notif] Background tap: ${response.payload}');
  }

  // ── Notification locale message ──────────────────────────────
  Future<void> showMessageNotificationInApp({
    required String senderName,
    required String body,
    required int conversationId,
    required int messageId,
  }) async {
    if (kIsWeb) return;
    await _showMessageNotification(
      title: senderName,
      body: body,
      data: {
        'type': 'new_message',
        'conversation_id': conversationId.toString(),
        'message_id': messageId.toString(),
      },
    );
  }

  // ── Notification locale appel entrant ────────────────────────
  Future<void> showIncomingCallNotificationInApp({
    required String callerName,
    required String callType,
    required int callId,
    required int conversationId,
  }) async {
    if (kIsWeb) return;
    await _showCallNotification(
      callId: callId.toString(),
      callerName: callerName,
      callerPhone: '',
      callType: callType,
      convId: conversationId.toString(),
    );
  }

  // ── Afficher notification message ──────────────────────────────
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
      playSound: true,
      enableVibration: true,
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

  Future<void> _showCallNotification({
    required String callId,
    required String callerName,
    required String callerPhone,
    required String callType,
    required String convId,
  }) async {
    final callTypeLabel =
        callType == 'video' ? '📹 Appel vidéo' : '📞 Appel audio';

    final payload = jsonEncode({
      'type': 'incoming_call',
      'call_id': callId,
      'conversation_id': convId,
      'caller_name': callerName,
      'caller_phone': callerPhone,
      'call_type': callType,
    });

    final androidDetails = AndroidNotificationDetails(
      'calls',
      'Appels entrants',
      channelDescription: "Notifications d'appels entrants",
      importance: Importance.max,
      priority: Priority.max,
      // FIX CRITIQUE: fullScreenIntent pour réveiller l'écran
      fullScreenIntent: true,
      // FIX: ongoing=true pour ne pas être balayé accidentellement
      ongoing: true,
      autoCancel: false,
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFF1B7F4A),
      ledOnMs: 500,
      ledOffMs: 500,
      ticker: '$callerName appelle',
      // FIX: category CALL pour Android 13+
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      actions: [
        const AndroidNotificationAction(
          'reject_call',
          '❌ Refuser',
          cancelNotification: true,
          showsUserInterface: false,
          inputs: [],
        ),
        const AndroidNotificationAction(
          'answer_call',
          '✅ Répondre',
          cancelNotification: true,
          showsUserInterface: true,
          inputs: [],
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );

    await _localNotifs.show(
      int.tryParse(callId) ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      callerName,
      '$callTypeLabel entrant...',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  Future<void> cancelCallNotification(int callId) async {
    await _localNotifs.cancel(callId);
  }

  Future<void> cancelAll() async {
    await _localNotifs.cancelAll();
  }
}


class _Color {
  const _Color(int value);
}
