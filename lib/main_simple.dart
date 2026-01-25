import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  debugPrint(('Starting simple app...').toString());

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(SimpleEqualApp());
}

class SimpleEqualApp extends StatelessWidget {
  const SimpleEqualApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Equal - Simple Test',
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
      home: SimpleTestScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SimpleTestScreen extends StatefulWidget {
  const SimpleTestScreen({super.key});

  @override
  _SimpleTestScreenState createState() => _SimpleTestScreenState();
}

class _SimpleTestScreenState extends State<SimpleTestScreen> {
  bool _isLoading = true;
  String _status = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    debugPrint(('Simple app initialization started').toString());

    setState(() {
      _status = 'Testing basic functionality...';
    });

    // Simulate some initialization time
    await Future.delayed(Duration(seconds: 2));

    setState(() {
      _status = 'App ready!';
      _isLoading = false;
    });

    debugPrint(('Simple app initialization completed').toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Text(
                  'EQUAL',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            SizedBox(height: 40),

            // Status text
            Text(_status, style: TextStyle(color: Colors.white, fontSize: 18)),
            SizedBox(height: 20),

            // Loading indicator or success message
            if (_isLoading)
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              )
            else
              Column(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 48),
                  SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      debugPrint(('Test button pressed').toString());
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('App is working correctly!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    child: Text('Test App'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

