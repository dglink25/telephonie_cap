import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class MessagesNotifier
    extends StateNotifier<AsyncValue<List<MessageModel>>> {
  final int conversationId;
  final ApiClient _api = ApiClient();
  int _currentPage = 1;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  MessagesNotifier(this.conversationId) : super(const AsyncLoading()) {
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _currentPage = 1;
      _hasMore = true;
      state = const AsyncLoading();
    }
    try {
      final response =
          await _api.getMessages(conversationId, page: _currentPage);
      final data = response.data as Map<String, dynamic>;
      final list = (data['data'] as List<dynamic>)
          .map((e) => MessageModel.fromJson(e as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
      _hasMore = (data['current_page'] as int) < (data['last_page'] as int);

      if (refresh || _currentPage == 1) {
        state = AsyncData(list);
      } else {
        state.whenData(
            (existing) => state = AsyncData([...list, ...existing]));
      }
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;
    _currentPage++;
    await load();
    _isLoadingMore = false;
  }

  void addMessage(MessageModel message) {
    state.whenData((msgs) {
      if (msgs.any((m) => m.id == message.id)) return;
      state = AsyncData([...msgs, message]);
    });
  }

  void removeMessage(int messageId) {
    state.whenData(
      (msgs) =>
          state = AsyncData(msgs.where((m) => m.id != messageId).toList()),
    );
  }

  Future<bool> sendText(String body) async {
    try {
      final response =
          await _api.sendMessage(conversationId, body: body, type: 'text');
      final msg =
          MessageModel.fromJson(response.data as Map<String, dynamic>);
      addMessage(msg);
      return true;
    } catch (e) {
      debugPrint('[Messages] sendText error: $e');
      return false;
    }
  }

  /// Limite par type de fichier
  static int _maxBytesForType(String messageType) {
    switch (messageType) {
      case 'video':
        return 25 * 1024 * 1024; // 25 MB pour vidéo
      case 'image':
        return 10 * 1024 * 1024; // 10 MB pour image
      case 'audio':
        return 16 * 1024 * 1024; // 16 MB pour audio
      default:
        return 50 * 1024 * 1024; // 50 MB pour docs
    }
  }

  /// Send file from disk path
  Future<bool> sendFile(
    String filePath,
    String messageType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        debugPrint('[Messages] sendFile: file does not exist at $filePath');
        return false;
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        debugPrint('[Messages] sendFile: file is empty');
        return false;
      }

      final maxBytes = _maxBytesForType(messageType);
      if (fileSize > maxBytes) {
        final maxMb = maxBytes ~/ (1024 * 1024);
        debugPrint(
            '[Messages] sendFile: file too large (${fileSize}B > ${maxBytes}B)');
        debugPrint('[Messages] Limite: $maxMb MB pour le type $messageType');
        return false;
      }

      final fileName = filePath.split('/').last;
      final mimeType =
          lookupMimeType(filePath) ?? _fallbackMime(messageType);

      debugPrint(
          '[Messages] Sending file: $fileName ($mimeType, ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

      final multipartFile = await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      );

      final response = await _api.sendMessage(
        conversationId,
        type: messageType,
        file: multipartFile,
        onSendProgress: onProgress,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final msg =
            MessageModel.fromJson(response.data as Map<String, dynamic>);
        addMessage(msg);
        debugPrint('[Messages] File sent successfully: ${msg.id}');
        return true;
      } else {
        debugPrint(
            '[Messages] sendFile: unexpected status ${response.statusCode}');
        debugPrint('[Messages] Response: ${response.data}');
        return false;
      }
    } on DioException catch (e) {
      debugPrint('[Messages] sendFile DioException: ${e.type}');
      debugPrint('[Messages] Status: ${e.response?.statusCode}');
      debugPrint('[Messages] Response data: ${e.response?.data}');
      debugPrint('[Messages] Message: ${e.message}');
      return false;
    } catch (e, stack) {
      debugPrint('[Messages] sendFile error: $e');
      debugPrint(stack.toString());
      return false;
    }
  }

  /// Send file from bytes (web or in-memory)
  Future<bool> sendFileBytes(
    Uint8List bytes,
    String fileName,
    String messageType,
    String mimeType, {
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      if (bytes.isEmpty) {
        debugPrint('[Messages] sendFileBytes: bytes are empty');
        return false;
      }

      final maxBytes = _maxBytesForType(messageType);
      if (bytes.length > maxBytes) {
        final maxMb = maxBytes ~/ (1024 * 1024);
        debugPrint(
            '[Messages] sendFileBytes: too large (${bytes.length}B). Limite: $maxMb MB pour $messageType');
        return false;
      }

      debugPrint(
          '[Messages] Sending bytes: $fileName ($mimeType, ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB)');

      final multipartFile = MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      );

      final response = await _api.sendMessage(
        conversationId,
        type: messageType,
        file: multipartFile,
        onSendProgress: onProgress,
      );

      if (response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300) {
        final msg =
            MessageModel.fromJson(response.data as Map<String, dynamic>);
        addMessage(msg);
        debugPrint('[Messages] Bytes sent successfully: ${msg.id}');
        return true;
      } else {
        debugPrint(
            '[Messages] sendFileBytes: status ${response.statusCode}');
        debugPrint('[Messages] Response: ${response.data}');
        return false;
      }
    } on DioException catch (e) {
      debugPrint('[Messages] sendFileBytes DioException: ${e.type}');
      debugPrint('[Messages] Status: ${e.response?.statusCode}');
      debugPrint('[Messages] Response: ${e.response?.data}');
      return false;
    } catch (e, stack) {
      debugPrint('[Messages] sendFileBytes error: $e');
      debugPrint(stack.toString());
      return false;
    }
  }

  Future<bool> deleteMessage(int messageId) async {
    try {
      await _api.deleteMessage(messageId);
      removeMessage(messageId);
      return true;
    } catch (e) {
      debugPrint('[Messages] deleteMessage error: $e');
      return false;
    }
  }

  Future<void> sendTyping(bool isTyping) async {
    try {
      await _api.sendTyping(conversationId, isTyping);
    } catch (_) {}
  }

  String _fallbackMime(String type) {
    switch (type) {
      case 'image':
        return 'image/jpeg';
      case 'video':
        return 'video/mp4';
      case 'audio':
        return 'audio/m4a';
      default:
        return 'application/octet-stream';
    }
  }
}

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    AsyncValue<List<MessageModel>>, int>(
  (ref, conversationId) => MessagesNotifier(conversationId),
);