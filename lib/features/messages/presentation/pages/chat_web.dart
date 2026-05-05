// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

Future<void> downloadFileImpl(
  String url,
  String fileName,
  String? authToken,
) async {
  try {
    final dio = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: authToken != null ? {'Authorization': 'Bearer $authToken'} : {},
      ),
    );
    final blob    = html.Blob([response.data]);
    final blobUrl = html.Url.createObjectUrl(blob);
    html.AnchorElement(href: blobUrl)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(blobUrl);
  } catch (e) {
    debugPrint('[Download] Web error: $e');
  }
}
