import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class ConversationsNotifier
    extends StateNotifier<AsyncValue<List<ConversationModel>>> {
  final ApiClient _api = ApiClient();

  ConversationsNotifier() : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final response = await _api.getConversations();
      final data = response.data;
      List<dynamic> list;
      // BUG FIX: API may return paginated or plain list
      if (data is Map && data.containsKey('data')) {
        list = data['data'] as List<dynamic>;
      } else if (data is List) {
        list = data;
      } else {
        list = [];
      }
      final conversations = list
          .map((e) => ConversationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      state = AsyncData(conversations);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  // BUG FIX: Matches fixed ApiClient.startDirectConversation(int userId)
  Future<ConversationModel?> startDirect(int userId) async {
    try {
      final response = await _api.startDirectConversation(userId);
      final conv = ConversationModel.fromJson(
          response.data as Map<String, dynamic>);
      await load();
      return conv;
    } catch (_) {
      return null;
    }
  }

  void markRead(int conversationId) {
    state.whenData((convs) {
      final updated = convs.map((c) {
        if (c.id == conversationId) {
          return c.copyWith(lastReadAt: DateTime.now());
        }
        return c;
      }).toList();
      state = AsyncData(updated);
    });
  }

  void addOrUpdateConversation(ConversationModel conv) {
    state.whenData((convs) {
      final idx = convs.indexWhere((c) => c.id == conv.id);
      List<ConversationModel> updated;
      if (idx >= 0) {
        updated = [...convs];
        updated[idx] = conv;
      } else {
        updated = [conv, ...convs];
      }
      updated.sort((a, b) {
        final at = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
      state = AsyncData(updated);
    });
  }
}

final conversationsProvider = StateNotifierProvider<ConversationsNotifier,
    AsyncValue<List<ConversationModel>>>(
  (ref) => ConversationsNotifier(),
);