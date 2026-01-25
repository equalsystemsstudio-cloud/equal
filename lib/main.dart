import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/post_detail_wrapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'screens/language_selection_screen.dart';
import 'screens/main_feed_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/update_password_screen.dart';
import 'screens/main_screen.dart';
import 'services/localization_service.dart';
import 'services/app_service.dart';
import 'services/push_notification_service.dart';
import 'services/preferences_service.dart';
import 'config/app_colors.dart';
import 'config/supabase_config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/push_notification_service.dart'
    show PushNotificationService, firebaseMessagingBackgroundHandler;
import 'package:flutter/foundation.dart';
import 'services/history_service.dart';
import 'screens/history_screen.dart';

// Global RouteObserver for tracking navigation
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Global error handlers to prevent silent crashes in release
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint(('FlutterError: ${details.exceptionAsString()}').toString());
    if (details.stack != null) {
      debugPrint(details.stack.toString());
    }
  };
  // Capture errors outside Flutter widgets (e.g., platform/channel errors)
  WidgetsBinding.instance.platformDispatcher.onError =
      (Object error, StackTrace stack) {
        debugPrint(('PlatformDispatcher Error: $error').toString());
        debugPrint(stack.toString());
        return true; // prevent app from silently crashing
      };

  // Initialize app service first
  final appService = AppService();

  try {
    // Initialize Supabase first (critical for app functionality)
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    );
    debugPrint(('Supabase initialized successfully').toString());
  } catch (e, st) {
    debugPrint(('Supabase initialization failed: $e').toString());
    debugPrint(st.toString());
    // This is critical - app cannot function without Supabase
  }

  try {
    // Initialize Firebase with timeout
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint(('Firebase initialized successfully').toString());

    // Register background message handler immediately after Firebase init
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    debugPrint(('Firebase initialization failed: $e').toString());
    debugPrint(st.toString());
    // Continue without Firebase
  }

  try {
    // Initialize push notifications with timeout
    await PushNotificationService().initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint(('Push notification initialization timed out').toString());
      },
    );
  } catch (e, st) {
    debugPrint(('Push notification initialization failed: $e').toString());
    debugPrint(st.toString());
    // Continue without push notifications
  }

  try {
    // Initialize localization service with timeout
    await LocalizationService.init().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint(('Localization initialization timed out').toString());
      },
    );
    // Disable dynamic auto-translation to keep UI strictly keyed
    LocalizationService.clearAutoTranslateCache();
    await LocalizationService.setAutoTranslateEnabled(false);
  } catch (e, st) {
    debugPrint(('Localization initialization failed: $e').toString());
    debugPrint(st.toString());
    // Continue with default language
  }

  try {
    // Initialize HistoryService to populate notifier from SharedPreferences
    await HistoryService.init();
  } catch (e) {
    debugPrint(('HistoryService init failed: $e').toString());
  }

  try {
    // Set system UI overlay style
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );

    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } catch (e, st) {
    debugPrint(('System UI configuration failed: $e').toString());
    debugPrint(st.toString());
    // Continue without system UI changes
  }

  try {
    // Initialize app services with timeout
    await appService.initialize().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint(('App service initialization timed out').toString());
      },
    );
  } catch (e, st) {
    debugPrint(('App service initialization failed: $e').toString());
    debugPrint(st.toString());
    // Continue with limited functionality
  }

  runApp(EqualApp(appService: appService));
}

class EqualApp extends StatefulWidget {
  final AppService appService;

  const EqualApp({super.key, required this.appService});

  @override
  State<EqualApp> createState() => _EqualAppState();
}

class _EqualAppState extends State<EqualApp> {
  final PreferencesService _preferencesService = PreferencesService();
  ThemeMode _themeMode = ThemeMode.dark; // Default to current dark vibe

  // Listen to locale changes
  late final VoidCallback _localeListener;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
    // Listen for dark mode preference changes and update theme in real time
    PreferencesService.darkModeNotifier.addListener(_handleDarkModeChange);

    // Subscribe to locale changes to rebuild MaterialApp
    _localeListener = () {
      if (!mounted) return;
      setState(() {});
    };
    LocalizationService.localeNotifier.addListener(_localeListener);

    // After first frame, process any pending notification navigation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        PushNotificationService().processPendingNavigation();
      } catch (e) {
        debugPrint(('Error processing pending navigation: $e').toString());
      }
    });
  }

  Future<void> _loadThemePreference() async {
    try {
      final darkEnabled = await _preferencesService.getDarkModeEnabled();
      if (mounted) {
        setState(() {
          _themeMode = darkEnabled ? ThemeMode.dark : ThemeMode.light;
        });
      }
    } catch (e) {
      // Keep default ThemeMode.dark if prefs fail
    }
  }

  void _handleDarkModeChange() {
    if (!mounted) return;
    setState(() {
      _themeMode = PreferencesService.darkModeNotifier.value
          ? ThemeMode.dark
          : ThemeMode.light;
    });
  }

  @override
  void dispose() {
    PreferencesService.darkModeNotifier.removeListener(_handleDarkModeChange);
    LocalizationService.localeNotifier.removeListener(_localeListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData lightTheme = ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(
        0xFFF3F4F6,
      ), // Whitish gray background
      textTheme: GoogleFonts.poppinsTextTheme(
        Theme.of(context).textTheme,
      ).apply(bodyColor: Colors.black87, displayColor: Colors.black87),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      useMaterial3: true,
    );

    final ThemeData darkTheme = ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.black,
      textTheme: GoogleFonts.poppinsTextTheme(
        Theme.of(context).textTheme,
      ).apply(bodyColor: Colors.white, displayColor: Colors.white),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      useMaterial3: true,
    );

    return MaterialApp(
      key: ValueKey(LocalizationService.currentLanguage),
      title: 'Equal - Revolutionary Social Media',
      debugShowCheckedModeBanner: false,
      navigatorKey: PushNotificationService.navigatorKey,
      navigatorObservers: [routeObserver],
      locale: LocalizationService.localeNotifier.value, // react to changes
      supportedLocales: LocalizationService.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routes: {
        '/main': (context) => const MainScreen(),
        '/login': (context) => const LoginScreen(),
        '/update-password': (context) => const UpdatePasswordScreen(),
        '/language-selection': (context) => const LanguageSelectionScreen(),
        '/main-feed': (context) => const MainFeedScreen(),
        '/history': (context) => const HistoryScreen(),
      },
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _themeMode,
      builder: (context, child) {
        // Clamp global text scaling to keep consistent sizes across devices
        final media = MediaQuery.of(context);
        final fixedScaleMedia = media.copyWith(
          // Slightly reduce global text size to mitigate overflow
          textScaler: const TextScaler.linear(0.95),
        );
        // Global error UI to avoid blank screen in release
        ErrorWidget.builder = (FlutterErrorDetails details) {
          debugPrint(
            ('ErrorWidget: ${details.exceptionAsString()}').toString(),
          );
          final bool isAuthenticated =
              Supabase.instance.client.auth.currentUser != null;
          return Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.white,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Something went wrong',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          details.exceptionAsString(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.black,
                              ),
                              onPressed: () {
                                final navigator = PushNotificationService
                                    .navigatorKey
                                    .currentState;
                                if (navigator == null) return;
                                if (isAuthenticated) {
                                  navigator.pushNamedAndRemoveUntil(
                                    '/main',
                                    (route) => false,
                                  );
                                } else {
                                  navigator.pushNamedAndRemoveUntil(
                                    '/login',
                                    (route) => false,
                                  );
                                }
                              },
                              child: const Text('Go to Home'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        };
        // Ensure we always render something; avoid blank page when child is null on web
        return MediaQuery(
          data: fixedScaleMedia,
          child: child ?? const SplashScreen(),
        );
      },
      home: AuthWrapper(appService: widget.appService),
      onGenerateRoute: (settings) {
        if (settings.name == '/post_detail') {
          final postId = settings.arguments as String?;
          if (postId != null) {
            return MaterialPageRoute(
              builder: (context) => PostDetailWrapper(postId: postId),
            );
          }
        }
        return null;
      },
    );
  }
}

class AuthWrapper extends StatefulWidget {
  final AppService appService;

  const AuthWrapper({super.key, required this.appService});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> with WidgetsBindingObserver {
  bool _isLoading = true;
  User? _user;
  late AppLinks _appLinks;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeAppLinks();
    _checkAuthState();
    _setupAppStateListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initializeAppLinks() {
    if (kIsWeb) {
      // Check initial URL on web for auth callback
      _handleIncomingLink(Uri.base);
      return;
    }
    try {
      _appLinks = AppLinks();
      // Handle incoming links when app is already running
      _appLinks.uriLinkStream.listen((uri) {
        _handleIncomingLink(uri);
      });
      // Handle initial link when app is launched from a link
      _appLinks.getInitialLink().then((uri) {
        if (uri != null) {
          _handleIncomingLink(uri);
        }
      });
    } catch (e) {
      debugPrint('AppLinks init failed: $e');
    }
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    // 1. Auth Callback Handling (Deep Link & Web)
    // Check for explicit deep link OR web URL with auth fragment
    final isDeepLinkAuth =
        uri.scheme == 'equal' && uri.host == 'auth' && uri.path == '/callback';
    final isWebAuth = kIsWeb && uri.fragment.contains('access_token');

    if (isDeepLinkAuth || isWebAuth) {
      // Extract the fragment from the URI which contains the auth tokens
      final fragment = uri.fragment;
      if (fragment.isNotEmpty) {
        // Parse the fragment to get access_token and refresh_token
        final params = Uri.splitQueryString(fragment);
        final accessToken = params['access_token'];
        final refreshToken = params['refresh_token'];
        final type = params['type'];

        if (refreshToken != null) {
          // Check if this is a password recovery flow BEFORE setting session
          // This prevents the race condition where auth state listener fires
          // 'authenticated' (triggering main nav) before we can set the recovery flag
          if (type == 'recovery') {
            widget.appService.handlePasswordRecovery();
          }

          // Set the session with the refresh token
          await Supabase.instance.client.auth.setSession(refreshToken);

          // If recovery, stop here - AppService listener will handle the rest
          if (type == 'recovery') return;

          // Manually update the UI state after setting session
          final user = Supabase.instance.client.auth.currentUser;
          if (mounted && user != null) {
            setState(() {
              _user = user;
            });
          }
        }
      }
      return;
    }

    // Post deep links: equal://post/<id> or https://equal-co.com/post/<id>
    String? postId;
    if (uri.scheme == 'equal' && uri.host == 'post') {
      if (uri.pathSegments.isNotEmpty) {
        postId = uri.pathSegments.first;
      }
    } else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        (uri.host == 'equal-co.com' || uri.host == 'www.equal-co.com')) {
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.first == 'post') {
        if (uri.pathSegments.length > 1) {
          postId = uri.pathSegments[1];
        }
      }
    }

    if (postId != null) {
      // Navigate to post detail
      PushNotificationService.navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => PostDetailWrapper(postId: postId!),
        ),
      );
      return;
    }

    // Referral deep links: capture code and store in preferences
    try {
      String? code;
      // Custom scheme: equal://ref/<code> or equal://referral/<code>
      if (uri.scheme == 'equal' &&
          (uri.host == 'ref' || uri.host == 'referral')) {
        if (uri.pathSegments.isNotEmpty) {
          code = uri.pathSegments.first;
        }
        code ??= uri.queryParameters['code'] ?? uri.queryParameters['ref'];
      }
      // HTTPS links: https://equal.app/ref/<code> or /r/<code> or ?ref=CODE
      else if ((uri.scheme == 'https' || uri.scheme == 'http') &&
          (uri.host == 'equal.app' || uri.host == 'www.equal.app')) {
        if (uri.pathSegments.isNotEmpty &&
            (uri.pathSegments.first == 'ref' ||
                uri.pathSegments.first == 'r' ||
                uri.pathSegments.first == 'referral')) {
          if (uri.pathSegments.length > 1) {
            code = uri.pathSegments[1];
          }
        }
        code ??= uri.queryParameters['ref'] ?? uri.queryParameters['code'];
      }

      if (code != null && code.isNotEmpty) {
        await PreferencesService().setPendingReferralCode(code);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('referral_code_captured')),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint(('Referral deep link parse failed: $e').toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        widget.appService.onAppPaused();
        break;
      case AppLifecycleState.resumed:
        widget.appService.onAppResumed();
        break;
      default:
        break;
    }
  }

  Future<void> _checkAuthState() async {
    // Minimal splash time for visual polish
    await Future.delayed(const Duration(milliseconds: 600));

    // Decide whether to show language selection based on persisted preference
    final hasSelectedLanguage = LocalizationService.hasSelectedLanguage();

    if (!hasSelectedLanguage) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Navigator.of(context).pushReplacementNamed('/language-selection');
        return;
      }
    }

    // If language is already selected, continue to auth gate
    final user = Supabase.instance.client.auth.currentUser;

    if (mounted) {
      setState(() {
        _user = user;
        _isLoading = false;
      });
    }
  }

  void _setupAppStateListener() {
    widget.appService.appStateStream.listen((appState) {
      if (mounted) {
        switch (appState) {
          case AppState.authenticated:
            setState(() {
              _user = Supabase.instance.client.auth.currentUser;
            });
            // Ensure we reset navigation stack to main after login/auth
            // This prevents being stuck on deep routes after re-auth
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Use global navigatorKey to avoid context issues
              PushNotificationService.navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/main', (route) => false);
            });
            break;
          case AppState.passwordRecovery:
            // Navigate to update password screen
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              PushNotificationService.navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil(
                    '/update-password',
                    (route) => false,
                  );
            });
            break;
          case AppState.unauthenticated:
            setState(() {
              _user = null;
            });
            // Actively route to login and clear the stack on sign-out
            // This fixes the hang where UI stays on the previous screen until refresh
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              // Use global navigatorKey to avoid context issues
              PushNotificationService.navigatorKey.currentState
                  ?.pushNamedAndRemoveUntil('/login', (route) => false);
            });
            break;
          default:
            break;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SplashScreen();
    }

    return _user != null ? const MainScreen() : const LoginScreen();
  }
}
