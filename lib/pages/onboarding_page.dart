import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  bool _checkingPrefs = true;

  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _applySystemBars();       // ← make system status/nav bars teal[50]
    _checkIfSeen();
  }

  void _applySystemBars() {
    final teal50 = Colors.teal[50]!;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: teal50,                 // Android status bar bg
        systemNavigationBarColor: teal50,       // Android bottom nav bar bg
        systemNavigationBarDividerColor: teal50,
        statusBarIconBrightness: Brightness.dark,          // Android icons
        systemNavigationBarIconBrightness: Brightness.dark, // Android icons
        // iOS uses the "dark" style for dark icons on light backgrounds via AnnotatedRegion below
      ),
    );
  }

  Future<void> _checkIfSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool('has_seen_onboarding') ?? false;
    if (!mounted) return;
    if (seen) {
      _goToHome();
    } else {
      setState(() => _checkingPrefs = false);
    }
  }

  void _goToHome() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    });
  }

  Future<void> _finishTutorial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    _goToHome();
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingPrefs) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
          ),
        ),
      );
    }

    final teal50 = Colors.teal[50]!;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Ensures dark icons on iOS and Android over a light teal background
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: teal50, // ← whole page background (fixes white edges)
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  children: [
                    _buildSlide(
                      bg: teal50,
                      icon: Icons.toggle_on_rounded,
                      title: "Simple Status Toggle",
                      description: "Toggle your status with a single button - ON or OFF",
                    ),
                    _buildSlide(
                      bg: teal50,
                      icon: Icons.people_rounded,
                      title: "Friend Visibility",
                      description: "Friends can see your status without messages",
                    ),
                    _buildSlide(
                      bg: teal50,
                      icon: Icons.power_input,
                      title: "Morse Communication",
                      description: "Send secret signals using morse code",
                    ),
                    _buildSlide(
                      bg: teal50,
                      icon: Icons.battery_saver_rounded,
                      title: "Low Battery & Free",
                      description: "Efficient design, no costs, notification toggle",
                    ),
                  ],
                ),
              ),

              // Page indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final active = _currentPage == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.all(4),
                    width: active ? 16 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: active ? Colors.teal : Colors.grey[400],
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),

              // Next / Finish button
              Padding(
                padding: const EdgeInsets.all(20),
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage == 3) {
                      _finishTutorial();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    backgroundColor: Colors.teal,
                  ),
                  child: Text(
                    _currentPage == 3 ? "Enter MeWorld" : "Next",
                    style: const TextStyle(fontSize: 18, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlide({
    required Color bg,
    required IconData icon,
    required String title,
    required String description,
    Color color = Colors.teal,
  }) {
    return Container(
      color: bg, // each page matches Scaffold background
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 100, color: color),
            const SizedBox(height: 40),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              description,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
