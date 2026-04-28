import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/app_constants.dart';
import 'auth_storage.dart'; // ← utilise le fallback web

class ApiClient {
  late final Dio _dio;

  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {'Accept': 'application/json'},
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // ✅ On passe par AuthStorage qui gère le fallback web/mobile
          final token = await AuthStorage.getToken();
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          if (options.data is! FormData) {
            options.headers['Content-Type'] = 'application/json';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) {
          debugPrint('[API] Error ${error.response?.statusCode}: ${error.message}');
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  // ─── Auth ─────────────────────────────────────────────────────
  Future<Response> login(String email, String password) =>
      _dio.post('/login', data: {'email': email, 'password': password});

  Future<Response> logout() => _dio.post('/logout');

  Future<Response> me() => _dio.get('/me');

  Future<Response> checkInvitation(String token) =>
      _dio.get('/invitations/check/$token');

  Future<Response> completeProfile(
    String token,
    String fullName,
    String password,
    String passwordConfirmation,
  ) =>
      _dio.post('/invitations/complete/$token', data: {
        'full_name': fullName,
        'password': password,
        'password_confirmation': passwordConfirmation,
      });

  // ─── Utilisateurs ─────────────────────────────────────────────
  Future<Response> searchUsers(String query) =>
      _dio.get('/users/search', queryParameters: {'q': query});

  // ─── Conversations ────────────────────────────────────────────
  Future<Response> getConversations() => _dio.get('/conversations');

  Future<Response> startDirectConversation(int userId) =>
      _dio.post('/conversations/direct', data: {'user_id': userId});

  Future<Response> getConversation(int id) => _dio.get('/conversations/$id');

  Future<Response> markAsRead(int conversationId) =>
      _dio.post('/conversations/$conversationId/read');

  // ─── Messages ─────────────────────────────────────────────────
  Future<Response> getMessages(int conversationId, {int page = 1}) =>
      _dio.get(
        '/conversations/$conversationId/messages',
        queryParameters: {'page': page},
      );

  Future<Response> sendMessage(
    int conversationId, {
    String? body,
    required String type,
    MultipartFile? file,
  }) async {
    final formData = FormData.fromMap({
      if (body != null && body.isNotEmpty) 'body': body,
      'type': type,
      if (file != null) 'file': file,
    });
    return _dio.post(
      '/conversations/$conversationId/messages',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
  }

  Future<Response> sendTyping(int conversationId, bool isTyping) =>
      _dio.post(
        '/conversations/$conversationId/typing',
        data: {'is_typing': isTyping},
      );

  Future<Response> deleteMessage(int messageId) =>
      _dio.delete('/messages/$messageId');

  // ─── Groupes ──────────────────────────────────────────────────
  Future<Response> getGroups() => _dio.get('/groups');

  Future<Response> createGroup(
    String name, {
    String? description,
    List<int>? memberIds,
  }) =>
      _dio.post('/groups', data: {
        'name': name,
        if (description != null) 'description': description,
        if (memberIds != null) 'member_ids': memberIds,
      });

  Future<Response> getGroup(int id) => _dio.get('/groups/$id');

  Future<Response> updateGroup(int id, {String? name, String? description}) =>
      _dio.put('/groups/$id', data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      });

  Future<Response> deleteGroup(int id) => _dio.delete('/groups/$id');

  Future<Response> addMember(int groupId, int userId) =>
      _dio.post('/groups/$groupId/members', data: {'user_id': userId});

  Future<Response> removeMember(int groupId, int userId) =>
      _dio.delete('/groups/$groupId/members/$userId');

  Future<Response> leaveGroup(int groupId) =>
      _dio.post('/groups/$groupId/leave');

  // ─── Appels ───────────────────────────────────────────────────
  Future<Response> initiateCall(int conversationId, String type) =>
      _dio.post('/conversations/$conversationId/calls', data: {'type': type});

  Future<Response> answerCall(int callId) =>
      _dio.post('/calls/$callId/answer');

  Future<Response> rejectCall(int callId) =>
      _dio.post('/calls/$callId/reject');

  Future<Response> endCall(int callId) => _dio.post('/calls/$callId/end');

  Future<Response> sendSignal(
    int callId,
    String signalType,
    Map<String, dynamic> payload,
  ) =>
      _dio.post('/calls/$callId/signal', data: {
        'signal_type': signalType,
        'payload': payload,
      });

  Future<Response> getCallHistory(int conversationId) =>
      _dio.get('/conversations/$conversationId/calls');

  // ─── Notifications ────────────────────────────────────────────
  Future<Response> getNotifications({int page = 1}) =>
      _dio.get('/notifications', queryParameters: {'page': page});

  Future<Response> readNotification(String id) =>
      _dio.post('/notifications/$id/read');

  Future<Response> readAllNotifications() =>
      _dio.post('/notifications/read-all');

  Future<Response> getUnreadCount() => _dio.get('/notifications/unread-count');

  Future<Response> updateFcmToken(String token) =>
      _dio.post('/fcm-token', data: {'fcm_token': token});

  // ─── Admin ────────────────────────────────────────────────────
  Future<Response> adminGetUsers({String? status, String? search, int page = 1}) =>
      _dio.get('/admin/users', queryParameters: {
        'page': page,
        if (status != null) 'status': status,
        if (search != null) 'search': search,
      });

  Future<Response> adminGetUser(int id) => _dio.get('/admin/users/$id');

  Future<Response> adminUpdateStatus(int id, String status) =>
      _dio.patch('/admin/users/$id/status', data: {'status': status});

  Future<Response> adminDeleteUser(int id) =>
      _dio.delete('/admin/users/$id');

  Future<Response> adminGetInvitations() => _dio.get('/admin/invitations');

  Future<Response> adminCreateInvitation(String email) =>
      _dio.post('/admin/invitations', data: {'email': email});

  Future<Response> adminDeleteInvitation(int id) =>
      _dio.delete('/admin/invitations/$id');
}