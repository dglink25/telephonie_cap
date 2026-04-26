import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/api/api_client.dart';
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

class _ChatPageState extends ConsumerState<ChatPage> {
  final _textController  = TextEditingController();
  final _scrollController = ScrollController();
  final _ws = WebSocketService();
  final _callService = CallService();

  bool _isTyping      = false;
  bool _otherTyping   = false;
  String? _otherTypingName;
  ConversationModel? _conversation;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    _loadConversation();
    _markRead();
    _subscribeToWebSocket();

    // Charger plus de messages au scroll vers le haut
    _scrollController.addListener(() {
      if (_scrollController.position.pixels <= 50) {
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
        // Auto-arrêt indicateur frappe après 3s d'inactivité
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
      // Nouveau message reçu
      'message.sent': (data) {
        if (!mounted) return;
        final msg = MessageModel.fromJson(data);
        // Ne pas ajouter si c'est notre propre message (déjà ajouté localement)
        if (msg.senderId != currentUser?.id) {
          ref
              .read(messagesProvider(widget.conversationId).notifier)
              .addMessage(msg);
          _markRead();
          _scrollToBottom();
        }
        // Mettre à jour la liste des conversations
        ref.read(conversationsProvider.notifier).load();
      },

      // Indicateur de frappe
      'user.typing': (data) {
        if (!mounted) return;
        final userId   = data['user_id'] as int?;
        final isTyping = data['is_typing'] as bool? ?? false;
        final name     = data['full_name'] as String? ?? '';

        if (userId != currentUser?.id) {
          setState(() {
            _otherTyping     = isTyping;
            _otherTypingName = name;
          });

          // Auto-reset après 4s (sécurité)
          if (isTyping) {
            Future.delayed(const Duration(seconds: 4), () {
              if (mounted && _otherTyping) {
                setState(() => _otherTyping = false);
              }
            });
          }
        }
      },

      // Appel initié dans cette conversation
      'call.initiated': (data) {
        if (!mounted) return;
        final callerId = data['caller_id'] as int?;
        if (callerId == currentUser?.id) return; // Ignoré si on est l'appelant

        final call = CallModel.fromJson(data);
        context.push('/calls/${call.id}', extra: call);
      },

      // Mise à jour statut appel
      'call.status.updated': (data) {
        _callService.onCallStatusChanged?.call(data['status'] as String);
      },

      // Signal WebRTC
      'call.signal': (data) {
        final senderId = data['sender_id'] as int?;
        if (senderId != currentUser?.id) {
          // Déléguer au CallService
         // _callService.onCallSignalReceived(data);
        }
      },
    });

    // Également écouter les appels entrants sur le canal utilisateur
    _callService.listenToConversation(widget.conversationId);
  }

  Future<void> _loadConversation() async {
    try {
      final response = await ApiClient().getConversation(widget.conversationId);
      if (mounted) {
        setState(() {
          _conversation = ConversationModel.fromJson(response.data);
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

    await ref
        .read(messagesProvider(widget.conversationId).notifier)
        .sendText(text);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Appel ─────────────────────────────────────────────────────
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de démarrer l\'appel')),
      );
    }
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _ws.unsubscribeFromConversation(widget.conversationId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));
    final currentUser   = ref.watch(currentUserProvider);
    final conv          = _conversation;
    final displayName   = conv?.getDisplayName(currentUser?.id ?? 0) ?? 'Conversation';
    final other         = conv?.getOtherParticipant(currentUser?.id ?? 0);

    return Scaffold(
      backgroundColor: AppColors.background,
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
                    const Icon(Icons.error_outline,
                        color: AppColors.grey300, size: 48),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => ref
                          .read(messagesProvider(widget.conversationId).notifier)
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
          if (_otherTyping) _buildTypingIndicator(),
          _buildInputArea(),
        ],
      ),
    );
  }

  AppBar _buildAppBar(String name, UserModel? other, ConversationModel? conv) {
    return AppBar(
      backgroundColor: AppColors.white,
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppColors.grey700, size: 20),
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          if (conv?.isGroup == true)
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  conv?.group?.initials ?? 'G',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    fontFamily: 'Nunito',
                  ),
                ),
              ),
            )
          else
            AvatarWidget(name: other?.fullName ?? name, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.grey800,
                    fontFamily: 'Nunito',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (conv?.isGroup == true)
                  Text(
                    '${conv?.participants.length ?? 0} membres',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontFamily: 'Nunito',
                    ),
                  )
                else if (other?.phoneNumber != null)
                  Text(
                    other!.phoneNumber!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.grey400,
                      fontFamily: 'Nunito',
                    ),
                  )
                else
                  const Text(
                    'En ligne',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.online,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Nunito',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.call_outlined),
          color: AppColors.grey700,
          onPressed: () => _initiateCall('audio'),
          tooltip: 'Appel audio',
        ),
        if (conv?.isGroup == false)
          IconButton(
            icon: const Icon(Icons.videocam_outlined),
            color: AppColors.grey700,
            onPressed: () => _initiateCall('video'),
            tooltip: 'Appel vidéo',
          ),
      ],
    );
  }

  Widget _buildMessageList(List<MessageModel> messages, int currentUserId) {
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
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline_rounded,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 12),
            const Text(
              'Commencez la conversation !',
              style: TextStyle(
                color: AppColors.grey400,
                fontFamily: 'Nunito',
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg     = messages[index];
        final isMine  = msg.senderId == currentUserId;
        final showAvatar = !isMine &&
            (index == 0 ||
                messages[index - 1].senderId != msg.senderId);

        return _MessageBubble(
          message:    msg,
          isMine:     isMine,
          showAvatar: showAvatar,
          onDelete:   isMine
              ? () => ref
                    .read(messagesProvider(widget.conversationId).notifier)
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
      child: Row(
        children: [
          const SizedBox(width: 4),
          Text(
            '${_otherTypingName ?? ''} est en train d\'écrire',
            style: const TextStyle(
              color: AppColors.grey400,
              fontSize: 12,
              fontStyle: FontStyle.italic,
              fontFamily: 'Nunito',
            ),
          ),
          const SizedBox(width: 6),
          _TypingDots(),
        ],
      ),
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
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.attach_file_rounded,
                color: AppColors.grey400),
            onPressed: () {}, // TODO: file picker
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
                  color: AppColors.grey800,
                ),
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
          const SizedBox(width: 8),
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
                    color: hasText ? AppColors.primary : AppColors.grey200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: hasText ? Colors.white : AppColors.grey400,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Indicateur points de frappe animés ─────────────────────────────
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
            final opacity = (((_controller.value * 3) - i).clamp(0.0, 1.0));
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.grey400,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Message Bubble ───────────────────────────────────────────────
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
            onLongPress: onDelete != null ? () => _showMenu(context) : null,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMine && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        message.sender?.fullName ?? '',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Nunito',
                        ),
                      ),
                    ),
                  if (message.isDeleted)
                    Text(
                      'Message supprimé',
                      style: TextStyle(
                        color: isMine
                            ? Colors.white.withOpacity(0.6)
                            : AppColors.grey400,
                        fontSize: 14,
                        fontStyle: FontStyle.italic,
                        fontFamily: 'Nunito',
                      ),
                    )
                  else ...[
                    if (message.isImage && message.mediaUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          message.mediaUrl!,
                          width: 220,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image),
                        ),
                      ),
                    if (message.isFile)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.attach_file_rounded,
                              color: AppColors.primary, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              message.mediaName ?? 'Fichier',
                              style: TextStyle(
                                color: isMine
                                    ? Colors.white
                                    : AppColors.grey800,
                                fontFamily: 'Nunito',
                                fontSize: 14,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    if (message.body != null && message.body!.isNotEmpty)
                      Text(
                        message.body!,
                        style: TextStyle(
                          color: isMine
                              ? AppColors.bubbleSentText
                              : AppColors.bubbleReceivedText,
                          fontSize: 15,
                          height: 1.4,
                          fontFamily: 'Nunito',
                        ),
                      ),
                  ],
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
                        fontFamily: 'Nunito',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error),
              title: const Text(
                'Supprimer le message',
                style: TextStyle(color: AppColors.error, fontFamily: 'Nunito'),
              ),
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