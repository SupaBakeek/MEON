import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';
import 'friends_page.dart';
import 'settings_page.dart';

class MeonHomePage extends StatefulWidget {
  final String currentUserName;
  final String currentUserId;

  const MeonHomePage({
    super.key,
    required this.currentUserName,
    required this.currentUserId,
  });

  @override
  State<MeonHomePage> createState() => _MeonHomePageState();
}

class _MeonHomePageState extends State<MeonHomePage>
    with WidgetsBindingObserver {
  bool isOn = false;
  bool morseMode = false;

  Timer? _statusSaveDebounceTimer;
  Timer? _friendVisibilityDebounceTimer;

  Map<String, bool> cachedFriendVisibility = {};

  // Morse communication variables
  String? morseReceiverId;
  String? morseReceiverName;
  Timer? _morseResetTimer;
  final List<String> _morseBuffer = [];
  StreamSubscription<QuerySnapshot>? _morseListener;
  StreamSubscription<QuerySnapshot>? _friendVisibilityListener;

  // Morse timing variables
  DateTime? _pressStartTime;
  String lastSignal = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatusFromPrefs();
    _initFCMToken();
    _loadCachedFriendVisibility();
    _setupFriendVisibilityListener();
    _loadMorseReceiver();
    _setupMorseListener();
    NotificationService.onToggle = _toggleStatusFromNotification;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSaveDebounceTimer?.cancel();
    _friendVisibilityDebounceTimer?.cancel();
    _friendVisibilityListener?.cancel();
    _morseResetTimer?.cancel();
    _morseListener?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCachedFriendVisibility();
    }
  }

  Future<void> _loadStatusFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStatus = prefs.getBool('meon_status') ?? false;
      setState(() {
        isOn = savedStatus;
      });
      _saveUserStatusToFirestore(isOn); // initial sync
      _showSelfToggleNotification(isOn);
    } catch (e, st) {
      debugPrint('Error loading status from prefs: $e\n$st');
    }
  }

  Future<void> _saveStatusToPrefs(bool status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('meon_status', status);
    } catch (e, st) {
      debugPrint('Error saving status to prefs: $e\n$st');
    }
  }

  Future<void> _saveMorseModeToPrefs(bool mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('morse_mode', mode);
    } catch (e, st) {
      debugPrint('Error saving morse mode to prefs: $e\n$st');
    }
  }

  Future<void> _initFCMToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission();

      final prefs = await SharedPreferences.getInstance();
      final savedToken = prefs.getString('fcm_token');

      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null && token != savedToken) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUserId)
            .update({'fcmToken': token});
        await prefs.setString('fcm_token', token);
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUserId)
            .update({'fcmToken': newToken});
        await prefs.setString('fcm_token', newToken);
      });
    } catch (e, st) {
      debugPrint('Error initializing FCM token: $e\n$st');
    }
  }

  Future<void> _saveUserStatusToFirestore(
    bool status, {
    int retries = 3,
  }) async {
    _statusSaveDebounceTimer?.cancel();
    _statusSaveDebounceTimer = Timer(const Duration(seconds: 2), () async {
      for (int attempt = 1; attempt <= retries; attempt++) {
        try {
          final token = await FirebaseMessaging.instance.getToken();
          if (token != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(widget.currentUserId)
                .set({
                  'isOn': status,
                  'fcmToken': token,
                  'lastUpdated': FieldValue.serverTimestamp(),
                }, SetOptions(merge: true));
            return;
          }
        } catch (e, st) {
          debugPrint('Attempt $attempt: Error saving user status: $e\n$st');
          if (attempt == retries) {
            debugPrint('Max retries reached for saving user status.');
          } else {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    });
  }

  Future<void> toggleStatus() async {
    final newStatus = !isOn;

    setState(() {
      isOn = newStatus;
    });

    await _saveStatusToPrefs(newStatus);
    await _saveUserStatusToFirestore(newStatus);
    await _showSelfToggleNotification(newStatus);
  }

  Future<void> _toggleStatusFromNotification() async {
    if (!mounted) return;
    await toggleStatus();
  }

  Future<void> _showSelfToggleNotification(bool status) async {
    try {
      await NotificationService.showSelfToggleNotification(status);
    } catch (e, st) {
      debugPrint('Error showing self toggle notification: $e\n$st');
    }
  }

  Future<void> _loadCachedFriendVisibility() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final friendVis = <String, bool>{};
      for (final key in keys) {
        if (key.startsWith('friend_visibility_')) {
          friendVis[key.replaceFirst('friend_visibility_', '')] =
              prefs.getBool(key) ?? false;
        }
      }
      setState(() {
        cachedFriendVisibility = friendVis;
      });
    } catch (e, st) {
      debugPrint('Error loading cached friend visibility: $e\n$st');
    }
  }

  Future<void> _updateFriendVisibilityInCache(
    String friendId,
    bool canSee,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('friend_visibility_$friendId', canSee);
      setState(() {
        cachedFriendVisibility[friendId] = canSee;
      });
    } catch (e, st) {
      debugPrint('Error updating friend visibility in cache: $e\n$st');
    }
  }

  Future<void> _toggleFriendVisibility(
    String friendId,
    bool currentValue, {
    int retries = 3,
  }) async {
    final newValue = !currentValue;
    await _updateFriendVisibilityInCache(friendId, newValue);

    _friendVisibilityDebounceTimer?.cancel();
    _friendVisibilityDebounceTimer = Timer(
      const Duration(seconds: 3),
      () async {
        for (int attempt = 1; attempt <= retries; attempt++) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(widget.currentUserId)
                .collection('friends')
                .doc(friendId)
                .update({'canSeeStatus': newValue});
            return;
          } catch (e, st) {
            debugPrint(
              'Attempt $attempt: Error updating friend visibility: $e\n$st',
            );
            if (attempt == retries) {
              debugPrint('Max retries reached for updating friend visibility.');
            } else {
              await Future.delayed(const Duration(seconds: 2));
            }
          }
        }
      },
    );
  }

  void _setupFriendVisibilityListener() {
    _friendVisibilityListener?.cancel();

    _friendVisibilityListener = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .collection('friends')
        .snapshots()
        .listen(
          (snapshot) {
            final updatedVisibility = <String, bool>{};
            for (final doc in snapshot.docs) {
              final canSee = doc.data()['canSeeStatus'] ?? false;
              updatedVisibility[doc.id] = canSee;
            }

            bool changed = false;
            updatedVisibility.forEach((key, value) {
              if (cachedFriendVisibility[key] != value) {
                changed = true;
              }
            });

            if (changed) {
              setState(() {
                cachedFriendVisibility = updatedVisibility;
              });
              // Also update SharedPreferences cache for persistence
              _syncVisibilityCache(updatedVisibility);
            }
          },
          onError: (error, stackTrace) {
            debugPrint('Friend visibility listener error: $error\n$stackTrace');
          },
        );
  }

  Future<void> _syncVisibilityCache(Map<String, bool> visibilityMap) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final entry in visibilityMap.entries) {
        await prefs.setBool('friend_visibility_${entry.key}', entry.value);
      }
    } catch (e, st) {
      debugPrint('Error syncing visibility cache: $e\n$st');
    }
  }

  // Morse communication methods
  Future<void> _loadMorseReceiver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final receiverId = prefs.getString('morse_receiver_id');
      final receiverName = prefs.getString('morse_receiver_name');
      
      if (receiverId != null && receiverName != null) {
        setState(() {
          morseReceiverId = receiverId;
          morseReceiverName = receiverName;
          lastSignal = 'Ready to signal $receiverName';
        });
      } else {
        setState(() => lastSignal = 'Select a friend for Morse');
      }
    } catch (e, st) {
      debugPrint('Error loading Morse receiver: $e\n$st');
    }
  }

  Future<void> _setMorseReceiver(String friendId, String friendName) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('morse_receiver_id', friendId);
      await prefs.setString('morse_receiver_name', friendName);
      
      setState(() {
        morseReceiverId = friendId;
        morseReceiverName = friendName;
        lastSignal = 'Ready to signal $friendName';
      });
    } catch (e, st) {
      debugPrint('Error setting Morse receiver: $e\n$st');
    }
  }

  Future<void> _clearMorseReceiver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('morse_receiver_id');
      await prefs.remove('morse_receiver_name');
      
      setState(() {
        morseReceiverId = null;
        morseReceiverName = null;
        lastSignal = 'Select a friend first';
      });
    } catch (e, st) {
      debugPrint('Error clearing Morse receiver: $e\n$st');
    }
  }

  Future<void> _sendMorseSignal(String signal) async {
    if (morseReceiverId == null) {
      setState(() => lastSignal = 'Select a friend first');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('morse_signals').add({
        'senderId': widget.currentUserId,
        'receiverId': morseReceiverId,
        'signal': signal,
        'timestamp': FieldValue.serverTimestamp(),
      });
      
      setState(() {
        _morseBuffer.add(signal);
        lastSignal = 'Sent to $morseReceiverName: ${_morseBuffer.join()}';
      });
      
      _morseResetTimer?.cancel();
      _morseResetTimer = Timer(const Duration(seconds: 5), () {
        setState(() {
          _morseBuffer.clear();
          lastSignal = 'Ready to signal $morseReceiverName';
        });
      });
    } catch (e, st) {
      debugPrint('Error sending Morse signal: $e\n$st');
      setState(() => lastSignal = 'Failed to send signal');
    }
  }

  void _setupMorseListener() {
    _morseListener = FirebaseFirestore.instance
        .collection('morse_signals')
        .where('receiverId', isEqualTo: widget.currentUserId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isEmpty) return;
          
          final doc = snapshot.docs.first;
          if (doc['senderId'] == widget.currentUserId) return;
          
          final senderId = doc['senderId'];
          final signal = doc['signal'];
          
          // Get sender name from cached friends
          final friendName = cachedFriendVisibility.keys.firstWhere(
            (id) => id == senderId,
            orElse: () => 'a friend',
          );
          
          NotificationService.showMorseNotification(friendName, signal);
          
          if (mounted && morseMode) {
            setState(() {
              lastSignal = 'Received from $friendName: $signal';
            });
          }
        }, onError: (e) => debugPrint('Morse listener error: $e'));
  }

  void _onPressStart() {
    if (!morseMode) return;
    _pressStartTime = DateTime.now();
    setState(() {
      lastSignal = '...holding...';
    });
  }

  void _onPressEnd() {
    if (!morseMode || _pressStartTime == null) return;

    final duration = DateTime.now().difference(_pressStartTime!);
    _pressStartTime = null;

    String signal;
    if (duration < const Duration(milliseconds: 500)) {
      signal = '.'; // Dot: short press
    } else if (duration < const Duration(seconds: 3)) {
      signal = '-'; // Dash: medium hold
    } else {
      signal = '_'; // Long hold > 3s (custom signal)
    }

    _sendMorseSignal(signal);
  }

  Future<void> logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.red[50],
        title: Text(
          'MEOUT',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.red[600],
          ),
        ),
        content: Text(
          'You Want to Meout?',
          style: TextStyle(fontSize: 18, color: Colors.red[600]),
        ),
        actions: [
          TextButton(
            child: Text(
              'Cancel',
              style: TextStyle(fontSize: 16, color: Colors.red[600]),
            ),
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[100]),
            child: Text(
              'Meout',
              style: TextStyle(fontSize: 16, color: Colors.red[600]),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_name');
      await prefs.remove('user_id');
      await prefs.remove('morse_receiver_id');
      await prefs.remove('morse_receiver_name');
      await FirebaseMessaging.instance.deleteToken();

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    } catch (e, st) {
      debugPrint('Error during logout: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: isOn ? Colors.teal[50] : Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          child: IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.red[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.logout_rounded,
                color: Colors.red[600],
                size: 18,
              ),
            ),
            tooltip: 'Leave MeWorld',
            onPressed: logout,
          ),
        ),
        title: Text(
          'M E O N',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 28,
            color: Colors.teal[800],
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            child: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.teal[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.people_rounded,
                  color: Colors.teal[700],
                  size: 18,
                ),
              ),
              tooltip: 'MeFriends',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FriendsPage(
                      currentUserId: widget.currentUserId,
                      currentUserName: widget.currentUserName,
                      toggleVisibilityCallback: _toggleFriendVisibility,
                      cachedVisibility: cachedFriendVisibility,
                      setMorseReceiver: _setMorseReceiver,
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            child: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.teal[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: Colors.teal[700],
                  size: 18,
                ),
              ),
              tooltip: 'MeSettings',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        SettingsPage(userId: widget.currentUserId),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: isOn ? Colors.teal[100] : Colors.grey[300],
            borderRadius: BorderRadius.circular(25),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isOn ? Icons.wb_sunny_outlined : Icons.bedtime_outlined,
                size: 50,
                color: isOn ? Colors.teal[700] : Colors.grey[800],
              ),
              const SizedBox(height: 30),

              // Morse receiver indicator
              if (morseMode && morseReceiverName != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    'Signaling: $morseReceiverName',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[700],
                    ),
                  ),
                ),

              // The main button with Morse support
              GestureDetector(
                onTap: () {
                  if (!morseMode) {
                    toggleStatus();
                  }
                },
                onTapDown: (_) => _onPressStart(),
                onTapUp: (_) => _onPressEnd(),
                onTapCancel: () {
                  if (morseMode) _pressStartTime = null;
                },
                child: ElevatedButton(
                  onPressed: () {
                    if (!morseMode) toggleStatus();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOn ? Colors.teal[600] : Colors.grey[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 50,
                      vertical: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    textStyle: const TextStyle(fontSize: 20),
                  ),
                  child: Text(isOn ? "MEON" : "MEOFF"),
                ),
              ),

              const SizedBox(height: 10),

              // Morse mode toggle
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Normal'),
                  Switch(
                    value: morseMode,
                    onChanged: (val) async {
                      setState(() {
                        morseMode = val;
                        lastSignal = val
                            ? (morseReceiverName != null
                                ? 'Ready to signal $morseReceiverName'
                                : 'Select a friend first')
                            : '';
                      });
                      await _saveMorseModeToPrefs(val);
                    },
                    activeColor: Colors.teal,
                  ),
                  const Text('Morse'),
                ],
              ),

              const SizedBox(height: 10),

              // Morse feedback text
              Text(
                lastSignal.isEmpty
                    ? (morseMode
                        ? 'Select a friend first'
                        : 'Tap button to toggle status')
                    : lastSignal,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}