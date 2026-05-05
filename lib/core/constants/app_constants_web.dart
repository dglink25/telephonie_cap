// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Récupère le hostname de la page web courante.
String getWebHostname() {
  final hostname = html.window.location.hostname;
  if (hostname == null || hostname.isEmpty) return '192.168.100.195';
  return hostname;
}
