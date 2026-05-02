import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import '../../../../core/api/api_client.dart';
import '../../../../core/api/auth_storage.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/call_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/websocket/websocket_service.dart';
import '../../../../shared/models/models.dart';
import '../../../../shared/widgets/avatar_widget.dart';
import '../../../auth/data/auth_provider.dart';
import '../../../conversations/data/conversations_provider.dart';
import '../../data/messages_provider.dart';

class ChatPage extends ConsumerStatefulWidget {
  final int conversationId;
  const ChatPage({super.key, required this.conversationId});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with TickerProviderStateMixin {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _ws = WebSocketService();
  final _callService = CallService();
  final _imagePicker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();

  bool _isTyping = false;
  bool _otherTyping = false;
  String? _otherTypingName;
  ConversationModel? _conversation;
  Timer? _typingTimer;

  // File sending state
  bool _isSendingFile = false;
  String? _sendingFileError;

  // Voice recording state
  bool _isRecording = false;
  bool _isLongPressing = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  String? _currentRecordPath;
  late AnimationController _recordingPulseController;

  // Swipe to reveal attachment options
  bool _showAttachBar = false;

  bool get isGroup => _conversation?.isGroup ?? false;

  @override
  void initState() {
    super.initState();
    _recordingPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _loadConversation();
    _markRead();
    _subscribeToWebSocket();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 200 &&
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
    setState(() {}); // rebuild send/mic button
  }

  // ── WebSocket ──────────────────────────────────────────────────
  void _subscribeToWebSocket() {
    final currentUser = ref.read(currentUserProvider);

    _ws.subscribeToConversation(widget.conversationId, events: {
      'message.sent': (data) {
        if (!mounted) return;
        final msg = MessageModel.fromJson(data);
        if (msg.senderId != currentUser?.id) {
          ref
              .read(messagesProvider(widget.conversationId).notifier)
              .addMessage(msg);
          _markRead();
          _scrollToBottom();
        }
        ref.read(conversationsProvider.notifier).load();
      },

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

      'call.initiated': (data) {
        if (!mounted) return;
        final callerId = data['caller_id'] as int?;
        if (callerId == currentUser?.id) return;
        final call = CallModel.fromJson(data);
        context.push('/calls/${call.id}', extra: call);
      },

      'call.status': (data) {
        _callService.onCallStatusChanged
            ?.call(data['status'] as String? ?? '');
      },

      'call.signal': (data) {
        final senderId = data['sender_id'] as int?;
        if (senderId != currentUser?.id) {
          _callService.onCallSignalReceived(data);
        }
      },
    });

    _callService.listenToConversation(widget.conversationId);
  }

  Future<void> _loadConversation() async {
    try {
      final response = await ApiClient().getConversation(widget.conversationId);
      if (mounted) {
        setState(() {
          _conversation =
              ConversationModel.fromJson(response.data as Map<String, dynamic>);
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
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController
              .jumpTo(_scrollController.position.maxScrollExtent);
        }
      }
    });
  }

  // ── Voice Recording ───────────────────────────────────────────
  Future<void> _startRecording() async {
    // Web: recording to stream only (no file path)
    if (kIsWeb) {
      _showError('Enregistrement vocal non disponible sur le web');
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        _showError('Permission microphone refusée');
        return;
      }

      final dir = await getTemporaryDirectory();
      _currentRecordPath =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      // record v6 API: start(RecordConfig(), path: '...')
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordPath!,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        }
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      _showError('Impossible de démarrer l\'enregistrement: $e');
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    setState(() => _isRecording = false);

    try {
      final path = await _recorder.stop();
      if (path == null || _recordingDuration.inSeconds < 1) {
        // Too short, discard
        if (path != null) File(path).deleteSync();
        return;
      }

      setState(() => _isSendingFile = true);
      final success = await ref
          .read(messagesProvider(widget.conversationId).notifier)
          .sendFile(path, 'audio');

      setState(() => _isSendingFile = false);

      if (!success) {
        _showError('Échec de l\'envoi du message vocal');
      } else {
        _scrollToBottom();
      }

      // Clean up temp file
      try {
        File(path).deleteSync();
      } catch (_) {}
    } catch (e) {
      setState(() => _isSendingFile = false);
      _showError('Erreur lors de l\'envoi vocal');
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });

    try {
      final path = await _recorder.stop();
      if (path != null) File(path).deleteSync();
    } catch (_) {}

    HapticFeedback.lightImpact();
  }

  // ── File Picking ───────────────────────────────────────────────
  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          withData: true,
        );
        if (result?.files.first.bytes != null) {
          await _sendFileBytes(
            result!.files.first.bytes!,
            result.files.first.name,
            'image',
            'image/jpeg',
          );
        }
        return;
      }

      final picked = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked != null) {
        await _sendFilePath(picked.path, 'image');
      }
    } catch (e) {
      _showError('Impossible de charger l\'image: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          withData: true,
        );
        if (result?.files.first.bytes != null) {
          await _sendFileBytes(
            result!.files.first.bytes!,
            result.files.first.name,
            'video',
            'video/mp4',
          );
        }
        return;
      }

      final picked =
          await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked != null) {
        await _sendFilePath(picked.path, 'video');
      }
    } catch (e) {
      _showError('Impossible de charger la vidéo: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: kIsWeb,
        withReadStream: !kIsWeb,
      );
      if (result == null) return;

      if (kIsWeb && result.files.first.bytes != null) {
        final f = result.files.first;
        final mime = _guessMime(f.name);
        final msgType = _fileTypeFromMime(mime);
        await _sendFileBytes(f.bytes!, f.name, msgType, mime);
      } else if (!kIsWeb && result.files.first.path != null) {
        final path = result.files.first.path!;
        final mime = _guessMime(path);
        final msgType = _fileTypeFromMime(mime);
        await _sendFilePath(path, msgType);
      }
    } catch (e) {
      _showError('Impossible d\'envoyer le fichier: $e');
    }
  }

  Future<void> _sendFilePath(String path, String type) async {
    setState(() {
      _isSendingFile = true;
      _sendingFileError = null;
    });

    final success = await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendFile(path, type);

    setState(() => _isSendingFile = false);

    if (!success) {
      _showError('Échec de l\'envoi. Vérifiez votre connexion et réessayez.');
    } else {
      _scrollToBottom();
    }
  }

  Future<void> _sendFileBytes(
    Uint8List bytes,
    String fileName,
    String type,
    String mime,
  ) async {
    setState(() {
      _isSendingFile = true;
      _sendingFileError = null;
    });

    final success = await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendFileBytes(bytes, fileName, type, mime);

    setState(() => _isSendingFile = false);

    if (!success) {
      _showError('Échec de l\'envoi. Vérifiez votre connexion et réessayez.');
    } else {
      _scrollToBottom();
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

  // ── Call ───────────────────────────────────────────────────────
  Future<void> _initiateCall(String type) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) return;

    final callData = await _callService.initiateCall(
      widget.conversationId,
      type,
      currentUser.id,
    );

    if (callData != null && mounted) {
      final call = CallModel.fromJson(callData);
      context.push('/calls/${call.id}', extra: call);
    } else if (mounted) {
      _showError('Impossible de démarrer l\'appel.');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(msg,
                  style: const TextStyle(fontFamily: 'Nunito', fontSize: 14)),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _startPrivateFromGroup(UserModel sender) async {
    final conv =
        await ref.read(conversationsProvider.notifier).startDirect(sender.id);
    if (conv != null && mounted) {
      context.push('/conversations/${conv.id}');
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _recordingTimer?.cancel();
    _recordingPulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    _ws.unsubscribeFromConversation(widget.conversationId);
    _callService.stopListening(widget.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));
    final currentUser = ref.watch(currentUserProvider);
    final conv = _conversation;
    final displayName =
        conv?.getDisplayName(currentUser?.id ?? 0) ?? 'Conversation';
    final other = conv?.getOtherParticipant(currentUser?.id ?? 0);

    return Scaffold(
      backgroundColor: const Color(0xFFEBE5DC), // WhatsApp beige background
      appBar: _buildAppBar(displayName, other, conv),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: AppColors.grey300, size: 48),
                    const SizedBox(height: 12),
                    const Text('Impossible de charger les messages',
                        style: TextStyle(
                            color: AppColors.grey500, fontFamily: 'Nunito')),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => ref
                          .read(messagesProvider(widget.conversationId)
                              .notifier)
                          .load(refresh: true),
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
              data: (messages) =>
                  _buildMessageList(messages, currentUser?.id ?? 0),
            ),
          ),
          if (_isSendingFile) _buildSendingIndicator(),
          if (_otherTyping) _buildTypingIndicator(),
          _buildInputArea(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      String name, UserModel? other, ConversationModel? conv) {
    return AppBar(
      backgroundColor: const Color(0xFF1B7F4A),
      foregroundColor: Colors.white,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          if (conv?.isGroup == true)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  conv?.group?.initials ?? 'G',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    fontFamily: 'Nunito',
                  ),
                ),
              ),
            )
          else
            _WhatsAppAvatar(name: other?.fullName ?? name, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFamily: 'Nunito',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  conv?.isGroup == true
                      ? '${conv?.participants.length ?? 0} membres'
                      : (other?.phoneNumber ?? 'appuyez pour plus d\'infos'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.85),
                    fontFamily: 'Nunito',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!isGroup)
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            onPressed: () => _initiateCall('video'),
          ),
        if (!isGroup)
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Colors.white),
            onPressed: () => _initiateCall('audio'),
          ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: () => _showMoreMenu(),
        ),
      ],
    );
  }

  void _showMoreMenu() {
    final conv = _conversation;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            if (isGroup && conv != null)
              ListTile(
                leading:
                    const Icon(Icons.settings_rounded, color: AppColors.primary),
                title: const Text('Paramètres du groupe',
                    style: TextStyle(fontFamily: 'Nunito')),
                onTap: () {
                  Navigator.pop(context);
                  final groupId = conv.group?.id ?? conv.groupId;
                  if (groupId != null)
                    context.push('/groups/$groupId/settings');
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.search_rounded, color: AppColors.grey600),
              title: const Text('Rechercher',
                  style: TextStyle(fontFamily: 'Nunito')),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildSendingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFFDCF8C6),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          const Text('Envoi en cours...',
              style: TextStyle(
                  color: AppColors.primary,
                  fontFamily: 'Nunito',
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<MessageModel> messages, int currentUserId) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3C4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '🔒 Les messages sont chiffrés de bout en bout',
                style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7D6608),
                    fontFamily: 'Nunito'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final msg = messages[index];
          final isMine = msg.senderId == currentUserId;

          // Show date separator
          final showDateSep = index == 0 ||
              !_isSameDay(messages[index - 1].createdAt, msg.createdAt);

          // Show avatar for group chats when sender changes
          final showAvatar = !isMine &&
              isGroup &&
              (index == 0 || messages[index - 1].senderId != msg.senderId);

          final showName = !isMine &&
              isGroup &&
              (index == 0 || messages[index - 1].senderId != msg.senderId);

          return Column(
            children: [
              if (showDateSep) _buildDateSeparator(msg.createdAt),
              _MessageBubble(
                message: msg,
                isMine: isMine,
                showAvatar: showAvatar,
                showName: showName,
                isGroup: isGroup,
                onDelete: isMine
                    ? () => ref
                        .read(messagesProvider(widget.conversationId).notifier)
                        .deleteMessage(msg.id)
                    : null,
                onNameTap: !isMine && msg.sender != null
                    ? () => _startPrivateFromGroup(msg.sender!)
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Aujourd\'hui';
    } else if (_isSameDay(
        date, now.subtract(const Duration(days: 1)))) {
      label = 'Hier';
    } else {
      label = '${date.day}/${date.month}/${date.year}';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFD1F0E0),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 2,
                  offset: const Offset(0, 1))
            ],
          ),
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4A5E57),
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 12, bottom: 4, top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.07),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _otherTypingName ?? '',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            _TypingDots(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    final hasText = _textController.text.trim().isNotEmpty;

    return Container(
      color: const Color(0xFFF0F2F5),
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: _isRecording
          ? _buildRecordingBar()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attachment + emoji button in text field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 4)
                      ],
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Emoji / attachment toggle
                        IconButton(
                          icon: const Icon(Icons.emoji_emotions_outlined,
                              color: Color(0xFF8696A0), size: 24),
                          onPressed: () {},
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            maxLines: 5,
                            minLines: 1,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontSize: 15,
                              color: Color(0xFF111B21),
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              hintStyle: TextStyle(
                                  color: Color(0xFF8696A0), fontSize: 15),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 0, vertical: 10),
                              isDense: true,
                            ),
                          ),
                        ),
                        // Attach button
                        IconButton(
                          icon: const Icon(Icons.attach_file_rounded,
                              color: Color(0xFF8696A0), size: 24),
                          onPressed: _showAttachmentMenu,
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(),
                        ),
                        // Camera button (only when no text)
                        if (!hasText)
                          IconButton(
                            icon: const Icon(Icons.camera_alt_outlined,
                                color: Color(0xFF8696A0), size: 24),
                            onPressed: () =>
                                _pickImage(source: ImageSource.camera),
                            padding: const EdgeInsets.all(10),
                            constraints: const BoxConstraints(),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Send / Mic button
                GestureDetector(
                  onTap: hasText ? _send : null,
                  onLongPressStart: hasText
                      ? null
                      : (_) async {
                          setState(() => _isLongPressing = true);
                          await _startRecording();
                        },
                  onLongPressEnd: hasText
                      ? null
                      : (_) async {
                          setState(() => _isLongPressing = false);
                          await _stopAndSendRecording();
                        },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B7F4A),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFF1B7F4A).withOpacity(0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3))
                      ],
                    ),
                    child: Icon(
                      hasText ? Icons.send_rounded : Icons.mic_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildRecordingBar() {
    final minutes = _recordingDuration.inMinutes;
    final seconds = _recordingDuration.inSeconds % 60;
    final timeStr =
        '$minutes:${seconds.toString().padLeft(2, '0')}';

    return Row(
      children: [
        // Cancel swipe hint
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.1), blurRadius: 4)
              ],
            ),
            child: const Icon(Icons.delete_outline_rounded,
                color: AppColors.error, size: 22),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.06), blurRadius: 4)
              ],
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _recordingPulseController,
                  builder: (_, __) => Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(
                          0.5 + 0.5 * _recordingPulseController.value),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  timeStr,
                  style: const TextStyle(
                      fontSize: 15,
                      color: Color(0xFF111B21),
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                const Text(
                  '< Glisser pour annuler',
                  style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8696A0),
                      fontFamily: 'Nunito'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _stopAndSendRecording,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFF1B7F4A),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFF1B7F4A).withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3))
              ],
            ),
            child: const Icon(Icons.send_rounded,
                color: Colors.white, size: 22),
          ),
        ),
      ],
    );
  }

  void _showAttachmentMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _AttachmentSheet(
        onPickImage: () {
          Navigator.pop(context);
          _pickImage();
        },
        onPickCamera: () {
          Navigator.pop(context);
          _pickImage(source: ImageSource.camera);
        },
        onPickFile: () {
          Navigator.pop(context);
          _pickFile();
        },
        onPickVideo: () {
          Navigator.pop(context);
          _pickVideo();
        },
      ),
    );
  }
}

// ── WhatsApp Avatar ───────────────────────────────────────────────
class _WhatsAppAvatar extends StatelessWidget {
  final String name;
  final double size;

  const _WhatsAppAvatar({required this.name, required this.size});

  String get _initials {
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
            fontFamily: 'Nunito',
          ),
        ),
      ),
    );
  }
}

// ── Attachment Sheet ───────────────────────────────────────────────
class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onPickImage;
  final VoidCallback onPickCamera;
  final VoidCallback onPickFile;
  final VoidCallback onPickVideo;

  const _AttachmentSheet({
    required this.onPickImage,
    required this.onPickCamera,
    required this.onPickFile,
    required this.onPickVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.insert_drive_file_rounded,
                label: 'Document',
                color: const Color(0xFF7B5EA7),
                onTap: onPickFile,
              ),
              _AttachOption(
                icon: Icons.camera_alt_rounded,
                label: 'Appareil photo',
                color: const Color(0xFFFF6B6B),
                onTap: onPickCamera,
              ),
              _AttachOption(
                icon: Icons.photo_library_rounded,
                label: 'Galerie',
                color: const Color(0xFF4ECDC4),
                onTap: onPickImage,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(
                icon: Icons.videocam_rounded,
                label: 'Vidéo',
                color: const Color(0xFFFF9F43),
                onTap: onPickVideo,
              ),
              _AttachOption(
                icon: Icons.headphones_rounded,
                label: 'Audio',
                color: const Color(0xFF1B7F4A),
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              const SizedBox(width: 80),
            ],
          ),
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
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: color.withOpacity(0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Nunito',
              fontSize: 12,
              color: Color(0xFF4A5E57),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Typing Dots ────────────────────────────────────────────────────
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
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
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
      builder: (_, __) {
        return Row(
          children: List.generate(3, (i) {
            final t = (_controller.value * 3 - i).clamp(0.0, 1.0);
            final opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF8696A0).withOpacity(0.3 + 0.7 * opacity),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Message Bubble ──────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final bool showAvatar;
  final bool showName;
  final bool isGroup;
  final VoidCallback? onDelete;
  final VoidCallback? onNameTap;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showAvatar,
    required this.showName,
    required this.isGroup,
    this.onDelete,
    this.onNameTap,
  });

  // Colors for group participant names
  static const List<Color> _nameColors = [
    Color(0xFF1B7F4A),
    Color(0xFF2196F3),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFFFF5722),
    Color(0xFF009688),
  ];

  Color _nameColor(int senderId) =>
      _nameColors[senderId % _nameColors.length];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: 2,
        left: isMine ? 60 : 2,
        right: isMine ? 2 : 60,
      ),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine && isGroup) ...[
            if (showAvatar)
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 2),
                child: AvatarWidget(
                    name: message.sender?.fullName ?? '?', size: 28),
              )
            else
              const SizedBox(width: 34),
          ],
          GestureDetector(
            onLongPress: onDelete != null ? () => _showMenu(context) : null,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                color: isMine
                    ? const Color(0xFFDCF8C6) // WhatsApp green sent
                    : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMine ? 12 : 2),
                  bottomRight: Radius.circular(isMine ? 2 : 12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMine ? 12 : 2),
                  bottomRight: Radius.circular(isMine ? 2 : 12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine && showName && message.sender != null)
                      Padding(
                        padding: const EdgeInsets.only(
                            left: 10, right: 10, top: 6),
                        child: GestureDetector(
                          onTap: onNameTap,
                          child: Text(
                            message.sender!.fullName,
                            style: TextStyle(
                              color: _nameColor(message.senderId),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Nunito',
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: _contentPadding(),
                      child: message.isDeleted
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.block_rounded,
                                    size: 14,
                                    color: isMine
                                        ? const Color(0xFF667781)
                                        : const Color(0xFF8696A0)),
                                const SizedBox(width: 5),
                                Text(
                                  'Message supprimé',
                                  style: TextStyle(
                                    color: isMine
                                        ? const Color(0xFF667781)
                                        : const Color(0xFF8696A0),
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                    fontFamily: 'Nunito',
                                  ),
                                ),
                              ],
                            )
                          : _buildContent(context),
                    ),
                    // Timestamp row
                    Padding(
                      padding: const EdgeInsets.only(
                          right: 8, left: 8, bottom: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(child: const SizedBox()),
                          Text(
                            _formatTime(message.createdAt),
                            style: TextStyle(
                              fontSize: 10,
                              color: isMine
                                  ? const Color(0xFF667781)
                                  : const Color(0xFF8696A0),
                              fontFamily: 'Nunito',
                            ),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 3),
                            const Icon(Icons.done_all_rounded,
                                size: 14, color: Color(0xFF53BDEB)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsets _contentPadding() {
    if (message.isImage) return const EdgeInsets.all(3);
    return const EdgeInsets.only(left: 10, right: 10, top: 6, bottom: 2);
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildContent(BuildContext context) {
    final rawUrl = message.mediaUrl;
    String? mediaUrl;

    if (rawUrl != null && rawUrl.isNotEmpty) {
      if (rawUrl.startsWith('http')) {
        mediaUrl = rawUrl;
      } else {
        // Ensure proper URL construction
        final base = AppConstants.storageBaseUrl;
        mediaUrl =
            rawUrl.startsWith('/') ? '$base$rawUrl' : '$base/$rawUrl';
      }
    }

    if (message.isImage && mediaUrl != null) {
      return _AuthNetworkImage(url: mediaUrl, width: 240);
    }

    if (message.isAudio && mediaUrl != null) {
      return _AudioBubble(
        url: mediaUrl,
        isMine: isMine,
        mediaName: message.mediaName,
        duration: message.mediaSize != null
            ? Duration(seconds: (message.mediaSize! / 16000).round())
            : null,
      );
    }

    if (message.isVideo && mediaUrl != null) {
      return GestureDetector(
        onTap: () => _openUrl(mediaUrl!),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 240,
              height: 145,
              color: Colors.black87,
              child: const Center(
                child:
                    Icon(Icons.videocam_rounded, color: Colors.white54, size: 52),
              ),
            ),
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
            ),
            if (message.mediaName != null)
              Positioned(
                bottom: 8,
                left: 8,
                right: 8,
                child: Text(
                  message.mediaName!,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, fontFamily: 'Nunito'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      );
    }

    if (message.isFile && mediaUrl != null) {
      final sizeStr = message.mediaSize != null
          ? _formatFileSize(message.mediaSize!)
          : '';
      final ext = (message.mediaName ?? '').split('.').last.toUpperCase();

      return GestureDetector(
        onTap: () => _openUrl(mediaUrl!),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isMine
                    ? const Color(0xFF1B7F4A).withOpacity(0.15)
                    : const Color(0xFF1B7F4A).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.insert_drive_file_rounded,
                      color: AppColors.primary, size: 20),
                  if (ext.isNotEmpty)
                    Text(ext,
                        style: const TextStyle(
                            fontSize: 8,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Nunito')),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.mediaName ?? 'Fichier',
                    style: TextStyle(
                      color: isMine
                          ? const Color(0xFF111B21)
                          : const Color(0xFF111B21),
                      fontFamily: 'Nunito',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (sizeStr.isNotEmpty)
                    Text(
                      sizeStr,
                      style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8696A0),
                          fontFamily: 'Nunito'),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.download_rounded,
                color: AppColors.primary, size: 20),
          ],
        ),
      );
    }

    // Text
    if (message.body != null && message.body!.isNotEmpty) {
      return SelectableText(
        message.body!,
        style: const TextStyle(
          color: Color(0xFF111B21),
          fontSize: 15,
          height: 1.4,
          fontFamily: 'Nunito',
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
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
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(2))),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text('Supprimer',
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

// ── Authenticated Network Image ─────────────────────────────────────
/// Fetches images with the Bearer token so private storage works
class _AuthNetworkImage extends StatefulWidget {
  final String url;
  final double width;

  const _AuthNetworkImage({required this.url, this.width = 220});

  @override
  State<_AuthNetworkImage> createState() => _AuthNetworkImageState();
}

class _AuthNetworkImageState extends State<_AuthNetworkImage> {
  Uint8List? _imageBytes;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _fetchImage();
  }

  Future<void> _fetchImage() async {
    try {
      final token = await AuthStorage.getToken();
      final dio = Dio();
      final response = await dio.get<List<int>>(
        widget.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: token != null
              ? {'Authorization': 'Bearer $token'}
              : {},
          validateStatus: (s) => s != null && s < 500,
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        if (mounted) {
          setState(() {
            _imageBytes = Uint8List.fromList(response.data!);
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() {
          _error = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        width: widget.width,
        height: widget.width * 0.65,
        color: const Color(0xFFEBEBEB),
        child: const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.primary),
        ),
      );
    }

    if (_error || _imageBytes == null) {
      return GestureDetector(
        onTap: () => launchUrl(Uri.parse(widget.url),
            mode: LaunchMode.externalApplication),
        child: Container(
          width: widget.width,
          height: 120,
          color: const Color(0xFFEBEBEB),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(Icons.image_not_supported_rounded,
                  color: AppColors.grey400, size: 36),
              SizedBox(height: 6),
              Text('Appuyer pour ouvrir',
                  style: TextStyle(
                      color: AppColors.grey400,
                      fontSize: 12,
                      fontFamily: 'Nunito')),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(
          _imageBytes!,
          width: widget.width,
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.open_in_browser_rounded,
                    color: Colors.white),
                onPressed: () => launchUrl(Uri.parse(widget.url),
                    mode: LaunchMode.externalApplication),
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.memory(_imageBytes!, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Audio Bubble ────────────────────────────────────────────────────
class _AudioBubble extends StatelessWidget {
  final String url;
  final bool isMine;
  final String? mediaName;
  final Duration? duration;

  const _AudioBubble(
      {required this.url,
      required this.isMine,
      this.mediaName,
      this.duration});

  String get _durationStr {
    if (duration == null) return '0:00';
    final m = duration!.inMinutes;
    final s = duration!.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

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
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isMine
                  ? const Color(0xFF1B7F4A)
                  : const Color(0xFF1B7F4A).withOpacity(0.85),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Waveform placeholder
              Row(
                children: List.generate(
                  18,
                  (i) => Container(
                    width: 3,
                    height: 8.0 + (i % 4) * 5.0,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      color: isMine
                          ? const Color(0xFF1B7F4A).withOpacity(0.6)
                          : const Color(0xFF8696A0).withOpacity(0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _durationStr,
                style: TextStyle(
                    fontSize: 11,
                    color: isMine
                        ? const Color(0xFF667781)
                        : const Color(0xFF8696A0),
                    fontFamily: 'Nunito'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}