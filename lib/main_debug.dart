import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/post_detail_wrapper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/language_selection_screen.dart';
import 'screens/main_feed_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/splash_screen.dart';
import 'services/localization_service.dart';
import 'services/app_service.dart';
import 'services/push_notification_service.dart';
import 'services/preferences_service.dart';
import 'config/app_colors.dart';
import 'config/supabase_config.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'config/feature_flags.dart';

// Global RouteObserver for tracking navigation
final RouteObserver<PageRoute> routeObserver = RouteObserver<PageRoute>();

void main() async {
  debugPrint(('DEBUG: Starting app initialization...').toString());

  try {
    debugPrint(('DEBUG: Ensuring Flutter binding...').toString());
    WidgetsFlutterBinding.ensureInitialized();
    debugPrint(('DEBUG: Flutter binding initialized successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: CRITICAL ERROR - Flutter binding failed: $e').toString(),
    );
    return;
  }

  // Initialize app service first
  debugPrint(('DEBUG: Creating AppService instance...').toString());
  final appService = AppService();
  debugPrint(('DEBUG: AppService created successfully').toString());

  try {
    debugPrint(('DEBUG: Starting Supabase initialization...').toString());
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
    ).timeout(const Duration(seconds: 10));
    debugPrint(('DEBUG: Supabase initialized successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: ERROR - Supabase initialization failed: $e').toString(),
    );
    // This is critical - app cannot function without Supabase
  }

  try {
    debugPrint(('DEBUG: Starting Firebase initialization...').toString());
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint(('DEBUG: Firebase initialized successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: ERROR - Firebase initialization failed: $e').toString(),
    );
    // Continue without Firebase
  }

  try {
    debugPrint(
      ('DEBUG: Starting push notification initialization...').toString(),
    );
    await PushNotificationService().initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint(
          ('DEBUG: Push notification initialization timed out').toString(),
        );
      },
    );
    debugPrint(
      ('DEBUG: Push notifications initialized successfully').toString(),
    );
  } catch (e) {
    debugPrint(
      ('DEBUG: ERROR - Push notification initialization failed: $e').toString(),
    );
    // Continue without push notifications
  }

  try {
    debugPrint(('DEBUG: Starting localization initialization...').toString());
    await LocalizationService.init().timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        debugPrint(('DEBUG: Localization initialization timed out').toString());
      },
    );
    debugPrint(('DEBUG: Localization initialized successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: ERROR - Localization initialization failed: $e').toString(),
    );
    // Continue with default language
  }

  try {
    debugPrint(('DEBUG: Setting system UI overlay style...').toString());
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    debugPrint(('DEBUG: System UI overlay style set successfully').toString());

    debugPrint(('DEBUG: Setting preferred orientations...').toString());
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    debugPrint(('DEBUG: Preferred orientations set successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: ERROR - System UI configuration failed: $e').toString(),
    );
    // Continue without system UI changes
  }

  try {
    debugPrint(('DEBUG: Starting app service initialization...').toString());
    await appService.initialize().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint(('DEBUG: App service initialization timed out').toString());
      },
    );
    debugPrint(('DEBUG: App service initialized successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: ERROR - App service initialization failed: $e').toString(),
    );
    // Continue with limited functionality
  }

  debugPrint(('DEBUG: Starting EqualApp...').toString());
  try {
    runApp(EqualApp(appService: appService));
    debugPrint(('DEBUG: EqualApp started successfully').toString());
  } catch (e) {
    debugPrint(
      ('DEBUG: CRITICAL ERROR - Failed to start EqualApp: $e').toString(),
    );
  }
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
    debugPrint(('DEBUG: EqualApp initState called').toString());
    super.initState();
    try {
      _loadThemePreference();
      // Listen for dark mode preference changes and update theme in real time
      PreferencesService.darkModeNotifier.addListener(_handleDarkModeChange);
      // Subscribe to locale changes to rebuild MaterialApp
      _localeListener = () {
        if (!mounted) return;
        setState(() {});
      };
      LocalizationService.localeNotifier.addListener(_localeListener);
      debugPrint(
        ('DEBUG: EqualApp initState completed successfully').toString(),
      );
    } catch (e) {
      debugPrint(('DEBUG: ERROR in EqualApp initState: $e').toString());
    }
  }

  Future<void> _loadThemePreference() async {
    try {
      debugPrint(('DEBUG: Loading theme preference...').toString());
      final darkEnabled = await _preferencesService.getDarkModeEnabled();
      if (mounted) {
        setState(() {
          _themeMode = darkEnabled ? ThemeMode.dark : ThemeMode.light;
        });
      }
      debugPrint(('DEBUG: Theme preference loaded successfully').toString());
    } catch (e) {
      debugPrint(('DEBUG: ERROR loading theme preference: $e').toString());
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
    debugPrint(('DEBUG: EqualApp dispose called').toString());
    PreferencesService.darkModeNotifier.removeListener(_handleDarkModeChange);
    LocalizationService.localeNotifier.removeListener(_localeListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(('DEBUG: EqualApp build called').toString());
    try {
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

      debugPrint(('DEBUG: Creating MaterialApp...').toString());
      return MaterialApp(
        title: 'Equal - Revolutionary Social Media (DEBUG)',
        debugShowCheckedModeBanner: false,
        navigatorKey: PushNotificationService.navigatorKey,
        navigatorObservers: [routeObserver],
        locale: LocalizationService.localeNotifier.value,
        supportedLocales: LocalizationService.supportedLocales,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: _themeMode,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(0.95)),
            child: child ?? const SplashScreen(),
          );
        },
        home: DebugAuthWrapper(appService: widget.appService),
        routes: {
          '/language-selection': (context) => const LanguageSelectionScreen(),
          '/main-feed': (context) => const MainFeedScreen(),
          '/login': (context) => const LoginScreen(),
          '/main': (context) => const MainScreen(),
        },
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          PushNotificationService().processPendingNavigation();
        } catch (e) {
          debugPrint(
            ('DEBUG: Error processing pending navigation: $e').toString(),
          );
        }
      });
    } catch (e) {
      debugPrint(('DEBUG: CRITICAL ERROR in EqualApp build: $e').toString());
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('${LocalizationService.t('build_error')}: $e'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    // Try to restart the app
                    main();
                  },
                  child: const Text('Restart App'),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }
}

class DebugAuthWrapper extends StatefulWidget {
  final AppService appService;

  const DebugAuthWrapper({super.key, required this.appService});

  @override
  State<DebugAuthWrapper> createState() => _DebugAuthWrapperState();
}

class _DebugAuthWrapperState extends State<DebugAuthWrapper>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  User? _user;
  late AppLinks _appLinks;
  String _debugStatus = 'Initializing...';

  @override
  void initState() {
    debugPrint(('DEBUG: DebugAuthWrapper initState called').toString());
    super.initState();
    try {
      WidgetsBinding.instance.addObserver(this);
      _initializeAppLinks();
      _checkAuthState();
      _setupAppStateListener();
      debugPrint(
        ('DEBUG: DebugAuthWrapper initState completed successfully').toString(),
      );
    } catch (e) {
      debugPrint(('DEBUG: ERROR in DebugAuthWrapper initState: $e').toString());
      setState(() {
        _debugStatus = 'Init Error: $e';
      });
    }
  }

  @override
  void dispose() {
    debugPrint(('DEBUG: DebugAuthWrapper dispose called').toString());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _initializeAppLinks() {
    try {
      debugPrint(('DEBUG: Initializing app links...').toString());
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
      debugPrint(('DEBUG: App links initialized successfully').toString());
    } catch (e) {
      debugPrint(('DEBUG: ERROR initializing app links: $e').toString());
    }
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    try {
      debugPrint(('DEBUG: Handling incoming link: $uri').toString());
      if (uri.scheme == 'equal' &&
          uri.host == 'auth' &&
          uri.path == '/callback') {
        // Extract the fragment from the URI which contains the auth tokens
        final fragment = uri.fragment;
        if (fragment.isNotEmpty) {
          // Parse the fragment to get access_token and refresh_token
          final params = Uri.splitQueryString(fragment);
          final accessToken = params['access_token'];
          final refreshToken = params['refresh_token'];

          if (refreshToken != null) {
            // Set the session with the refresh token
            await Supabase.instance.client.auth.setSession(refreshToken);

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
      // Referral deep links: capture code and store in preferences
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
        debugPrint(
          ('DEBUG: Referral code captured from link: $code').toString(),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(LocalizationService.t('referral_code_captured')),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
      debugPrint(('DEBUG: Incoming link handled successfully').toString());
    } catch (e) {
      debugPrint(('DEBUG: ERROR handling incoming link: $e').toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    try {
      debugPrint(('DEBUG: App lifecycle state changed to: $state').toString());
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
    } catch (e) {
      debugPrint(('DEBUG: ERROR in app lifecycle state change: $e').toString());
    }
  }

  Future<void> _checkAuthState() async {
    try {
      debugPrint(('DEBUG: Checking auth state...').toString());
      setState(() {
        _debugStatus = 'Showing splash screen...';
      });

      // Show splash screen for at least 2 seconds
      await Future.delayed(const Duration(seconds: 2));

      // Screenshot/demo mode: skip language/auth flow and go straight to main
      if (FeatureFlags.screenshotDemoMode) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _debugStatus = 'Screenshot demo mode';
          });
        }
        return;
      }
      setState(() {
        _debugStatus = 'Checking language selection...';
      });

      // Check if language has been selected first
      final hasSelectedLanguage = LocalizationService.hasSelectedLanguage();

      if (!hasSelectedLanguage) {
        debugPrint(
          ('DEBUG: Language not selected, navigating to language selection')
              .toString(),
        );
        if (mounted) {
          setState(() {
            _isLoading = false;
            _debugStatus = 'Language selection required';
          });
          Navigator.of(context).pushReplacementNamed('/language-selection');
          return;
        }
      }

      setState(() {
        _debugStatus = 'Getting current user...';
      });

      final user = Supabase.instance.client.auth.currentUser;

      if (mounted) {
        setState(() {
          _user = user;
          _isLoading = false;
          _debugStatus = user != null
              ? 'User authenticated'
              : 'User not authenticated';
        });
      }
      debugPrint(('DEBUG: Auth state check completed successfully').toString());
    } catch (e) {
      debugPrint(('DEBUG: ERROR checking auth state: $e').toString());
      if (mounted) {
        setState(() {
          _isLoading = false;
          _debugStatus = 'Auth check error: $e';
        });
      }
    }
  }

  void _setupAppStateListener() {
    try {
      debugPrint(('DEBUG: Setting up app state listener...').toString());
      widget.appService.appStateStream.listen((appState) {
        if (mounted) {
          debugPrint(('DEBUG: App state changed to: $appState').toString());
          switch (appState) {
            case AppState.authenticated:
              setState(() {
                _user = Supabase.instance.client.auth.currentUser;
                _debugStatus = 'App state: authenticated';
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Use global navigatorKey to ensure route reset
                PushNotificationService.navigatorKey.currentState
                    ?.pushNamedAndRemoveUntil('/main', (route) => false);
              });
              break;
            case AppState.unauthenticated:
              setState(() {
                _user = null;
                _debugStatus = 'App state: unauthenticated';
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                // Use global navigatorKey to ensure route reset
                PushNotificationService.navigatorKey.currentState
                    ?.pushNamedAndRemoveUntil('/login', (route) => false);
              });
              break;
            default:
              setState(() {
                _debugStatus = 'App state: $appState';
              });
              break;
          }
        }
      });
      debugPrint(('DEBUG: App state listener set up successfully').toString());
    } catch (e) {
      debugPrint(('DEBUG: ERROR setting up app state listener: $e').toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      ('DEBUG: DebugAuthWrapper build called - isLoading: $_isLoading, user: ${_user?.id}')
          .toString(),
    );

    // Screenshot/demo mode: always show MainScreen regardless of auth state
    if (FeatureFlags.screenshotDemoMode) {
      return const MainScreen();
    }

    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 20),
              Text(
                'DEBUG MODE',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _debugStatus,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    try {
      return _user != null ? const MainScreen() : const LoginScreen();
    } catch (e) {
      debugPrint(('DEBUG: ERROR in DebugAuthWrapper build: $e').toString());
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Build Error: $e'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _debugStatus = 'Restarting...';
                  });
                  _checkAuthState();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
  }
}
