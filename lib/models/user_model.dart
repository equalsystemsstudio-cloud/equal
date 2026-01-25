
class UserModel {
  final String id;
  final String username;
  final String displayName;
  final String avatarUrl;
  final String bio;
  final int postsCount;
  final bool isVerified;
  final bool isFollowing;

  const UserModel({
    required this.id,
    required this.username,
    this.displayName = '',
    this.avatarUrl = '',
    this.bio = '',
    this.postsCount = 0,
    this.isVerified = false,
    this.isFollowing = false,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id']?.toString() ?? '',
      username: map['username']?.toString() ?? '',
      displayName: map['display_name']?.toString() ?? '',
      avatarUrl: map['avatar_url']?.toString() ?? '',
      bio: map['bio']?.toString() ?? '',
      postsCount: _parseInt(map['posts_count']),
      isVerified: _parseBool(map['is_verified']),
      isFollowing: _parseBool(map['is_following']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'bio': bio,
      'posts_count': postsCount,
      'is_verified': isVerified,
      'is_following': isFollowing,
    };
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1';
    }
    if (v is num) return v != 0;
    return false;
  }
}