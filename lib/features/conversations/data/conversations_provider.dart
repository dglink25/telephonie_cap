import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class ConversationsNotifier extends StateNotifier<AsyncValue<List<ConversationModel>>> {
  final ApiClient _api = ApiClient();

  ConversationsNotifier() : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final response = await _api.getConversations();
      final list = (response.data as List)
          .map((e) => ConversationModel.fromJson(e))
          .toList();
      state = AsyncData(list);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<ConversationModel?> startDirect(int userId) async {
    try {
      final response = await _api.startDirectConversation(userId);
      final conv = ConversationModel.fromJson(response.data);
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
          return ConversationModel(
            id: c.id,
            type: c.type,
            groupId: c.groupId,
            group: c.group,
            participants: c.participants,
            lastMessage: c.lastMessage,
            lastMessageAt: c.lastMessageAt,
            lastReadAt: DateTime.now(),
          );
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

final conversationsProvider =
    StateNotifierProvider<ConversationsNotifier, AsyncValue<List<ConversationModel>>>(
  (ref) => ConversationsNotifier(),
);