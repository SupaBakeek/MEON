import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:meon/pages/meon_home_page.dart';
import 'package:meon/pages/onboarding_page.dart';
import 'package:meon/pages/signup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _meNameController = TextEditingController();
  final TextEditingController _meWordController = TextEditingController();
  bool _meHidden = true;
  bool _meWaiting = false;
  String? _errorMessage;

  final CollectionReference _users = FirebaseFirestore.instance.collection('users');

  // Hash password for security (consistent with signup page)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool _validateMeName(String username) {
    final regex = RegExp(r'^[a-zA-Z0-9 ]{2,20}$');
    return regex.hasMatch(username);
  }

  Future<void> _login() async {
    final username = _meNameController.text.trim();
    final password = _meWordController.text;

    // Clear previous errors
    setState(() {
      _errorMessage = null;
    });

    // Validation
    if (!_validateMeName(username)) {
      setState(() {
        _errorMessage = 'MeName must be 2-20 chars: letters, numbers, spaces only.';
      });
      return;
    }
    
    if (password.isEmpty || password.length < 6) {
      setState(() {
        _errorMessage = 'MeWord must be at least 6 characters.';
      });
      return;
    }

    setState(() => _meWaiting = true);
    SystemChannels.textInput.invokeMethod('TextInput.hide');

    try {
      final query = await _users
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        setState(() {
          _errorMessage = 'MeName not found.';
          _meWaiting = false;
        });
        return;
      }

      final userDoc = query.docs.first;
      final userData = userDoc.data() as Map<String, dynamic>;

      // Compare hashed passwords
      final hashedPassword = _hashPassword(password);
      if (userData['password'] != hashedPassword) {
        setState(() {
          _errorMessage = 'Incorrect MeWord.';
          _meWaiting = false;
        });
        return;
      }

      // Save user data to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', userDoc.id);
      await prefs.setString('user_name', username);

      if (!mounted) return;
      
      // Navigate to home page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MeonHomePage(
            currentUserId: userDoc.id,
            currentUserName: username,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Login failed. Please try again.';
        _meWaiting = false;
      });
    }
  }

  void _toggleMeVision() {
    setState(() {
      _meHidden = !_meHidden;
    });
  }

  void _goToSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupPage()),
    );
  }

  void _goToOnboarding() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OnboardingPage()),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontStyle: FontStyle.italic,
        ),
        prefixIcon: Icon(icon, color: Colors.teal[600]),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.teal, width: 2),
        ),
        floatingLabelStyle: const TextStyle(
          color: Colors.teal,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red[200]!),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.red[600],
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuthButton({
    required String text,
    required VoidCallback onPressed,
    required bool isLoading,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _meNameController.dispose();
    _meWordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tealColor = Colors.teal;

    return Scaffold(
      backgroundColor: tealColor[50],
      body: Center(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with subtle styling
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: tealColor[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.emoji_people,
                    size: 36,
                    color: tealColor[700],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'ME-IN',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    color: tealColor[800],
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome to MeWorld',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 40),

                // Input container with subtle background
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: tealColor[100],
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // MeName field
                      _buildTextField(
                        controller: _meNameController,
                        labelText: 'MeName',
                        hintText: 'What\'s your MeName?',
                        icon: Icons.emoji_emotions_outlined,
                      ),

                      const SizedBox(height: 16),

                      // MeWord field
                      _buildTextField(
                        controller: _meWordController,
                        labelText: 'MeWord',
                        hintText: 'Shh... your secret MeWord',
                        icon: Icons.password,
                        obscureText: _meHidden,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _meHidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: Colors.grey[500],
                          ),
                          onPressed: _toggleMeVision,
                        ),
                      ),

                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildErrorWidget(_errorMessage!),
                      ],

                      const SizedBox(height: 24),

                      // ME IN button
                      _buildAuthButton(
                        text: 'ME IN',
                        onPressed: _login,
                        isLoading: _meWaiting,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Skip onboarding button
                TextButton(
                  onPressed: _goToOnboarding,
                  child: const Text('Skip Onboarding'),
                ),

                const SizedBox(height: 16),

                // Sign up link
                TextButton(
                  onPressed: _meWaiting ? null : _goToSignup,
                  child: Text.rich(
                    TextSpan(
                      text: 'No MeWorld? ',
                      style: TextStyle(color: Colors.grey[600]),
                      children: [
                        TextSpan(
                          text: 'MeUP!',
                          style: TextStyle(
                            color: tealColor,
                            fontWeight: FontWeight.w600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}