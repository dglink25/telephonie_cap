import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class MessagesNotifier
    extends StateNotifier<AsyncValue<List<MessageModel>>> {
  final int conversationId;
  final ApiClient _api = ApiClient();
  int _currentPage = 1;
  bool _hasMore = true;

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
      final list = (data['data'] as List)
          .map((e) => MessageModel.fromJson(e))
          .toList()
          .reversed
          .toList();
      _hasMore = data['current_page'] < data['last_page'];

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
    if (!_hasMore) return;
    _currentPage++;
    await load();
  }

  void addMessage(MessageModel message) {
    state.whenData((msgs) => state = AsyncData([...msgs, message]));
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
      final msg = MessageModel.fromJson(response.data);
      addMessage(msg);
      return true;
    } catch (_) {
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