import 'dart:async';
import 'package:flutter/material.dart';
import 'package:meon/appwidgets.dart';
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
  final Map<String, String> _friendNameCache = {};
  bool _friendListenerInitialized = false;

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
  bool _isHolding = false;

  // Morse history state
  final List<MorseHistoryItem> _sentHistory = [];
  final List<MorseHistoryItem> _receivedHistory = [];
  Timer? _historyCleanupPeriodicTimer;

  // ==================== CONSTANTS ====================
  
  static const Duration _debounceDelay = Duration(seconds: 2);
  static const Duration _visibilityDebounceDelay = Duration(seconds: 3);
  static const Duration _morseResetDelay = Duration(seconds: 3);
  static const Duration _displayResetDelay = Duration(seconds: 2);
  static const Duration _historyRetentionPeriod = Duration(minutes: 3);
  static const Duration _historyCleanupInterval = Duration(minutes: 1);
  static const Duration _progressUpdateInterval = Duration(milliseconds: 50);
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  // Signal thresholds
  static const int _dotThreshold = 1000;
  static const int _dashThreshold = 3000;
  static const int _longThreshold = 6000;

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
    await Future.wait([
      _loadStatusFromPrefs(),
      _initFCMToken(),
      _loadCachedFriendVisibility(),
      _loadMorseReceiver(),
      _loadMorseModeFromPrefs(),
    ]);
    
    _setupListeners();
    _setupNotificationCallbacks();
    _startHistoryCleanup();
  }

  void _setupListeners() {
    _setupFriendVisibilityListener();
    _setupMorseListener();
    _setupFriendResponseListener();
  }

  void _setupNotificationCallbacks() {
    NotificationService.onToggleOffline ??= () async {
      if (mounted) await toggleStatus();
    };
    NotificationService.onFriendResponse ??= _sendFriendResponse;
  }

  void _startHistoryCleanup() {
    _historyCleanupPeriodicTimer = Timer.periodic(
      _historyCleanupInterval,
      (_) => _performHistoryCleanup(),
    );
  }

  void _disposeResources() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelAllTimers();
    _cancelAllStreams();
  }

  void _cancelAllTimers() {
    final timers = [
      _statusSaveDebounceTimer,
      _friendVisibilityDebounceTimer,
      _morseResetTimer,
      _pressUpdateTimer,
      _pressDisplayResetTimer,
      _historyCleanupPeriodicTimer,
    ];
    for (final timer in timers) {
      timer?.cancel();
    }
  }

  void _cancelAllStreams() {
    final streams = [
      _friendVisibilityListener,
      _morseListener,
      _fcmTokenListener,
    ];
    for (final stream in streams) {
      stream?.cancel();
    }
  }

  // ==================== SHARED PREFERENCES HELPERS ====================

  Future<void> _saveToPrefs(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    }
  }

  Future<void> _removeFromPrefs(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  // ==================== STATUS MANAGEMENT ====================

  Future<void> _loadStatusFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStatus = prefs.getBool('meon_status') ?? false;
      setState(() => isMeOn = savedStatus);
      await _saveUserStatusToFirestore(isMeOn);
      await _showSelfToggleNotification(isMeOn);
    } catch (e, st) {
      _logError('loading status from prefs', e, st);
    }
  }

  Future<void> _loadMorseModeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool('morse_mode') ?? false;
      setState(() => morseMode = saved);
      if (morseMode) _updateMorseStatus();
    } catch (e, st) {
      _logError('loading morse mode from prefs', e, st);
    }
  }

  Future<void> toggleStatus() async {
    final newStatus = !isMeOn;
    setState(() => isMeOn = newStatus);
    
    await Future.wait([
      _saveToPrefs('meon_status', newStatus),
      _saveUserStatusToFirestore(newStatus),
      _showSelfToggleNotification(newStatus),
    ]);
  }

  // ==================== FIREBASE OPERATIONS WITH RETRY ====================

  Future<void> _performWithRetry(
    String operation,
    Future<void> Function() action, {
    int retries = _maxRetries,
    Duration delay = _retryDelay,
  }) async {
    for (int attempt = 1; attempt <= retries; attempt++) {
      try {
        await action();
        return;
      } catch (e, st) {
        _logError('$operation (attempt $attempt)', e, st);
        if (attempt == retries) {
          debugPrint('Max retries reached for $operation');
        } else {
          await Future.delayed(delay);
        }
      }
    }
  }

  Future<void> _saveUserStatusToFirestore(bool status) async {
    _statusSaveDebounceTimer?.cancel();
    _statusSaveDebounceTimer = Timer(_debounceDelay, () async {
      await _performWithRetry('saving user status', () async {
        final token = await FirebaseMessaging.instance.getToken();
        final data = {
          'isOn': status,
          'lastUpdated': FieldValue.serverTimestamp(),
          if (token != null) 'fcmToken': token,
        };
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUserId)
            .set(data, SetOptions(merge: true));
      });
    });
  }

  Future<void> _toggleFriendVisibility(String friendId, bool currentValue) async {
    final newValue = !currentValue;
    await _updateFriendVisibilityInCache(friendId, newValue);

    _friendVisibilityDebounceTimer?.cancel();
    _friendVisibilityDebounceTimer = Timer(_visibilityDebounceDelay, () async {
      await _performWithRetry('updating friend visibility', () async {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUserId)
            .collection('friends')
            .doc(friendId)
            .update({'canSeeStatus': newValue});
      });
    });
  }

  // ==================== FCM TOKEN MANAGEMENT ====================

  Future<void> _initFCMToken() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      await _updateFCMTokenIfChanged();
      _setupTokenRefreshListener();
    } catch (e, st) {
      _logError('initializing FCM token', e, st);
    }
  }

  Future<void> _updateFCMTokenIfChanged() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('fcm_token');
    final token = await FirebaseMessaging.instance.getToken();
    
    if (token != null && token != savedToken) {
      await _updateTokenInFirestore(token);
      await prefs.setString('fcm_token', token);
    }
  }

  void _setupTokenRefreshListener() {
    _fcmTokenListener = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      try {
        await _updateTokenInFirestore(newToken);
        await _saveToPrefs('fcm_token', newToken);
      } catch (e, st) {
        _logError('handling token refresh', e, st);
      }
    });
  }

  Future<void> _updateTokenInFirestore(String token) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .set({'fcmToken': token}, SetOptions(merge: true));
  }

  // ==================== FRIEND MANAGEMENT ====================

  Future<String> _getFriendNameCached(String friendId) async {
    if (_friendNameCache.containsKey(friendId)) {
      return _friendNameCache[friendId]!;
    }
    final name = await _getFriendName(friendId);
    _friendNameCache[friendId] = name;
    return name;
  }

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
      _logError('getting friend name', e);
      return 'Unknown Friend';
    }
  }

  Future<void> _sendFriendResponse(String friendId) async {
    try {
      final friendName = await _getFriendNameCached(friendId);

      await FirebaseFirestore.instance.collection('friend_responses').add({
        'senderId': widget.currentUserId,
        'senderName': widget.currentUserName,
        'receiverId': friendId,
        'message': 'I see you!',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _showSnackBar('👋 Sent "I see you" to $friendName', Colors.green[600]);
    } catch (e) {
      _logError('sending friend response', e);
    }
  }

  // ==================== MORSE COMMUNICATION ====================

  Future<void> _loadMorseReceiver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final receiverId = prefs.getString('morse_receiver_id');
      final receiverName = prefs.getString('morse_receiver_name');

      if (receiverId != null && receiverName != null) {
        setState(() {
          morseReceiverId = receiverId;
          morseReceiverName = receiverName;
        });
        _updateMorseStatus();
      } else {
        _updateMorseStatus();
      }
    } catch (e, st) {
      _logError('loading Morse receiver', e, st);
    }
  }

  Future<void> _setMorseReceiver(String friendId, String friendName) async {
    try {
      await Future.wait([
        _saveToPrefs('morse_receiver_id', friendId),
        _saveToPrefs('morse_receiver_name', friendName),
      ]);

      setState(() {
        morseReceiverId = friendId;
        morseReceiverName = friendName;
      });
      _updateMorseStatus();
    } catch (e, st) {
      _logError('setting Morse receiver', e, st);
    }
  }

  Future<void> _clearMorseReceiver() async {
    try {
      await Future.wait([
        _removeFromPrefs('morse_receiver_id'),
        _removeFromPrefs('morse_receiver_name'),
      ]);

      setState(() {
        morseReceiverId = null;
        morseReceiverName = null;
      });
      _updateMorseStatus();
    } catch (e, st) {
      _logError('clearing Morse receiver', e, st);
    }
  }

  Future<void> _sendMorseSignal(String signal) async {
    if (morseReceiverId == null) {
      _updateMorseStatus('Select a friend first');
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('morse_signals').add({
        'senderId': widget.currentUserId,
        'receiverId': morseReceiverId,
        'signal': signal,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _updateMorseHistoryAndBuffer(signal);
      _scheduleBufferReset();
    } catch (e, st) {
      _logError('sending Morse signal', e, st);
      _updateMorseStatus('Failed to send signal');
    }
  }

  void _updateMorseHistoryAndBuffer(String signal) {
    setState(() {
      _sentHistory.add(MorseHistoryItem(signal: signal, timestamp: DateTime.now()));
      _morseBuffer.add(signal);
    });
    _updateMorseStatus('Sent to $morseReceiverName: ${_morseBuffer.join()}');
  }

  void _scheduleBufferReset() {
    _morseResetTimer?.cancel();
    _morseResetTimer = Timer(_morseResetDelay, () {
      if (!mounted) return;
      _morseBuffer.clear();
      _updateMorseStatus();
    });
  }

  // ==================== MORSE TIMING LOGIC ====================

  void _onPressStart() {
    if (!morseMode) return;

    _pressStartTime = DateTime.now();
    _isHolding = true;
    _startProgressUpdater();
    _updateMorseStatus('Holding...');
  }

  void _onPressEnd() {
    if (!morseMode || _pressStartTime == null || !_isHolding) return;

    final duration = DateTime.now().difference(_pressStartTime!);
    _resetPressState(duration);
    
    final signal = _signalFromDuration(duration);
    _sendMorseSignal(signal);
    _scheduleDisplayReset();
  }

  void _onPressCancel() {
    if (!morseMode) return;
    _resetPressState();
    _updateMorseStatus();
  }

  void _resetPressState([Duration? lastDuration]) {
    _pressStartTime = null;
    _isHolding = false;
    _pressUpdateTimer?.cancel();
    
    setState(() {
      _currentPressDuration = Duration.zero;
      if (lastDuration != null) _lastPressDuration = lastDuration;
    });
  }

  void _startProgressUpdater() {
    _pressUpdateTimer?.cancel();
    _pressUpdateTimer = Timer.periodic(_progressUpdateInterval, (_) {
      if (_pressStartTime == null || !_isHolding) return;
      setState(() {
        _currentPressDuration = DateTime.now().difference(_pressStartTime!);
      });
    });
  }

  void _scheduleDisplayReset() {
    _pressDisplayResetTimer?.cancel();
    _pressDisplayResetTimer = Timer(_displayResetDelay, () {
      if (!mounted) return;
      setState(() => _lastPressDuration = null);
    });
  }

  // ==================== MORSE SIGNAL HELPERS ====================

  String _signalFromDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms <= _dotThreshold) return '.';
    if (ms <= _dashThreshold) return '-';
    if (ms <= _longThreshold) return '_';
    return '~';
  }

  String _labelForDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms <= _dotThreshold) return 'Dot (·)';
    if (ms <= _dashThreshold) return 'Dash (–)';
    if (ms <= _longThreshold) return 'Daaash (~~)';
    return 'Long hold';
  }

  double _progressForDuration(Duration d) {
    final ms = d.inMilliseconds;
    return (ms / _longThreshold.toDouble()).clamp(0.0, 1.0);
  }

  void _updateMorseStatus([String? message]) {
    if (!mounted || !morseMode) return;

    final computed = message ?? 
        (morseReceiverName != null 
            ? 'Ready to Signal $morseReceiverName' 
            : '');

    if (computed == lastSignal) return;
    setState(() => lastSignal = computed);
  }

  // ==================== LISTENERS ====================

  void _setupFriendVisibilityListener() {
    _friendVisibilityListener?.cancel();
    _friendVisibilityListener = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .collection('friends')
        .snapshots()
        .listen(_handleFriendVisibilitySnapshot, 
               onError: (e, st) => _logError('friend visibility listener', e, st));
  }

  void _handleFriendVisibilitySnapshot(QuerySnapshot snapshot) async {
    final updatedVisibility = <String, bool>{};
    
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>?;
      final canSee = data?['canSeeStatus'] ?? false;
      updatedVisibility[doc.id] = canSee;

      final name = data?['name'];
      if (name != null) _friendNameCache[doc.id] = name as String;
    }

    _checkForFriendsComingOnline(updatedVisibility);
    _updateVisibilityIfChanged(updatedVisibility);
  }

  void _checkForFriendsComingOnline(Map<String, bool> updatedVisibility) {
    if (!_friendListenerInitialized) {
      _friendListenerInitialized = true;
      return;
    }

    updatedVisibility.forEach((friendId, canSee) {
      final wasOnline = cachedFriendVisibility[friendId] ?? false;
      if (!wasOnline && canSee) {
        final friendName = _friendNameCache[friendId] ?? 'Friend';
        _onFriendCameOnline(friendName, friendId);
      }
    });
  }

  void _updateVisibilityIfChanged(Map<String, bool> updatedVisibility) {
    if (_hasVisibilityChanged(updatedVisibility)) {
      setState(() => cachedFriendVisibility = updatedVisibility);
      _syncVisibilityCache(updatedVisibility);
    }
  }

  bool _hasVisibilityChanged(Map<String, bool> newVisibility) {
    return newVisibility.entries.any((entry) => 
        cachedFriendVisibility[entry.key] != entry.value);
  }

  void _setupMorseListener() {
    _morseListener?.cancel();
    _morseListener = FirebaseFirestore.instance
        .collection('morse_signals')
        .where('receiverId', isEqualTo: widget.currentUserId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(_handleMorseSnapshot, 
               onError: (e) => _logError('morse listener', e));
  }

  void _handleMorseSnapshot(QuerySnapshot snapshot) {
    if (snapshot.docs.isEmpty) return;

    final doc = snapshot.docs.first;
    final data = doc.data() as Map<String, dynamic>?;
    final senderId = data?['senderId'];
    if (senderId == widget.currentUserId) return;

    final signal = data?['signal'];
    if (senderId != null && signal != null) {
      _handleIncomingMorse(senderId as String, signal as String);
    }
  }

  Future<void> _handleIncomingMorse(String senderId, String signal) async {
    try {
      final friendName = await _getFriendNameCached(senderId);
      _addToReceivedHistory(signal, friendName);
      _showMorseNotification(friendName, signal);
      _updateMorseDisplayForReceived(friendName, signal);
    } catch (e, st) {
      _logError('handling incoming morse', e, st);
    }
  }

  void _addToReceivedHistory(String signal, String friendName) {
    if (mounted) {
      setState(() {
        _receivedHistory.add(MorseHistoryItem(
          signal: signal,
          timestamp: DateTime.now(),
          senderName: friendName,
        ));
      });
      _performHistoryCleanup();
    }
  }

  void _showMorseNotification(String friendName, String signal) {
    try {
      NotificationService.showMorseNotification(friendName, signal);
    } catch (e, st) {
      _logError('showing morse notification', e, st);
    }
  }

  void _updateMorseDisplayForReceived(String friendName, String signal) {
    if (mounted && morseMode && !_isHolding) {
      _updateMorseStatus('Received from $friendName: $signal');
      _pressDisplayResetTimer?.cancel();
      _pressDisplayResetTimer = Timer(_displayResetDelay, _updateMorseStatus);
    }
  }

  // ==================== UTILITY METHODS ====================

  void _logError(String operation, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('Error $operation: $error${stackTrace != null ? ' $stackTrace' : ''}');
  }

  void _showSnackBar(String message, Color? backgroundColor) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: _displayResetDelay,
      ),
    );
  }

  Future<void> _performHistoryCleanup() async {
    if (!mounted) return;
    final cutoff = DateTime.now().subtract(_historyRetentionPeriod);
    setState(() {
      _sentHistory.removeWhere((item) => item.timestamp.isBefore(cutoff));
      _receivedHistory.removeWhere((item) => item.timestamp.isBefore(cutoff));
    });
  }

  // ==================== REMAINING METHODS (Kept Same) ====================

  void _setupFriendResponseListener() {
    NotificationService.onFriendResponse ??= (String friendId) async {
      if (!mounted) return;
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.currentUserId)
            .collection('friendResponses')
            .doc(friendId)
            .set({'timestamp': FieldValue.serverTimestamp(), 'status': 'seen'});
        debugPrint("Friend response handled for $friendId");
      } catch (e) {
        debugPrint("Error handling friend response: $e");
      }
    };
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

  Future<void> _updateFriendVisibilityInCache(String friendId, bool canSee) async {
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

  void _onFriendCameOnline(String friendName, String friendId) {
    NotificationService.showFriendOnlineNotification(
      friendName,
      friendId,
      userId: widget.currentUserId,
    );
  }

  Future<void> _showSelfToggleNotification(bool status) async {
    try {
      await NotificationService.showMeonStatusNotification(
        status,
        userId: widget.currentUserId,
      );

      if (status) {
        await _startOfflineReminderIfEnabled();
      } else {
        await NotificationService.stopOfflineReminder();
      }
    } catch (e, st) {
      debugPrint('Error showing self toggle notification: $e $st');
    }
  }

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
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    } catch (e, st) {
      debugPrint('Error during logout: $e $st');
    }
  }

  // ==================== UI HELPER METHODS ====================

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

  String get _progressText {
    if (_isHolding) {
      final seconds = (_currentPressDuration.inMilliseconds / 1000.0).toStringAsFixed(2);
      final label = _labelForDuration(_currentPressDuration);
      return 'Holding: ${seconds}s — $label';
    } else if (_lastPressDuration != null) {
      final seconds = (_lastPressDuration!.inMilliseconds / 1000.0).toStringAsFixed(2);
      final label = _labelForDuration(_lastPressDuration!);
      return 'Last: ${seconds}s — $label';
    } else {
      return 'Tap or hold to send signals';
    }
  }

  double get _currentProgress {
    if (_pressStartTime != null && _isHolding) {
      return _progressForDuration(_currentPressDuration);
    } else if (_lastPressDuration != null) {
      return _progressForDuration(_lastPressDuration!);
    } else {
      return 0.0;
    }
  }

  Color get _progressColor {
    if (_isHolding) return Colors.blue[600]!;
    if (_lastPressDuration != null) return Colors.blue[400]!;
    return Colors.grey[400]!;
  }

  // ==================== BUILD METHOD ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: _buildAppBar(),
      body: Container(
        margin: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildMainContainer(),
              const SizedBox(height: 20),
              _buildProgressSection(),
              const SizedBox(height: 12),
              _buildHistorySection(),
              const SizedBox(height: 12),
              _buildMorseStatusSection(),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
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
          onPressed: _navigateToFriends,
        ),
        AppWidgets.appBarIconButton(
          icon: Icons.tune_rounded,
          color: Colors.grey[700]!,
          tooltip: 'MeSettings',
          onPressed: _navigateToSettings,
        ),
      ],
    );
  }

  Widget _buildMainContainer() {
    return AppWidgets.mainContainerWithCheckbox(
      backgroundColor: _mainContainerColor,
      isChecked: morseMode,
      checkboxColor: Colors.blue[700],
      checkboxUncheckedBorderColor: _checkboxUncheckedBorderColor,
      onCheckboxTap: _toggleMorseMode,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_mainIcon, size: 50, color: _primaryColor),
          const SizedBox(height: 30),
          AppWidgets.mainButton(
            text: _buttonText,
            backgroundColor: morseMode ? Colors.blue[700]! : _primaryColor,
            isElevated: _isHolding,
            onPressed: morseMode ? null : toggleStatus,
            onTapDown: _onPressStart,
            onTapUp: _onPressEnd,
            onTapCancel: _onPressCancel,
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    return AppWidgets.fixedHeightAnimatedContainer(
      showContent: morseMode,
      child: Column(
        children: [
          AppWidgets.progressIndicator(
            progress: _currentProgress,
            isHolding: _isHolding,
            activeColor: _progressColor,
          ),
          const SizedBox(height: 8),
          Text(
            _progressText,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistorySection() {
    return Column(
      children: [
        if (_sentHistory.isNotEmpty && morseReceiverName != null)
          AppWidgets.sentHistoryContainer(
            sentHistory: _sentHistory,
            onDeleteSent: _deleteSentSignal,
            receiverName: morseReceiverName!,
          ),
        if (_receivedHistory.isNotEmpty) ...[
          if (_sentHistory.isNotEmpty && morseReceiverName != null) const SizedBox(height: 8),
          AppWidgets.receivedHistoryContainer(
            receivedHistory: _receivedHistory,
            onDeleteReceived: _deleteReceivedSignal,
          ),
        ],
      ],
    );
  }

  Widget _buildMorseStatusSection() {
    if (morseReceiverName == null) {
      return AppWidgets.textButton(
      text: 'Select a friend first',
      onPressed: _navigateToFriends,
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            lastSignal,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          ),
          const SizedBox(width: 8),
          if (morseMode) 
          GestureDetector(
            onTap: _clearMorseReceiver,
            child: Icon(
              Icons.clear,
              size: 16,
              color: Colors.red[400],
            ),
          ),
      ],
      );
    }
  }

  // ==================== NAVIGATION HELPERS ====================

  void _navigateToFriends() {
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
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsPage(userId: widget.currentUserId),
      ),
    );
  }

  // ==================== MODE TOGGLE ====================

  Future<void> _toggleMorseMode() async {
    final newValue = !morseMode;
    setState(() {
      morseMode = newValue;
      if (!newValue) {
        _resetMorseState();
      } else {
        _updateMorseStatus();
      }
    });
    await _saveToPrefs('morse_mode', newValue);
  }

  void _resetMorseState() {
    _cancelAllTimers();
    _clearMorseReceiver();
    _pressStartTime = null;
    _currentPressDuration = Duration.zero;
    _lastPressDuration = null;
    _isHolding = false;
    lastSignal = '';
  }
}