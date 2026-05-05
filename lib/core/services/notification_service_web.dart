// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'package:flutter/foundation.dart';

void requestWebPermission() {
  try {
    js.context.callMethod('eval', [
      "if(typeof Notification!=='undefined' && Notification.permission==='default'){ Notification.requestPermission(); }"
    ]);
  } catch (e) {
    debugPrint('[WebNotif] requestPermission error: \$e');
  }
}

void showWebNotification({
  required String title,
  required String body,
  required Map<String, dynamic> data,
}) {
  try {
    js.context.callMethod('_showWebNotification', [
      title,
      body,
      js.JsObject.jsify(data),
    ]);
  } catch (e) {
    debugPrint('[WebNotif] showWebNotification error: \$e');
  }
}
