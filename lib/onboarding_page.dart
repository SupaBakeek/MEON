import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _hasSeenTutorial = false;

  @override
  void initState() {
    super.initState();
    _checkIfSeen();
  }

  Future<void> _checkIfSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('has_seen_onboarding') ?? false;
    if (seen) {
      _goToHome();
    } else {
      setState(() {
        _hasSeenTutorial = false;
      });
    }
  }

  void _goToHome() {
    Navigator.pushReplacementNamed(context, '/home');
  }

  Future<void> _finishTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    _goToHome();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenTutorial) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Meon')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text(
              "Welcome to Meon!",
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            const Text(
              "This app lets you toggle your status with a single button.\n\n"
              "Your friends can see when you are ON or OFF without sending messages.\n\n"
              "You can even use the notification toggle to change status without opening the app.\n\n"
              "Make your own secret meanings for ON/OFF status.\n\n"
              "This app keeps things simple, low battery, and no costs.",
              style: TextStyle(fontSize: 16),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _finishTutorial,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                child: Text('Got it, start using Meon', style: TextStyle(fontSize: 18)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
