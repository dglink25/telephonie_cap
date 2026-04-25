import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../shared/models/models.dart';

class GroupsNotifier extends StateNotifier<AsyncValue<List<GroupModel>>> {
  final ApiClient _api = ApiClient();

  GroupsNotifier() : super(const AsyncLoading()) {
    load();
  }

  Future<void> load() async {
    state = const AsyncLoading();
    try {
      final response = await _api.getGroups();
      final list = (response.data as List)
          .map((e) => GroupModel.fromJson(e))
          .toList();
      state = AsyncData(list);
    } catch (e, s) {
      state = AsyncError(e, s);
    }
  }

  Future<GroupModel?> create(String name, {String? description, List<int>? memberIds}) async {
    try {
      final response = await _api.createGroup(name, description: description, memberIds: memberIds);
      final group = GroupModel.fromJson(response.data);
      state.whenData((groups) => state = AsyncData([...groups, group]));
      return group;
    } catch (_) {
      return null;
    }
  }

  Future<bool> leave(int groupId) async {
    try {
      await _api.leaveGroup(groupId);
      state.whenData(
        (groups) => state = AsyncData(groups.where((g) => g.id != groupId).toList()),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> delete(int groupId) async {
    try {
      await _api.deleteGroup(groupId);
      state.whenData(
        (groups) => state = AsyncData(groups.where((g) => g.id != groupId).toList()),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

final groupsProvider =
    StateNotifierProvider<GroupsNotifier, AsyncValue<List<GroupModel>>>(
  (ref) => GroupsNotifier(),
);