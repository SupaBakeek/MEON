import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:meon/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'onboarding_page.dart';
import 'login_page.dart';
import 'meon_home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (defaultTargetPlatform == TargetPlatform.android) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.android,
    );
  } else {
    await Firebase.initializeApp();
  }

  runApp(const MeonApp());
}

class MeonApp extends StatefulWidget {
  const MeonApp({super.key});

  @override
  State<MeonApp> createState() => _MeonAppState();
}

class _MeonAppState extends State<MeonApp> {
  bool _initialized = false;
  bool _error = false;
  bool _hasSeenOnboarding = false;
  User? _firebaseUser;

  late final Stream<User?> _authStateChanges;

  @override
  void initState() {
    super.initState();
    _authStateChanges = FirebaseAuth.instance.authStateChanges();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;

      // Listen to auth state changes and update UI accordingly
      _authStateChanges.listen((user) {
        setState(() {
          _firebaseUser = user;
        });
      });

      // For initial state, get current user if any
      _firebaseUser = FirebaseAuth.instance.currentUser;

      setState(() {
        _initialized = true;
      });
    } catch (e) {
      debugPrint('Error during app initialization: $e');
      setState(() {
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Something went wrong. Please restart the app.',
              style: TextStyle(fontSize: 18),
            ),
          ),
        ),
      );
    }

    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    Widget homeScreen;

    if (!_hasSeenOnboarding) {
      homeScreen = const OnboardingPage();
    } else if (_firebaseUser == null) {
      homeScreen = const LoginPage();
    } else {
      homeScreen = MeonHomePage(
        currentUserId: _firebaseUser!.uid,
        currentUserName: 'User-${_firebaseUser!.uid.substring(0, 5)}',
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: homeScreen,
      routes: {
        '/onboarding': (context) => const OnboardingPage(),
        '/login': (context) => const LoginPage(),
        '/home': (context) {
          final user = FirebaseAuth.instance.currentUser;
          return MeonHomePage(
            currentUserId: user!.uid,
            currentUserName: 'User-${user.uid.substring(0, 5)}',
          );
        }
      },
    );
  }
}
