import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_client.dart';

/// Top-level handler pour les messages FCM en arrière-plan
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('[FCM Background] ${message.messageId}');
}

class NotificationService {
  static final NotificationService _instance =
      NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  // Callbacks navigation
  Function(Map<String, dynamic> data)? onMessageTap;
  Function(Map<String, dynamic> data)? onIncomingCallNotification;

  bool _initialized = false;

  // ── Initialisation ─────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler);

    // Permissions
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true, // important pour sonneries d'appel
    );

    // Désactiver le throttling FCM en premier plan
    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await _setupAndroidChannels();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _localNotifs.initialize(
      const InitializationSettings(
          android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationTap,
    );

    // Messages FCM en premier plan
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Tap notification en arrière-plan
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Notification initiale
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    await _registerFcmToken();

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
      enableVibration: true,
      playSound: true,
    );

    // Canal appel avec importance MAX pour heads-up notification
    const callsChannel = AndroidNotificationChannel(
      'calls',
      'Appels entrants',
      description: "Notifications d'appels entrants",
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
      showBadge: true,
    );

    final plugin = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await plugin?.createNotificationChannel(messagesChannel);
    await plugin?.createNotificationChannel(callsChannel);
  }

  // ── Token FCM ──────────────────────────────────────────────────
  Future<void> _registerFcmToken() async {
    if (kIsWeb) return;
    try {
      final token = await _fcm.getToken();
      if (token != null) {
        await ApiClient().updateFcmToken(token);
        debugPrint('[FCM] Token enregistré: ${token.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('[FCM] Token registration error: $e');
    }
  }

  // ── Méthode publique pour forcer le re-register (après login) ──
  Future<void> refreshFcmToken() => _registerFcmToken();

  // ── Message en premier plan (FCM push) ─────────────────────────
  void _handleForegroundMessage(RemoteMessage message) {
    final data = message.data;
    final type = data['type'] as String?;

    debugPrint('[FCM Foreground] type=$type data=$data');

    if (type == 'incoming_call') {
      _showCallNotification(
        callId: data['call_id'] ?? '',
        callerName: data['caller_name'] ?? 'Appel entrant',
        callerPhone: data['caller_phone'] ?? '',
        callType: data['call_type'] ?? 'audio',
        convId: data['conversation_id'] ?? '',
      );
      onIncomingCallNotification?.call(data);
    } else if (type == 'new_message') {
      _showMessageNotification(
        title: message.notification?.title ??
            data['sender_name'] as String? ??
            'Message',
        body: message.notification?.body ??
            data['body'] as String? ??
            '',
        data: data,
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    onMessageTap?.call(message.data);
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data =
            jsonDecode(response.payload!) as Map<String, dynamic>;
        onMessageTap?.call(data);
      } catch (_) {}
    }
  }

  @pragma('vm:entry-point')
  static void _onBackgroundNotificationTap(
      NotificationResponse response) {
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

  // ── Afficher notification appel entrant ───────────────────────
  Future<void> _showCallNotification({
    required String callId,
    required String callerName,
    required String callerPhone,
    required String callType,
    required String convId,
  }) async {
    final callTypeLabel =
        callType == 'video' ? '📹 Appel vidéo' : '📞 Appel audio';

    final androidDetails = AndroidNotificationDetails(
      'calls',
      'Appels entrants',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      ongoing: false, // false pour permettre le swipe dismiss
      icon: '@mipmap/ic_launcher',
      playSound: true,
      enableVibration: true,
      ticker: '$callerName appelle',
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
    );

    await _localNotifs.show(
      int.tryParse(callId) ?? 0,
      callerName,
      '$callTypeLabel entrant...',
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: jsonEncode({
        'type': 'incoming_call',
        'call_id': callId,
        'conversation_id': convId,
        'caller_name': callerName,
        'caller_phone': callerPhone,
        'call_type': callType,
      }),
    );
  }

  Future<void> cancelCallNotification(int callId) async {
    await _localNotifs.cancel(callId);
  }

  Future<void> cancelAll() async {
    await _localNotifs.cancelAll();
  }
}