import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:ui' show Color;
import '../constants/app_constants.dart';

// Conditional import pour dart:js (web uniquement)
import 'notification_service_web.dart'
    if (dart.library.io) 'notification_service_stub.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  Function(Map<String, dynamic> data)? onMessageTap;
  Function(Map<String, dynamic> data)? onIncomingCallNotification;

  bool _initialized = false;

  // ── Initialisation ──────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (kIsWeb) {
      requestWebPermission();
      return;
    }

    await _setupAndroidChannels();

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
  }

  // ── Canaux Android ────────────────────────────────────────────────────────
  Future<void> _setupAndroidChannels() async {
    final plugin = _localNotifs.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (plugin == null) return;

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

    await plugin.createNotificationChannel(
      const AndroidNotificationChannel(
        'calls',
        'Appels entrants',
        description: "Notifications d'appels entrants",
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        showBadge: true,
        enableLights: true,
        ledColor: Color(0xFF1B7F4A),
      ),
    );
  }

  // ── Tap notification ──────────────────────────────────────────────────────
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
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

  // ── Notification message ─────────────────────────────────────────────────
  Future<void> showMessageNotificationInApp({
    required String senderName,
    required String body,
    required int conversationId,
    required int messageId,
  }) async {
    if (kIsWeb) {
      showWebNotification(
        title: senderName,
        body: body,
        data: {
          'type':            'new_message',
          'conversation_id': conversationId.toString(),
          'message_id':      messageId.toString(),
        },
      );
      return;
    }

    await _showMessageNotification(
      title: senderName,
      body: body,
      data: {
        'type':            'new_message',
        'conversation_id': conversationId.toString(),
        'message_id':      messageId.toString(),
      },
    );
  }

  // ── Notification appel entrant ───────────────────────────────────────────
  Future<void> showIncomingCallNotificationInApp({
    required String callerName,
    required String callType,
    required int callId,
    required int conversationId,
  }) async {
    if (kIsWeb) {
      showWebNotification(
        title: callerName,
        body: callType == 'video' ? '📹 Appel vidéo entrant' : '📞 Appel audio entrant',
        data: {
          'type':            'incoming_call',
          'call_id':         callId.toString(),
          'conversation_id': conversationId.toString(),
          'call_type':       callType,
        },
      );
      return;
    }

    await _showCallNotification(
      callId:      callId.toString(),
      callerName:  callerName,
      callerPhone: '',
      callType:    callType,
      convId:      conversationId.toString(),
    );
  }

  // ── Affichage notification message (natif) ───────────────────────────────
  Future<void> _showMessageNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'messages',
      'Messages',
      importance: Importance.high,
      priority:   Priority.high,
      icon:       '@mipmap/ic_launcher',
      playSound:  true,
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

  // ── Affichage notification appel (natif) ─────────────────────────────────
  Future<void> _showCallNotification({
    required String callId,
    required String callerName,
    required String callerPhone,
    required String callType,
    required String convId,
  }) async {
    final callTypeLabel = callType == 'video' ? '📹 Appel vidéo' : '📞 Appel audio';

    final payload = jsonEncode({
      'type':            'incoming_call',
      'call_id':         callId,
      'conversation_id': convId,
      'caller_name':     callerName,
      'caller_phone':    callerPhone,
      'call_type':       callType,
    });

    final androidDetails = AndroidNotificationDetails(
      'calls',
      'Appels entrants',
      channelDescription: "Notifications d'appels entrants",
      importance:    Importance.max,
      priority:      Priority.max,
      fullScreenIntent: true,
      ongoing:       true,
      autoCancel:    false,
      icon:          '@mipmap/ic_launcher',
      playSound:     true,
      enableVibration: true,
      enableLights:  true,
      ledColor:      const Color(0xFF1B7F4A),
      ledOnMs:       500,
      ledOffMs:      500,
      ticker:        '$callerName appelle',
      category:      AndroidNotificationCategory.call,
      visibility:    NotificationVisibility.public,
      actions: [
        const AndroidNotificationAction(
          'reject_call',
          'Refuser',
          cancelNotification: true,
          showsUserInterface: false,
          inputs: [],
        ),
        const AndroidNotificationAction(
          'answer_call',
          'Répondre',
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
    if (kIsWeb) return;
    await _localNotifs.cancel(callId);
  }

  Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _localNotifs.cancelAll();
  }
}
