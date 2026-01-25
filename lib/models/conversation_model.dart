import 'package:timeago/timeago.dart' as timeago;
import '../services/localization_service.dart';

class ConversationModel {
  final String id;
  final String participant1Id;
  final String participant2Id;
  final String? lastMessageId;
  final DateTime? lastMessageAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, dynamic>? participant1Info;
  final Map<String, dynamic>? participant2Info;
  final Map<String, dynamic>? lastMessageInfo;

  ConversationModel({
    required this.id,
    required this.participant1Id,
    required this.participant2Id,
    this.lastMessageId,
    this.lastMessageAt,
    required this.createdAt,
    required this.updatedAt,
    this.participant1Info,
    this.participant2Info,
    this.lastMessageInfo,
  });

  factory ConversationModel.fromJson(Map<String, dynamic> json) {
    return ConversationModel(
      id: json['id'] ?? '',
      participant1Id: json['participant_1_id'] ?? '',
      participant2Id: json['participant_2_id'] ?? '',
      lastMessageId: json['last_message_id'],
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'])
          : null,
      createdAt: DateTime.parse(
        json['created_at'] ?? DateTime.now().toIso8601String(),
      ),
      updatedAt: DateTime.parse(
        json['updated_at'] ?? DateTime.now().toIso8601String(),
      ),
      participant1Info: json['participant_1'],
      participant2Info: json['participant_2'],
      lastMessageInfo: json['last_message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'participant_1_id': participant1Id,
      'participant_2_id': participant2Id,
      'last_message_id': lastMessageId,
      'last_message_at': lastMessageAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  ConversationModel copyWith({
    String? id,
    String? participant1Id,
    String? participant2Id,
    String? lastMessageId,
    DateTime? lastMessageAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Map<String, dynamic>? participant1Info,
    Map<String, dynamic>? participant2Info,
    Map<String, dynamic>? lastMessageInfo,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      participant1Id: participant1Id ?? this.participant1Id,
      participant2Id: participant2Id ?? this.participant2Id,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      participant1Info: participant1Info ?? this.participant1Info,
      participant2Info: participant2Info ?? this.participant2Info,
      lastMessageInfo: lastMessageInfo ?? this.lastMessageInfo,
    );
  }

  // Helper methods
  Map<String, dynamic>? getOtherParticipant(String currentUserId) {
    if (participant1Id == currentUserId) {
      return participant2Info;
    } else if (participant2Id == currentUserId) {
      return participant1Info;
    }
    return null;
  }

  String getOtherParticipantId(String currentUserId) {
    if (participant1Id == currentUserId) {
      return participant2Id;
    } else if (participant2Id == currentUserId) {
      return participant1Id;
    }
    return '';
  }

  String getOtherParticipantName(String currentUserId) {
    final otherParticipant = getOtherParticipant(currentUserId);
    final displayName =
        (otherParticipant?['display_name'] as String?)?.trim() ?? '';
    if (displayName.isNotEmpty) {
      return displayName;
    }
    final username = (otherParticipant?['username'] as String?)?.trim() ?? '';
    return username.isNotEmpty ? '@$username' : 'Unknown User';
  }

  String getOtherParticipantUsername(String currentUserId) {
    final otherParticipant = getOtherParticipant(currentUserId);
    return (otherParticipant?['username'] as String?) ?? '';
  }

  String? getOtherParticipantAvatar(String currentUserId) {
    final otherParticipant = getOtherParticipant(currentUserId);
    return otherParticipant?['avatar_url'];
  }

  String get lastMessageContent {
    if (lastMessageInfo == null)
      return LocalizationService.t('no_messages_yet');

    final mediaType = lastMessageInfo!['media_type'] ?? 'text';
    final content = (lastMessageInfo!['content'] ?? '').toString();

    switch (mediaType) {
      case 'voice':
        return '🎵 ${LocalizationService.t('voice_message')}';
      case 'image':
        return '📷 ${LocalizationService.t('photo')}';
      case 'video':
        return '🎥 ${LocalizationService.t('video')}';
      default:
        return content.isEmpty ? LocalizationService.t('message') : content;
    }
  }

  String get timeAgo {
    if (lastMessageAt == null) return '';
    return timeago.format(
      lastMessageAt!,
      locale: LocalizationService.resolveTimeagoLocale(
        LocalizationService.currentLanguage,
      ),
    );
  }

  bool get hasLastMessage => lastMessageInfo != null;

  bool isParticipant(String userId) {
    return participant1Id == userId || participant2Id == userId;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConversationModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'ConversationModel(id: $id, participant1Id: $participant1Id, participant2Id: $participant2Id, lastMessageAt: $lastMessageAt)';
  }
}
