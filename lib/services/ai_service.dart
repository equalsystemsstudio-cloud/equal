import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../config/api_config.dart';
import '../config/supabase_config.dart';
import 'analytics_service.dart';
import 'preferences_service.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  final AnalyticsService _analyticsService = AnalyticsService();
  final PreferencesService _preferencesService = PreferencesService();
  late final http.Client _client;
  String? _apiKey;
  bool _isInitialized = false;

  // Qwen API configuration
  static const String _qwenBaseUrl = 'https://dashscope.aliyuncs.com/api/v1';
  static const String _qwenCompatibleUrl = 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1';
  static const String _imageEndpoint = '/images/generations';
  static const String _textEndpoint = '/services/aigc/text-generation/generation';
  static const String _audioEndpoint = '/services/aigc/text2speech/synthesis';
  
  // Hugging Face API configuration (Free alternative)
  static const String _huggingFaceBaseUrl = 'https://router.huggingface.co/hf-inference/models';
  
  // Rate limiting for free tier
  static DateTime? _lastHuggingFaceRequest;
  
  // Model configurations
  static const String _imageModel = 'flux-schnell'; // Qwen's FLUX model
  static const String _textModel = 'qwen-turbo';
  static const String _audioModel = 'cosyvoice-v1';

  // Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _client = http.Client();
    await _loadApiKey();
    _isInitialized = true;
    
    if (kDebugMode) {
      debugPrint(('AI Service initialized with Qwen integration').toString());
    }
  }

  // Load API key from secure storage
  Future<void> _loadApiKey() async {
    try {
      _apiKey = await _preferencesService.getQwenApiKey();
      
      // Fallback to hardcoded key for development (should be removed in production)
      if (_apiKey == null || _apiKey!.isEmpty) {
        _apiKey = 'sk-5ea80c497de74cb8afbab22858bbf0a3';
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error loading API key: $e').toString());
      }
    }
  }

  // Set API key and save to secure storage
  Future<void> setApiKey(String apiKey) async {
    _apiKey = apiKey;
    try {
      await _preferencesService.setQwenApiKey(apiKey);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(('Error saving API key: $e').toString());
      }
    }
  }

  // Validate API key format
  bool validateApiKey(String apiKey) {
    if (apiKey.isEmpty) return false;
    if (apiKey == 'YOUR_QWEN_API_KEY_HERE') return false;
    // Basic validation - Qwen API keys typically start with 'sk-'
    return apiKey.startsWith('sk-') && apiKey.length > 10;
  }

  // Get current API key
  Future<String> getApiKey() async {
    if (_apiKey == null) {
      await _loadApiKey();
    }
    return _apiKey ?? '';
  }

  // Getter for base URL compatibility
  String get _baseUrl => _qwenCompatibleUrl;

  // Check if Qwen service is properly configured
  bool isConfigured() {
    final configured = _apiKey != null && 
           _apiKey!.isNotEmpty && 
           _apiKey != 'YOUR_QWEN_API_KEY_HERE' &&
           _apiKey != 'sk-5ea80c497de74cb8afbab22858bbf0a3'; // Remove hardcoded key check in production
    
    if (kDebugMode) {
      debugPrint(('AIService.isConfigured(): $_apiKey -> $configured').toString());
    }
    
    return configured;
  }

  // MARK: - Image Generation
  
  /// Generate image using AI with automatic fallback
  Future<dynamic> generateImage({
    required String prompt,
    String size = '1024x1024',
    String style = 'realistic',
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for image generation (premium)').toString());
      }
      return await _generateImageWithQwen(prompt, size, style, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for image generation (free)').toString());
      }
      return await _generateImageWithHuggingFace(prompt, size, style, onProgress);
    }
  }

  /// Generate image using Qwen's FLUX model (Premium)
  Future<dynamic> _generateImageWithQwen(
    String prompt,
    String size,
    String style,
    Function(double)? onProgress,
  ) async {

    try {
      if (kDebugMode) {
        debugPrint(('Starting Qwen AI image generation with prompt: $prompt').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_image_generation_qwen',
        properties: {
          'prompt_length': prompt.length,
          'model': _imageModel,
          'size': size,
          'style': style,
        },
      );

      onProgress?.call(0.1);

      final enhancedPrompt = _enhanceImagePrompt(prompt, style);
      
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      };

      final body = {
        'model': _imageModel,
        'prompt': enhancedPrompt,
        'n': 1,
        'size': size,
        'response_format': 'url',
      };

      onProgress?.call(0.3);

      final response = await _client
          .post(
            Uri.parse('$_qwenCompatibleUrl$_imageEndpoint'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 120));

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final imageUrl = responseData['data'][0]['url'] as String;

        if (kDebugMode) {
          debugPrint(('Qwen image generated successfully: $imageUrl').toString());
        }

        final imageData = await _downloadImage(imageUrl, onProgress);

        await _analyticsService.trackFeatureUsed(
          'ai_image_generation_qwen_success',
          properties: {
            'prompt_length': prompt.length,
            'model': _imageModel,
            'size': size,
          },
        );

        return imageData;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        throw AIGenerationException('Qwen AI API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_image_generation_qwen', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. Please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to generate image with Qwen: ${e.toString()}');
      }
    }
  }

  /// Generate image using Hugging Face (Free alternative)
  Future<dynamic> _generateImageWithHuggingFace(
    String prompt,
    String size,
    String style,
    Function(double)? onProgress,
  ) async {
    // Rate limiting for free tier
    if (_lastHuggingFaceRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastHuggingFaceRequest!);
      if (timeSinceLastRequest < ApiConfig.huggingFaceRateLimit) {
        final waitTime = ApiConfig.huggingFaceRateLimit - timeSinceLastRequest;
        if (kDebugMode) {
          debugPrint(('Rate limiting: waiting ${waitTime.inSeconds} seconds before next request').toString());
        }
        throw AIGenerationException(
          'Please wait ${waitTime.inSeconds} seconds before generating another image (free tier limit).',
        );
      }
    }
    
    _lastHuggingFaceRequest = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint(('Starting Hugging Face AI image generation with prompt: $prompt').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_image_generation_huggingface',
        properties: {
          'prompt_length': prompt.length,
          'model': ApiConfig.huggingFaceImageModel,
          'size': size,
          'style': style,
        },
      );

      onProgress?.call(0.1);

      final enhancedPrompt = _enhanceImagePrompt(prompt, style);
      
      final useProxy = ApiConfig.huggingFaceUseProxy && kIsWeb;
      // Using app-wide Hugging Face API token (configured by developer)
      final headers = useProxy
          ? {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}',
              'apikey': SupabaseConfig.supabaseAnonKey,
              'x-hf-token': ApiConfig.huggingFaceApiToken,
            }
          : {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${ApiConfig.huggingFaceApiToken}',
            };

      final body = {
        'inputs': enhancedPrompt,
        'parameters': {
          'negative_prompt': 'blurry, bad quality, distorted, ugly',
        },
      };

      onProgress?.call(0.3);

      final response = await _client
          .post(
            Uri.parse(
              useProxy
                  ? '${SupabaseConfig.supabaseUrl}/functions/v1/hf_proxy?model=${Uri.encodeComponent(ApiConfig.huggingFaceImageModel)}'
                  : '$_huggingFaceBaseUrl/${ApiConfig.huggingFaceImageModel}',
            ),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180));

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        // Hugging Face returns image data directly as bytes
        final imageBytes = response.bodyBytes;

        if (kDebugMode) {
          debugPrint(('Hugging Face image generated successfully').toString());
        }

        onProgress?.call(1.0);

        await _analyticsService.trackFeatureUsed(
          'ai_image_generation_huggingface_success',
          properties: {
            'prompt_length': prompt.length,
            'model': ApiConfig.huggingFaceImageModel,
            'size': size,
          },
        );

        // Return image bytes directly (compatible with existing code)
        return imageBytes;
      } else {
        String errorMessage = 'Unknown error';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? errorData.toString();
        } catch (_) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        }
        
        // Handle model loading case
        if (response.statusCode == 503) {
          throw AIGenerationException('AI model is loading, please try again in a few moments.');
        }
        
        throw AIGenerationException('Hugging Face API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_image_generation_huggingface', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. The free AI service may be busy, please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to generate image: ${e.toString()}');
      }
    }
  }

  // MARK: - Text Generation
  
  /// Generate text content using Qwen
  Future<Map<String, dynamic>> generateText({
    required String prompt,
    int maxTokens = 1000,
    double temperature = 0.7,
    String? systemMessage,
  }) async {
    if (!_isInitialized) await initialize();
    
    if (!isConfigured()) {
      return {
        'success': false,
        'error': 'Qwen API key not configured. Please set your API key.',
      };
    }

    try {
      final messages = <Map<String, String>>[
        if (systemMessage != null)
          {'role': 'system', 'content': systemMessage},
        {'role': 'user', 'content': prompt},
      ];

      final response = await _client.post(
        Uri.parse('$_qwenBaseUrl$_textEndpoint'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _textModel,
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
        debugPrint(('Error generating text: $e').toString());
      }
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // MARK: - Audio Generation
  
  /// Generate audio from text with automatic fallback
  Future<dynamic> generateAudio({
    required String text,
    String voice = 'longwan',
    String format = 'mp3',
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    if (kDebugMode) {
      debugPrint(('generateAudio called with text: ${text.substring(0, text.length > 50 ? 50 : text.length)}...').toString());
    }
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for audio generation (premium)').toString());
      }
      return await _generateAudioWithQwen(text, voice, format, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for audio generation (free)').toString());
      }
      return await _generateAudioWithHuggingFace(text, voice, format, onProgress);
    }
  }

  /// Generate audio using Qwen (Premium)
  Future<dynamic> _generateAudioWithQwen(
    String text,
    String voice,
    String format,
    Function(double)? onProgress,
  ) async {
    try {
      await _analyticsService.trackFeatureUsed(
        'ai_audio_generation_qwen',
        properties: {
          'text_length': text.length,
          'voice': voice,
          'format': format,
        },
      );

      onProgress?.call(0.1);

      final response = await _client.post(
        Uri.parse('$_qwenBaseUrl$_audioEndpoint'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _audioModel,
          'input': {
            'text': text,
          },
          'parameters': {
            'voice': voice,
            'format': format,
          },
        }),
      );

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final audioUrl = data['output']['audio_url'] as String;
        
        // Download audio file
        final audioData = await _downloadAudio(audioUrl, onProgress);
        
        await _analyticsService.trackFeatureUsed('ai_audio_generation_qwen_success');
        return audioData;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['message'] ?? 'Unknown error';
        throw AIGenerationException('Audio generation failed: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_audio_generation_qwen', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else {
        throw AIGenerationException('Failed to generate audio: ${e.toString()}');
      }
    }
  }

  /// Generate audio using Hugging Face (Free alternative)
  Future<dynamic> _generateAudioWithHuggingFace(
    String text,
    String voice,
    String format,
    Function(double)? onProgress,
  ) async {
    // For now, throw a user-friendly error since free audio generation is complex
    throw AIGenerationException(
      'Audio generation is currently unavailable with the free tier. Please configure a premium API key in Settings for full audio generation capabilities.',
    );
  }

  // MARK: - Style Transfer
  
  /// Apply style transfer with automatic fallback
  Future<dynamic> applyStyleTransfer({
    required File sourceImage,
    required String style,
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for style transfer (premium)').toString());
      }
      return await _applyStyleTransferWithQwen(sourceImage, style, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for style transfer (free)').toString());
      }
      return await _applyStyleTransferWithHuggingFace(sourceImage, style, onProgress);
    }
  }

  /// Apply style transfer using Qwen (Premium)
  Future<dynamic> _applyStyleTransferWithQwen(
    File sourceImage,
    String style,
    Function(double)? onProgress,
  ) async {
    try {
      await _analyticsService.trackFeatureUsed(
        'ai_style_transfer_qwen',
        properties: {'style': style},
      );

      onProgress?.call(0.1);

      // Read image file and convert to base64
      final imageBytes = await sourceImage.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      
      onProgress?.call(0.3);
      
      final response = await _client.post(
        Uri.parse('$_qwenBaseUrl/services/aigc/multimodal-generation/generation'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'qwen-vl-plus',
          'input': {
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'image': 'data:image/jpeg;base64,$base64Image'
                  },
                  {
                    'text': 'Transfer the style of this image to $style style while maintaining the main subject and composition. Apply the artistic characteristics of $style including color palette, brushwork, and visual aesthetics.'
                  }
                ]
              }
            ]
          },
          'parameters': {
            'watermark': false,
            'negative_prompt': 'blurry, low quality, distorted, artifacts'
          }
        }),
      ).timeout(const Duration(seconds: 120));

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['output'] != null && data['output']['choices'] != null && data['output']['choices'].isNotEmpty) {
          final imageUrl = data['output']['choices'][0]['message']['content'][0]['image'];
          
          // Download the generated image
          final styledImageData = await _downloadImage(imageUrl, onProgress);
          
          await _analyticsService.trackFeatureUsed(
            'ai_style_transfer_qwen_success',
            properties: {'style': style},
          );
          
          return styledImageData;
        } else {
          throw AIGenerationException('No styled image generated');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw AIGenerationException('Style transfer failed: ${errorData['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_style_transfer_qwen', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. Please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to apply style transfer: ${e.toString()}');
      }
    }
  }

  /// Apply style transfer using Hugging Face (Free alternative)
  Future<dynamic> _applyStyleTransferWithHuggingFace(
    File sourceImage,
    String style,
    Function(double)? onProgress,
  ) async {
    // Rate limiting for free tier
    if (_lastHuggingFaceRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastHuggingFaceRequest!);
      if (timeSinceLastRequest < ApiConfig.huggingFaceRateLimit) {
        final waitTime = ApiConfig.huggingFaceRateLimit - timeSinceLastRequest;
        if (kDebugMode) {
          debugPrint(('Rate limiting: waiting ${waitTime.inSeconds} seconds before next request').toString());
        }
        throw AIGenerationException(
          'Please wait ${waitTime.inSeconds} seconds before applying another style transfer (free tier limit).',
        );
      }
    }
    
    _lastHuggingFaceRequest = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint(('Starting Hugging Face AI style transfer with style: $style').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_style_transfer_huggingface',
        properties: {
          'style': style,
          'model': ApiConfig.huggingFaceStyleTransferModel,
        },
      );

      onProgress?.call(0.1);

      // Read image file and convert to base64
      final imageBytes = await sourceImage.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      
      // Using app-wide Hugging Face API token (configured by developer)
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${ApiConfig.huggingFaceApiToken}',
      };

      final body = {
        'inputs': {
          'image': base64Image,
          'prompt': 'Apply $style artistic style to this image while maintaining the main subject and composition',
        },
        'parameters': {
          'num_inference_steps': 20,
          'guidance_scale': 7.5,
          'image_guidance_scale': 1.5,
        },
      };

      onProgress?.call(0.3);

      final response = await _client
          .post(
            Uri.parse('$_huggingFaceBaseUrl/${ApiConfig.huggingFaceStyleTransferModel}'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180)); // Longer timeout for free service

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        // Hugging Face returns image data directly as bytes
        final styledImageBytes = response.bodyBytes;

        if (kDebugMode) {
          debugPrint(('Hugging Face style transfer completed successfully').toString());
        }

        onProgress?.call(1.0);

        await _analyticsService.trackFeatureUsed(
          'ai_style_transfer_huggingface_success',
          properties: {
            'style': style,
            'model': ApiConfig.huggingFaceStyleTransferModel,
          },
        );

        // Return styled image bytes directly (compatible with existing code)
        return styledImageBytes;
      } else {
        String errorMessage = 'Unknown error';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? errorData.toString();
        } catch (_) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        }
        
        // Handle model loading case
        if (response.statusCode == 503) {
          throw AIGenerationException('AI model is loading, please try again in a few moments.');
        }
        
        throw AIGenerationException('Hugging Face API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_style_transfer_huggingface', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. The free AI service may be busy, please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to apply style transfer: ${e.toString()}');
      }
    }
  }

  // MARK: - Avatar Generation
  
  /// Generate avatar with automatic fallback
  Future<dynamic> generateAvatar({
    required String description,
    String style = 'realistic',
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    if (kDebugMode) {
      debugPrint(('generateAvatar called with description: ${description.substring(0, description.length > 50 ? 50 : description.length)}...').toString());
    }
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for avatar generation (premium)').toString());
      }
      return await _generateAvatarWithQwen(description, style, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for avatar generation (free)').toString());
      }
      return await _generateAvatarWithHuggingFace(description, style, onProgress);
    }
  }

  /// Generate avatar using Qwen (Premium)
  Future<dynamic> _generateAvatarWithQwen(
    String description,
    String style,
    Function(double)? onProgress,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint(('Starting Qwen AI avatar generation with description: $description').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_avatar_generation_qwen',
        properties: {
          'description_length': description.length,
          'model': _imageModel,
          'style': style,
        },
      );

      onProgress?.call(0.1);

      final enhancedPrompt = 'Create a detailed avatar portrait: $description, $style style, high quality, professional headshot';
      
      final headers = {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'model': _imageModel,
        'prompt': enhancedPrompt,
        'size': '1024x1024',
        'n': 1,
        'response_format': 'url',
      });

      onProgress?.call(0.3);

      final response = await http
          .post(
            Uri.parse('$_baseUrl/images/generations'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final imageUrl = responseData['data'][0]['url'];

        if (kDebugMode) {
          debugPrint(('Qwen avatar generated successfully: $imageUrl').toString());
        }

        final imageData = await _downloadImage(imageUrl, onProgress);

        await _analyticsService.trackFeatureUsed(
          'ai_avatar_generation_qwen_success',
          properties: {
            'description_length': description.length,
            'model': _imageModel,
            'style': style,
          },
        );

        return imageData;
      } else {
        final errorData = jsonDecode(response.body);
        final errorMessage = errorData['error']?['message'] ?? 'Unknown error';
        throw AIGenerationException('Qwen AI API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_avatar_generation_qwen', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. Please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to generate avatar with Qwen: ${e.toString()}');
      }
    }
  }

  /// Generate avatar using Hugging Face (Free alternative)
  Future<dynamic> _generateAvatarWithHuggingFace(
    String description,
    String style,
    Function(double)? onProgress,
  ) async {
    // Rate limiting for free tier
    if (_lastHuggingFaceRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastHuggingFaceRequest!);
      if (timeSinceLastRequest < ApiConfig.huggingFaceRateLimit) {
        final waitTime = ApiConfig.huggingFaceRateLimit - timeSinceLastRequest;
        if (kDebugMode) {
          debugPrint(('Rate limiting: waiting ${waitTime.inSeconds} seconds before next request').toString());
        }
        throw AIGenerationException(
          'Please wait ${waitTime.inSeconds} seconds before generating another avatar (free tier limit).',
        );
      }
    }
    
    _lastHuggingFaceRequest = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint(('Starting Hugging Face AI avatar generation with description: $description').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_avatar_generation_huggingface',
        properties: {
          'description_length': description.length,
          'model': ApiConfig.huggingFaceAvatarModel,
          'style': style,
        },
      );

      onProgress?.call(0.1);

      final enhancedPrompt = 'Portrait of $description, $style style, high quality avatar, professional headshot, detailed face';
      
      // Using app-wide Hugging Face API token (configured by developer)
      final headers = {
        'Authorization': 'Bearer ${ApiConfig.huggingFaceApiToken}',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'inputs': enhancedPrompt,
        'parameters': {
          'num_inference_steps': 20,
          'guidance_scale': 7.5,
          'width': 1024,
          'height': 1024,
        },
      });

      onProgress?.call(0.3);

      final response = await _client
          .post(
            Uri.parse('$_huggingFaceBaseUrl/${ApiConfig.huggingFaceAvatarModel}'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final imageBytes = response.bodyBytes;
        
        if (kDebugMode) {
          debugPrint(('Hugging Face avatar generated successfully, size: ${imageBytes.length} bytes').toString());
        }

        onProgress?.call(1.0);

        await _analyticsService.trackFeatureUsed(
          'ai_avatar_generation_huggingface_success',
          properties: {
            'description_length': description.length,
            'model': ApiConfig.huggingFaceAvatarModel,
            'style': style,
            'image_size_bytes': imageBytes.length,
          },
        );

        return imageBytes;
      } else {
        String errorMessage = 'Unknown error';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? errorData['message'] ?? errorMessage;
        } catch (_) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        }
        
        // Handle model loading case
        if (response.statusCode == 503) {
          throw AIGenerationException('AI model is loading, please try again in a few moments.');
        }
        
        throw AIGenerationException('Hugging Face API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_avatar_generation_huggingface', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. The free AI service may be busy, please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to generate avatar: ${e.toString()}');
      }
    }
  }

  // MARK: - Background Removal
  
  /// Remove background with automatic fallback
  Future<dynamic> removeBackground({
    required File sourceImage,
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for background removal (premium)').toString());
      }
      return await _removeBackgroundWithQwen(sourceImage, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for background removal (free)').toString());
      }
      return await _removeBackgroundWithHuggingFace(sourceImage, onProgress);
    }
  }

  /// Remove background using Qwen (Premium)
  Future<dynamic> _removeBackgroundWithQwen(
    File sourceImage,
    Function(double)? onProgress,
  ) async {
    try {
      await _analyticsService.trackFeatureUsed(
        'ai_background_removal_qwen',
        properties: {},
      );

      onProgress?.call(0.1);

      // Read image file and convert to base64
      final imageBytes = await sourceImage.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      
      onProgress?.call(0.3);
      
      final response = await _client.post(
        Uri.parse('$_qwenBaseUrl/services/aigc/multimodal-generation/generation'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'qwen-vl-plus',
          'input': {
            'messages': [
              {
                'role': 'user',
                'content': [
                  {
                    'image': 'data:image/jpeg;base64,$base64Image'
                  },
                  {
                    'text': 'Remove the background from this image, keeping only the main subject. Make the background transparent or white.'
                  }
                ]
              }
            ]
          },
          'parameters': {
            'watermark': false,
            'negative_prompt': 'blurry, low quality, distorted, artifacts'
          }
        }),
      ).timeout(const Duration(seconds: 120));

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        if (data['output'] != null && data['output']['choices'] != null && data['output']['choices'].isNotEmpty) {
          final imageUrl = data['output']['choices'][0]['message']['content'][0]['image'];
          
          // Download the processed image
          final processedImageData = await _downloadImage(imageUrl, onProgress);
          
          await _analyticsService.trackFeatureUsed(
            'ai_background_removal_qwen_success',
            properties: {},
          );
          
          return processedImageData;
        } else {
          throw AIGenerationException('No processed image generated');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw AIGenerationException('Background removal failed: ${errorData['message'] ?? 'Unknown error'}');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_background_removal_qwen', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. Please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to remove background: ${e.toString()}');
      }
    }
  }

  /// Remove background using Hugging Face (Free alternative)
  Future<dynamic> _removeBackgroundWithHuggingFace(
    File sourceImage,
    Function(double)? onProgress,
  ) async {
    // Rate limiting for free tier
    if (_lastHuggingFaceRequest != null) {
      final timeSinceLastRequest = DateTime.now().difference(_lastHuggingFaceRequest!);
      if (timeSinceLastRequest < ApiConfig.huggingFaceRateLimit) {
        final waitTime = ApiConfig.huggingFaceRateLimit - timeSinceLastRequest;
        if (kDebugMode) {
          debugPrint(('Rate limiting: waiting ${waitTime.inSeconds} seconds before next request').toString());
        }
        throw AIGenerationException(
          'Please wait ${waitTime.inSeconds} seconds before removing another background (free tier limit).',
        );
      }
    }
    
    _lastHuggingFaceRequest = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint(('Starting Hugging Face AI background removal').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_background_removal_huggingface',
        properties: {
          'model': ApiConfig.huggingFaceBackgroundRemovalModel,
        },
      );

      onProgress?.call(0.1);

      // Read image file
      final imageBytes = await sourceImage.readAsBytes();
      
      // Using app-wide Hugging Face API token (configured by developer)
      final headers = {
        'Authorization': 'Bearer ${ApiConfig.huggingFaceApiToken}',
      };

      onProgress?.call(0.3);

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_huggingFaceBaseUrl/${ApiConfig.huggingFaceBackgroundRemovalModel}'),
      );
      
      request.headers.addAll(headers);
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: 'image.jpg',
        ),
      );

      final streamedResponse = await request.send().timeout(const Duration(seconds: 180));
      final response = await http.Response.fromStream(streamedResponse);

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        // Hugging Face returns processed image data directly as bytes
        final processedImageBytes = response.bodyBytes;

        if (kDebugMode) {
          debugPrint(('Hugging Face background removal completed successfully').toString());
        }

        onProgress?.call(1.0);

        await _analyticsService.trackFeatureUsed(
          'ai_background_removal_huggingface_success',
          properties: {
            'model': ApiConfig.huggingFaceBackgroundRemovalModel,
          },
        );

        // Return processed image bytes directly (compatible with existing code)
        return processedImageBytes;
      } else {
        String errorMessage = 'Unknown error';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? errorData.toString();
        } catch (_) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        }
        
        // Handle model loading case
        if (response.statusCode == 503) {
          throw AIGenerationException('AI model is loading, please try again in a few moments.');
        }
        
        throw AIGenerationException('Hugging Face API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_background_removal_huggingface', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. The free AI service may be busy, please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to remove background: ${e.toString()}');
      }
    }
  }

  // MARK: - Helper Methods
  
  String _enhanceImagePrompt(String prompt, String style) {
    final styleEnhancements = {
      'realistic': 'photorealistic, high quality, detailed, professional photography',
      'anime': 'anime style, manga, cel shading, vibrant colors',
      'oil painting': 'oil painting style, artistic, brushstrokes, classical art',
      'cyberpunk': 'cyberpunk style, neon lights, futuristic, sci-fi',
      'fantasy': 'fantasy art, magical, ethereal, mystical atmosphere',
    };
    
    final enhancement = styleEnhancements[style.toLowerCase()] ?? styleEnhancements['realistic']!;
    return '$prompt, $enhancement';
  }

  Future<dynamic> _downloadImage(String imageUrl, Function(double)? onProgress) async {
    try {
      final response = await _client.get(Uri.parse(imageUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        onProgress?.call(1.0);

        if (kIsWeb) {
          return bytes;
        } else {
          final tempDir = await getTemporaryDirectory();
          final fileName = 'ai_generated_${DateTime.now().millisecondsSinceEpoch}.png';
          final file = File(path.join(tempDir.path, fileName));
          await file.writeAsBytes(bytes);
          return file;
        }
      } else {
        throw Exception('Failed to download image: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to download generated image: $e');
    }
  }

  Future<dynamic> _downloadAudio(String audioUrl, Function(double)? onProgress) async {
    try {
      final response = await _client.get(Uri.parse(audioUrl));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        onProgress?.call(1.0);

        if (kIsWeb) {
          return bytes;
        } else {
          final tempDir = await getTemporaryDirectory();
          final fileName = 'ai_generated_${DateTime.now().millisecondsSinceEpoch}.mp3';
          final file = File(path.join(tempDir.path, fileName));
          await file.writeAsBytes(bytes);
          return file;
        }
      } else {
        throw Exception('Failed to download audio: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to download generated audio: $e');
    }
  }

  // MARK: - Video Generation
  
  /// Generate video from text with automatic fallback
  Future<dynamic> generateTextToVideo({
    required String prompt,
    int durationSeconds = 5,
    String style = 'realistic',
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    if (kDebugMode) {
      debugPrint(('generateTextToVideo called with prompt: ${prompt.substring(0, prompt.length > 50 ? 50 : prompt.length)}...').toString());
    }
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for text-to-video generation (premium)').toString());
      }
      return await _generateTextToVideoWithQwen(prompt, durationSeconds, style, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for text-to-video generation (free)').toString());
      }
      return await _generateTextToVideoWithHuggingFace(prompt, durationSeconds, style, onProgress);
    }
  }

  /// Generate video from image with automatic fallback
  Future<dynamic> generateImageToVideo({
    required File sourceImage,
    String prompt = '',
    int durationSeconds = 5,
    Function(double)? onProgress,
  }) async {
    if (!_isInitialized) await initialize();
    
    // Use Qwen if configured, otherwise fallback to Hugging Face (free)
    if (isConfigured()) {
      if (kDebugMode) {
        debugPrint(('Using Qwen AI for image-to-video generation (premium)').toString());
      }
      return await _generateImageToVideoWithQwen(sourceImage, prompt, durationSeconds, onProgress);
    } else {
      if (kDebugMode) {
        debugPrint(('Using Hugging Face AI for image-to-video generation (free)').toString());
      }
      return await _generateImageToVideoWithHuggingFace(sourceImage, prompt, durationSeconds, onProgress);
    }
  }

  /// Generate text-to-video using Qwen (Premium)
  Future<dynamic> _generateTextToVideoWithQwen(
    String prompt,
    int durationSeconds,
    String style,
    Function(double)? onProgress,
  ) async {
    try {
      await _analyticsService.trackFeatureUsed(
        'ai_text_to_video_qwen',
        properties: {
          'prompt_length': prompt.length,
          'duration': durationSeconds,
          'style': style,
        },
      );

      onProgress?.call(0.1);

      // Note: This is a placeholder implementation
      // Qwen doesn't currently support video generation in their public API
      throw AIGenerationException('Text-to-video generation with Qwen is not yet available. Please use the free Hugging Face option.');
    } catch (e) {
      await _analyticsService.trackError('ai_text_to_video_qwen', e.toString());
      rethrow;
    }
  }

  /// Generate text-to-video using Hugging Face (Free alternative)
  Future<dynamic> _generateTextToVideoWithHuggingFace(
    String prompt,
    int durationSeconds,
    String style,
    Function(double)? onProgress,
  ) async {
    // For now, throw a user-friendly error since free video generation is complex
    throw AIGenerationException(
      'Video generation is currently unavailable with the free tier. Please configure a premium API key in Settings for full video generation capabilities.',
    );
  }

  /// Generate image-to-video using Qwen (Premium)
  Future<dynamic> _generateImageToVideoWithQwen(
    File sourceImage,
    String prompt,
    int durationSeconds,
    Function(double)? onProgress,
  ) async {
    try {
      await _analyticsService.trackFeatureUsed(
        'ai_image_to_video_qwen',
        properties: {
          'prompt_length': prompt.length,
          'duration': durationSeconds,
        },
      );

      onProgress?.call(0.1);

      // Note: This is a placeholder implementation
      // Qwen doesn't currently support video generation in their public API
      throw AIGenerationException('Image-to-video generation with Qwen is not yet available. Please use the free Hugging Face option.');
    } catch (e) {
      await _analyticsService.trackError('ai_image_to_video_qwen', e.toString());
      rethrow;
    }
  }

  /// Generate image-to-video using Hugging Face (Free alternative)
  Future<dynamic> _generateImageToVideoWithHuggingFace(
    File sourceImage,
    String prompt,
    int durationSeconds,
    Function(double)? onProgress,
  ) async {
    // Rate limiting for free tier - use video-specific rate limit
     if (_lastHuggingFaceRequest != null) {
       final timeSinceLastRequest = DateTime.now().difference(_lastHuggingFaceRequest!);
       if (timeSinceLastRequest < ApiConfig.huggingFaceVideoRateLimit) {
         final waitTime = ApiConfig.huggingFaceVideoRateLimit - timeSinceLastRequest;
         if (kDebugMode) {
           debugPrint(('Rate limiting: waiting ${waitTime.inSeconds} seconds before next video request').toString());
         }
         throw AIGenerationException(
           'Please wait ${waitTime.inSeconds} seconds before generating another video (free tier limit).',
         );
       }
     }
    
    _lastHuggingFaceRequest = DateTime.now();
    
    try {
      if (kDebugMode) {
        debugPrint(('Starting Hugging Face AI image-to-video generation').toString());
      }

      await _analyticsService.trackFeatureUsed(
        'ai_image_to_video_huggingface',
        properties: {
          'prompt_length': prompt.length,
          'model': ApiConfig.huggingFaceImageToVideoModel,
          'duration': durationSeconds,
        },
      );

      onProgress?.call(0.1);

      // Convert image to base64
      final imageBytes = await sourceImage.readAsBytes();
      final base64Image = base64Encode(imageBytes);
      
      // Using app-wide Hugging Face API token (configured by developer)
      final headers = {
        'Authorization': 'Bearer ${ApiConfig.huggingFaceApiToken}',
        'Content-Type': 'application/json',
      };

      final body = jsonEncode({
        'inputs': {
          'image': base64Image,
          'prompt': prompt.isNotEmpty ? prompt : 'animate this image with smooth motion',
        },
        'parameters': {
          'num_frames': durationSeconds * 8, // ~8 FPS
          'num_inference_steps': 25,
        },
      });

      onProgress?.call(0.3);

      final response = await http
          .post(
            Uri.parse('https://router.huggingface.co/hf-inference/models/${ApiConfig.huggingFaceImageToVideoModel}'),
            headers: headers,
            body: body,
          )
          .timeout(const Duration(seconds: 120)); // Longer timeout for video

      onProgress?.call(0.7);

      if (response.statusCode == 200) {
        final videoBytes = response.bodyBytes;
        
        if (kDebugMode) {
          debugPrint(('Hugging Face image-to-video generated successfully, size: ${videoBytes.length} bytes').toString());
        }

        onProgress?.call(1.0);

        await _analyticsService.trackFeatureUsed(
          'ai_image_to_video_huggingface_success',
          properties: {
            'prompt_length': prompt.length,
            'model': ApiConfig.huggingFaceImageToVideoModel,
            'duration': durationSeconds,
            'video_size_bytes': videoBytes.length,
          },
        );

        return videoBytes;
      } else {
        String errorMessage = 'Unknown error';
        try {
          final errorData = jsonDecode(response.body);
          errorMessage = errorData['error'] ?? errorData['message'] ?? errorMessage;
        } catch (_) {
          errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        }
        
        // Handle model loading case
        if (response.statusCode == 503) {
          throw AIGenerationException('AI model is loading, please try again in a few moments.');
        }
        
        throw AIGenerationException('Hugging Face API error: $errorMessage');
      }
    } catch (e) {
      await _analyticsService.trackError('ai_image_to_video_huggingface', e.toString());
      
      if (e is AIGenerationException) {
        rethrow;
      } else if (e is TimeoutException) {
        throw AIGenerationException('Request timed out. Video generation may take longer, please try again.');
      } else if (e is SocketException) {
        throw AIGenerationException('Network error. Please check your connection.');
      } else {
        throw AIGenerationException('Failed to generate video: ${e.toString()}');
      }
    }
  }



  // Get suggested prompts based on style
  List<String> getSuggestedPrompts(String style) {
    // Return localization keys; UI will resolve them via LocalizationService/LocalizedText
    final Map<String, List<String>> stylePrompts = {
      'Realistic': [
        'prompt_realistic_1',
        'prompt_realistic_2',
        'prompt_realistic_3',
        'prompt_realistic_4',
      ],
      'Anime': [
        'prompt_anime_1',
        'prompt_anime_2',
        'prompt_anime_3',
        'prompt_anime_4',
      ],
      'Oil Painting': [
        'prompt_oil_painting_1',
        'prompt_oil_painting_2',
        'prompt_oil_painting_3',
        'prompt_oil_painting_4',
      ],
      'Cyberpunk': [
        'prompt_cyberpunk_1',
        'prompt_cyberpunk_2',
        'prompt_cyberpunk_3',
        'prompt_cyberpunk_4',
      ],
      'Fantasy': [
        'prompt_fantasy_1',
        'prompt_fantasy_2',
        'prompt_fantasy_3',
        'prompt_fantasy_4',
      ],
    };

    return stylePrompts[style] ?? stylePrompts['Realistic']!;
  }

  // Dispose resources
  void dispose() {
    _client.close();
  }
}

// Custom exception for AI generation errors
class AIGenerationException implements Exception {
  final String message;

  AIGenerationException(this.message);

  @override
  String toString() => 'AIGenerationException: $message';
}

// Generated content models
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
        .map((match) => match.group(0)!)
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

