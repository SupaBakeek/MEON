import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer';

// Background message handler must be a top-level function
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  log('🔔 Background message received: ${message.messageId}');
  // You can handle background notifications here (e.g., update local storage)
}

class FirebasePushService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize FCM: permissions, token handling, listeners.
  Future<void> init(String userId) async {
    try {
      // Request permissions (iOS and Android 13+)
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Get and save FCM token
      final String? token = await _messaging.getToken();
      if (token != null) {
        log('🔥 Firebase Token: $token');
        await _saveTokenToFirestore(userId, token);
      }

      // Listen for token refresh and update Firestore
      _messaging.onTokenRefresh.listen((newToken) async {
        log('🔄 Token refreshed: $newToken');
        await _saveTokenToFirestore(userId, newToken);
      });

      // Foreground messages listener
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        log("📬 Foreground message: ${message.notification?.title}");
        // You can trigger local notifications here if desired
      });

      // When app opened from background via notification tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        log("🟢 Opened from notification: ${message.notification?.title}");
        _handleNotificationTap(message);
      });

      // Set background message handler
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e) {
      log('Error initializing FirebasePushService: $e');
      // Optionally rethrow or notify UI layer
    }
  }

  /// Save FCM token to Firestore with error handling
  Future<void> _saveTokenToFirestore(String userId, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'fcmToken': token,
      });
    } catch (e) {
      log('Failed to save FCM token: $e');
    }
  }

  /// Handle notification tap, navigate or update UI accordingly
  void _handleNotificationTap(RemoteMessage message) {
    final action = message.data['action'];
    log("🔔 Notification action: $action");

    // Example: Navigate or update UI depending on `action`
    // For example:
    // if (action == 'open_friend_requests') {
    //   navigatorKey.currentState?.pushNamed('/friend_requests');
    // }
  }

  /// Clear stored FCM token on logout or cleanup
  Future<void> clearToken(String userId) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'fcmToken': FieldValue.delete(),
      });
    } catch (e) {
      log('Failed to clear FCM token: $e');
    }
  }
}
