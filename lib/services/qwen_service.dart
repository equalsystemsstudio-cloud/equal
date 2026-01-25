import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class QwenService {
  static final QwenService _instance = QwenService._internal();
  factory QwenService() => _instance;
  QwenService._internal();

  // Qwen API configuration
  static const String baseUrl = 'https://dashscope.aliyuncs.com/api/v1';
  static const String model = 'qwen-turbo';
  
  // Note: API key should be set from environment or secure storage
  String? _apiKey;
  
  late final http.Client _client;

  // Initialize the service with API key
  Future<void> initialize({String? apiKey}) async {
    _client = http.Client();
    _apiKey = apiKey;
    
    if (kDebugMode) {
      debugPrint('Qwen service initialized');
    }
  }

  // Set API key (should be called with secure key)
  void setApiKey(String apiKey) {
    _apiKey = apiKey;
  }

  // Generate text content
  Future<Map<String, dynamic>> generateText({
    required String prompt,
    int maxTokens = 1000,
    double temperature = 0.7,
    String? systemMessage,
  }) async {
    if (_apiKey == null) {
      return {
        'success': false,
        'error': 'API key not set. Please configure Qwen API key.',
      };
    }

    try {
      final messages = <Map<String, String>>[
        if (systemMessage != null)
          {'role': 'system', 'content': systemMessage},
        {'role': 'user', 'content': prompt},
      ];

      final response = await _client.post(
        Uri.parse('$baseUrl/services/aigc/text-generation/generation'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'input': {
            'messages': messages,
          },
          'parameters': {
            'max_tokens': maxTokens,
            'temperature': temperature,
            'top_p': 0.8,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['output'] != null && data['output']['text'] != null) {
          return {
            'success': true,
            'text': data['output']['text'] as String,
            'usage': data['usage'] ?? {},
          };
        } else {
          throw Exception('Invalid response format from Qwen API');
        }
      } else {
        throw Exception('Qwen API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error generating text: $e');
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // Generate social media post content
  Future<Map<String, dynamic>> generatePostContent({
    required String topic,
    String platform = 'general',
    String tone = 'casual',
    int maxLength = 280,
  }) async {
    final systemMessage = '''
You are a creative social media content creator. Generate engaging, authentic posts that:
- Are appropriate for $platform
- Have a $tone tone
- Are under $maxLength characters
- Include relevant hashtags
- Are engaging and shareable
''';

    final prompt = '''
Create a social media post about: $topic

Requirements:
- Platform: $platform
- Tone: $tone
- Max length: $maxLength characters
- Include 2-3 relevant hashtags
- Make it engaging and authentic
''';

    return await generateText(
      prompt: prompt,
      systemMessage: systemMessage,
      maxTokens: 200,
      temperature: 0.8,
    );
  }

  // Generate image captions
  Future<Map<String, dynamic>> generateImageCaption({
    required String imageDescription,
    String style = 'creative',
  }) async {
    final systemMessage = '''
You are an expert at writing engaging image captions for social media. Create captions that:
- Are $style in style
- Complement the image content
- Include relevant hashtags
- Encourage engagement
- Are concise but impactful
''';

    final prompt = '''
Write a caption for an image that shows: $imageDescription

Style: $style
Include 2-3 relevant hashtags.
Make it engaging and encourage comments or likes.
''';

    return await generateText(
      prompt: prompt,
      systemMessage: systemMessage,
      maxTokens: 150,
      temperature: 0.8,
    );
  }

  // Generate hashtags for content
  Future<Map<String, dynamic>> generateHashtags({
    required String content,
    int count = 5,
    String category = 'general',
  }) async {
    final prompt = '''
Generate $count relevant hashtags for this content:
"$content"

Category: $category

Requirements:
- Mix of popular and niche hashtags
- Relevant to the content and category
- Include trending hashtags when appropriate
- Format as a simple list without explanations
''';

    return await generateText(
      prompt: prompt,
      maxTokens: 100,
      temperature: 0.6,
    );
  }

  // Improve existing content
  Future<Map<String, dynamic>> improveContent({
    required String originalContent,
    String improvementType = 'engagement',
  }) async {
    final systemMessage = '''
You are a social media expert. Improve the given content by:
- Enhancing $improvementType
- Maintaining the original message
- Making it more compelling
- Optimizing for social media
''';

    final prompt = '''
Improve this social media content:
"$originalContent"

Focus on: $improvementType

Make it more engaging while keeping the core message intact.
''';

    return await generateText(
      prompt: prompt,
      systemMessage: systemMessage,
      maxTokens: 300,
      temperature: 0.7,
    );
  }

  // Generate content ideas
  Future<Map<String, dynamic>> generateContentIdeas({
    required String niche,
    int count = 5,
    String contentType = 'posts',
  }) async {
    final prompt = '''
Generate $count creative $contentType ideas for the $niche niche.

Requirements:
- Each idea should be unique and engaging
- Suitable for social media
- Include brief descriptions
- Focus on trending topics when relevant
- Make them actionable

Format as a numbered list with brief descriptions.
''';

    return await generateText(
      prompt: prompt,
      maxTokens: 400,
      temperature: 0.8,
    );
  }

  // Generate video script
  Future<Map<String, dynamic>> generateVideoScript({
    required String topic,
    int durationSeconds = 60,
    String style = 'educational',
  }) async {
    final systemMessage = '''
You are a video script writer. Create engaging scripts that:
- Are appropriate for $durationSeconds second videos
- Have a $style style
- Include clear structure (hook, content, call-to-action)
- Are optimized for social media
- Include timing cues
''';

    final prompt = '''
Write a $durationSeconds-second video script about: $topic

Style: $style

Structure:
- Hook (0-5 seconds)
- Main content (5-50 seconds)
- Call-to-action (50-60 seconds)

Include timing cues and engagement elements.
''';

    return await generateText(
      prompt: prompt,
      systemMessage: systemMessage,
      maxTokens: 500,
      temperature: 0.7,
    );
  }

  // Analyze content sentiment
  Future<Map<String, dynamic>> analyzeContentSentiment({
    required String content,
  }) async {
    final prompt = '''
Analyze the sentiment and tone of this content:
"$content"

Provide:
1. Overall sentiment (positive/negative/neutral)
2. Tone description
3. Emotional impact score (1-10)
4. Suggestions for improvement if needed

Be concise and actionable.
''';

    return await generateText(
      prompt: prompt,
      maxTokens: 200,
      temperature: 0.3,
    );
  }

  // Generate trending topic suggestions
  Future<Map<String, dynamic>> getTrendingSuggestions({
    required String industry,
    String region = 'global',
  }) async {
    final prompt = '''
Suggest 5 trending topics for content creation in the $industry industry.

Region: $region

For each topic, provide:
- Topic name
- Why it's trending
- Content angle suggestion
- Potential hashtags

Focus on current and emerging trends.
''';

    return await generateText(
      prompt: prompt,
      maxTokens: 400,
      temperature: 0.7,
    );
  }

  // Dispose resources
  void dispose() {
    _client.close();
  }
}

// Content generation models
class ContentSuggestion {
  final String title;
  final String description;
  final List<String> hashtags;
  final String category;
  final DateTime createdAt;

  ContentSuggestion({
    required this.title,
    required this.description,
    required this.hashtags,
    required this.category,
    required this.createdAt,
  });

  factory ContentSuggestion.fromJson(Map<String, dynamic> json) {
    return ContentSuggestion(
      title: json['title'] as String,
      description: json['description'] as String,
      hashtags: List<String>.from(json['hashtags'] as List),
      category: json['category'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'description': description,
      'hashtags': hashtags,
      'category': category,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

class GeneratedContent {
  final String content;
  final List<String> hashtags;
  final String tone;
  final double confidenceScore;
  final Map<String, dynamic>? metadata;

  GeneratedContent({
    required this.content,
    required this.hashtags,
    required this.tone,
    required this.confidenceScore,
    this.metadata,
  });

  factory GeneratedContent.fromQwenResponse(Map<String, dynamic> response) {
    final content = response['text'] as String? ?? '';
    
    // Extract hashtags from content
    final hashtagRegex = RegExp(r'#\w+');
    final hashtags = hashtagRegex
        .allMatches(content)
        .map((match) => match.group(0) ?? '')
        .toList();

    return GeneratedContent(
      content: content,
      hashtags: hashtags,
      tone: 'generated',
      confidenceScore: 0.8,
      metadata: response['usage'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'hashtags': hashtags,
      'tone': tone,
      'confidence_score': confidenceScore,
      if (metadata != null) 'metadata': metadata,
    };
  }
}