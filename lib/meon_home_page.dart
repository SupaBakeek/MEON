import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/notification_service.dart';
import 'friends_page.dart';
import 'settings_page.dart';
import 'appwidgets.dart';

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
  // ==================== STATE VARIABLES ====================

  // Basic status
  bool isMeOn = false;
  bool morseMode = false;
  
  // Timers and streams
  Timer? _statusSaveDebounceTimer;
  Timer? _friendVisibilityDebounceTimer;
  StreamSubscription<QuerySnapshot>? _morseListener;
  StreamSubscription<QuerySnapshot>? _friendVisibilityListener;
  StreamSubscription<String?>? _fcmTokenListener;

  // Friend visibility cache
  Map<String, bool> cachedFriendVisibility = {};
  // Friend name cache (avoid repeated lookups)
  final Map<String, String> _friendNameCache = {};

  // Morse communication state
  String? morseReceiverId;
  String? morseReceiverName;
  Timer? _morseResetTimer;
  final List<String> _morseBuffer = [];
  String lastSignal = '';

  // Morse timing state
  DateTime? _pressStartTime;
  Duration _currentPressDuration = Duration.zero;
  Duration? _lastPressDuration;
  Timer? _pressUpdateTimer;
  Timer? _pressDisplayResetTimer;
  bool _isHolding = false; // Track holding state to fix the stuck issue

  // Morse history state
  final List<MorseHistoryItem> _sentHistory = [];
  final List<MorseHistoryItem> _receivedHistory = [];
  Timer? _historyCleanupPeriodicTimer;

  // ==================== LIFECYCLE METHODS ====================

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeApp();
  }

  @override
  void dispose() {
    _disposeResources();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadCachedFriendVisibility();
    }
  }

  // ==================== INITIALIZATION LOGIC ====================

  Future<void> _initializeApp() async {
    await _loadStatusFromPrefs();
    await _initFCMToken();
    await _loadCachedFriendVisibility();
    await _loadMorseReceiver();
    await _loadMorseModeFromPrefs();
    _setupFriendVisibilityListener();
    _setupMorseListener();
    _setupFriendResponseListener();
    _toggleStatusFromNotification();

    // Start a periodic cleanup timer that runs independently of new signals
    _historyCleanupPeriodicTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _performHistoryCleanup(),
    );

    // Set up notification callbacks - FIXED VERSION
    NotificationService.onToggleOffline = () async {
      // Handle user tapping "Go Offline" from notification
      if (mounted) {
        await toggleStatus(); // This will properly toggle the status
      }
    };
    NotificationService.onFriendResponse = (String friendId) {
      // Handle user tapping "I see you" from friend online notification
      _sendFriendResponse(friendId);
    };
  }

  // Add this new method for friend responses:
  Future<void> _sendFriendResponse(String friendId) async {
    try {
      // Get friend's name first
      final friendName = await _getFriendNameCached(friendId);

      // Send "I see you" notification to friend via Firestore
      await FirebaseFirestore.instance.collection('friend_responses').add({
        'senderId': widget.currentUserId,
        'senderName': widget.currentUserName,
        'receiverId': friendId,
        'message': 'I see you!',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Show local feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('👋 Sent "I see you" to $friendName'),
            backgroundColor: Colors.green[600],
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error sending friend response: $e');
    }
  }

  // Add a listener for friend responses (add this to your _initializeApp method):
void _setupFriendResponseListener() {
  NotificationService.onFriendResponse = (String friendId) async {
    if (!mounted) return;

    try {
      // Example: mark friend response in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .collection('friendResponses')
          .doc(friendId)
          .set({
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'seen',
      });

      debugPrint("Friend response handled for $friendId");
    } catch (e) {
      debugPrint("Error handling friend response: $e");
    }
  };
}

  void _disposeResources() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSaveDebounceTimer?.cancel();
    _friendVisibilityDebounceTimer?.cancel();
    _friendVisibilityListener?.cancel();
    _morseResetTimer?.cancel();
    _morseListener?.cancel();
    _fcmTokenListener?.cancel();
    _pressUpdateTimer?.cancel();
    _pressDisplayResetTimer?.cancel();
    _historyCleanupPeriodicTimer?.cancel();
  }

  // ==================== SHARED PREFERENCES LOGIC ====================

  Future<void> _loadStatusFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStatus = prefs.getBool('meon_status') ?? false;
      setState(() {
        isMeOn = savedStatus;
      });
      // Try to sync this status immediately to Firestore (debounced inside)
      _saveUserStatusToFirestore(isMeOn);
      _showSelfToggleNotification(isMeOn);
    } catch (e, st) {
      debugPrint('Error loading status from prefs: $e $st');
    }
  }

  Future<void> _loadMorseModeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('morse_mode') ?? false;
      setState(() {
        morseMode = saved;
      });
    } catch (e, st) {
      debugPrint('Error loading morse mode from prefs: $e $st');
    }
  }

  Future<void> _saveStatusToPrefs(bool status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('meon_status', status);
    } catch (e, st) {
      debugPrint('Error saving status to prefs: $e $st');
    }
  }

  Future<void> _saveMorseModeToPrefs(bool mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('morse_mode', mode);
    } catch (e, st) {
      debugPrint('Error saving morse mode to prefs: $e $st');
    }
  }

  // ==================== FIREBASE & FCM LOGIC ====================

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
            .set({'fcmToken': token}, SetOptions(merge: true));
        await prefs.setString('fcm_token', token);
      }

      // Keep a reference so we can cancel when disposed
      _fcmTokenListener = FirebaseMessaging.instance.onTokenRefresh.listen((
        newToken,
      ) async {
        try {
          if (newToken != null) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(widget.currentUserId)
                .set({'fcmToken': newToken}, SetOptions(merge: true));
            await prefs.setString('fcm_token', newToken);
          }
        } catch (e, st) {
          debugPrint('Error handling token refresh: $e $st');
        }
      });
    } catch (e, st) {
      debugPrint('Error initializing FCM token: $e $st');
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

          // We always set the status even if token is null (merge to avoid wiping other fields)
          final data = {
            'isOn': status,
            'lastUpdated': FieldValue.serverTimestamp(),
          };
          if (token != null) data['fcmToken'] = token;

          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.currentUserId)
              .set(data, SetOptions(merge: true));
          return;
        } catch (e, st) {
          debugPrint('Attempt $attempt: Error saving user status: $e $st');
          if (attempt == retries) {
            debugPrint('Max retries reached for saving user status.');
          } else {
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    });
  }

  // ==================== STATUS TOGGLE LOGIC ====================

  Future<void> toggleStatus() async {
    final newStatus = !isMeOn;

    setState(() {
      isMeOn = newStatus;
    });

    await _saveStatusToPrefs(newStatus);
    await _saveUserStatusToFirestore(newStatus);
    await _showSelfToggleNotification(newStatus);
  }
////////////////////////////////////////////////////////////////////////////////////////////
  Future<void> _toggleStatusFromNotification() async {
    if (!mounted) return;
    await toggleStatus();
  }

  // Update your existing _showSelfToggleNotification method:
  Future<void> _showSelfToggleNotification(bool status) async {
    try {
      // Use the correct method name from your cleaned notification service
      await NotificationService.showMeonStatusNotification(
        status,
        userId: widget.currentUserId,
      );

      // Handle offline reminder when going online
      if (status) {
        // User just went online, start offline reminder if enabled
        await _startOfflineReminderIfEnabled();
      } else {
        // User went offline, stop offline reminder
        await NotificationService.stopOfflineReminder();
      }
    } catch (e, st) {
      debugPrint('Error showing self toggle notification: $e $st');
    }
  }

  // Add this new method to handle offline reminders:
  Future<void> _startOfflineReminderIfEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled =
          prefs.getBool('offline_reminder_enabled_${widget.currentUserId}') ??
          true;
      final minutes =
          prefs.getInt('offline_reminder_minutes_${widget.currentUserId}') ?? 5;

      if (isEnabled) {
        await NotificationService.startOfflineReminder(
          widget.currentUserId,
          minutes,
        );
      }
    } catch (e) {
      debugPrint('Error starting offline reminder: $e');
    }
  }

  // Add this method to handle when friends come online (call this from your friend visibility listener):
  void _onFriendCameOnline(String friendName, String friendId) {
    NotificationService.showFriendOnlineNotification(
      friendName,
      friendId,
      userId: widget.currentUserId,
    );
  }

  // ==================== FRIEND VISIBILITY LOGIC ====================
  Future<String> _getFriendName(String friendId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .collection('friends')
          .doc(friendId)
          .get();
      return doc.data()?['name'] ?? 'Unknown Friend';
    } catch (e) {
      debugPrint('Friend name error: $e');
      return 'Unknown Friend';
    }
  }

  Future<String> _getFriendNameCached(String friendId) async {
    if (_friendNameCache.containsKey(friendId)) {
      return _friendNameCache[friendId]!;
    }
    final name = await _getFriendName(friendId);
    _friendNameCache[friendId] = name;
    return name;
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
      debugPrint('Error loading cached friend visibility: $e $st');
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
      debugPrint('Error updating friend visibility in cache: $e $st');
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
              'Attempt $attempt: Error updating friend visibility: $e $st',
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

  // Update your _setupFriendVisibilityListener to detect when friends come online:
void _setupFriendVisibilityListener() {
  _friendVisibilityListener?.cancel();

  _friendVisibilityListener = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.currentUserId)
      .collection('friends')
      .snapshots()
      .listen(
        (snapshot) async {
          final updatedVisibility = <String, bool>{};
          for (final doc in snapshot.docs) {
            final canSee = doc.data()['canSeeStatus'] ?? false;
            updatedVisibility[doc.id] = canSee;

            // Cache names while we're here
            final name = doc.data()['name'];
            if (name != null) _friendNameCache[doc.id] = name as String;
          }

          // Check for friends who just came online
          updatedVisibility.forEach((friendId, canSee) {
            final wasOnline = cachedFriendVisibility[friendId] ?? false;
            if (!wasOnline && canSee) {
              // Friend just came online!
              final friendName = _friendNameCache[friendId] ?? 'Friend';
              _onFriendCameOnline(friendName, friendId);
            }
          });

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
            _syncVisibilityCache(updatedVisibility);
          }
        },
        onError: (error, stackTrace) {
          debugPrint('Friend visibility listener error: $error $stackTrace');
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
      debugPrint('Error syncing visibility cache: $e $st');
    }
  }

  // ==================== MORSE COMMUNICATION LOGIC ====================

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
      debugPrint('Error loading Morse receiver: $e $st');
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
      debugPrint('Error setting Morse receiver: $e $st');
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
      debugPrint('Error clearing Morse receiver: $e $st');
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

      // Add to sent history
      setState(() {
        _sentHistory.add(
          MorseHistoryItem(signal: signal, timestamp: DateTime.now()),
        );
        _morseBuffer.add(signal);
        lastSignal = 'Sent to $morseReceiverName: ${_morseBuffer.join()}';
      });

      // Start/reset the short-term reset timer for UI
      _morseResetTimer?.cancel();
      _morseResetTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          setState(() {
            _morseBuffer.clear();
            lastSignal = 'Ready to signal $morseReceiverName';
          });
        }
      });
    } catch (e, st) {
      debugPrint('Error sending Morse signal: $e $st');
      setState(() => lastSignal = 'Failed to send signal');
    }
  }

  // ==================== HISTORY MANAGEMENT ====================
  void _performHistoryCleanup() {
    if (!mounted) return;
    setState(() {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 3));
      _sentHistory.removeWhere((item) => item.timestamp.isBefore(cutoff));
      _receivedHistory.removeWhere((item) => item.timestamp.isBefore(cutoff));
    });
  }

  void _deleteSentSignal(int index) {
    setState(() {
      if (index >= 0 && index < _sentHistory.length) {
        _sentHistory.removeAt(index);
      }
    });
  }

  void _deleteReceivedSignal(int index) {
    setState(() {
      if (index >= 0 && index < _receivedHistory.length) {
        _receivedHistory.removeAt(index);
      }
    });
  }

  void _setupMorseListener() {
    _morseListener?.cancel();

    _morseListener = FirebaseFirestore.instance
        .collection('morse_signals')
        .where('receiverId', isEqualTo: widget.currentUserId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) {
          if (snapshot.docs.isEmpty) return;

          final doc = snapshot.docs.first;
          final senderId = doc['senderId'];

          // Ignore signals we sent ourselves
          if (senderId == widget.currentUserId) return;

          final signal = doc['signal'];

          // Handle incoming signal asynchronously so we can fetch the sender's name
          _handleIncomingMorse(senderId as String, signal as String);
        }, onError: (e) => debugPrint('Morse listener error: $e'));
  }
  

  Future<void> _handleIncomingMorse(String senderId, String signal) async {
    try {
      final friendName = await _getFriendNameCached(senderId);

      if (mounted) {
        setState(() {
          _receivedHistory.add(
            MorseHistoryItem(
              signal: signal,
              timestamp: DateTime.now(),
              senderName: friendName,
            ),
          );
        });

        // Keep the history trimmed
        _performHistoryCleanup();
      }

      // Show notification
      try {
        NotificationService.showMorseNotification(friendName, signal);
      } catch (e, st) {
        debugPrint('Error showing morse notification: $e $st');
      }

      // Update UI lastSignal when in morse mode
      if (mounted && morseMode) {
        setState(() {
          lastSignal = 'Received from $friendName: $signal';
        });
      }
    } catch (e, st) {
      debugPrint('Error handling incoming morse: $e $st');
    }
  }

  // ==================== MORSE TIMING LOGIC ====================

  void _onPressStart() {
    if (!morseMode) return;

    _pressStartTime = DateTime.now();
    _isHolding = true;

    _pressUpdateTimer?.cancel();
    _pressUpdateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_pressStartTime == null || !_isHolding) return;
      setState(() {
        _currentPressDuration = DateTime.now().difference(_pressStartTime!);
      });
    });

    setState(() {
      lastSignal = 'Holding...';
    });
  }

  void _onPressEnd() {
    if (!morseMode || _pressStartTime == null || !_isHolding) return;

    final duration = DateTime.now().difference(_pressStartTime!);
    _pressStartTime = null;
    _isHolding = false;

    _pressUpdateTimer?.cancel();
    setState(() {
      _currentPressDuration = Duration.zero;
      _lastPressDuration = duration;
    });

    final signal = _signalFromDuration(duration);
    _sendMorseSignal(signal);

    _pressDisplayResetTimer?.cancel();
    _pressDisplayResetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _lastPressDuration = null;
        });
      }
    });
  }

  void _onPressCancel() {
    if (!morseMode) return;

    _pressStartTime = null;
    _isHolding = false;
    _pressUpdateTimer?.cancel();

    setState(() {
      _currentPressDuration = Duration.zero;
      lastSignal = morseReceiverName != null
          ? 'Ready to signal $morseReceiverName'
          : 'Select a friend first';
    });
  }

  String _signalFromDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms <= 1000) {
      return '.';
    } else if (ms <= 3000) {
      return '-';
    } else if (ms <= 6000) {
      return '_';
    } else {
      return '~';
    }
  }

  String _labelForDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms <= 1000) {
      return 'Dot (·)';
    } else if (ms <= 3000) {
      return 'Dash (–)';
    } else if (ms <= 6000) {
      return 'Daaash (~~)';
    } else {
      return 'Long hold';
    }
  }

  double _progressForDuration(Duration d) {
    final ms = d.inMilliseconds;
    final value = ms / 6000.0;
    return value.clamp(0.0, 1.0);
  }

  // ==================== LOGOUT LOGIC ====================

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
      // Remove all previous routes so user cannot navigate back
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e, st) {
      debugPrint('Error during logout: $e $st');
    }
  }

  // ==================== HELPER METHODS FOR COLORS ====================

  Color get _backgroundColor {
    if (morseMode) return Colors.blue[50]!;
    return isMeOn ? Colors.teal[50]! : Colors.grey[100]!;
  }

  Color get _mainContainerColor {
    if (morseMode) return Colors.blue[100]!;
    return isMeOn ? Colors.teal[100]! : Colors.grey[300]!;
  }

  Color get _primaryColor {
    if (morseMode) return Colors.blue[700]!;
    return isMeOn ? Colors.teal[700]! : Colors.grey[800]!;
  }

  Color get _checkboxUncheckedBorderColor {
    return isMeOn ? Colors.teal[700]! : Colors.grey[800]!;
  }

  IconData get _mainIcon {
    if (morseMode) return Icons.power_input;
    return isMeOn ? Icons.wb_sunny_outlined : Icons.bedtime_outlined;
  }

  String get _buttonText {
    if (morseMode) return 'MECODE';
    return isMeOn ? "MEON" : "MEOFF";
  }

  // ==================== BUILD METHOD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: AppWidgets.appBarIconButton(
          icon: Icons.logout_rounded,
          color: Colors.red[600]!,
          size: 18,
          tooltip: 'Leave MeWorld',
          onPressed: logout,
        ),
        title: Text(
          'M E O N',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 28,
            color: Colors.grey[800],
            letterSpacing: 2,
          ),
        ),
        centerTitle: true,
        actions: [
          AppWidgets.appBarIconButton(
            icon: Icons.people_rounded,
            color: Colors.grey[700]!,
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
          AppWidgets.appBarIconButton(
            icon: Icons.tune_rounded,
            color: Colors.grey[700]!,
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
        ],
      ),
      body: Container(
        margin: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Main content container with Stack for checkbox positioning
              AppWidgets.mainContainerWithCheckbox(
                backgroundColor: _mainContainerColor,
                isChecked: morseMode,
                checkboxColor: Colors.blue[700],
                checkboxUncheckedBorderColor: _checkboxUncheckedBorderColor,
                onCheckboxTap: () async {
                  final newValue = !morseMode;
                  setState(() {
                    morseMode = newValue;
                    lastSignal = newValue
                        ? (morseReceiverName != null
                              ? 'Ready to signal $morseReceiverName'
                              : 'Select a friend first')
                        : '';
                    if (!newValue) {
                      _pressUpdateTimer?.cancel();
                      _pressDisplayResetTimer?.cancel();
                      _pressStartTime = null;
                      _currentPressDuration = Duration.zero;
                      _lastPressDuration = null;
                      _isHolding = false;
                    }
                  });
                  await _saveMorseModeToPrefs(newValue);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_mainIcon, size: 50, color: _primaryColor),
                    const SizedBox(height: 30),
                    if (morseMode && morseReceiverName != null)
                      AppWidgets.morseReceiverDisplay(
                        receiverName: morseReceiverName!,
                        onClear: _clearMorseReceiver,
                      ),
                    AppWidgets.mainButton(
                      text: _buttonText,
                      backgroundColor: morseMode
                          ? Colors.blue[700]!
                          : _primaryColor,
                      isElevated: _isHolding,
                      onPressed: morseMode ? null : toggleStatus,
                      onTapDown: _onPressStart,
                      onTapUp: _onPressEnd,
                      onTapCancel: _onPressCancel,
                    ),
                  ],
                ),
              ),

              // Fixed height container for progress bar
              AppWidgets.fixedHeightAnimatedContainer(
                showContent: morseMode,
                child: Column(
                  children: [
                    AppWidgets.progressIndicator(
                      progress: (_pressStartTime != null && _isHolding)
                          ? _progressForDuration(_currentPressDuration)
                          : (_lastPressDuration != null
                                ? _progressForDuration(_lastPressDuration!)
                                : 0.0),
                      isHolding: _isHolding,
                      activeColor: _isHolding
                          ? Colors.blue[600]!
                          : (_lastPressDuration != null
                                ? Colors.blue[400]!
                                : Colors.grey[400]!),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isHolding
                          ? 'Holding: ${(_currentPressDuration.inMilliseconds / 1000.0).toStringAsFixed(2)}s — ${_labelForDuration(_currentPressDuration)}'
                          : (_lastPressDuration != null
                                ? 'Last: ${(_lastPressDuration!.inMilliseconds / 1000.0).toStringAsFixed(2)}s — ${_labelForDuration(_lastPressDuration!)}'
                                : 'Tap or hold to send signals'),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              // History bars below
              const SizedBox(height: 12),
              Column(
                children: [
                  if (_sentHistory.isNotEmpty)
                    AppWidgets.sentHistoryContainer(
                      sentHistory: _sentHistory,
                      onDeleteSent: _deleteSentSignal,
                    ),
                  if (_receivedHistory.isNotEmpty) ...[
                    if (_sentHistory.isNotEmpty) const SizedBox(height: 8),
                    AppWidgets.receivedHistoryContainer(
                      receivedHistory: _receivedHistory,
                      onDeleteReceived: _deleteReceivedSignal,
                    ),
                  ],
                ],
              ),

              // Last signal display
              const SizedBox(height: 12),
              // If no Morse receiver selected, show a button that opens FriendsPage to pick one
              if (morseReceiverName == null)
                AppWidgets.textButton(
                  text: 'Select a friend first',
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
                )
              else
                Text(
                  lastSignal,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
