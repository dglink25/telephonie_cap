import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

Future<void> downloadFileImpl(
  String url,
  String fileName,
  String? authToken,
) async {
  try {
    final dio      = Dio();
    final response = await dio.get<List<int>>(
      url,
      options: Options(
        responseType: ResponseType.bytes,
        headers: authToken != null ? {'Authorization': 'Bearer $authToken'} : {},
      ),
    );
    final directory = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final file      = File('${directory.path}/$fileName');
    await file.writeAsBytes(response.data!);
    debugPrint('[Download] Sauvegardé: ${file.path}');
  } catch (e) {
    debugPrint('[Download] Native error: $e');
  }
}
