// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

void sendTokenToServiceWorker(String token) {
  try {
    final controller = js.context['navigator']['serviceWorker']['controller'];
    if (controller != null) {
      controller.callMethod('postMessage', [
        js.JsObject.jsify({'type': 'SET_AUTH_TOKEN', 'token': token})
      ]);
      debugPrint('[Auth] Token envoyé au Service Worker');
    }
  } catch (e) {
    debugPrint('[Auth] sendTokenToServiceWorker error: $e');
  }
}
