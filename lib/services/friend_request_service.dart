import 'package:cloud_firestore/cloud_firestore.dart';

class FriendRequestService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Store last request timestamp per target user to limit frequency (simple in-memory cache)
  final Map<String, DateTime> _lastRequestTime = {};

  static const Duration requestCooldown = Duration(seconds: 10);

  /// Sends a friend request from [fromUserId] to [toUserId] with [fromUserName].
  /// Returns true if sent, false if rate-limited or failed.
  Future<bool> sendFriendRequest(String fromUserId, String toUserId, String fromUserName) async {
    try {
      // Rate limiting: prevent sending multiple requests to same user within cooldown
      final now = DateTime.now();
      final lastTime = _lastRequestTime[toUserId];
      if (lastTime != null && now.difference(lastTime) < requestCooldown) {
        // Too soon to send another request
        return false;
      }

      final docRef = _firestore
          .collection('users')
          .doc(toUserId)
          .collection('friendRequests')
          .doc(fromUserId);

      final existing = await docRef.get();
      if (existing.exists) return false; // Already requested

      await docRef.set({
        'from': fromUserId,
        'name': fromUserName,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      _lastRequestTime[toUserId] = now; // Update cooldown timestamp
      return true;
    } catch (e) {
      // Log or rethrow if needed
      return false;
    }
  }

  /// Accepts friend request from [fromUserId] for [currentUserId].
  /// Returns true on success, false on failure.
  Future<bool> acceptFriendRequest(String currentUserId, String fromUserId) async {
    try {
      final userRef = _firestore.collection('users');

      await userRef.doc(currentUserId).collection('friends').doc(fromUserId).set({
        'canSeeStatus': true,
      });

      await userRef.doc(fromUserId).collection('friends').doc(currentUserId).set({
        'canSeeStatus': true,
      });

      await userRef
          .doc(currentUserId)
          .collection('friendRequests')
          .doc(fromUserId)
          .delete();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Rejects friend request from [fromUserId] for [currentUserId].
  /// Returns true on success, false on failure.
  Future<bool> rejectFriendRequest(String currentUserId, String fromUserId) async {
    try {
      await _firestore
          .collection('users')
          .doc(currentUserId)
          .collection('friendRequests')
          .doc(fromUserId)
          .delete();
      return true;
    } catch (e) {
      return false;
    }
  }
}
