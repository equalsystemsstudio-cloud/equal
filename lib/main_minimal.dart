import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  debugPrint(('🚀 Starting minimal Equal app...').toString());
  
  try {
    // Only set system UI - no external services
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.black,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    debugPrint(('✅ System UI configured').toString());
  } catch (e) {
    debugPrint(('❌ System UI configuration failed: $e').toString());
  }
  
  try {
    // Set preferred orientations
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    debugPrint(('✅ Orientation configured').toString());
  } catch (e) {
    debugPrint(('❌ Orientation configuration failed: $e').toString());
  }
  
  debugPrint(('🎯 Launching app widget...').toString());
  runApp(MinimalEqualApp());
}

class MinimalEqualApp extends StatelessWidget {
  const MinimalEqualApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equal - Minimal Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: const TextScaler.linear(1.0)),
          child: child!,
        );
      },
      home: MinimalTestScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MinimalTestScreen extends StatefulWidget {
  const MinimalTestScreen({super.key});

  @override
  _MinimalTestScreenState createState() => _MinimalTestScreenState();
}

class _MinimalTestScreenState extends State<MinimalTestScreen> {
  String _status = 'App started successfully! 🎉';
  int _counter = 0;

  @override
  void initState() {
    super.initState();
    debugPrint(('📱 MinimalTestScreen initialized').toString());
  }

  void _incrementCounter() {
    setState(() {
      _counter++;
      _status = 'Button pressed $_counter times';
    });
    debugPrint(('🔢 Counter: $_counter').toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Equal - Minimal Test',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.blue,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 80,
              ),
              const SizedBox(height: 20),
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Text(
                'Counter: $_counter',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _incrementCounter,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 15,
                  ),
                ),
                child: const Text(
                  'Test Button',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green),
                ),
                child: const Column(
                  children: [
                    Text(
                      '✅ Basic Flutter functionality working',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '✅ No external services initialized',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '✅ App should work on any device',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

