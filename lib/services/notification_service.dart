import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  static Function? onToggleOffline;
  static Function? onFriendResponse;
  
  static const int statusNotificationId = 0;
  static const int morseNotificationId = 1;
  static const int friendOnlineNotificationId = 2;
  static const int friendResponseNotificationId = 3;
  static const int offlineReminderNotificationId = 4;
  
  // Timer for offline reminder functionality
  static Timer? _offlineReminderTimer;
  static String? _currentUserId;
  static bool _isReminderActive = false;

  static Future<void> init() async {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.payload == 'TOGGLE_MEON') {
          debugPrint("User tapped GO OFFLINE");
          if (onToggleOffline != null) {
            onToggleOffline!();
          }
        } else if (response.payload?.startsWith('I_SEE_YOU_') == true) {
          final friendId = response.payload!.substring('I_SEE_YOU_'.length);
          debugPrint("User tapped I SEE YOU for friend: $friendId");
          if (onFriendResponse != null) {
            onFriendResponse!(friendId);
          }
        } else if (response.payload == 'REMIND_GO_OFFLINE') {
          debugPrint("User tapped offline reminder");
          if (onToggleOffline != null) {
            onToggleOffline!();
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse response) {
    if (response.payload == 'TOGGLE_MEON') {
      debugPrint('Background tap: GO OFFLINE');
    } else if (response.payload?.startsWith('I_SEE_YOU_') == true) {
      debugPrint('Background tap: I SEE YOU');
    } else if (response.payload == 'REMIND_GO_OFFLINE') {
      debugPrint('Background tap: OFFLINE REMINDER');
    }
  }

  // Start offline reminder system (remind user to go offline after X minutes online)
  static Future<void> startOfflineReminder(String userId, int minutes) async {
    _currentUserId = userId;
    await _scheduleOfflineReminder(minutes);
  }

  // Stop offline reminder system
  static Future<void> stopOfflineReminder() async {
    _offlineReminderTimer?.cancel();
    _offlineReminderTimer = null;
    _isReminderActive = false;
    await flutterLocalNotificationsPlugin.cancel(offlineReminderNotificationId);
    debugPrint('Offline reminder system stopped');
  }

  // Schedule offline reminder
  static Future<void> _scheduleOfflineReminder(int minutes) async {
    // Cancel existing timer
    _offlineReminderTimer?.cancel();
    
    if (minutes <= 0) {
      _isReminderActive = false;
      return;
    }

    _isReminderActive = true;
    final duration = Duration(minutes: minutes);
    
    debugPrint('Scheduling offline reminder after $minutes minutes');
    
    _offlineReminderTimer = Timer(duration, () async {
      await _showOfflineReminderNotification();
    });
  }

  // Show offline reminder notification
  static Future<void> _showOfflineReminderNotification() async {
    if (!_isReminderActive || _currentUserId == null) return;

    try {
      // Check if user preferences allow notifications
      final prefs = await SharedPreferences.getInstance();
      final soundEnabled = prefs.getBool('notif_sound_$_currentUserId') ?? true;
      final vibrationEnabled = prefs.getBool('notif_vibration_$_currentUserId') ?? true;
      final screenLightEnabled = prefs.getBool('notif_screen_light_$_currentUserId') ?? true;

      final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'offline_reminder_channel',
        'Offline Reminders',
        channelDescription: 'Reminders to go offline after being online for a while',
        importance: Importance.high,
        priority: Priority.high,
        playSound: soundEnabled,
        enableVibration: vibrationEnabled,
        enableLights: screenLightEnabled,
        vibrationPattern: vibrationEnabled 
            ? Int64List.fromList([0, 400, 400, 400]) 
            : Int64List.fromList([]),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'REMIND_GO_OFFLINE',
            'Go MEOFF',
            showsUserInterface: true,
          ),
        ],
      );

      await flutterLocalNotificationsPlugin.show(
        offlineReminderNotificationId,
        'Are you Still MEON?',
        'You\'ve been online for a while. Tap to go offline.',
        NotificationDetails(android: androidDetails),
        payload: 'REMIND_GO_OFFLINE',
      );

      debugPrint('Offline reminder notification sent');
    } catch (e) {
      debugPrint('Failed to show offline reminder notification: $e');
    }
  }

  // Update offline reminder interval
  static Future<void> updateOfflineReminderInterval(int minutes) async {
    if (_currentUserId == null) return;
    
    debugPrint('Updating offline reminder interval to $minutes minutes');
    await _scheduleOfflineReminder(minutes);
  }

  // Check if offline reminder is active
  static bool get isOfflineReminderActive => _isReminderActive;

  // Show persistent notification when user is MEON (online)
  static Future<void> showMeonStatusNotification(bool isOn, {String? userId}) async {
    if (!isOn) {
      await flutterLocalNotificationsPlugin.cancel(statusNotificationId);
      return;
    }

    // Get user notification preferences
    bool soundEnabled = true;
    bool vibrationEnabled = true;
    
    if (userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        soundEnabled = prefs.getBool('notif_sound_$userId') ?? true;
        vibrationEnabled = prefs.getBool('notif_vibration_$userId') ?? true;
      } catch (e) {
        debugPrint('Failed to load notification preferences: $e');
      }
    }

    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'meon_status_channel',
      'Meon Status',
      channelDescription: 'Your current Meon online status',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      vibrationPattern: vibrationEnabled 
          ? Int64List.fromList([0, 300, 300, 300])
          : Int64List.fromList([]),
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'TOGGLE_MEON',
          'Go MEOFF',
          showsUserInterface: true,
        ),
      ],
    );

    await flutterLocalNotificationsPlugin.show(
      statusNotificationId,
      'You are MEON',
      'Your friends can see you\'re online. Tap MEOFF to disconnect.',
      NotificationDetails(android: androidDetails),
      payload: 'TOGGLE_MEON',
    );
  }

  // Show notification when a friend comes online
  static Future<void> showFriendOnlineNotification(
    String friendName, 
    String friendId, 
    {String? userId}
  ) async {
    // Get user notification preferences
    bool soundEnabled = true;
    bool vibrationEnabled = true;
    bool screenLightEnabled = true;
    
    if (userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        soundEnabled = prefs.getBool('notif_sound_$userId') ?? true;
        vibrationEnabled = prefs.getBool('notif_vibration_$userId') ?? true;
        screenLightEnabled = prefs.getBool('notif_screen_light_$userId') ?? true;
      } catch (e) {
        debugPrint('Failed to load notification preferences: $e');
      }
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'friend_online_channel',
      'Friends Online',
      channelDescription: 'Notifications when friends come online',
      importance: Importance.high,
      priority: Priority.high,
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      enableLights: screenLightEnabled,
      vibrationPattern: vibrationEnabled 
          ? Int64List.fromList([0, 500, 300, 500, 300, 500])
          : Int64List.fromList([]),
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'I_SEE_YOU_$friendId',
          '👋 I see you',
          showsUserInterface: false,
        ),
      ],
    );

    await flutterLocalNotificationsPlugin.show(
      friendOnlineNotificationId,
      '🟢 $friendName is online',
      'Your friend $friendName just came online!',
      NotificationDetails(android: androidDetails),
      payload: 'I_SEE_YOU_$friendId',
    );
  }

  // Show notification when friend responds with "I see you"
  static Future<void> showFriendResponseNotification(
    String friendName, 
    {String? userId}
  ) async {
    // Get user notification preferences
    bool soundEnabled = true;
    bool vibrationEnabled = true;
    bool screenLightEnabled = true;
    
    if (userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        soundEnabled = prefs.getBool('notif_sound_$userId') ?? true;
        vibrationEnabled = prefs.getBool('notif_vibration_$userId') ?? true;
        screenLightEnabled = prefs.getBool('notif_screen_light_$userId') ?? true;
      } catch (e) {
        debugPrint('Failed to load notification preferences: $e');
      }
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'friend_response_channel',
      'Friend Responses',
      channelDescription: 'When friends acknowledge seeing you online',
      importance: Importance.high,
      priority: Priority.high,
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      enableLights: screenLightEnabled,
      vibrationPattern: vibrationEnabled 
          ? Int64List.fromList([0, 200, 200, 200, 200, 200])
          : Int64List.fromList([]),
    );

    await flutterLocalNotificationsPlugin.show(
      friendResponseNotificationId,
      '👋 $friendName sees you!',
      '$friendName acknowledged that you\'re online',
      NotificationDetails(android: androidDetails),
    );
  }

  // Keep morse notifications as they were
  static Future<void> showMorseNotification(
    String senderName, 
    String signal, 
    {String? userId}
  ) async {
    // Get user notification preferences
    bool soundEnabled = true;
    bool vibrationEnabled = true;
    bool screenLightEnabled = true;
    
    if (userId != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        soundEnabled = prefs.getBool('notif_sound_$userId') ?? true;
        vibrationEnabled = prefs.getBool('notif_vibration_$userId') ?? true;
        screenLightEnabled = prefs.getBool('notif_screen_light_$userId') ?? true;
      } catch (e) {
        debugPrint('Failed to load notification preferences: $e');
      }
    }

    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'morse_signals_channel',
      'Morse Signals',
      channelDescription: 'Incoming Morse code signals',
      importance: Importance.high,
      priority: Priority.high,
      playSound: soundEnabled,
      enableVibration: vibrationEnabled,
      enableLights: screenLightEnabled,
      vibrationPattern: vibrationEnabled 
          ? Int64List.fromList(const [0, 250, 250, 250, 250, 250])
          : Int64List.fromList([]),
      styleInformation: BigTextStyleInformation(
        'Signal: $signal',
        contentTitle: 'Morse from $senderName',
        summaryText: 'New Morse signal received',
      ),
    );

    await flutterLocalNotificationsPlugin.show(
      morseNotificationId,
      'Morse from $senderName',
      'Signal: $signal',
      NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> cancelAllNotifications() async {
    await flutterLocalNotificationsPlugin.cancelAll();
    await stopOfflineReminder();
  }

  static Future<void> cancelStatusNotification() async {
    await flutterLocalNotificationsPlugin.cancel(statusNotificationId);
  }
}