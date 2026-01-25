import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/posts_service.dart';
import 'main_screen.dart';
import 'dart:convert';
import 'package:equal/config/supabase_config.dart';
import '../services/localization_service.dart';

class TextCreationScreen extends StatefulWidget {
  final String? parentPostId;
  const TextCreationScreen({super.key, this.parentPostId});

  @override
  State<TextCreationScreen> createState() => _TextCreationScreenState();
}

class _TextCreationScreenState extends State<TextCreationScreen>
    with TickerProviderStateMixin {
  // Listen for locale changes to rebuild UI when language switches
  late VoidCallback _localeListener;
  // Track whether the center text is still the default localized hint
  bool _isDefaultText = true;
  final TextEditingController _textController = TextEditingController();
  final TextEditingController _captionController = TextEditingController();
  final TextEditingController _hashtagController = TextEditingController();

  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  // Text styling properties
  String _selectedFont = 'Poppins';
  double _fontSize = 24.0;
  Color _textColor = Colors.white;
  final Color _backgroundColor = Colors.blue;
  TextAlign _textAlign = TextAlign.center;
  FontWeight _fontWeight = FontWeight.normal;
  bool _isItalic = false;
  bool _hasStroke = false;
  final Color _strokeColor = Colors.black;
  final double _strokeWidth = 2.0;
  bool _hasShadow = false;
  final Color _shadowColor = Colors.black54;
  final double _shadowBlur = 4.0;
  final Offset _shadowOffset = const Offset(2, 2);

  // Background properties
  int _selectedBackground = 0;
  bool _showBackgrounds = false;
  bool _showFonts = false;
  bool _showColors = false;
  bool _showTemplates = false;

  final List<String> _fonts = [
    'Poppins',
    'Roboto',
    'Montserrat',
    'Playfair Display',
    'Dancing Script',
    'Bebas Neue',
    'Pacifico',
    'Righteous',
    'Fredoka One',
    'Comfortaa',
  ];

  final List<Color> _textColors = [
    Colors.white,
    Colors.black,
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.blue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lime,
    Colors.yellow,
    Colors.orange,
    Colors.brown,
    Colors.grey,
  ];

  final List<LinearGradient> _backgrounds = [
    const LinearGradient(
      colors: [Color(0xFF667eea), Color(0xFF764ba2)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFFf093fb), Color(0xFFf5576c)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFF4facfe), Color(0xFF00f2fe)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFF43e97b), Color(0xFF38f9d7)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFFfa709a), Color(0xFFfee140)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFFa8edea), Color(0xFFfed6e3)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFFffecd2), Color(0xFFfcb69f)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFFa18cd1), Color(0xFFfbc2eb)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFF89f7fe), Color(0xFF66a6ff)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    const LinearGradient(
      colors: [Color(0xFFfad0c4), Color(0xFFffd1ff)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  ];

  final List<Map<String, dynamic>> _templates = [
    {
      'name': 'template_quote',
      'text': '"Your text here"',
      'fontSize': 28.0,
      'fontWeight': FontWeight.w600,
      'textAlign': TextAlign.center,
      'background': 0,
    },
    {
      'name': 'template_motivation',
      'text': 'BELIEVE\nIN\nYOURSELF',
      'fontSize': 32.0,
      'fontWeight': FontWeight.bold,
      'textAlign': TextAlign.center,
      'background': 1,
    },
    {
      'name': 'template_announcement',
      'text': 'BIG NEWS!\nSomething amazing\nis coming...',
      'fontSize': 24.0,
      'fontWeight': FontWeight.w700,
      'textAlign': TextAlign.center,
      'background': 2,
    },
    {
      'name': 'template_question',
      'text': 'What do you think\nabout this?',
      'fontSize': 26.0,
      'fontWeight': FontWeight.w500,
      'textAlign': TextAlign.center,
      'background': 3,
    },
    {
      'name': 'template_celebration',
      'text': '🎉 AMAZING! 🎉\nWe did it!',
      'fontSize': 30.0,
      'fontWeight': FontWeight.bold,
      'textAlign': TextAlign.center,
      'background': 4,
    },
    {
      'name': 'template_tip',
      'text': '💡 Pro Tip:\nYour helpful advice here',
      'fontSize': 22.0,
      'fontWeight': FontWeight.w600,
      'textAlign': TextAlign.left,
      'background': 5,
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _textController.text = LocalizationService.t('tap_to_edit_text');
    _isDefaultText = true;
    // Rebuild the screen when the app language changes so all
    // LocalizationService.t(...) usages refresh correctly
    _localeListener = () {
      if (!mounted) return;
      // If unchanged by the user, keep the hint in sync with locale
      if (_isDefaultText) {
        _textController.text = LocalizationService.t('tap_to_edit_text');
      }
      setState(() {});
    };
    LocalizationService.localeNotifier.addListener(_localeListener);
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _textController.dispose();
    _captionController.dispose();
    _hashtagController.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    LocalizationService.localeNotifier.removeListener(_localeListener);
    super.dispose();
  }

  void _showPanel(String panel) {
    setState(() {
      _showBackgrounds = panel == 'backgrounds';
      _showFonts = panel == 'fonts';
      _showColors = panel == 'colors';
      _showTemplates = panel == 'templates';
    });

    if (panel != 'none') {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _textController.text = template['text'];
      _fontSize = template['fontSize'];
      _fontWeight = template['fontWeight'];
      _textAlign = template['textAlign'];
      _selectedBackground = template['background'];
    });
    _showPanel('none');
  }

  Future<void> _publishPost() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LocalizedText('please_enter_text_to_post'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check text size limit
    final bytes = utf8.encode(_textController.text);
    if (bytes.length > SupabaseConfig.maxTextSize) {
      final limit = (SupabaseConfig.maxTextSize ~/ (1024 * 1024)).toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LocalizationService.t(
              'text_size_exceeds_limit',
            ).replaceAll('{limit}', limit),
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      // Prepare post content
      String postContent = _textController.text.trim();

      // Add caption if provided
      if (_captionController.text.trim().isNotEmpty) {
        postContent += '\n\n${_captionController.text.trim()}';
      }

      // Create text post using PostsService
      await PostsService().createPost(
        type: 'text',
        caption: postContent,
        hashtags: _hashtagController.text.trim().isEmpty
            ? null
            : _hashtagController.text.trim().split(' '),
        parentPostId: widget.parentPostId,
      );

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: LocalizedText('text_post_published_success'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${LocalizationService.t('failed_to_publish_text_post')}: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  TextStyle _getFontPreviewStyle(String fontName) {
    // Helper method for font previews in the font selection panel
    switch (fontName) {
      case 'Poppins':
        return GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Roboto':
        return GoogleFonts.roboto(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Montserrat':
        return GoogleFonts.montserrat(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Playfair Display':
        return GoogleFonts.playfairDisplay(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Dancing Script':
        return GoogleFonts.dancingScript(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Bebas Neue':
        return GoogleFonts.bebasNeue(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Pacifico':
        return GoogleFonts.pacifico(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Righteous':
        return GoogleFonts.righteous(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Fredoka One':
        return GoogleFonts.fredoka(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      case 'Comfortaa':
        return GoogleFonts.comfortaa(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
      default:
        return GoogleFonts.poppins(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        );
    }
  }

  TextStyle _getTextStyle() {
    // Map font names to their correct GoogleFonts methods
    switch (_selectedFont) {
      case 'Poppins':
        return GoogleFonts.poppins(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Roboto':
        return GoogleFonts.roboto(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Montserrat':
        return GoogleFonts.montserrat(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Playfair Display':
        return GoogleFonts.playfairDisplay(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Dancing Script':
        return GoogleFonts.dancingScript(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Bebas Neue':
        return GoogleFonts.bebasNeue(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Pacifico':
        return GoogleFonts.pacifico(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Righteous':
        return GoogleFonts.righteous(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Fredoka One':
        return GoogleFonts.fredoka(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      case 'Comfortaa':
        return GoogleFonts.comfortaa(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
      default:
        return GoogleFonts.poppins(
          fontSize: _fontSize,
          color: _textColor,
          fontWeight: _fontWeight,
          fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: _hasShadow
              ? [
                  Shadow(
                    color: _shadowColor,
                    blurRadius: _shadowBlur,
                    offset: _shadowOffset,
                  ),
                ]
              : null,
        );
    }
  }

  Widget _buildStrokeText(String text, TextStyle style) {
    if (!_hasStroke) {
      return Text(text, style: style, textAlign: _textAlign);
    }

    return Stack(
      children: [
        // Stroke
        Text(
          text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _strokeWidth
              ..color = _strokeColor,
          ),
          textAlign: _textAlign,
        ),
        // Fill
        Text(text, style: style, textAlign: _textAlign),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: _backgrounds[_selectedBackground],
              ),
            ),
          ),

          // Main Text Display
          Positioned.fill(
            child: Center(
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.all(40),
                      child: GestureDetector(
                        onTap: () {
                          _showEditDialog();
                        },
                        child: _buildStrokeText(
                          _textController.text,
                          _getTextStyle(),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Top Controls
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Close Button
                GestureDetector(
                  onTap: () => Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const MainScreen()),
                    (route) => false,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),

                // Title
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: LocalizedText(
                    'text_post',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

                // Share Button
                GestureDetector(
                  onTap: _publishPost,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.send, color: Colors.white, size: 16),
                        const SizedBox(width: 4),
                        LocalizedText(
                          'publish',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Side Controls
          Positioned(
            right: 20,
            top: MediaQuery.of(context).size.height * 0.25,
            child: Column(
              children: [
                _buildSideButton(
                  icon: Icons.palette,
                  labelKey: 'backgrounds',
                  isActive: _showBackgrounds,
                  onTap: () =>
                      _showPanel(_showBackgrounds ? 'none' : 'backgrounds'),
                ),
                const SizedBox(height: 15),
                _buildSideButton(
                  icon: Icons.font_download,
                  labelKey: 'fonts',
                  isActive: _showFonts,
                  onTap: () => _showPanel(_showFonts ? 'none' : 'fonts'),
                ),
                const SizedBox(height: 15),
                _buildSideButton(
                  icon: Icons.color_lens,
                  labelKey: 'colors',
                  isActive: _showColors,
                  onTap: () => _showPanel(_showColors ? 'none' : 'colors'),
                ),
                const SizedBox(height: 15),
                _buildSideButton(
                  icon: Icons.auto_awesome,
                  labelKey: 'templates',
                  isActive: _showTemplates,
                  onTap: () =>
                      _showPanel(_showTemplates ? 'none' : 'templates'),
                ),
                const SizedBox(height: 15),
                _buildSideButton(
                  icon: Icons.text_fields,
                  labelKey: 'text_style',
                  isActive: false,
                  onTap: _showStyleDialog,
                ),
              ],
            ),
          ),

          // Bottom Panels
          if (_showBackgrounds || _showFonts || _showColors || _showTemplates)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.95),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (_showBackgrounds) _buildBackgroundPanel(),
                      if (_showFonts) _buildFontPanel(),
                      if (_showColors) _buildColorPanel(),
                      if (_showTemplates) _buildTemplatePanel(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSideButton({
    required IconData icon,
    required String labelKey,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blue.withValues(alpha: 0.8)
              : Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? Colors.blue : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            LocalizedText(
              labelKey,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundPanel() {
    return Expanded(
      child: Column(
        children: [
          LocalizedText(
            'choose_background',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _backgrounds.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedBackground = index;
                    });
                  },
                  child: Container(
                    width: 60,
                    height: 80,
                    margin: const EdgeInsets.only(right: 15),
                    decoration: BoxDecoration(
                      gradient: _backgrounds[index],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedBackground == index
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFontPanel() {
    return Expanded(
      child: Column(
        children: [
          LocalizedText(
            'choose_font',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _fonts.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFont = _fonts[index];
                    });
                  },
                  child: Container(
                    width: 80,
                    margin: const EdgeInsets.only(right: 15),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _selectedFont == _fonts[index]
                          ? Colors.blue.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedFont == _fonts[index]
                            ? Colors.blue
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Aa', style: _getFontPreviewStyle(_fonts[index])),
                        const SizedBox(height: 4),
                        Text(
                          _fonts[index],
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorPanel() {
    return Expanded(
      child: Column(
        children: [
          LocalizedText(
            'choose_text_color',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _textColors.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _textColor = _textColors[index];
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: _textColors[index],
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _textColor == _textColors[index]
                            ? Colors.white
                            : Colors.transparent,
                        width: 3,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplatePanel() {
    return Expanded(
      child: Column(
        children: [
          LocalizedText(
            'choose_template',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 15),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _templates.length,
              itemBuilder: (context, index) {
                final template = _templates[index];
                return GestureDetector(
                  onTap: () => _applyTemplate(template),
                  child: Container(
                    width: 100,
                    margin: const EdgeInsets.only(right: 15),
                    decoration: BoxDecoration(
                      gradient: _backgrounds[template['background']],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Center(
                            child: Text(
                              template['text'],
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: template['fontWeight'],
                              ),
                              textAlign: template['textAlign'],
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(12),
                            ),
                          ),
                          child: LocalizedText(
                            template['name'],
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
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
      ),
    );
  }

  void _showEditDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: LocalizedText(
          'edit_text',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: TextField(
          controller: _textController,
          style: GoogleFonts.poppins(color: Colors.white),
          maxLines: 5,
          decoration: InputDecoration(
            hintText: LocalizationService.t('enter_text_here'),
            hintStyle: GoogleFonts.poppins(color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              LocalizationService.t('cancel'),
              style: GoogleFonts.poppins(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // If user leaves it empty, restore localized hint; otherwise
              // mark as user-provided so we don't auto-change on locale switch
              final newText = _textController.text.trim();
              setState(() {
                if (newText.isEmpty) {
                  _textController.text = LocalizationService.t(
                    'tap_to_edit_text',
                  );
                  _isDefaultText = true;
                } else {
                  _isDefaultText = false;
                }
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              LocalizationService.t('apply'),
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

  void _showStyleDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: LocalizedText(
            'text_style',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Font Size
                Row(
                  children: [
                    Text(
                      '${LocalizationService.t('size')}: ${_fontSize.round()}',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    Expanded(
                      child: Slider(
                        value: _fontSize,
                        min: 12,
                        max: 48,
                        activeColor: Colors.blue,
                        onChanged: (value) {
                          setDialogState(() {
                            _fontSize = value;
                          });
                          setState(() {});
                        },
                      ),
                    ),
                  ],
                ),

                // Font Weight
                Row(
                  children: [
                    Text(
                      '${LocalizationService.t('weight')}:',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<FontWeight>(
                      value: _fontWeight,
                      dropdownColor: Colors.grey[800],
                      style: GoogleFonts.poppins(color: Colors.white),
                      items: [
                        DropdownMenuItem(
                          value: FontWeight.w300,
                          child: Text(LocalizationService.t('light')),
                        ),
                        DropdownMenuItem(
                          value: FontWeight.normal,
                          child: Text(LocalizationService.t('normal')),
                        ),
                        DropdownMenuItem(
                          value: FontWeight.w600,
                          child: Text(LocalizationService.t('semi_bold')),
                        ),
                        DropdownMenuItem(
                          value: FontWeight.bold,
                          child: Text(LocalizationService.t('bold')),
                        ),
                        DropdownMenuItem(
                          value: FontWeight.w900,
                          child: Text(LocalizationService.t('black')),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _fontWeight = value!;
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ),

                // Text Align
                Row(
                  children: [
                    Text(
                      '${LocalizationService.t('align')}:',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    DropdownButton<TextAlign>(
                      value: _textAlign,
                      dropdownColor: Colors.grey[800],
                      style: GoogleFonts.poppins(color: Colors.white),
                      items: [
                        DropdownMenuItem(
                          value: TextAlign.left,
                          child: Text(LocalizationService.t('left')),
                        ),
                        DropdownMenuItem(
                          value: TextAlign.center,
                          child: Text(LocalizationService.t('center')),
                        ),
                        DropdownMenuItem(
                          value: TextAlign.right,
                          child: Text(LocalizationService.t('right')),
                        ),
                      ],
                      onChanged: (value) {
                        setDialogState(() {
                          _textAlign = value!;
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ),

                // Italic Toggle
                Row(
                  children: [
                    Text(
                      '${LocalizationService.t('italic')}:',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    Switch(
                      value: _isItalic,
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setDialogState(() {
                          _isItalic = value;
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ),

                // Stroke Toggle
                Row(
                  children: [
                    Text(
                      '${LocalizationService.t('stroke')}:',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    Switch(
                      value: _hasStroke,
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setDialogState(() {
                          _hasStroke = value;
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ),

                // Shadow Toggle
                Row(
                  children: [
                    Text(
                      '${LocalizationService.t('shadow')}:',
                      style: GoogleFonts.poppins(color: Colors.white),
                    ),
                    Switch(
                      value: _hasShadow,
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setDialogState(() {
                          _hasShadow = value;
                        });
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                LocalizationService.t('done'),
                style: GoogleFonts.poppins(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
