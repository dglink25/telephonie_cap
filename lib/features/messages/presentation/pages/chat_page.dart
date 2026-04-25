import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../../core/api/api_client.dart';
import '../../../../core/theme/app_theme.dart';
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
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isTyping = false;
  bool _otherTyping = false;
  String? _otherTypingName;
  ConversationModel? _conversation;

  @override
  void initState() {
    super.initState();
    _loadConversation();
    _markRead();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels == _scrollController.position.maxScrollExtent) {
        ref.read(messagesProvider(widget.conversationId).notifier).loadMore();
      }
    });

    _textController.addListener(() {
      final typing = _textController.text.isNotEmpty;
      if (typing != _isTyping) {
        _isTyping = typing;
        ref.read(messagesProvider(widget.conversationId).notifier).sendTyping(typing);
      }
    });
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
      ref.read(conversationsProvider.notifier).markRead(widget.conversationId);
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textController.clear();
    await ref.read(messagesProvider(widget.conversationId).notifier).sendText(text);
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

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messagesProvider(widget.conversationId));
    final currentUser = ref.watch(currentUserProvider);
    final conv = _conversation;
    final displayName = conv?.getDisplayName(currentUser?.id ?? 0) ?? 'Conversation';
    final other = conv?.getOtherParticipant(currentUser?.id ?? 0);

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
                child: Text('Erreur: $e',
                    style: const TextStyle(color: AppColors.grey500)),
              ),
              data: (messages) => _buildMessageList(messages, currentUser?.id ?? 0),
            ),
          ),

          // Typing indicator
          if (_otherTyping)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              alignment: Alignment.centerLeft,
              child: Text(
                '$_otherTypingName est en train d\'écrire...',
                style: const TextStyle(
                  color: AppColors.grey400,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  fontFamily: 'Nunito',
                ),
              ),
            ),

          _buildInputArea(),
        ],
      ),
    );
  }

  AppBar _buildAppBar(String name, UserModel? other, ConversationModel? conv) {
    return AppBar(
      backgroundColor: AppColors.white,
      titleSpacing: 0,
      title: Row(
        children: [
          if (conv?.isGroup == true)
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
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
          onPressed: () => _initiateCall('audio'),
        ),
        IconButton(
          icon: const Icon(Icons.videocam_outlined),
          onPressed: () => _initiateCall('video'),
        ),
        IconButton(
          icon: const Icon(Icons.more_vert_rounded),
          onPressed: () {},
        ),
      ],
    );
  }

  Future<void> _initiateCall(String type) async {
    try {
      final response = await ApiClient().initiateCall(widget.conversationId, type);
      final call = CallModel.fromJson(response.data);
      if (mounted) context.push('/calls/${call.id}', extra: call);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de démarrer l\'appel')),
        );
      }
    }
  }

  Widget _buildMessageList(List<MessageModel> messages, int currentUserId) {
    if (messages.isEmpty) {
      return const Center(
        child: Text(
          'Envoyez votre premier message !',
          style: TextStyle(color: AppColors.grey400, fontFamily: 'Nunito'),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        final isMine = message.senderId == currentUserId;
        final prevMsg = index > 0 ? messages[index - 1] : null;
        final showAvatar = !isMine &&
            (prevMsg == null || prevMsg.senderId != message.senderId);

        return _MessageBubble(
          message: message,
          isMine: isMine,
          showAvatar: showAvatar,
          onDelete: isMine
              ? () => ref
                  .read(messagesProvider(widget.conversationId).notifier)
                  .deleteMessage(message.id)
              : null,
        );
      },
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
            icon: const Icon(Icons.attach_file_rounded, color: AppColors.grey400),
            onPressed: () {},
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
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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

// ─── Message Bubble ──────────────────────────────────────────
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
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            showAvatar
                ? AvatarWidget(name: message.sender?.fullName ?? '?', size: 30)
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
                color: isMine ? AppColors.bubbleSent : AppColors.bubbleReceived,
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
                    if (message.body != null)
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
              leading: const Icon(Icons.delete_outline_rounded, color: AppColors.error),
              title: const Text('Supprimer le message',
                  style: TextStyle(color: AppColors.error, fontFamily: 'Nunito')),
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