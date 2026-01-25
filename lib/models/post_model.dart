enum MediaType {
  text,
  image,
  video,
  audio,
}

class PostModel {
  final String id;
  final String userId;
  final String username;
  final String? userAvatar;
  final String? displayName;
  final String content;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final MediaType mediaType;
  int likes;
  final int comments;
  final int shares;
  final int views;
  final int saves;
  bool isLiked;
  final DateTime timestamp;
  final List<String>? hashtags;
  final List<String>? mentions;
  final String? location;
  final bool isVerified;
  final double? aspectRatio;
  final int? duration;
  final int? width;
  final int? height;
  final bool isAiGenerated;
  final String? aiPrompt;
  final String? aiModel;
  final bool isPublic;
  final bool allowComments;
  final bool allowDuets;
  final Map<String, dynamic>? user;
  final String? parentPostId; // For harmony/duet relationships
  final bool adsEnabled;
  final DateTime? monetizationEnabledAt;
  final double? viralScore;
  final Map<String, dynamic>? effects;
  final Map<String, dynamic>? aiMetadata;
  final String? musicId;

  // Getter aliases for compatibility
  int get likesCount => likes;
  int get commentsCount => comments;
  int get sharesCount => shares;
  int get viewsCount => views;
  DateTime get createdAt => timestamp;
  String get type => mediaType.toString().split('.').last;

  PostModel({
    required this.id,
    required this.userId,
    required this.username,
    this.userAvatar,
    this.displayName,
    required this.content,
    this.mediaUrl,
    this.thumbnailUrl,
    required this.mediaType,
    required this.likes,
    required this.comments,
    required this.shares,
    this.views = 0,
    this.saves = 0,
    required this.isLiked,
    required this.timestamp,
    this.hashtags,
    this.mentions,
    this.location,
    this.isVerified = false,
    this.aspectRatio,
    this.duration,
    this.width,
    this.height,
    this.isAiGenerated = false,
    this.aiPrompt,
    this.aiModel,
    this.isPublic = true,
    this.allowComments = true,
    this.allowDuets = true,
    this.user,
    this.parentPostId,
    this.adsEnabled = false,
    this.monetizationEnabledAt,
    this.viralScore,
    this.effects,
    this.aiMetadata,
    this.musicId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'username': username,
      'userAvatar': userAvatar,
      'content': content,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType.toString().split('.').last,
      'likes': likes,
      'comments': comments,
      'shares': shares,
      'isLiked': isLiked,
      'timestamp': timestamp.toIso8601String(),
      'hashtags': hashtags,
      'mentions': mentions,
      'location': location,
      'isVerified': isVerified,
      'aspectRatio': aspectRatio,
      'adsEnabled': adsEnabled,
      'monetizationEnabledAt': monetizationEnabledAt?.toIso8601String(),
      'viralScore': viralScore,
      'effects': effects,
      'aiMetadata': aiMetadata,
      'musicId': musicId,
    };
  }

  factory PostModel.fromJson(Map<String, dynamic> json) {
    // Handle user data from joined query or separate field
    final Map<String, dynamic>? userData =
        (json['user'] as Map<String, dynamic>?) ??
        (json['users'] as Map<String, dynamic>?);

    // Resolve comments count from either posts.comments_count or aggregated comments(count)
    int commentsCount = 0;
    final dynamic rawCommentsCount = json['comments_count'];
    if (rawCommentsCount is num) {
      commentsCount = rawCommentsCount.toInt();
    }

    // Also check aggregated comments(count) from joined relation
    int aggregatedCount = 0;
    final dynamic agg = json['comments'];
    if (agg is List && agg.isNotEmpty) {
      final first = agg.first;
      if (first is Map<String, dynamic>) {
        final dynamic c = first['count'];
        if (c is num) {
          aggregatedCount = c.toInt();
        }
      }
    }

    final int resolvedCommentsCount = aggregatedCount > commentsCount ? aggregatedCount : commentsCount;

    // Fallback: derive parentPostId from effects.harmony if column missing
    String? derivedParentId;
    try {
      final Map<String, dynamic>? effects = json['effects'] as Map<String, dynamic>?;
      final dynamic harmony = effects != null ? effects['harmony'] : null;
      if (harmony is Map<String, dynamic>) {
        final dynamic pid = harmony['parent_post_id'];
        if (pid is String && pid.trim().isNotEmpty) {
          derivedParentId = pid;
        }
      }
    } catch (_) {}
    final String? parentIdColumn = json['parent_post_id'] as String?;
    final String? resolvedParentId = parentIdColumn ?? derivedParentId;
    
    return PostModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      username: userData?['username'] as String? ?? json['username'] as String? ?? '',
      userAvatar: userData?['avatar_url'] as String? ?? json['avatar_url'] as String?,
      displayName: userData?['display_name'] as String? ?? json['display_name'] as String?,
      content: json['caption'] as String? ?? json['content'] as String? ?? '',
      mediaUrl: json['media_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      mediaType: _parseMediaType(json['type'] as String?),
      likes: json['likes_count'] as int? ?? 0,
      comments: resolvedCommentsCount,
      shares: json['shares_count'] as int? ?? 0,
      views: json['views_count'] as int? ?? 0,
      saves: json['saves_count'] as int? ?? 0,
      isLiked: json['is_liked'] as bool? ?? false,
      timestamp: DateTime.parse(json['created_at'] as String? ?? DateTime.now().toIso8601String()),
      hashtags: (json['hashtags'] as List<dynamic>?)?.cast<String>(),
      location: json['location'] as String?,
      isVerified: userData?['is_verified'] as bool? ?? json['is_verified'] as bool? ?? false,
      aspectRatio: json['aspect_ratio'] as double?,
      duration: json['duration'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      isAiGenerated: json['is_ai_generated'] as bool? ?? false,
      aiPrompt: json['ai_prompt'] as String?,
      aiModel: json['ai_model'] as String?,
      isPublic: json['is_public'] as bool? ?? true,
      allowComments: json['allow_comments'] as bool? ?? true,
      allowDuets: json['allow_duets'] as bool? ?? true,
      user: userData,
      parentPostId: resolvedParentId,
      adsEnabled: json['ads_enabled'] as bool? ?? false,
      monetizationEnabledAt: json['monetization_enabled_at'] != null 
          ? DateTime.parse(json['monetization_enabled_at'] as String)
          : null,
      viralScore: json['viral_score'] as double?,
      effects: json['effects'] as Map<String, dynamic>?,
      aiMetadata: (json['ai_metadata'] as Map<String, dynamic>?) ?? (json['aiMetadata'] as Map<String, dynamic>?),
      musicId: json['music_id'] as String? ?? json['musicId'] as String?,
    );
  }
  
  static MediaType _parseMediaType(String? type) {
    switch (type?.toLowerCase()) {
      case 'image':
      case 'photo':
        return MediaType.image;
      case 'video':
        return MediaType.video;
      case 'audio':
        return MediaType.audio;
      default:
        return MediaType.text;
    }
  }

  PostModel copyWith({
    String? id,
    String? userId,
    String? username,
    String? userAvatar,
    String? displayName,
    String? content,
    String? mediaUrl,
    String? thumbnailUrl,
    MediaType? mediaType,
    int? likes,
    int? comments,
    int? shares,
    int? views,
    int? saves,
    bool? isLiked,
    DateTime? timestamp,
    List<String>? hashtags,
    List<String>? mentions,
    String? location,
    bool? isVerified,
    double? aspectRatio,
    int? duration,
    int? width,
    int? height,
    bool? isAiGenerated,
    String? aiPrompt,
    String? aiModel,
    bool? isPublic,
    bool? allowComments,
    bool? allowDuets,
    Map<String, dynamic>? user,
    String? parentPostId,
    bool? adsEnabled,
    DateTime? monetizationEnabledAt,
    double? viralScore,
    Map<String, dynamic>? effects,
    Map<String, dynamic>? aiMetadata,
    String? musicId,
  }) {
    return PostModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      userAvatar: userAvatar ?? this.userAvatar,
      displayName: displayName ?? this.displayName,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      mediaType: mediaType ?? this.mediaType,
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      shares: shares ?? this.shares,
      views: views ?? this.views,
      saves: saves ?? this.saves,
      isLiked: isLiked ?? this.isLiked,
      timestamp: timestamp ?? this.timestamp,
      hashtags: hashtags ?? this.hashtags,
      mentions: mentions ?? this.mentions,
      location: location ?? this.location,
      isVerified: isVerified ?? this.isVerified,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      duration: duration ?? this.duration,
      width: width ?? this.width,
      height: height ?? this.height,
      isAiGenerated: isAiGenerated ?? this.isAiGenerated,
      aiPrompt: aiPrompt ?? this.aiPrompt,
      aiModel: aiModel ?? this.aiModel,
      isPublic: isPublic ?? this.isPublic,
      allowComments: allowComments ?? this.allowComments,
      allowDuets: allowDuets ?? this.allowDuets,
      user: user ?? this.user,
      parentPostId: parentPostId ?? this.parentPostId,
      adsEnabled: adsEnabled ?? this.adsEnabled,
      monetizationEnabledAt: monetizationEnabledAt ?? this.monetizationEnabledAt,
      viralScore: viralScore ?? this.viralScore,
      effects: effects ?? this.effects,
      aiMetadata: aiMetadata ?? this.aiMetadata,
      musicId: musicId ?? this.musicId,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PostModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'PostModel(id: $id, username: $username, content: $content, mediaType: $mediaType)';
  }

  String get formattedLikes {
    if (likes >= 1000000) {
      return '${(likes / 1000000).toStringAsFixed(1)}M';
    } else if (likes >= 1000) {
      return '${(likes / 1000).toStringAsFixed(1)}K';
    }
    return likes.toString();
  }

  String get formattedComments {
    if (comments >= 1000000) {
      return '${(comments / 1000000).toStringAsFixed(1)}M';
    } else if (comments >= 1000) {
      return '${(comments / 1000).toStringAsFixed(1)}K';
    }
    return comments.toString();
  }

  String get formattedShares {
    if (shares >= 1000000) {
      return '${(shares / 1000000).toStringAsFixed(1)}M';
    } else if (shares >= 1000) {
      return '${(shares / 1000).toStringAsFixed(1)}K';
    }
    return shares.toString();
  }

  Duration get timeAgo {
    return DateTime.now().difference(timestamp);
  }

  String get formattedTimeAgo {
    final duration = timeAgo;
    if (duration.inDays > 0) {
      return '${duration.inDays}d';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m';
    } else {
      return 'now';
    }
  }
}