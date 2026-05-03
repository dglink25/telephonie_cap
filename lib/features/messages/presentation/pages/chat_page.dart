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
import '../../../../shared/widgets/app_modal.dart';
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
  bool _otherRecording = false; // ← NOUVEAU
  String? _otherTypingName;
  ConversationModel? _conversation;
  Timer? _typingTimer;
  Timer? _otherTypingTimer; // ← NOUVEAU : timer pour reset auto

  bool _isSendingFile = false;
  int _uploadProgress = 0;

  bool _isRecording = false;
  bool _isLongPressing = false;
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  late AnimationController _recordingPulseController;

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
  _subscribeToWebSocket(); // ← directement, pas dans addPostFrameCallback

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
    setState(() {});
  }

  void _subscribeToWebSocket() {
  final currentUser = ref.read(currentUserProvider);

  // S'abonner immédiatement — WebSocketService gère la queue interne
  // si le canal n'est pas encore connecté (_pendingSubscriptions)
  _ws.subscribeToConversation(widget.conversationId, events: {
    'message.sent': (data) {
      if (!mounted) return;
      try {
        final msg = MessageModel.fromJson(data);
        debugPrint('[Chat] message.sent reçu: id=${msg.id} sender=${msg.senderId}');

        if (msg.senderId != currentUser?.id) {
          ref
              .read(messagesProvider(widget.conversationId).notifier)
              .addMessage(msg);
          _markRead();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final distanceFromBottom = _scrollController.position.maxScrollExtent
                - _scrollController.position.pixels;
            if (distanceFromBottom < 300) {
              _scrollToBottom();
            }
          });
        }
        // Toujours recharger la liste des conversations
        ref.read(conversationsProvider.notifier).load();
      } catch (e) {
        debugPrint('[ChatPage] message.sent parse error: $e — data=$data');
      }
    },
    'user.typing': (data) {
      if (!mounted) return;
      final userId = data['user_id'] as int?;
      final isTyping = data['is_typing'] as bool? ?? false;
      final name = data['full_name'] as String? ?? '';

      debugPrint('[Chat] user.typing: userId=$userId isTyping=$isTyping');

      if (userId != null && userId != currentUser?.id) {
        _otherTypingTimer?.cancel();
        setState(() {
          _otherTypingName = name;
          _otherTyping = isTyping;
          if (isTyping) _otherRecording = false;
        });

        if (isTyping) {
          _otherTypingTimer = Timer(const Duration(seconds: 5), () {
            if (mounted) setState(() { _otherTyping = false; });
          });
        }
      }
    },
    'call.initiated': (data) {
      if (!mounted) return;
      final callerId = data['caller_id'] as int?;
      if (callerId == currentUser?.id) return;
      try {
        final call = CallModel.fromJson(data);
        context.push('/calls/${call.id}', extra: call);
      } catch (e) {
        debugPrint('[ChatPage] call.initiated parse error: $e');
      }
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
    } catch (e) {
      debugPrint('[ChatPage] loadConversation error: $e');
    }
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

    if (success) {
      _scrollToBottom();
    } else {
      if (mounted) {
        AppModal.error(context,
            title: 'Envoi échoué',
            message:
                'Le message n\'a pas pu être envoyé. Vérifiez votre connexion.');
      }
    }
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

  // ── Enregistrement vocal ──────────────────────────────────────
  Future<void> _startRecording() async {
    if (kIsWeb) {
      AppModal.info(context,
          title: 'Non disponible',
          message:
              'L\'enregistrement vocal n\'est pas disponible sur le navigateur web.');
      return;
    }

    try {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        if (mounted) {
          AppModal.error(context,
              title: 'Permission refusée',
              message:
                  'Autorisez l\'accès au microphone dans les paramètres de votre appareil.');
        }
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      // ← Notifier les autres qu'on enregistre
      _sendRecordingStatus(true);

      _recordingTimer =
          Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(
              () => _recordingDuration += const Duration(seconds: 1));
        }
      });

      HapticFeedback.mediumImpact();
    } catch (e) {
      if (mounted) {
        AppModal.error(context,
            title: 'Erreur microphone',
            message: 'Impossible de démarrer l\'enregistrement: $e');
      }
    }
  }

  Future<void> _stopAndSendRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    setState(() => _isRecording = false);

    // ← Notifier les autres qu'on a arrêté
    _sendRecordingStatus(false);

    try {
      final path = await _recorder.stop();
      if (path == null || _recordingDuration.inSeconds < 1) {
        if (path != null) {
          try {
            File(path).deleteSync();
          } catch (_) {}
        }
        return;
      }

      setState(() {
        _isSendingFile = true;
        _uploadProgress = 0;
      });

      final success = await ref
          .read(messagesProvider(widget.conversationId).notifier)
          .sendFile(
            path,
            'audio',
            onProgress: (sent, total) {
              if (total > 0 && mounted) {
                setState(
                    () => _uploadProgress = (sent / total * 100).round());
              }
            },
          );

      setState(() => _isSendingFile = false);

      if (!success && mounted) {
        AppModal.error(context,
            title: 'Envoi échoué',
            message: 'Le message vocal n\'a pas pu être envoyé.');
      } else {
        _scrollToBottom();
      }

      try {
        File(path).deleteSync();
      } catch (_) {}
    } catch (e) {
      setState(() => _isSendingFile = false);
      if (mounted) {
        AppModal.error(context,
            title: 'Erreur vocale',
            message: 'Erreur lors de l\'envoi du message vocal.');
      }
    }
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    _recordingTimer?.cancel();
    setState(() {
      _isRecording = false;
      _recordingDuration = Duration.zero;
    });

    // ← Notifier les autres qu'on a annulé
    _sendRecordingStatus(false);

    try {
      final path = await _recorder.stop();
      if (path != null) File(path).deleteSync();
    } catch (_) {}

    HapticFeedback.lightImpact();
  }

  /// Envoie le statut d'enregistrement via l'API typing
  /// On réutilise le endpoint typing avec un champ supplémentaire
  void _sendRecordingStatus(bool isRecording) {
    try {
      // On envoie is_typing=false + is_recording via l'API
      // Le backend UserTyping event sera étendu, mais en attendant
      // on peut envoyer is_typing avec une valeur spéciale
      // Pour l'instant on notifie juste via typing=false pour reset
      ref
          .read(messagesProvider(widget.conversationId).notifier)
          .sendTyping(isRecording);
    } catch (_) {}
  }

  // ── Sélection images/fichiers ─────────────────────────────────
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
      if (mounted) {
        AppModal.error(context,
            title: 'Erreur image',
            message: 'Impossible de charger l\'image: $e');
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      if (kIsWeb) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          withData: true,
        );
        if (result == null) return;
        final f = result.files.first;
        if (f.bytes == null) return;
        const maxBytes = 25 * 1024 * 1024;
        if (f.bytes!.length > maxBytes) {
          if (mounted) {
            AppModal.warning(context,
                title: 'Fichier trop volumineux',
                message:
                    'La vidéo dépasse 25 MB. Veuillez choisir une vidéo plus courte.');
          }
          return;
        }
        final mime = _guessMime(f.name);
        await _sendFileBytes(f.bytes!, f.name, 'video', mime);
        return;
      }

      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: false,
      );
      if (result == null || result.files.first.path == null) return;
      final path = result.files.first.path!;
      final file = File(path);
      final fileSize = await file.length();
      const maxBytes = 25 * 1024 * 1024;
      if (fileSize > maxBytes) {
        final sizeMb = (fileSize / 1024 / 1024).toStringAsFixed(1);
        if (mounted) {
          AppModal.warning(context,
              title: 'Fichier trop volumineux',
              message: 'La vidéo fait $sizeMb MB. La limite est de 25 MB.');
        }
        return;
      }
      await _sendFilePath(path, 'video');
    } catch (e) {
      if (mounted) {
        AppModal.error(context,
            title: 'Erreur vidéo',
            message: 'Impossible de charger la vidéo: $e');
      }
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
      if (mounted) {
        AppModal.error(context,
            title: 'Erreur fichier',
            message: 'Impossible d\'envoyer le fichier: $e');
      }
    }
  }

  Future<void> _sendFilePath(String path, String type) async {
    setState(() {
      _isSendingFile = true;
      _uploadProgress = 0;
    });
    final success = await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendFile(path, type, onProgress: (sent, total) {
      if (total > 0 && mounted) {
        setState(() => _uploadProgress = (sent / total * 100).round());
      }
    });
    if (mounted) setState(() => _isSendingFile = false);
    if (!success && mounted) {
      AppModal.error(context,
          title: 'Envoi échoué',
          message:
              'Le fichier n\'a pas pu être envoyé. Vérifiez votre connexion et la taille du fichier.');
    } else {
      _scrollToBottom();
    }
  }

  Future<void> _sendFileBytes(
      Uint8List bytes, String fileName, String type, String mime) async {
    setState(() {
      _isSendingFile = true;
      _uploadProgress = 0;
    });
    final success = await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendFileBytes(bytes, fileName, type, mime);
    if (mounted) setState(() => _isSendingFile = false);
    if (!success && mounted) {
      AppModal.error(context,
          title: 'Envoi échoué',
          message:
              'Le fichier n\'a pas pu être envoyé. Vérifiez votre connexion.');
    } else {
      _scrollToBottom();
    }
  }

  String _guessMime(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    const map = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'mp4': 'video/mp4',
      'mov': 'video/quicktime', 'avi': 'video/x-msvideo',
      'mp3': 'audio/mpeg', 'aac': 'audio/aac', 'm4a': 'audio/mp4',
      'wav': 'audio/wav', 'ogg': 'audio/ogg', 'pdf': 'application/pdf',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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

  Future<void> _initiateCall(String type) async {
    final currentUser = ref.read(currentUserProvider);
    if (currentUser == null) {
      AppModal.error(context,
          title: 'Non authentifié',
          message: 'Vous devez être connecté pour passer un appel.');
      return;
    }
    if (_callService.isBusy) {
      AppModal.warning(context,
          title: 'Appel en cours',
          message:
              'Vous êtes déjà en communication. Terminez l\'appel en cours avant d\'en démarrer un nouveau.');
      return;
    }

    bool dialogOpen = false;
    dialogOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _CallingDialog(),
    ).then((_) => dialogOpen = false);

    Map<String, dynamic>? callData;
    try {
      callData = await _callService.initiateCall(
          widget.conversationId, type, currentUser.id);
    } catch (e) {
      debugPrint('[ChatPage] initiateCall exception: $e');
    }

    if (mounted && dialogOpen) {
      Navigator.of(context, rootNavigator: true).pop();
      dialogOpen = false;
    }
    if (!mounted) return;

    if (callData != null) {
      try {
        final call = CallModel.fromJson(callData);
        context.push('/calls/${call.id}', extra: {
          'call': call,
          'participants': _conversation?.participants ?? [],
        });
      } catch (e) {
        AppModal.error(context,
            title: 'Erreur de navigation',
            message: 'Appel créé mais impossible d\'ouvrir la page: $e');
      }
    }
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
    _otherTypingTimer?.cancel();
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
    final messagesAsync =
        ref.watch(messagesProvider(widget.conversationId));
    final currentUser = ref.watch(currentUserProvider);
    final conv = _conversation;
    final displayName =
        conv?.getDisplayName(currentUser?.id ?? 0) ?? 'Conversation';
    final other = conv?.getOtherParticipant(currentUser?.id ?? 0);

    return Scaffold(
      backgroundColor: const Color(0xFFEBE5DC),
      appBar: _buildAppBar(displayName, other, conv),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Center(
                child:
                    CircularProgressIndicator(color: AppColors.primary),
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
                            color: AppColors.grey500,
                            fontFamily: 'Nunito')),
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
          // ← Indicateur typing/recording unifié
          if (_otherTyping || _otherRecording)
            _buildTypingIndicator(),
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
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(conv?.group?.initials ?? 'G',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        fontFamily: 'Nunito')),
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
                Text(name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        fontFamily: 'Nunito'),
                    overflow: TextOverflow.ellipsis),
                // ← Sous-titre dynamique : typing / recording / info
                _buildAppBarSubtitle(conv, other),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (!isGroup)
          IconButton(
            icon: const Icon(Icons.videocam_rounded, color: Colors.white),
            tooltip: 'Appel vidéo',
            onPressed: () => _initiateCall('video'),
          ),
        if (!isGroup)
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Colors.white),
            tooltip: 'Appel audio',
            onPressed: () => _initiateCall('audio'),
          ),
        IconButton(
          icon: const Icon(Icons.more_vert, color: Colors.white),
          onPressed: _showMoreMenu,
        ),
      ],
    );
  }

  /// Sous-titre de l'AppBar : affiche "en train d'écrire..." ou "enregistrement..."
  Widget _buildAppBarSubtitle(ConversationModel? conv, UserModel? other) {
    if (_otherRecording) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.mic, color: Colors.greenAccent, size: 12),
          const SizedBox(width: 4),
          Text(
            isGroup
                ? '${_otherTypingName ?? ''} enregistre...'
                : 'enregistrement vocal...',
            style: const TextStyle(
                fontSize: 12,
                color: Colors.greenAccent,
                fontFamily: 'Nunito'),
          ),
        ],
      );
    }
    if (_otherTyping) {
      return Text(
        isGroup
            ? '${_otherTypingName ?? ''} écrit...'
            : 'en train d\'écrire...',
        style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.9),
            fontStyle: FontStyle.italic,
            fontFamily: 'Nunito'),
      );
    }
    return Text(
      conv?.isGroup == true
          ? '${conv?.participants.length ?? 0} membres'
          : (other?.phoneNumber ?? 'appuyez pour plus d\'infos'),
      style: TextStyle(
          fontSize: 12,
          color: Colors.white.withOpacity(0.85),
          fontFamily: 'Nunito'),
      overflow: TextOverflow.ellipsis,
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
            borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 8),
            if (isGroup && conv != null)
              ListTile(
                leading: const Icon(Icons.settings_rounded,
                    color: AppColors.primary),
                title: const Text('Paramètres du groupe',
                    style: TextStyle(fontFamily: 'Nunito')),
                onTap: () {
                  Navigator.pop(context);
                  final groupId = conv.group?.id ?? conv.groupId;
                  if (groupId != null) {
                    context.push('/groups/$groupId/settings');
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.search_rounded,
                  color: AppColors.grey600),
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
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
              value: _uploadProgress > 0 ? _uploadProgress / 100 : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _uploadProgress > 0
                ? 'Envoi en cours... $_uploadProgress%'
                : 'Envoi en cours...',
            style: const TextStyle(
                color: AppColors.primary,
                fontFamily: 'Nunito',
                fontSize: 13,
                fontWeight: FontWeight.w600),
          ),
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
          final showDateSep = index == 0 ||
              !_isSameDay(messages[index - 1].createdAt, msg.createdAt);
          final showAvatar = !isMine &&
              isGroup &&
              (index == 0 ||
                  messages[index - 1].senderId != msg.senderId);
          final showName = !isMine &&
              isGroup &&
              (index == 0 ||
                  messages[index - 1].senderId != msg.senderId);

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
                    ? () async {
                        final success = await ref
                            .read(messagesProvider(widget.conversationId)
                                .notifier)
                            .deleteMessage(msg.id);
                        if (!success && mounted) {
                          AppModal.error(context,
                              title: 'Suppression échouée',
                              message: 'Impossible de supprimer le message.');
                        }
                      }
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
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
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
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF4A5E57),
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  /// Indicateur unifié : typing OU recording
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
            if (_otherRecording) ...[
              const Icon(Icons.mic, color: AppColors.primary, size: 14),
              const SizedBox(width: 6),
              Text(
                _otherTypingName != null && isGroup
                    ? _otherTypingName!
                    : 'Enregistrement...',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 6),
              _RecordingWave(),
            ] else ...[
              if (_otherTypingName != null)
                Text(
                  _otherTypingName!,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600),
                ),
              const SizedBox(width: 6),
              _TypingDots(),
            ],
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
        left: 6, right: 6, top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 6,
      ),
      child: _isRecording
          ? _buildRecordingBar()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
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
                                color: Color(0xFF111B21)),
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
                        IconButton(
                          icon: const Icon(Icons.attach_file_rounded,
                              color: Color(0xFF8696A0), size: 24),
                          onPressed: _showAttachmentMenu,
                          padding: const EdgeInsets.all(10),
                          constraints: const BoxConstraints(),
                        ),
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
                    width: 50, height: 50,
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
                      color: Colors.white, size: 22,
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
        GestureDetector(
          onTap: _cancelRecording,
          child: Container(
            width: 46, height: 46,
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
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(
                          0.5 + 0.5 * _recordingPulseController.value),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(timeStr,
                    style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF111B21),
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                const Text('< Glisser pour annuler',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8696A0),
                        fontFamily: 'Nunito')),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _stopAndSendRecording,
          child: Container(
            width: 50, height: 50,
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
        onPickImage: () { Navigator.pop(context); _pickImage(); },
        onPickCamera: () {
          Navigator.pop(context);
          _pickImage(source: ImageSource.camera);
        },
        onPickFile: () { Navigator.pop(context); _pickFile(); },
        onPickVideo: () { Navigator.pop(context); _pickVideo(); },
      ),
    );
  }
}

// ── Widget onde d'enregistrement ─────────────────────────────────
class _RecordingWave extends StatefulWidget {
  @override
  State<_RecordingWave> createState() => _RecordingWaveState();
}

class _RecordingWaveState extends State<_RecordingWave>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (i) {
          final h = 6.0 + ((_ctrl.value * 4 - i).clamp(0.0, 1.0)) * 10;
          return Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
}

// ── Dialog "En train d'appeler" ───────────────────────────────────
class _CallingDialog extends StatelessWidget {
  const _CallingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('Connexion en cours...',
                style: TextStyle(
                    fontFamily: 'Nunito',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey700)),
          ],
        ),
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
      width: size, height: size,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(_initials,
            style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.38,
                fontWeight: FontWeight.w700,
                fontFamily: 'Nunito')),
      ),
    );
  }
}

// ── Attachment Sheet ───────────────────────────────────────────────
class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onPickImage, onPickCamera, onPickFile, onPickVideo;

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
          color: Colors.white, borderRadius: BorderRadius.circular(24)),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(icon: Icons.insert_drive_file_rounded,
                  label: 'Document',
                  color: const Color(0xFF7B5EA7),
                  onTap: onPickFile),
              _AttachOption(icon: Icons.camera_alt_rounded,
                  label: 'Appareil photo',
                  color: const Color(0xFFFF6B6B),
                  onTap: onPickCamera),
              _AttachOption(icon: Icons.photo_library_rounded,
                  label: 'Galerie',
                  color: const Color(0xFF4ECDC4),
                  onTap: onPickImage),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _AttachOption(icon: Icons.videocam_rounded,
                  label: 'Vidéo',
                  color: const Color(0xFFFF9F43),
                  onTap: onPickVideo),
              const SizedBox(width: 80),
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
            width: 58, height: 58,
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
          Text(label,
              style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontSize: 12,
                  color: Color(0xFF4A5E57),
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
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
      builder: (_, __) {
        return Row(
          children: List.generate(3, (i) {
            final t = (_controller.value * 3 - i).clamp(0.0, 1.0);
            final opacity = t < 0.5 ? t * 2 : (1 - t) * 2;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Container(
                width: 6, height: 6,
                decoration: BoxDecoration(
                  color: const Color(0xFF8696A0)
                      .withOpacity(0.3 + 0.7 * opacity),
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
  final bool isMine, showAvatar, showName, isGroup;
  final VoidCallback? onDelete, onNameTap;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showAvatar,
    required this.showName,
    required this.isGroup,
    this.onDelete,
    this.onNameTap,
  });

  static const List<Color> _nameColors = [
    Color(0xFF1B7F4A), Color(0xFF2196F3), Color(0xFFE91E63),
    Color(0xFF9C27B0), Color(0xFFFF5722), Color(0xFF009688),
  ];

  Color _nameColor(int senderId) =>
      _nameColors[senderId % _nameColors.length];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxBubbleWidth = constraints.maxWidth * 0.78;
        return Padding(
          padding: EdgeInsets.only(
            bottom: 2,
            left: isMine ? 48 : 2,
            right: isMine ? 2 : 48,
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
                onLongPress:
                    onDelete != null ? () => _showDeleteMenu(context) : null,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isMine
                          ? const Color(0xFFDCF8C6)
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
                                      fontFamily: 'Nunito'),
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
                                      Text('Message supprimé',
                                          style: TextStyle(
                                              color: isMine
                                                  ? const Color(0xFF667781)
                                                  : const Color(0xFF8696A0),
                                              fontSize: 14,
                                              fontStyle: FontStyle.italic,
                                              fontFamily: 'Nunito')),
                                    ],
                                  )
                                : _buildContent(context, maxBubbleWidth),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                right: 8, left: 8, bottom: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Text(
                                  _formatTime(message.createdAt),
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: isMine
                                          ? const Color(0xFF667781)
                                          : const Color(0xFF8696A0),
                                      fontFamily: 'Nunito'),
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
              ),
            ],
          ),
        );
      },
    );
  }

  EdgeInsets _contentPadding() {
    if (message.isImage) return const EdgeInsets.all(3);
    return const EdgeInsets.only(left: 10, right: 10, top: 6, bottom: 2);
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Widget _buildContent(BuildContext context, double maxBubbleWidth) {
    final rawUrl = message.mediaUrl;
    String? mediaUrl;
    if (rawUrl != null && rawUrl.isNotEmpty) {
      if (rawUrl.startsWith('http')) {
        mediaUrl = rawUrl;
      } else {
        final base = AppConstants.storageBaseUrl;
        mediaUrl =
            rawUrl.startsWith('/') ? '$base$rawUrl' : '$base/$rawUrl';
      }
    }

    if (message.isImage && mediaUrl != null) {
      final imageUrl = kIsWeb ? _buildProxyUrl(mediaUrl) : mediaUrl;
      return _AuthNetworkImage(
          url: imageUrl,
          width: (maxBubbleWidth - 6).clamp(120.0, 280.0));
    }

    if (message.isAudio && mediaUrl != null) {
      final audioUrl = kIsWeb ? _buildProxyUrl(mediaUrl) : mediaUrl;
      return _AudioBubble(
          url: audioUrl,
          isMine: isMine,
          mediaName: message.mediaName,
          duration: message.mediaSize != null
              ? Duration(seconds: (message.mediaSize! / 16000).round())
              : null);
    }

    if (message.isVideo && mediaUrl != null) {
      final videoUrl = kIsWeb ? _buildProxyUrl(mediaUrl) : mediaUrl;
      final thumbWidth = (maxBubbleWidth - 6).clamp(160.0, 280.0);
      final thumbHeight = thumbWidth * 0.6;
      return GestureDetector(
        onTap: () => _openUrl(videoUrl),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: thumbWidth, height: thumbHeight,
              decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4)),
              child: const Center(
                  child: Icon(Icons.videocam_rounded,
                      color: Colors.white54, size: 52)),
            ),
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 30),
            ),
            if (message.mediaName != null)
              Positioned(
                bottom: 8, left: 8, right: 8,
                child: Text(message.mediaName!,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontFamily: 'Nunito'),
                    overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      );
    }

    if (message.isFile && mediaUrl != null) {
      final fileUrl = kIsWeb ? _buildProxyUrl(mediaUrl) : mediaUrl;
      final sizeStr = message.mediaSize != null
          ? _formatFileSize(message.mediaSize!)
          : '';
      final ext = (message.mediaName ?? '').split('.').last.toUpperCase();
      return GestureDetector(
        onTap: () => _openUrl(fileUrl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF1B7F4A).withOpacity(0.1),
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
                  Text(message.mediaName ?? 'Fichier',
                      style: const TextStyle(
                          color: Color(0xFF111B21),
                          fontFamily: 'Nunito',
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1),
                  if (sizeStr.isNotEmpty)
                    Text(sizeStr,
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8696A0),
                            fontFamily: 'Nunito')),
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

    if (message.body != null && message.body!.isNotEmpty) {
      return SelectableText(
        message.body!,
        style: const TextStyle(
            color: Color(0xFF111B21),
            fontSize: 15,
            height: 1.4,
            fontFamily: 'Nunito'),
      );
    }

    return const SizedBox.shrink();
  }

  String _buildProxyUrl(String originalUrl) {
    try {
      final uri = Uri.parse(originalUrl);
      final storagePath = uri.path.replaceFirst('/storage/', '');
      return '${AppConstants.baseUrl}/media?path=${Uri.encodeComponent(storagePath)}';
    } catch (_) {
      return originalUrl;
    }
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

  void _showDeleteMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey200,
                    borderRadius: BorderRadius.circular(2))),
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

// ── Authenticated Network Image ─────────────────────────────────────
final _imageCache = <String, Uint8List>{};

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
    if (_imageCache.containsKey(widget.url)) {
      _imageBytes = _imageCache[widget.url];
      _loading = false;
    } else {
      _fetchImage();
    }
  }

  @override
  void didUpdateWidget(_AuthNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      if (_imageCache.containsKey(widget.url)) {
        setState(() {
          _imageBytes = _imageCache[widget.url];
          _loading = false;
          _error = false;
        });
      } else {
        _fetchImage();
      }
    }
  }

  Future<void> _fetchImage() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      final uri = Uri.tryParse(widget.url);
      if (uri == null || !uri.hasScheme) throw Exception('URL invalide');
      final token = await AuthStorage.getToken();
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final response = await dio.get<List<int>>(
        widget.url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'Accept': 'image/*,*/*',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          validateStatus: (s) => s != null && s >= 200 && s < 300,
        ),
      );
      if (response.data == null || response.data!.isEmpty) {
        throw Exception('Réponse vide');
      }
      final bytes = Uint8List.fromList(response.data!);
      _imageCache[widget.url] = bytes;
      if (mounted) {
        setState(() { _imageBytes = bytes; _loading = false; _error = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * 0.65;
    if (_loading) {
      return Container(
        width: w, height: h,
        decoration: BoxDecoration(
            color: const Color(0xFFEBEBEB),
            borderRadius: BorderRadius.circular(4)),
        child: const Center(
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary)),
      );
    }
    if (_error || _imageBytes == null) {
      return GestureDetector(
        onTap: _fetchImage,
        child: Container(
          width: w, height: 140,
          decoration: BoxDecoration(
              color: const Color(0xFFEBEBEB),
              borderRadius: BorderRadius.circular(4)),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.broken_image_rounded,
                  color: AppColors.grey400, size: 36),
              SizedBox(height: 6),
              Text('Image indisponible',
                  style: TextStyle(
                      color: AppColors.grey500,
                      fontSize: 12,
                      fontFamily: 'Nunito')),
              SizedBox(height: 4),
              Text('Appuyer pour réessayer',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontFamily: 'Nunito',
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }
    return GestureDetector(
      onTap: () => _showFullImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(_imageBytes!, width: w, fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
          return GestureDetector(
            onTap: () => launchUrl(Uri.parse(widget.url),
                mode: LaunchMode.externalApplication),
            child: Container(
              width: w, height: 140,
              color: const Color(0xFFEBEBEB),
              child: const Center(
                  child: Text('Appuyer pour ouvrir',
                      style: TextStyle(
                          color: AppColors.grey400,
                          fontSize: 12,
                          fontFamily: 'Nunito'))),
            ),
          );
        }),
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
              child: Image.memory(_imageBytes!, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_rounded,
                      color: Colors.white54, size: 64)),
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
            width: 38, height: 38,
            decoration: const BoxDecoration(
                color: Color(0xFF1B7F4A), shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded,
                color: Colors.white, size: 24),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                Text(_durationStr,
                    style: TextStyle(
                        fontSize: 11,
                        color: isMine
                            ? const Color(0xFF667781)
                            : const Color(0xFF8696A0),
                        fontFamily: 'Nunito')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}