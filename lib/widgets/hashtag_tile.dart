import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HashtagTile extends StatelessWidget {
  final String hashtag;
  final int postCount;
  final VoidCallback? onTap;
  final EdgeInsets? padding;
  final bool showTrending;

  const HashtagTile({
    super.key,
    required this.hashtag,
    required this.postCount,
    this.onTap,
    this.padding,
    this.showTrending = false,
  });

  String get formattedHashtag {
    return hashtag.startsWith('#') ? hashtag : '#$hashtag';
  }

  String get formattedPostCount {
    if (postCount >= 1000000) {
      return '${(postCount / 1000000).toStringAsFixed(1)}M posts';
    } else if (postCount >= 1000) {
      return '${(postCount / 1000).toStringAsFixed(1)}K posts';
    } else {
      return '$postCount posts';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: padding ?? const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        child: Row(
          children: [
            // Hashtag icon
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.blue.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.tag,
                color: Colors.blue,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            
            // Hashtag info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          formattedHashtag,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showTrending) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            'Trending',
                            style: GoogleFonts.poppins(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formattedPostCount,
                    style: GoogleFonts.poppins(
                      color: Colors.grey[400],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            
            // Arrow icon
            Icon(
              Icons.arrow_forward_ios,
              color: Colors.grey[600],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

// Hashtag model for data structure
class HashtagModel {
  final String tag;
  final int postCount;
  final bool isTrending;
  final DateTime? lastUsed;

  const HashtagModel({
    required this.tag,
    required this.postCount,
    this.isTrending = false,
    this.lastUsed,
  });

  factory HashtagModel.fromJson(Map<String, dynamic> json) {
    return HashtagModel(
      tag: json['tag'] ?? '',
      postCount: json['post_count'] ?? 0,
      isTrending: json['is_trending'] ?? false,
      lastUsed: json['last_used'] != null 
          ? DateTime.parse(json['last_used'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tag': tag,
      'post_count': postCount,
      'is_trending': isTrending,
      'last_used': lastUsed?.toIso8601String(),
    };
  }
}
