import 'package:flutter/material.dart';
import '../../models/message_model.dart';
import 'voice_note_widget.dart';
import '../../config/app_colors.dart';

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool showAvatar;
  final String? otherUserAvatar;
  final Function(String) onPlayVoice;
  final VoidCallback onStopVoice;
  final bool otherUserOnline;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.showAvatar,
    this.otherUserAvatar,
    required this.onPlayVoice,
    required this.onStopVoice,
    required this.otherUserOnline,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            SizedBox(
              width: 32,
              child: showAvatar
                  ? CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.surfaceVariant,
                      backgroundImage: otherUserAvatar != null
                          ? NetworkImage(otherUserAvatar!)
                          : null,
                      child: otherUserAvatar == null
                          ? Text(
                              message.senderName.isNotEmpty
                                  ? message.senderName[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            )
                          : null,
                    )
                  : const SizedBox(),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.7,
              ),
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: message.isVoiceMessage
                        ? const EdgeInsets.all(8)
                        : const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary : AppColors.surfaceVariant,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isMe ? 18 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 18),
                      ),
                    ),
                    child: GestureDetector(
                      onLongPress: onLongPress,
                      child: _buildMessageContent(),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      message.formattedTime,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              child: Icon(
                message.isRead
                    ? Icons.done_all
                    : (otherUserOnline ? Icons.done_all : Icons.done),
                size: 16,
                color: message.isRead
                    ? (Color.lerp(AppColors.follow, AppColors.share, 0.5) ?? AppColors.primary)
                    : AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageContent() {
    if (message.isVoiceMessage) {
      return VoiceNoteWidget(
        message: message,
        isMe: isMe,
        onPlay: () => onPlayVoice(message.mediaUrl!),
        onStop: onStopVoice,
      );
    }

    if (message.isImageMessage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              message.mediaUrl!,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 200,
                  height: 200,
                  color: AppColors.surfaceVariant,
                  child: const Icon(
                    Icons.broken_image,
                    color: AppColors.textSecondary,
                    size: 50,
                  ),
                );
              },
            ),
          ),
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.content,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ],
        ],
      );
    }

    if (message.isVideoMessage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 200,
                  height: 200,
                  color: AppColors.overlay,
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill,
                      color: AppColors.textPrimary,
                      size: 50,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (message.content.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              message.content,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ],
        ],
      );
    }

    return Text(
      message.content,
      style: TextStyle(
        color: isMe ? Colors.white : AppColors.textPrimary,
        fontSize: 16,
      ),
    );
  }
}