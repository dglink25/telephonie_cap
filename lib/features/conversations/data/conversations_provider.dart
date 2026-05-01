import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';
import '../../../shared/models/user_model.dart';

// ─── Provider tous les utilisateurs actifs ────────────────────
final allUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final response = await ApiClient().dio.get('/users');
  final data = response.data;
  List<dynamic> list;
  if (data is Map && data.containsKey('data')) {
    list = data['data'] as List<dynamic>;
  } else if (data is List) {
    list = data;
  } else {
    list = [];
  }
  return list
      .map((e) => UserModel.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ─── Filtre actif ─────────────────────────────────────────────
enum ConversationFilter { all, unread, groups, favorites }

final conversationFilterProvider =
    StateProvider<ConversationFilter>((ref) => ConversationFilter.all);

// ─── Notifier ─────────────────────────────────────────────────
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

  Future<ConversationModel?> startDirect(int userId) async {
    try {
      final response = await _api.startDirectConversation(userId);
      final conv =
          ConversationModel.fromJson(response.data as Map<String, dynamic>);
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

  Future<void> toggleFavorite(int conversationId) async {
  try {
    await ApiClient().dio.post('/conversations/$conversationId/favorite');
    state.whenData((convs) {
      final updated = convs.map((c) {
        if (c.id == conversationId) {
          return c.copyWith(isFavorite: !(c.isFavorite ?? false));
        }
        return c;
      }).toList();
      // Cast explicite pour éviter l'erreur de type
      state = AsyncData(List<ConversationModel>.from(updated));
    });
  } catch (_) {}
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