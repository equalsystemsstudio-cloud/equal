import 'dart:convert';
import 'package:flutter/material.dart';

enum StatusType { text, image, video, audio }

class StatusModel {
  final String id;
  final String userId;
  final String? username;
  final String? displayName;
  final String? userAvatar;
  final StatusType type;
  final String? text;
  final String? mediaUrl;
  final String? thumbnailUrl;
  final Color? backgroundColor;
  final DateTime createdAt;
  final DateTime expiresAt;
  final Map<String, dynamic>? effects;

  StatusModel({
    required this.id,
    required this.userId,
    this.username,
    this.displayName,
    this.userAvatar,
    required this.type,
    this.text,
    this.mediaUrl,
    this.thumbnailUrl,
    this.backgroundColor,
    required this.createdAt,
    required this.expiresAt,
    this.effects,
  });

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  factory StatusModel.fromMap(Map<String, dynamic> map) {
    final bgColorHex = map['bg_color'] as String?;
    Color? bgColor;
    if (bgColorHex != null && bgColorHex.isNotEmpty) {
      // Expect hex like #RRGGBB or #AARRGGBB
      final hex = bgColorHex.replaceAll('#', '');
      final value = int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16);
      bgColor = Color(value);
    }

    Map<String, dynamic>? parsedEffects;
    final rawEffects = map['effects'];
    if (rawEffects is Map) {
      parsedEffects = Map<String, dynamic>.from(rawEffects);
    } else if (rawEffects is String && rawEffects.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawEffects);
        if (decoded is Map<String, dynamic>) {
          parsedEffects = decoded;
        }
      } catch (_) {}
    }

    return StatusModel(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      username: map['username'] as String?,
      displayName: map['display_name'] as String?,
      userAvatar: map['avatar_url'] as String?,
      type: _parseType(map['type']?.toString()),
      text: map['text_content'] as String?,
      mediaUrl: map['media_url'] as String?,
      thumbnailUrl: map['thumbnail_url'] as String?,
      backgroundColor: bgColor,
      createdAt: DateTime.parse(map['created_at'] as String),
      expiresAt: DateTime.parse(map['expires_at'] as String),
      effects: parsedEffects,
    );
  }

  static StatusType _parseType(String? v) {
    switch (v) {
      case 'image':
        return StatusType.image;
      case 'video':
        return StatusType.video;
      case 'audio':
        return StatusType.audio;
      case 'text':
      default:
        return StatusType.text;
    }
  }
}