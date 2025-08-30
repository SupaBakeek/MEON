import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import 'meon_home_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  final CollectionReference _users = FirebaseFirestore.instance.collection('users');

  // Hash password for security (basic implementation)
  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<void> _signup() async {
    // Clear previous errors
    setState(() {
      _errorMessage = null;
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    // Validation
    if (username.isEmpty || password.isEmpty || confirm.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields.');
      return;
    }

    if (password.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters.');
      return;
    }

    if (password != confirm) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Check if username exists
      final usernameQuery = await _users
          .where('username', isEqualTo: username)
          .limit(1)
          .get();

      if (usernameQuery.docs.isNotEmpty) {
        setState(() {
          _errorMessage = 'Username already taken.';
          _isLoading = false;
        });
        return;
      }

      // Create new user with hashed password
      final hashedPassword = _hashPassword(password);
      final newUserDoc = await _users.add({
        'username': username,
        'name': username,
        'password': hashedPassword,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Save user data to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_id', newUserDoc.id);
      await prefs.setString('user_name', username);

      if (!mounted) return;
      
      // Navigate to home page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MeonHomePage(
            currentUserId: newUserDoc.id,
            currentUserName: username,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Signup failed. Please try again.';
        _isLoading = false;
      });
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String labelText,
    required String hintText,
    required IconData icon,
    bool obscureText = false,
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: labelText,
        hintText: hintText,
        hintStyle: TextStyle(
          color: Colors.grey[400],
          fontStyle: FontStyle.italic,
        ),
        prefixIcon: Icon(icon, color: Colors.teal[600]),
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

  @override
  Widget build(BuildContext context) {
    final tealColor = Colors.teal;

    return Scaffold(
      backgroundColor: tealColor[50],
      appBar: AppBar(
        backgroundColor: tealColor[50],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: tealColor[100],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.person_add,
                    size: 36,
                    color: tealColor[700],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Join MeWorld',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create your MeSpace',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),

                const SizedBox(height: 32),

                // Input container
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
                        controller: _usernameController,
                        labelText: 'Mename',
                        hintText: 'Choose your Mename',
                        icon: Icons.emoji_emotions_outlined,
                        enabled: !_isLoading,
                      ),

                      const SizedBox(height: 16),

                      // MeWord field
                      _buildTextField(
                        controller: _passwordController,
                        labelText: 'Meword',
                        hintText: 'Create your Meword',
                        icon: Icons.password,
                        obscureText: true,
                        enabled: !_isLoading,
                      ),

                      const SizedBox(height: 16),

                      // Confirm MeWord field
                      _buildTextField(
                        controller: _confirmController,
                        labelText: 'Confirm MeWord',
                        hintText: 'Confirm your MeWord',
                        icon: Icons.lock_outline,
                        obscureText: true,
                        enabled: !_isLoading,
                      ),

                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Container(
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
                                  _errorMessage!,
                                  style: TextStyle(
                                    color: Colors.red[700],
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Signup button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signup,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: tealColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'MeUP',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ],
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