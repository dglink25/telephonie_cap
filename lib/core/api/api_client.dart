import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

class ApiClient {
  late final Dio _dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConstants.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _storage.read(key: AppConstants.tokenKey);
          if (token != null) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) {
          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  // ─── Auth ─────────────────────────────────────────────────
  Future<Response> login(String email, String password) async {
    return _dio.post('/login', data: {'email': email, 'password': password});
  }

  Future<Response> logout() async => _dio.post('/logout');

  Future<Response> me() async => _dio.get('/me');

  Future<Response> checkInvitation(String token) async =>
      _dio.get('/invitations/check/$token');

  Future<Response> completeProfile(String token, String fullName, String password, String passwordConfirmation) async {
    return _dio.post('/invitations/complete/$token', data: {
      'full_name': fullName,
      'password': password,
      'password_confirmation': passwordConfirmation,
    });
  }

  // ─── Conversations ────────────────────────────────────────
  Future<Response> getConversations() async => _dio.get('/conversations');

  Future<Response> startDirectConversation(int userId) async =>
      _dio.post('/conversations/direct', data: {'user_id': userId});

  Future<Response> getConversation(int id) async => _dio.get('/conversations/$id');

  Future<Response> markAsRead(int conversationId) async =>
      _dio.post('/conversations/$conversationId/read');

  // ─── Messages ────────────────────────────────────────────
  Future<Response> getMessages(int conversationId, {int page = 1}) async =>
      _dio.get('/conversations/$conversationId/messages', queryParameters: {'page': page});

  Future<Response> sendMessage(int conversationId, {
    String? body,
    required String type,
    dynamic file,
  }) async {
    final formData = FormData.fromMap({
      if (body != null) 'body': body,
      'type': type,
      if (file != null) 'file': file,
    });
    return _dio.post('/conversations/$conversationId/messages', data: formData);
  }

  Future<Response> sendTyping(int conversationId, bool isTyping) async =>
      _dio.post('/conversations/$conversationId/typing', data: {'is_typing': isTyping});

  Future<Response> deleteMessage(int messageId) async =>
      _dio.delete('/messages/$messageId');

  // ─── Groups ──────────────────────────────────────────────
  Future<Response> getGroups() async => _dio.get('/groups');

  Future<Response> createGroup(String name, {String? description, List<int>? memberIds}) async =>
      _dio.post('/groups', data: {
        'name': name,
        if (description != null) 'description': description,
        if (memberIds != null) 'member_ids': memberIds,
      });

  Future<Response> getGroup(int id) async => _dio.get('/groups/$id');

  Future<Response> updateGroup(int id, {String? name, String? description}) async =>
      _dio.put('/groups/$id', data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      });

  Future<Response> deleteGroup(int id) async => _dio.delete('/groups/$id');

  Future<Response> addMember(int groupId, int userId) async =>
      _dio.post('/groups/$groupId/members', data: {'user_id': userId});

  Future<Response> removeMember(int groupId, int userId) async =>
      _dio.delete('/groups/$groupId/members/$userId');

  Future<Response> leaveGroup(int groupId) async =>
      _dio.post('/groups/$groupId/leave');

  // ─── Calls ───────────────────────────────────────────────
  Future<Response> initiateCall(int conversationId, String type) async =>
      _dio.post('/conversations/$conversationId/calls', data: {'type': type});

  Future<Response> answerCall(int callId) async => _dio.post('/calls/$callId/answer');
  Future<Response> rejectCall(int callId) async => _dio.post('/calls/$callId/reject');
  Future<Response> endCall(int callId) async => _dio.post('/calls/$callId/end');

  Future<Response> sendSignal(int callId, String signalType, Map<String, dynamic> payload) async =>
      _dio.post('/calls/$callId/signal', data: {'signal_type': signalType, 'payload': payload});

  Future<Response> getCallHistory(int conversationId) async =>
      _dio.get('/conversations/$conversationId/calls');

  // ─── Notifications ───────────────────────────────────────
  Future<Response> getNotifications({int page = 1}) async =>
      _dio.get('/notifications', queryParameters: {'page': page});

  Future<Response> readNotification(String id) async =>
      _dio.post('/notifications/$id/read');

  Future<Response> readAllNotifications() async =>
      _dio.post('/notifications/read-all');

  Future<Response> getUnreadCount() async => _dio.get('/notifications/unread-count');

  Future<Response> updateFcmToken(String token) async =>
      _dio.post('/fcm-token', data: {'fcm_token': token});

  // ─── Admin ───────────────────────────────────────────────
  Future<Response> adminGetUsers({String? status}) async =>
      _dio.get('/admin/users', queryParameters: {if (status != null) 'status': status});

  Future<Response> adminGetUser(int id) async => _dio.get('/admin/users/$id');

  Future<Response> adminUpdateStatus(int id, String status) async =>
      _dio.patch('/admin/users/$id/status', data: {'status': status});

  Future<Response> adminDeleteUser(int id) async => _dio.delete('/admin/users/$id');

  Future<Response> adminGetInvitations() async => _dio.get('/admin/invitations');

  Future<Response> adminCreateInvitation(String email) async =>
      _dio.post('/admin/invitations', data: {'email': email});

  Future<Response> adminDeleteInvitation(int id) async =>
      _dio.delete('/admin/invitations/$id');
}