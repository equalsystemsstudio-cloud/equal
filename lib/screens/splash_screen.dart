import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'language_selection_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Brand tokens
  static const Color _brandGold = Color(0xFFFFD700);
  static const Color _brandGoldDark = Color(0xFFB8860B);
  static const Color _brandAccent = Color(0xFFFFA500);
  static const Color _brandBgDark = Color(0xFF0B1020);
  static const Color _brandBgLight = Color(0xFFF6F7FB);
  static const String _brandLogoSvg = 'assets/icons/app_icon.svg';
  late AnimationController _logoController;
  late AnimationController _textController;
  late AnimationController _backgroundController;
  late AnimationController _progressController;
  late AnimationController _pulseController;
  late AnimationController _tiltController;

  late Animation<double> _logoScale;
  // ignore: unused_field
  late Animation<double> _logoRotation;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _backgroundOpacity;
  late Animation<double> _progressAnimation;
  late Animation<double> _pulse;
  late Animation<double> _tilt;

  double _progress = 0.0;
  bool _hasNavigated = false;
  DateTime? _progressStartTime;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _startAnimationSequence();
  }

  void _initializeAnimations() {
    // Logo animations
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _logoScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );

    _logoRotation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.8, curve: Curves.easeInOut),
      ),
    );

    // Subtle breathing pulse
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.98, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Gentle 3D tilt for premium feel
    _tiltController = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    )..repeat(reverse: true);
    _tilt = Tween<double>(begin: -0.02, end: 0.02).animate(
      CurvedAnimation(parent: _tiltController, curve: Curves.easeInOut),
    );

    // Progress animations
    _progressController = AnimationController(
      duration: const Duration(
        milliseconds: 12000,
      ), // Slower progress for visibility
      vsync: this,
    );

    _progressAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressController, curve: Curves.easeInOut),
    );

    // Text animations
    _textController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _textController, curve: Curves.easeInOut),
    );

    _textSlide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _textController, curve: Curves.easeOutBack),
        );

    // Background animations
    _backgroundController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _backgroundOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _backgroundController, curve: Curves.easeInOut),
    );
  }

  void _startAnimationSequence() async {
    // Start background animation
    if (mounted) _backgroundController.forward();

    // Start logo animation after a short delay
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) _logoController.forward();

    // Start text animation
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) _textController.forward();

    // Start progress animation
    await Future.delayed(const Duration(milliseconds: 1000));
    if (mounted) {
      _progressStartTime = DateTime.now();
      _progressController.forward();
    }

    // Listen to progress changes
    _progressController.addListener(() {
      setState(() {
        _progress = _progressAnimation.value;
        final hasMinTimeElapsed =
            _progressStartTime != null &&
            DateTime.now().difference(_progressStartTime!).inMilliseconds >=
                10000;
        // Navigation is now controlled centrally by AuthWrapper.
        // SplashScreen no longer auto-navigates to LanguageSelectionScreen.
        // This prevents conflicting navigations and ensures language selection appears first consistently.
      });
    });

    // Navigation is handled when progress reaches 100%
    // (removed fixed delay navigation)
  }

  @override
  void dispose() {
    _logoController.dispose();
    _textController.dispose();
    _backgroundController.dispose();
    _progressController.dispose();
    _pulseController.dispose();
    _tiltController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool reduceMotion =
        MediaQuery.of(context).disableAnimations ||
        MediaQuery.of(context).accessibleNavigation;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color bgTop = isDark ? _brandBgDark : _brandBgLight;
    final Color bgBottom = isDark
        ? const Color(0xFF0F1430)
        : const Color(0xFFEFF2FA);
    final Color ringStart = _brandGold;
    final Color ringEnd = _brandAccent;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([
              _logoController,
              _textController,
              _backgroundController,
              _pulseController,
              _tiltController,
            ]),
            builder: (context, child) {
              return Stack(
                children: [
                  // Animated background particles
                  ...List.generate(20, (index) {
                    return Positioned(
                      left: (index * 37.0) % MediaQuery.of(context).size.width,
                      top: (index * 43.0) % MediaQuery.of(context).size.height,
                      child: AnimatedBuilder(
                        animation: _backgroundController,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _backgroundOpacity.value,
                            child: Container(
                              width: 4 + (index % 3) * 2,
                              height: 4 + (index % 3) * 2,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(
                                  alpha: 0.1 + (index % 4) * 0.1,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }),

                  // Main content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Premium 3D Logo with dynamic motion (accessible fallback respected)
                        Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..rotateX(reduceMotion ? 0.0 : _tilt.value)
                            ..rotateY(reduceMotion ? 0.0 : -_tilt.value),
                          child: Transform.scale(
                            scale: reduceMotion
                                ? 1.0
                                : (_logoScale.value * _pulse.value),
                            child: Transform.rotate(
                              angle: reduceMotion ? 0.0 : (_progress * 6.28318),
                              child: Container(
                                width: 140,
                                height: 140,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: ringStart.withValues(alpha: 0.6),
                                      blurRadius: 30,
                                      spreadRadius: 8,
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Outer gold ring
                                    Container(
                                      width: 120,
                                      height: 120,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            ringStart, // Gold
                                            ringEnd, // Orange gold
                                            _brandGoldDark, // Dark gold
                                            ringStart, // Gold
                                          ],
                                          stops: const [0.0, 0.3, 0.7, 1.0],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: ringStart.withValues(
                                              alpha: 0.8,
                                            ),
                                            blurRadius: 15,
                                            spreadRadius: 2,
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.3,
                                            ),
                                            blurRadius: 10,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Inner premium background
                                    Container(
                                      width: 100,
                                      height: 100,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Colors.white,
                                            const Color(
                                              0xFFF8F8FF,
                                            ), // Ghost white
                                            const Color(0xFFE6E6FA), // Lavender
                                            Colors.white,
                                          ],
                                          stops: const [0.0, 0.3, 0.7, 1.0],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.white.withValues(
                                              alpha: 0.9,
                                            ),
                                            blurRadius: 20,
                                            spreadRadius: 1,
                                          ),
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.1,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: SvgPicture.asset(
                                          _brandLogoSvg,
                                          width: 64,
                                          height: 64,
                                        ),
                                      ),
                                    ),
                                    // Highlight effect
                                    Positioned(
                                      top: 15,
                                      left: 20,
                                      child: Container(
                                        width: 25,
                                        height: 25,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: RadialGradient(
                                            colors: [
                                              Colors.white.withValues(
                                                alpha: 0.8,
                                              ),
                                              Colors.white.withValues(
                                                alpha: 0.0,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // App name with slide animation
                        SlideTransition(
                          position: _textSlide,
                          child: FadeTransition(
                            opacity: _textOpacity,
                            child: Column(
                              children: [
                                Text(
                                  'EQUAL',
                                  style: GoogleFonts.poppins(
                                    fontSize: 48,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 4,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.3,
                                        ),
                                        offset: const Offset(0, 4),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Where Everyone is a Star',
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white.withValues(alpha: 0.9),
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 60),

                        // Premium Progress Bar
                        FadeTransition(
                          opacity: _textOpacity,
                          child: Column(
                            children: [
                              // Progress percentage text
                              Text(
                                '${(_progress * 100).toInt()}%',
                                style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.9),
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Premium progress bar container
                              Container(
                                width: 280,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.2,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  children: [
                                    // Background track
                                    Container(
                                      width: 280,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white.withValues(alpha: 0.2),
                                            Colors.white.withValues(alpha: 0.1),
                                          ],
                                        ),
                                      ),
                                    ),
                                    // Progress fill
                                    Container(
                                      width: 280 * _progress,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            const Color(0xFFFFD700), // Gold
                                            const Color(
                                              0xFFFFA500,
                                            ), // Orange gold
                                            const Color(0xFFFFD700), // Gold
                                            Colors.white,
                                          ],
                                          stops: const [0.0, 0.3, 0.7, 1.0],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(
                                              0xFFFFD700,
                                            ).withValues(alpha: 0.6),
                                            blurRadius: 12,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Animated shimmer effect
                                    if (_progress > 0)
                                      Positioned(
                                        left: (280 * _progress) - 20,
                                        child: Container(
                                          width: 20,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            gradient: LinearGradient(
                                              colors: [
                                                Colors.white.withValues(
                                                  alpha: 0.0,
                                                ),
                                                Colors.white.withValues(
                                                  alpha: 0.8,
                                                ),
                                                Colors.white.withValues(
                                                  alpha: 0.0,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Loading text
                              Text(
                                'Loading Premium Experience...',
                                style: GoogleFonts.poppins(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white.withValues(alpha: 0.7),
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
