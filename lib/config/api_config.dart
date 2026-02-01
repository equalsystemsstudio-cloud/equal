/// API Configuration for Equal App
/// This file contains API keys and tokens used by the application.
///
/// IMPORTANT: Keep this file secure and do not commit actual tokens to version control.
/// For production, consider using environment variables or secure key management.
library;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_config.dart';
import 'package:flutter/foundation.dart';

class ApiConfig {
  // Hugging Face API Configuration
  // Get your free API token from: https://huggingface.co/settings/tokens
  //This token will be used by ALL users of your app
  static String _huggingFaceApiToken = 'hf_YOUR_ACTUAL_TOKEN_HERE';

  static String get huggingFaceApiToken => _huggingFaceApiToken;

  // Load configuration from Supabase
  static Future<void> loadRemoteConfig() async {
    try {
      // Access client safely - assuming Supabase is initialized
      final client = Supabase.instance.client;
      final response = await client
          .from('app_config')
          .select('value')
          .eq('key', 'hugging_face_api_token')
          .maybeSingle();

      if (response != null && response['value'] != null) {
        _huggingFaceApiToken = response['value'];
        if (kDebugMode) {
          debugPrint('Remote config loaded: hugging_face_api_token updated');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading remote config: $e');
      }
    }
  }

  // Qwen API Configuration (Premium)
  static const String qwenApiKey = 'YOUR_QWEN_API_KEY_HERE';
  static const String qwenBaseUrl =
      'https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis';

  // Model configurations
  static const String huggingFaceImageModel =
      'black-forest-labs/FLUX.1-schnell';
  static const String qwenImageModel = 'wanx-v1';
  // NSFW moderation model (image classification)
  static const String huggingFaceNSFWModel = 'GantMan/nsfw_model';

  // Hugging Face models for different AI features (using simple, reliable models)
  static const String huggingFaceAudioModel =
      'facebook/fastspeech2-en-ljspeech';
  static const String huggingFaceStyleTransferModel =
      'runwayml/stable-diffusion-v1-5';
  static const String huggingFaceBackgroundRemovalModel = 'briaai/RMBG-1.4';
  static const String huggingFaceAvatarModel = 'runwayml/stable-diffusion-v1-5';
  static const String huggingFaceTextToVideoModel =
      'runwayml/stable-diffusion-v1-5';
  static const String huggingFaceImageToVideoModel =
      'runwayml/stable-diffusion-v1-5';

  // Rate limiting (adjust based on your API plan)
  static const Duration huggingFaceRateLimit = Duration(seconds: 10);
  static const Duration huggingFaceVideoRateLimit = Duration(
    seconds: 30,
  ); // Longer for video generation
  // Moderation thresholds
  static const double nsfwThreshold = 0.85; // block when NSFW score >= 0.85

  // Validation methods
  static bool get isHuggingFaceConfigured =>
      huggingFaceApiToken.isNotEmpty &&
      huggingFaceApiToken != 'hf_YOUR_ACTUAL_TOKEN_HERE';

  static bool get isQwenConfigured =>
      qwenApiKey.isNotEmpty &&
      qwenApiKey != 'sk-4de8d45435624f7cb007baf24a6378c5';
  // Enable proxying Hugging Face requests via Supabase Edge Function to avoid CORS on web
  static const bool huggingFaceUseProxy = false;

  // WebRTC ICE server configuration
  // Replace the placeholders below with your actual STUN/TURN servers.
  // Example TURN URIs:
  //   turn:turn.yourdomain.com:3478?transport=udp
  //   turns:turn.yourdomain.com:5349?transport=tcp
  static const String stunUrl1 = 'stun:stun.l.google.com:19302';
  static const String stunUrl2 = '';
  static const String turnUrl = '';
  static const String turnsUrl = '';
  static const String turnUsername = '';
  static const String turnCredential = '';
}
