import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/call_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/websocket/websocket_service.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/models/user_model.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/data/auth_provider.dart';
import '../../../conversations/data/conversations_provider.dart';
import '../../../calls/presentation/pages/call_page.dart';
import '../../data/messages_provider.dart';

class ChatPage extends ConsumerStatefulWidget {
  final int conversationId;
  const ChatPage({super.key, required this.conversationId});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _ws = WebSocketService();
  final _callService = CallService();
  final _imagePicker = ImagePicker();

  bool _isTyping = false;
  bool _otherTyping = false;
  String? _otherTypingName;
  ConversationModel? _conversation;
  Timer? _typingTimer;
  bool _isSendingFile = false;

  /// Appel entrant visible dans la page chat
  IncomingCallInfo? _pendingIncomingCall;

  @override
  void initState() {
    super.initState();
    _loadConversation();
    _markRead();
    _subscribeToWebSocket();
    _setupCallServiceCallbacks();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 100 &&
          _scrollController.position.maxScrollExtent > 0) {
        ref
            .read(messagesProvider(widget.conversationId).notifier)
            .loadMore();
      }
    });

    _textController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final typing = _textController.text.isNotEmpty;
    if (typing != _isTyping) {
      _isTyping = typing;
      _typingTimer?.cancel();
      ref
          .read(messagesProvider(widget.conversationId).notifier)
          .sendTyping(typing);
      if (typing) {
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (_isTyping) {
            _isTyping = false;
            ref
                .read(messagesProvider(widget.conversationId).notifier)
                .sendTyping(false);
          }
        });
      }
    }
  }

  // ── WebSocket ──────────────────────────────────────────────────
  void _subscribeToWebSocket() {
    final currentUser = ref.read(currentUserProvider);

    _ws.subscribeToConversation(widget.conversationId, events: {
      // Nouveau message
      'message.sent': (data) {
        if (!mounted) return;
        final msg = MessageModel.fromJson(data);
        if (msg.senderId != currentUser?.id) {
          ref
              .read(messagesProvider(widget.conversationId).notifier)
              .addMessage(msg);
          _markRead();
          _scrollToBottom();

          if (!kIsWeb) {
            NotificationService().showMessageNotificationInApp(
              senderName: msg.sender?.fullName ?? 'Message',
              body: msg.type == 'text' ? (msg.body ?? '') : '📎 ${msg.type}',
              conversationId: widget.conversationId,
              messageId: msg.id,
            );
          }
        }
        ref.read(conversationsProvider.notifier).load();
      },

      // Indicateur de frappe
      'user.typing': (data) {
        if (!mounted) return;
        final userId = data['user_id'] as int?;
        final isTyping = data['is_typing'] as bool? ?? false;
        final name = data['full_name'] as String? ?? '';

        if (userId != currentUser?.id) {
          setState(() {
            _otherTyping = isTyping;
            _otherTypingName = name;
          });
          if (isTyping) {
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted && _otherTyping) {
                setState(() => _otherTyping = false);
              }
            });
          }
        }
      },

      // Appel entrant — IMPORTANT: on filtre ici via callerId
      'call.initiated': (data) {
        if (!mounted) return;
        final callerId = data['caller_id'] as int?
            ?? (data['caller'] as Map<String, dynamic>?)?['id'] as int?;

        // Ignorer si c'est MOI qui lance l'appel (broadcast.toOthers() devrait
        // déjà le faire, mais on double-vérifie côté client)
        if (callerId == currentUser?.id) return;

        // Déjà en appel → rejeter automatiquement
        if (_callService.isBusy) {
          final callId = data['call_id'] as int? ?? data['id'] as int? ?? 0;
          _autoRejectBusy(callId);
          return;
        }

        final info = IncomingCallInfo(
          callId: data['call_id'] as int? ?? data['id'] as int? ?? 0,
          conversationId:
              data['conversation_id'] as int? ?? widget.conversationId,
          callerName: (data['caller'] as Map<String, dynamic>?)?['full_name']
                  as String? ??
              data['caller_name'] as String? ??
              'Appel entrant',
          callType: data['type'] as String? ?? 'audio',
          callerId: callerId ?? 0,
          raw: data,
        );

        setState(() => _pendingIncomingCall = info);

        if (!kIsWeb) {
          NotificationService().showIncomingCallNotificationInApp(
            callerName: info.callerName,
            callType: info.callType,
            callId: info.callId,
            conversationId: info.conversationId,
          );
        }
      },

      'call.status': (data) {
        if (!mounted) return;
        final status = data['status'] as String? ?? '';
        _callService.onCallStatusChanged?.call(status);
        if (status == 'ended' || status == 'rejected') {
          setState(() => _pendingIncomingCall = null);
          if (!kIsWeb) {
            NotificationService()
                .cancelCallNotification(data['call_id'] as int? ?? 0);
          }
        }
      },

      'call.signal': (data) {
        final senderId = data['sender_id'] as int?;
        if (senderId != currentUser?.id) {
          _callService.onCallSignalReceived(data);
        }
      },
    });
  }

  void _setupCallServiceCallbacks() {
    // Ne pas re-enregistrer onIncomingCall ici car on gère déjà 'call.initiated'
    // via WebSocket ci-dessus. Éviter la double bannière.
    _callService.onCallStatusChanged = (status) {
      if (!mounted) return;
      if (status == 'ended' || status == 'rejected') {
        setState(() => _pendingIncomingCall = null);
      }
    };
  }

  Future<void> _autoRejectBusy(int callId) async {
    try {
      await ApiClient().rejectCall(callId);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Appel entrant refusé — vous êtes déjà en communication',
              style: TextStyle(fontFamily: 'Nunito')),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _acceptIncomingCall(IncomingCallInfo info) async {
    setState(() => _pendingIncomingCall = null);
    if (!kIsWeb) NotificationService().cancelCallNotification(info.callId);
    final currentUser = ref.read(currentUserProvider);

    final success = await _callService.answerCall(
      info.callId,
      info.conversationId,
      currentUser?.id ?? 0,
    );

    if (success && mounted) {
      // Construire un CallModel avec le caller correct (celui qui a appelé)
      final callerData = info.raw['caller'] as Map<String, dynamic>?;
      UserModel? caller;
      if (callerData != null) {
        caller = UserModel.fromJson(callerData);
      }

      final call = CallModel(
        id: info.callId,
        conversationId: info.conversationId,
        callerId: info.callerId,
        caller: caller,
        type: info.callType,
        status: 'active',
        startedAt: DateTime.now(),
        createdAt: DateTime.now(),
      );

      context.push(
        '/calls/${info.callId}',
        extra: {
          'call': call,
          'participants': _conversation?.participants ?? [],
        },
      );
    }
  }

  Future<void> _rejectIncomingCall(IncomingCallInfo info) async {
    setState(() => _pendingIncomingCall = null);
    if (!kIsWeb) NotificationService().cancelCallNotification(info.callId);
    await _callService.rejectCall(info.callId);
  }

  Future<void> _loadConversation() async {
    try {
      final response =
          await ApiClient().getConversation(widget.conversationId);
      if (mounted) {
        setState(() {
          _conversation = ConversationModel.fromJson(
              response.data as Map<String, dynamic>);
        });
      }
    } catch (_) {}
  }

  Future<void> _markRead() async {
    try {
      await ApiClient().markAsRead(widget.conversationId);
      ref
          .read(conversationsProvider.notifier)
          .markRead(widget.conversationId);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    _isTyping = false;

    final success = await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendText(text);
    if (success) _scrollToBottom();
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        if (animated) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  // ── Media Picking ─────────────────────────────────────────────
  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachmentSheet(
        onPickImage: _pickImage,
        onPickFile: _pickFile,
        onPickVideo: _pickVideo,
      ),
    );
  }

  Future<void> _pickImage() async {
    Navigator.pop(context);
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform
            .pickFiles(type: FileType.image, withData: true);
        if (result?.files.first.bytes != null) {
          setState(() => _isSendingFile = true);
          await ref
              .read(messagesProvider(widget.conversationId).notifier)
              .sendFileBytes(result!.files.first.bytes!,
                  result.files.first.name, 'image', 'image/jpeg');
          setState(() => _isSendingFile = false);
          _scrollToBottom();
        }
        return;
      }
      final picked = await _imagePicker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1920,
          maxHeight: 1920);
      if (picked != null) {
        setState(() => _isSendingFile = true);
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .sendFile(picked.path, 'image');
        setState(() => _isSendingFile = false);
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _isSendingFile = false);
      _showError("Impossible de charger l'image.");
    }
  }

  Future<void> _pickVideo() async {
    Navigator.pop(context);
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform
            .pickFiles(type: FileType.video, withData: true);
        if (result?.files.first.bytes != null) {
          setState(() => _isSendingFile = true);
          await ref
              .read(messagesProvider(widget.conversationId).notifier)
              .sendFileBytes(result!.files.first.bytes!,
                  result.files.first.name, 'video', 'video/mp4');
          setState(() => _isSendingFile = false);
          _scrollToBottom();
        }
        return;
      }
      final picked =
          await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        setState(() => _isSendingFile = true);
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .sendFile(picked.path, 'video');
        setState(() => _isSendingFile = false);
        _scrollToBottom();
      }
    } catch (e) {
      setState(() => _isSendingFile = false);
      _showError('Impossible de charger la vidéo.');
    }
  }

  Future<void> _pickFile() async {
    Navigator.pop(context);
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: kIsWeb,
        withReadStream: !kIsWeb,
      );
      if (result == null) return;
      setState(() => _isSendingFile = true);

      if (kIsWeb && result.files.first.bytes != null) {
        final f = result.files.first;
        final mime = _guessMime(f.name);
        final msgType = _fileTypeFromMime(mime);
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .sendFileBytes(f.bytes!, f.name, msgType, mime);
      } else if (!kIsWeb && result.files.first.path != null) {
        final path = result.files.first.path!;
        final mime = _guessMime(path);
        final msgType = _fileTypeFromMime(mime);
        await ref
            .read(messagesProvider(widget.conversationId).notifier)
            .sendFile(path, msgType);
      }

      setState(() => _isSendingFile = false);
      _scrollToBottom();
    } catch (e) {
      setState(() => _isSendingFile = false);
      _showError("Impossible d'envoyer le fichier.");
    }
  }

  String _guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg',
      'aac': 'audio/aac',
      'm4a': 'audio/mp4',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'zip': 'application/zip',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  String _fileTypeFromMime(String mime) {
    if (mime.startsWith('image/')) return 'image';
    if (mime.startsWith('video/')) return 'video';
    if (mime.startsWith('audio/')) return 'audio';
    return 'file';
  }

  // ── Appel sortant ─────────────────────────────────────────────
  Future<void> _initiateCall(String type) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    if (_callService.isBusy) {
      _showError('Vous êtes déjà en communication.');
      return;
    }

    try {
      final callData = await _callService.initiateCall(
        widget.conversationId,
        type,
        currentUser.id,
      );

      if (callData != null && mounted) {
        // Construire le CallModel depuis la réponse API
        final call = CallModel.fromJson(callData);

        // Naviguer vers CallPage en passant les participants pour
        // que l'appelant voie le nom du destinataire
        context.push(
          '/calls/${call.id}',
          extra: {
            'call': call,
            'participants': _conversation?.participants ?? <UserModel>[],
          },
        );
      } else if (mounted) {
        _showError("Impossible de démarrer l'appel.");
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().contains('422')
            ? 'Un appel est déjà en cours dans cette conversation.'
            : "Impossible de démarrer l'appel.";
        _showError(msg);
      }
    }
  }

  Future<void> _initiateVideoCallWithConfirm() async {
    final conv = _conversation;
    final isGroup = conv?.isGroup ?? false;

    if (isGroup) {
      _showError(
          'Les appels vidéo ne sont disponibles qu\'en conversation directe.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.videocam_rounded,
                color: AppColors.primary, size: 22),
            SizedBox(width: 10),
            Text('Appel vidéo',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800)),
          ],
        ),
        content: const Text(
          'Démarrer un appel vidéo avec cet utilisateur ?',
          style: TextStyle(fontFamily: 'Nunito', fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.videocam_rounded, size: 16),
            label: const Text('Démarrer'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await _initiateCall('video');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Nunito')),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _ws.unsubscribeFromConversation(widget.conversationId);
    _callService.onCallStatusChanged = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync =
        ref.watch(messagesProvider(widget.conversationId));
    final currentUser = ref.watch(currentUserProvider);
    final conv = _conversation;
    final displayName =
        conv?.getDisplayName(currentUser?.id ?? 0) ?? 'Conversation';
    final other = conv?.getOtherParticipant(currentUser?.id ?? 0);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(displayName, other, conv),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: messagesAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary)),
                  error: (e, _) => Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.grey300, size: 48),
                        const SizedBox(height: 12),
                        TextButton(
                          onPressed: () => ref
                              .read(messagesProvider(
                                      widget.conversationId)
                                  .notifier)
                              .load(refresh: true),
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                  data: (messages) => _buildMessageList(
                      messages, currentUser?.id ?? 0),
                ),
              ),

              // Indicateur envoi fichier
              if (_isSendingFile)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8),
                  color: AppColors.primarySurface,
                  child: Row(children: [
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary)),
                    const SizedBox(width: 10),
                    const Text('Envoi en cours...',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontFamily: 'Nunito',
                            fontSize: 13)),
                  ]),
                ),

              if (_otherTyping) _buildTypingIndicator(),
              _buildInputArea(),
            ],
          ),

          // Bannière appel entrant
          if (_pendingIncomingCall != null)
            _IncomingCallBanner(
              info: _pendingIncomingCall!,
              onAccept: () => _acceptIncomingCall(_pendingIncomingCall!),
              onReject: () => _rejectIncomingCall(_pendingIncomingCall!),
            ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(
      String name, UserModel? other, ConversationModel? conv) {
    final isGroup = conv?.isGroup ?? false;

    return AppBar(
      backgroundColor: AppColors.white,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppColors.grey700, size: 20),
        onPressed: () => context.pop(),
      ),
      title: Row(children: [
        if (isGroup)
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
                color: AppColors.primarySurface, shape: BoxShape.circle),
            child: Center(
              child: Text(conv?.group?.initials ?? 'G',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      fontFamily: 'Nunito')),
            ),
          )
        else
          AvatarWidget(name: other?.fullName ?? name, size: 38),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.grey800,
                      fontFamily: 'Nunito'),
                  overflow: TextOverflow.ellipsis),
              if (isGroup)
                Text('${conv?.participants.length ?? 0} membres',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grey400,
                        fontFamily: 'Nunito'))
              else if (other?.phoneNumber != null)
                Text(other!.phoneNumber!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.grey400,
                        fontFamily: 'Nunito'))
              else
                const Text('En ligne',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.online,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Nunito')),
            ],
          ),
        ),
      ]),
      actions: [
        Tooltip(
          message: 'Appel audio',
          child: IconButton(
            icon: const Icon(Icons.call_rounded),
            color: AppColors.primary,
            iconSize: 24,
            onPressed: () => _initiateCall('audio'),
          ),
        ),
        if (!isGroup)
          Tooltip(
            message: 'Appel vidéo',
            child: IconButton(
              icon: const Icon(Icons.videocam_rounded),
              color: AppColors.primary,
              iconSize: 26,
              onPressed: _initiateVideoCallWithConfirm,
            ),
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildMessageList(
      List<MessageModel> messages, int currentUserId) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                  color: AppColors.primarySurface,
                  shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 12),
            const Text('Commencez la conversation !',
                style: TextStyle(
                    color: AppColors.grey400, fontFamily: 'Nunito')),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMine = msg.senderId == currentUserId;
        final showAvatar = !isMine &&
            (index == 0 ||
                messages[index - 1].senderId != msg.senderId);

        return _MessageBubble(
          message: msg,
          isMine: isMine,
          showAvatar: showAvatar,
          onDelete: isMine
              ? () => ref
                  .read(messagesProvider(widget.conversationId)
                      .notifier)
                  .deleteMessage(msg.id)
              : null,
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      alignment: Alignment.centerLeft,
      child: Row(children: [
        const SizedBox(width: 4),
        Text(
          '${_otherTypingName ?? ''} est en train d\'écrire',
          style: const TextStyle(
              color: AppColors.grey400,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontFamily: 'Nunito'),
        ),
        const SizedBox(width: 6),
        _TypingDots(),
      ]),
    );
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, -2)),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file_rounded,
                color: AppColors.grey400, size: 22),
            onPressed: _showAttachmentMenu,
            padding: const EdgeInsets.all(8),
            constraints:
                const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.grey200),
              ),
              child: TextField(
                controller: _textController,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 15,
                    color: AppColors.grey800),
                decoration: const InputDecoration(
                  hintText: 'Message...',
                  hintStyle: TextStyle(color: AppColors.grey400),
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          ValueListenableBuilder(
            valueListenable: _textController,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? _send : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: hasText
                        ? AppColors.primary
                        : AppColors.grey200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.send_rounded,
                      color:
                          hasText ? Colors.white : AppColors.grey400,
                      size: 20),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Bannière appel entrant ──────────────────────────────────
class _IncomingCallBanner extends StatefulWidget {
  final IncomingCallInfo info;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _IncomingCallBanner({
    required this.info,
    required this.onAccept,
    required this.onReject,
  });

  @override
  State<_IncomingCallBanner> createState() => _IncomingCallBannerState();
}

class _IncomingCallBannerState extends State<_IncomingCallBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slide = Tween<Offset>(
            begin: const Offset(0, -1), end: Offset.zero)
        .animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slide,
        child: Material(
          elevation: 8,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primaryDark, AppColors.primary],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.info.callType == 'video'
                        ? Icons.videocam_rounded
                        : Icons.call_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.info.callerName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Nunito',
                            fontSize: 14),
                      ),
                      Text(
                        widget.info.callType == 'video'
                            ? 'Appel vidéo entrant...'
                            : 'Appel audio entrant...',
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 12,
                            fontFamily: 'Nunito'),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: widget.onReject,
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.call_end_rounded,
                        color: Colors.white, size: 20),
                  ),
                ),
                GestureDetector(
                  onTap: widget.onAccept,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.success,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.info.callType == 'video'
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Attachment Sheet ─────────────────────────────────────────
class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickFile;
  final VoidCallback onPickVideo;

  const _AttachmentSheet({
    required this.onPickImage,
    required this.onPickFile,
    required this.onPickVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.grey200,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 16),
          const Text('Joindre un fichier',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  fontFamily: 'Nunito',
                  color: AppColors.grey800)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                  icon: Icons.image_outlined,
                  label: 'Photo',
                  color: AppColors.info,
                  onTap: onPickImage),
              _AttachOption(
                  icon: Icons.videocam_outlined,
                  label: 'Vidéo',
                  color: AppColors.warning,
                  onTap: onPickVideo),
              _AttachOption(
                  icon: Icons.insert_drive_file_outlined,
                  label: 'Fichier',
                  color: AppColors.primary,
                  onTap: onPickFile),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  color: AppColors.grey600)),
        ],
      ),
    );
  }
}

// ─── Typing dots ──────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) => Row(
        children: List.generate(3, (i) {
          final opacity =
              ((_controller.value * 3) - i).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                    color: AppColors.grey400, shape: BoxShape.circle),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Message Bubble ───────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final bool showAvatar;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showAvatar,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            showAvatar
                ? AvatarWidget(
                    name: message.sender?.fullName ?? '?', size: 30)
                : const SizedBox(width: 30),
            const SizedBox(width: 8),
          ],
          GestureDetector(
            onLongPress:
                onDelete != null ? () => _showMenu(context) : null,
            child: Container(
              constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine
                    ? AppColors.bubbleSent
                    : AppColors.bubbleReceived,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMine ? 18 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMine && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(message.sender?.fullName ?? '',
                          style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Nunito')),
                    ),
                  if (message.isDeleted)
                    Text('Message supprimé',
                        style: TextStyle(
                            color: isMine
                                ? Colors.white.withOpacity(0.6)
                                : AppColors.grey400,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                            fontFamily: 'Nunito'))
                  else
                    _buildContent(context),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      timeago.format(message.createdAt, locale: 'fr'),
                      style: TextStyle(
                          fontSize: 10,
                          color: isMine
                              ? Colors.white.withOpacity(0.6)
                              : AppColors.grey400,
                          fontFamily: 'Nunito'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final mediaUrl = message.mediaUrl != null
        ? (message.mediaUrl!.startsWith('http')
            ? message.mediaUrl!
            : '${AppConstants.storageBaseUrl}${message.mediaUrl}')
        : null;

    if (message.isImage && mediaUrl != null) {
      return GestureDetector(
        onTap: () => _openUrl(mediaUrl),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedNetworkImage(
            imageUrl: mediaUrl,
            width: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 220,
              height: 140,
              color: AppColors.grey200,
              child: const Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
            ),
            errorWidget: (_, __, ___) => Container(
              width: 220,
              height: 120,
              color: AppColors.grey200,
              child: const Icon(Icons.broken_image,
                  color: AppColors.grey400),
            ),
          ),
        ),
      );
    }

    if (message.isAudio && mediaUrl != null) {
      return _AudioMessage(
          url: mediaUrl, isMine: isMine, mediaName: message.mediaName);
    }

    if (message.isVideo && mediaUrl != null) {
      return GestureDetector(
        onTap: () => _openUrl(mediaUrl),
        child: Container(
          width: 220,
          height: 130,
          decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8)),
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Icon(Icons.videocam_rounded,
                  color: Colors.white54, size: 48),
              Positioned(
                bottom: 6,
                left: 6,
                child: Text(message.mediaName ?? 'Vidéo',
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'Nunito'),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
      );
    }

    if (message.isFile && mediaUrl != null) {
      return GestureDetector(
        onTap: () => _openUrl(mediaUrl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.attach_file_rounded,
                color: isMine ? Colors.white70 : AppColors.primary,
                size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(message.mediaName ?? 'Fichier',
                  style: TextStyle(
                      color:
                          isMine ? Colors.white : AppColors.grey800,
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      decoration: TextDecoration.underline),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      );
    }

    if (message.body != null && message.body!.isNotEmpty) {
      return Text(message.body!,
          style: TextStyle(
              color: isMine
                  ? AppColors.bubbleSentText
                  : AppColors.bubbleReceivedText,
              fontSize: 15,
              height: 1.4,
              fontFamily: 'Nunito'));
    }

    return const SizedBox.shrink();
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(2)),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text('Supprimer le message',
                  style: TextStyle(
                      color: AppColors.error, fontFamily: 'Nunito')),
              onTap: () {
                Navigator.pop(context);
                onDelete?.call();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _AudioMessage extends StatelessWidget {
  final String url;
  final bool isMine;
  final String? mediaName;

  const _AudioMessage(
      {required this.url, required this.isMine, this.mediaName});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.audiotrack_rounded,
              color: isMine ? Colors.white70 : AppColors.primary,
              size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(mediaName ?? 'Message audio',
                style: TextStyle(
                    color: isMine ? Colors.white : AppColors.grey800,
                    fontFamily: 'Nunito',
                    fontSize: 13,
                    decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }
}