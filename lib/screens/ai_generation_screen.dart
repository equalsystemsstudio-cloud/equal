// ignore_for_file: unused_field, unused_element, unused_local_variable
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/ai_service.dart';
import '../services/app_service.dart';
import 'photo_creation_screen.dart';
import 'main_screen.dart';
import '../services/localization_service.dart';

class AIGenerationScreen extends StatefulWidget {
  const AIGenerationScreen({super.key});

  @override
  State<AIGenerationScreen> createState() => _AIGenerationScreenState();
}

class _AIGenerationScreenState extends State<AIGenerationScreen>
    with TickerProviderStateMixin {
  int _selectedAIType = 0;
  bool _isGenerating = false;
  double _generationProgress = 0.0;
  String _currentPrompt = '';
  String _selectedStyle = 'Realistic';
  dynamic _generatedImage; // File on mobile, Uint8List on web
  String? _generationError;

  late AnimationController _shimmerController;
  late AnimationController _pulseController;
  late Animation<double> _shimmerAnimation;
  late Animation<double> _pulseAnimation;

  final TextEditingController _promptController = TextEditingController();
  final PageController _pageController = PageController();
  final AIService _aiService = AIService();
  final AppService _appService = AppService();

  final List<Map<String, dynamic>> _aiTypes = [
    {
      'title': 'text_to_image',
      'subtitle': 'text_to_image_subtitle',
      'icon': Icons.image,
      'gradient': [Colors.purple, Colors.pink],
    },
  ];

  final List<String> _artStyles = [
    'Realistic',
    'Anime',
    'Oil Painting',
    'Cyberpunk',
    'Fantasy',
    'Watercolor',
    'Digital Art',
    'Sketch',
    'Pop Art',
    'Abstract',
    'Minimalist',
    'Vintage',
  ];

  List<String> get _promptSuggestions {
    return _aiService.getSuggestedPrompts(_selectedStyle);
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);

    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startGeneration() async {
    // Validate input - only text-to-image is available
    if (_currentPrompt.isEmpty) {
      _showSnackBar(
        LocalizationService.t('please_enter_prompt_to_generate_image'),
      );
      return;
    }

    // Initialize AI service
    await _aiService.initialize();

    setState(() {
      _isGenerating = true;
      _generationProgress = 0.0;
      _generatedImage = null;
      _generationError = null;
    });

    try {
      // Only handle text-to-image generation
      await _generateImage();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationProgress = 0.0;
          _generationError = e.toString();
        });
        _showSnackBar(
          '${LocalizationService.t('generation_failed')}: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _generateImage() async {
    try {
      final generatedImage = await _aiService.generateImage(
        prompt: _currentPrompt,
        size: '1024x1024',
        style: _selectedStyle.toLowerCase(),
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _generationProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatedImage = generatedImage;
          _generationProgress = 0.0;
        });
        _showGenerationComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationProgress = 0.0;
          _generationError = e.toString();
        });
        _showSnackBar(
          '${LocalizationService.t('image_generation_failed')}: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _generateAvatar() async {
    try {
      final generatedAvatar = await _aiService.generateAvatar(
        description: _currentPrompt,
        style: _selectedStyle.toLowerCase(),
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _generationProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatedImage = generatedAvatar;
          _generationProgress = 0.0;
        });
        _showGenerationComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationProgress = 0.0;
          _generationError = e.toString();
        });
        if (e.toString().contains('not yet implemented')) {
          _showSnackBar(LocalizationService.t('avatar_generation_coming_soon'));
        } else {
          _showSnackBar(
            '${LocalizationService.t('avatar_generation_failed')}: ${e.toString()}',
          );
        }
      }
    }
  }

  Future<void> _generateAudio() async {
    try {
      final generatedAudio = await _aiService.generateAudio(
        text: _currentPrompt,
        voice: 'longwan',
        format: 'mp3',
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _generationProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatedImage = generatedAudio; // Store audio file
          _generationProgress = 0.0;
        });
        _showGenerationComplete();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationProgress = 0.0;
          _generationError = e.toString();
        });
        if (e.toString().contains('not yet implemented')) {
          _showSnackBar(LocalizationService.t('audio_generation_coming_soon'));
        } else {
          _showSnackBar(
            '${LocalizationService.t('audio_generation_failed')}: ${e.toString()}',
          );
        }
      }
    }
  }

  Future<void> _handleStyleTransfer() async {
    try {
      // For now, show a message that file selection is needed
      _showSnackBar(LocalizationService.t('style_transfer_requires_image'));
      setState(() {
        _isGenerating = false;
        _generationProgress = 0.0;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generationProgress = 0.0;
          _generationError = e.toString();
        });
        _showSnackBar(
          '${LocalizationService.t('style_transfer_failed')}: ${e.toString()}',
        );
      }
    }
  }

  // This method is no longer needed as enhancement is handled in AIService
  // Keeping for backward compatibility
  String _enhancePrompt(String basePrompt, String style) {
    return basePrompt; // AIService now handles prompt enhancement
  }

  void _showGenerationComplete() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: LocalizedText(
          'generation_complete_title',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: _generatedImage != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildGeneratedImage(),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _aiTypes[_selectedAIType]['gradient'],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.auto_awesome,
                          size: 80,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            LocalizedText(
              _generatedImage != null
                  ? 'your_ai_generated_image_is_ready'
                  : 'generation_completed',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (_currentPrompt.isNotEmpty) ...[
              const SizedBox(height: 8),
              LocalizedText(
                '${LocalizationService.t('prompt_label')}: "$_currentPrompt"',
                style: GoogleFonts.poppins(
                  color: Colors.white54,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: LocalizedText(
              'generate_another',
              style: GoogleFonts.poppins(
                color: Colors.purple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_generatedImage != null)
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _navigateToCreatePost();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: LocalizedText(
                'create_post',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _navigateToCreatePost() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_generatedImage != null) {
      debugPrint(
        ('AIGenerationScreen: _generatedImage type: ${_generatedImage.runtimeType}')
            .toString(),
      );
      // Convert generated image to Uint8List if it's a File
      Uint8List? imageBytes;
      if (_generatedImage is Uint8List) {
        imageBytes = _generatedImage as Uint8List;
        debugPrint(
          ('AIGenerationScreen: Using Uint8List with ${imageBytes.length} bytes')
              .toString(),
        );
      } else if (_generatedImage is File) {
        // Read file bytes for File objects
        try {
          imageBytes = await (_generatedImage as File).readAsBytes();
          debugPrint(
            ('AIGenerationScreen: Read ${imageBytes.length} bytes from File')
                .toString(),
          );
        } catch (e) {
          debugPrint(('Error reading file bytes: $e').toString());
          messenger.showSnackBar(
            SnackBar(
              content: LocalizedText(
                'error_processing_generated_image',
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: Colors.purple,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          return;
        }
      }

      if (imageBytes != null) {
        debugPrint(
          ('AIGenerationScreen: Navigating to PhotoCreationScreen with ${imageBytes.length} bytes')
              .toString(),
        );
        final result = await navigator.push(
          MaterialPageRoute(
            builder: (context) =>
                PhotoCreationScreen(preGeneratedImage: imageBytes),
          ),
        );

        // Ensure generation state is reset when returning from PhotoCreationScreen
        debugPrint(
          ('AIGenerationScreen: Returned from PhotoCreationScreen, resetting state')
              .toString(),
        );
        if (mounted) {
          setState(() {
            _isGenerating = false;
            _generationProgress = 0.0;
          });
        }
      } else {
        debugPrint(('AIGenerationScreen: No image data available').toString());
        messenger.showSnackBar(
          SnackBar(
            content: LocalizedText('error_no_image_data_available'),
            backgroundColor: Colors.purple,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } else {
      debugPrint(('AIGenerationScreen: _generatedImage is null').toString());
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: LocalizedText(message),
        backgroundColor: Colors.purple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildGeneratedImage() {
    if (_generatedImage == null) return const SizedBox.shrink();

    // Handle Uint8List (image bytes) - works on all platforms
    if (_generatedImage is Uint8List) {
      return Image.memory(
        _generatedImage as Uint8List,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _aiTypes[_selectedAIType]['gradient'],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.error, size: 50, color: Colors.white),
            ),
          );
        },
      );
    }
    // Handle File (for local file paths) - only on mobile
    else if (_generatedImage is File && !kIsWeb) {
      return Image.file(
        _generatedImage as File,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _aiTypes[_selectedAIType]['gradient'],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(Icons.error, size: 50, color: Colors.white),
            ),
          );
        },
      );
    }

    // Fallback for unsupported types or web with File
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: _aiTypes[_selectedAIType]['gradient']),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.error, size: 50, color: Colors.white),
      ),
    );
  }

  String _getInstructionText() {
    switch (_selectedAIType) {
      case 1: // Style Transfer
        return 'instruction_style_transfer';
      case 3: // Background Remover
        return 'instruction_background_remover';
      case 5: // Text to Video
        return 'instruction_text_to_video';
      case 6: // Image to Video
        return 'instruction_image_to_video';
      default:
        return 'instruction_enter_prompt_above';
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    _pulseController.dispose();
    _promptController.dispose();
    _pageController.dispose();
    // Do not dispose singleton service here
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Debug logging for state
    debugPrint(
      ('AIGenerationScreen build: _isGenerating=$_isGenerating, _generationProgress=$_generationProgress')
          .toString(),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        debugPrint('AIGenerationScreen: PopScope didPop=$didPop');
        // Always navigate to main screen instead of popping
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: Stack(
          children: [
            // Background Gradient
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.purple.withValues(alpha: 0.1),
                    Colors.black,
                    Colors.blue.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),

            // Main Content
            SafeArea(
              child: SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        // Header
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 20,
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const MainScreen(),
                                  ),
                                  (route) => false,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      LocalizationService.t('ai_generation'),
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    LocalizedText(
                                      'ai_generation_subtitle',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Colors.purple, Colors.pink],
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // AI Type Selection
                        SizedBox(
                          height: 120,
                          child: PageView.builder(
                            controller: _pageController,
                            onPageChanged: (index) {
                              setState(() {
                                _selectedAIType = index;
                              });
                            },
                            itemCount: _aiTypes.length,
                            itemBuilder: (context, index) {
                              final aiType = _aiTypes[index];
                              final isSelected = index == _selectedAIType;

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                margin: EdgeInsets.symmetric(
                                  horizontal: isSelected ? 20 : 40,
                                  vertical: isSelected ? 10 : 20,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: aiType['gradient'],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: isSelected
                                      ? [
                                          BoxShadow(
                                            color: aiType['gradient'][0]
                                                .withValues(alpha: 0.3),
                                            blurRadius: 20,
                                            spreadRadius: 5,
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(
                                        aiType['icon'],
                                        color: Colors.white,
                                        size: isSelected ? 32 : 24,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            LocalizedText(
                                              aiType['title'],
                                              style: GoogleFonts.poppins(
                                                color: Colors.white,
                                                fontSize: isSelected ? 16 : 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (isSelected)
                                              LocalizedText(
                                                aiType['subtitle'],
                                                style: GoogleFonts.poppins(
                                                  color: Colors.white70,
                                                  fontSize: 12,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Style Selection for Text to Image
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                'art_style',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                height: 40,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: _artStyles.length,
                                  itemBuilder: (context, index) {
                                    final style = _artStyles[index];
                                    final isSelected = style == _selectedStyle;

                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedStyle = style;
                                        });
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? Colors.purple
                                              : Colors.white.withValues(
                                                  alpha: 0.1,
                                                ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                          border: isSelected
                                              ? Border.all(
                                                  color: Colors.purple,
                                                  width: 2,
                                                )
                                              : null,
                                        ),
                                        child: LocalizedText(
                                          style.toLowerCase().replaceAll(
                                            ' ',
                                            '_',
                                          ),
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Prompt Input
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LocalizedText(
                                'describe_what_you_want_to_create',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Text Input for Image Generation
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: TextField(
                                  controller: _promptController,
                                  onChanged: (value) {
                                    setState(() {
                                      _currentPrompt = value;
                                    });
                                  },
                                  maxLines: 4,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: LocalizationService.t(
                                      'describe_image_hint',
                                    ),
                                    hintStyle: GoogleFonts.poppins(
                                      color: Colors.white54,
                                      fontSize: 16,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.all(16),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // AI Service Status Message
                              Builder(
                                builder: (context) {
                                  final isQwenConfigured = _aiService
                                      .isConfigured();
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: isQwenConfigured
                                          ? Colors.purple.withValues(alpha: 0.1)
                                          : Colors.blue.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isQwenConfigured
                                            ? Colors.purple.withValues(
                                                alpha: 0.3,
                                              )
                                            : Colors.blue.withValues(
                                                alpha: 0.3,
                                              ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isQwenConfigured
                                              ? Icons.star
                                              : Icons.free_breakfast,
                                          color: isQwenConfigured
                                              ? Colors.purple.shade300
                                              : Colors.blue.shade300,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: LocalizedText(
                                            isQwenConfigured
                                                ? 'premium_ai_qwen_high_quality'
                                                : 'free_ai_hf_flux1',
                                            style: GoogleFonts.poppins(
                                              color: isQwenConfigured
                                                  ? Colors.purple.shade300
                                                  : Colors.blue.shade300,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              // Prompt Suggestions or Instructions
                              (_selectedAIType == 0 ||
                                      _selectedAIType == 2 ||
                                      _selectedAIType == 4)
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        LocalizedText(
                                          'try_these_prompts',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          height: 160,
                                          child: ListView.builder(
                                            itemCount:
                                                _promptSuggestions.length,
                                            itemBuilder: (context, index) {
                                              final suggestion =
                                                  _promptSuggestions[index];
                                              return GestureDetector(
                                                onTap: () {
                                                  _promptController.text =
                                                      suggestion;
                                                  setState(() {
                                                    _currentPrompt = suggestion;
                                                  });
                                                },
                                                child: Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 8,
                                                  ),
                                                  padding: const EdgeInsets.all(
                                                    12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white
                                                        .withValues(
                                                          alpha: 0.05,
                                                        ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.lightbulb_outline,
                                                        color: Colors.yellow
                                                            .withValues(
                                                              alpha: 0.7,
                                                            ),
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: LocalizedText(
                                                          suggestion,
                                                          style:
                                                              GoogleFonts.poppins(
                                                                color: Colors
                                                                    .white70,
                                                                fontSize: 12,
                                                              ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    )
                                  : SizedBox(
                                      height: 160,
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              _aiTypes[_selectedAIType]['icon'],
                                              size: 64,
                                              color: Colors.white.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            LocalizedText(
                                              _getInstructionText(),
                                              style: GoogleFonts.poppins(
                                                color: Colors.white70,
                                                fontSize: 14,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                            ],
                          ),
                        ),

                        // Close main Column and wrappers
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Generation Progress Overlay
            if (_isGenerating)
              Container(
                color: Colors.black.withValues(alpha: 0.8),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _pulseAnimation.value,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: _aiTypes[_selectedAIType]['gradient'],
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.auto_awesome,
                                color: Colors.white,
                                size: 50,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 32),
                      Text(
                        LocalizationService.t('generating_your_content'),
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 200,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: AnimatedBuilder(
                          animation: _shimmerAnimation,
                          builder: (context, child) {
                            return Stack(
                              children: [
                                Container(
                                  width: 200 * _generationProgress,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors:
                                          _aiTypes[_selectedAIType]['gradient'],
                                    ),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                if (_generationProgress > 0)
                                  Positioned(
                                    left:
                                        (200 * _generationProgress) +
                                        (_shimmerAnimation.value * 50) -
                                        25,
                                    child: Container(
                                      width: 50,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.white.withValues(alpha: 0.5),
                                            Colors.transparent,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${(_generationProgress * 100).toInt()}%',
                        style: GoogleFonts.poppins(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),

        // Generate Button
        floatingActionButton: !_isGenerating
            ? FloatingActionButton.extended(
                onPressed: _startGeneration,
                backgroundColor: Colors.purple,
                icon: const Icon(Icons.auto_awesome, color: Colors.white),
                label: LocalizedText(
                  'generate',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    );
  }
}
