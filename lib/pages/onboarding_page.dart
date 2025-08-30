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
    _applySystemBars();
    _checkIfSeen();
  }

  void _applySystemBars() {
    final teal50 = Colors.teal[50]!;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: teal50,
        systemNavigationBarColor: teal50,
        systemNavigationBarDividerColor: teal50,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarIconBrightness: Brightness.dark,
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

    final slides = [
      _SlideData(
        icon: Icons.toggle_on_outlined,
        title: "Simple Switch with No Limit",
        description: "Switch MEON and let your partner know instantly. No typing. No noise. No limits.",
      ),
      _SlideData(
        icon: Icons.people_outline,
        title: "Partner Signaling",
        description: "Let your partner understand you without a Language, communicate secretly.",
      ),
      _SlideData(
        icon: Icons.power_input,
        title: "MeCode Communication",
        description: "Send pulses, build a secret language only you two understand.",
      ),
      _SlideData(
        icon: Icons.layers_outlined,
        title: "Simplicity",
        description: "Minimal, lightweight,\nWhat's left? A tool made for ...",
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: teal50,
        body: SafeArea(
          child: Column(
            children: [
              // Progress bar at the top
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / slides.length,
                  backgroundColor: Colors.teal[100],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.teal[700]!),
                  borderRadius: BorderRadius.circular(10),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              // Page numbers
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${_currentPage + 1}/${slides.length}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.teal[700],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: slides.length,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, index) {
                    final slide = slides[index];
                    final active = _currentPage == index;
                    return AnimatedSlideContent(slide: slide, isActive: active);
                  },
                ),
              ),
              const SizedBox(height: 20),
              // Next / Finish button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: ElevatedButton(
                  onPressed: () {
                    if (_currentPage == slides.length - 1) {
                      _finishTutorial();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    backgroundColor: Colors.teal[700],
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    _currentPage == slides.length - 1 ? "Enter MEON" : "Next",
                    style: const TextStyle(
                      fontSize: 18, 
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlideData {
  final IconData icon;
  final String title;
  final String description;
  _SlideData({required this.icon, required this.title, required this.description});
}

class AnimatedSlideContent extends StatelessWidget {
  final _SlideData slide;
  final bool isActive;
  const AnimatedSlideContent({required this.slide, required this.isActive, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.teal[50],
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedScale(
            scale: isActive ? 1.0 : 0.8,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: Icon(slide.icon, size: 100, color: Colors.teal[700]),
          ),
          const SizedBox(height: 32),
          AnimatedOpacity(
            opacity: isActive ? 1.0 : 0.6,
            duration: const Duration(milliseconds: 300),
            child: Column(
              children: [
                Text(
                  slide.title,
                  style: const TextStyle(
                    fontSize: 24, 
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  slide.description,
                  style: TextStyle(
                    fontSize: 16, 
                    color: Colors.grey[700],
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}