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
      // BUG FIX: Avoid duplicate messages
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
      final msg = MessageModel.fromJson(
          response.data as Map<String, dynamic>);
      addMessage(msg);
      return true;
    } catch (_) {
      return false;
    }
  }

  // BUG FIX: Complete file sending with proper MIME type detection
  Future<bool> sendFile(String filePath, String messageType) async {
    try {
      final file = File(filePath);
      final fileName = filePath.split('/').last;
      final mimeType = lookupMimeType(filePath) ?? 'application/octet-stream';

      final multipartFile = await MultipartFile.fromFile(
        filePath,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      );

      final response = await _api.sendMessage(
        conversationId,
        type: messageType,
        file: multipartFile,
      );
      final msg = MessageModel.fromJson(
          response.data as Map<String, dynamic>);
      addMessage(msg);
      return true;
    } catch (e) {
      debugPrint('[Messages] sendFile error: $e');
      return false;
    }
  }

  // BUG FIX: Web file sending using bytes
  Future<bool> sendFileBytes(
    Uint8List bytes,
    String fileName,
    String messageType,
    String mimeType,
  ) async {
    try {
      final multipartFile = MultipartFile.fromBytes(
        bytes,
        filename: fileName,
        contentType: DioMediaType.parse(mimeType),
      );

      final response = await _api.sendMessage(
        conversationId,
        type: messageType,
        file: multipartFile,
      );
      final msg = MessageModel.fromJson(
          response.data as Map<String, dynamic>);
      addMessage(msg);
      return true;
    } catch (e) {
      debugPrint('[Messages] sendFileBytes error: $e');
      return false;
    }
  }

  Future<bool> deleteMessage(int messageId) async {
    try {
      await _api.deleteMessage(messageId);
      removeMessage(messageId);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> sendTyping(bool isTyping) async {
    try {
      await _api.sendTyping(conversationId, isTyping);
    } catch (_) {}
  }
}

final messagesProvider = StateNotifierProvider.family<MessagesNotifier,
    AsyncValue<List<MessageModel>>, int>(
  (ref, conversationId) => MessagesNotifier(conversationId),
);