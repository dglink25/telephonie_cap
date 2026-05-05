// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/material.dart';

void checkAndRequestWebPermission(BuildContext context) {
  try {
    final permission = js.context['Notification']?['permission']?.toString();
    if (permission == 'default') {
      js.context['Notification'].callMethod('requestPermission', []);
    }
  } catch (e) {
    debugPrint('[Web] Notification permission error: $e');
  }
}
