import 'dart:typed_data';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class NotificationService {
  static Function? onToggle;
  static const int statusNotificationId = 0;
  static const int morseNotificationId = 1;

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
          debugPrint("User tapped TOGGLE_MEON");
          if (onToggle != null) {
            onToggle!();
          }
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
  }

  @pragma('vm:entry-point')
  static void notificationTapBackground(NotificationResponse response) {
    if (response.payload == 'TOGGLE_MEON') {
      debugPrint('Background tap received TOGGLE_MEON');
    }
  }

  static Future<void> showSelfToggleNotification(bool isOn) async {
    if (!isOn) {
      await flutterLocalNotificationsPlugin.cancel(statusNotificationId);
      return;
    }

     AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'meon_status_channel',
      'Meon Status',
      channelDescription: 'Toggle your Meon status',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 500, 1000, 500]),
      ongoing: true,
      autoCancel: false,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(
          'TOGGLE_MEON',
          'Toggle Meon',
          showsUserInterface: true,
        ),
      ],
    );

    await flutterLocalNotificationsPlugin.show(
      statusNotificationId,
      'Meon is currently ON',
      'Tap "Toggle Meon" to change your status',
      NotificationDetails(android: androidDetails),
      payload: 'TOGGLE_MEON',
    );
  }

  static Future<void> showMorseNotification(String senderName, String signal) async {
    final AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'morse_signals_channel',
      'Morse Signals',
      channelDescription: 'Incoming Morse code signals',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(const [0, 250, 250, 250, 250, 250]),
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
  }
}