import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'friend_requests_page.dart';

class FriendsPage extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;
  final Future<void> Function(String friendId, bool currentValue)
  toggleVisibilityCallback;
  final Map<String, bool> cachedVisibility;
  final Function(String, String) setMorseReceiver;

  const FriendsPage({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
    required this.toggleVisibilityCallback,
    required this.cachedVisibility,
    required this.setMorseReceiver,
  });

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  final TextEditingController _controller = TextEditingController();
  final CollectionReference users = FirebaseFirestore.instance.collection(
    'users',
  );

  static const int pageSize = 20;
  List<String> friendIds = [];
  Map<String, Map<String, dynamic>> friendDataMap = {}; // cache friend data

  final bool _isLoading = false;
  bool _isSendingRequest = false;
  String? _lastDocumentId;
  bool _hasMore = true;
  bool _isPaginating = false;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _listenToFriendsRealtime();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  // Real-time listener for friends and their data with pagination support
  StreamSubscription<QuerySnapshot>? _friendsSubscription;

  void _listenToFriendsRealtime() {
    _friendsSubscription?.cancel();

    _friendsSubscription = users
        .doc(widget.currentUserId)
        .collection('friends')
        .orderBy(FieldPath.documentId) // ordering by documentId for pagination
        .limit(pageSize)
        .snapshots()
        .listen((snapshot) async {
          if (!mounted) return;

          final docs = snapshot.docs;
          if (docs.isEmpty) {
            setState(() {
              friendIds = [];
              friendDataMap = {};
              _lastDocumentId = null;
              _hasMore = false;
            });
            return;
          }

          final ids = docs.map((doc) => doc.id).toList();
          final lastDocId = ids.isNotEmpty ? ids.last : null;

          // Fetch user info for these friends
          final friendUsersSnapshot = await users
              .where(FieldPath.documentId, whereIn: ids)
              .get();

          final dataMap = {
            for (var doc in friendUsersSnapshot.docs)
              doc.id: doc.data() as Map<String, dynamic>,
          };

          setState(() {
            friendIds = ids;
            friendDataMap = dataMap;
            _lastDocumentId = lastDocId;
            _hasMore = docs.length == pageSize;
          });
        });
  }

  Future<void> _paginateFriends() async {
    if (!_hasMore || _isPaginating || _lastDocumentId == null) return;

    setState(() => _isPaginating = true);

    try {
      final snapshot = await users
          .doc(widget.currentUserId)
          .collection('friends')
          .orderBy(FieldPath.documentId)
          .startAfter([_lastDocumentId])
          .limit(pageSize)
          .get();

      final docs = snapshot.docs;
      if (docs.isEmpty) {
        setState(() => _hasMore = false);
        return;
      }

      final newIds = docs.map((doc) => doc.id).toList();

      // Fetch new friend user info
      final friendUsersSnapshot = await users
          .where(FieldPath.documentId, whereIn: newIds)
          .get();

      final newDataMap = {
        for (var doc in friendUsersSnapshot.docs)
          doc.id: doc.data() as Map<String, dynamic>,
      };

      setState(() {
        friendIds.addAll(newIds);
        friendDataMap.addAll(newDataMap);
        _lastDocumentId = newIds.last;
        _hasMore = docs.length == pageSize;
      });
    } catch (e) {
      debugPrint("Pagination error: $e");
    } finally {
      setState(() => _isPaginating = false);
    }
  }

  Future<void> sendFriendRequestByCode(String friendCode) async {
    final code = friendCode.trim().toUpperCase();
    if (code.isEmpty) return;
    if (_isSendingRequest) return;

    if (code == widget.cachedVisibility[widget.currentUserId].toString()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("You can't add yourself to MeWorld!"),
          backgroundColor: Colors.orange[600],
        ),
      );
      return;
    }

    setState(() => _isSendingRequest = true);

    try {
      final query = await users
          .where('friendCode', isEqualTo: code)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("MeFriend with this code not found."),
            backgroundColor: Colors.red[600],
          ),
        );
        return;
      }

      final friendDoc = query.docs.first;
      final friendId = friendDoc.id;
      final friendName = friendDoc['name'] ?? 'Unknown';

      if (friendId == widget.currentUserId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("You can't add yourself to MeWorld!"),
            backgroundColor: Colors.orange[600],
          ),
        );
        return;
      }

      final existingFriend = await users
          .doc(widget.currentUserId)
          .collection('friends')
          .doc(friendId)
          .get();
      if (existingFriend.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Already MeFriends!"),
            backgroundColor: Colors.blue[600],
          ),
        );
        return;
      }

      final requestDoc = await users
          .doc(friendId)
          .collection('friendRequests')
          .doc(widget.currentUserId)
          .get();

      if (requestDoc.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("MeFriend request already sent."),
            backgroundColor: Colors.blue[600],
          ),
        );
        return;
      }

      await users
          .doc(friendId)
          .collection('friendRequests')
          .doc(widget.currentUserId)
          .set({
            'from': widget.currentUserId,
            'name': widget.currentUserName,
            'status': 'pending',
            'timestamp': FieldValue.serverTimestamp(),
          });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("MeFriend request sent to $friendName!"),
          backgroundColor: Colors.teal[600],
        ),
      );

      _controller.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to send MeRequest: $e"),
          backgroundColor: Colors.red[600],
        ),
      );
    } finally {
      setState(() => _isSendingRequest = false);
    }
  }

  Future<void> removeFriend(String friendId) async {
    final friendName = friendDataMap[friendId]?['name'] ?? 'this friend';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.person_remove_rounded,
                color: Colors.red[600],
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Remove MeFriend?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to remove $friendName from your MeWorld?',
          style: TextStyle(color: Colors.grey[700], fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('MeCancel', style: TextStyle(color: Colors.grey[600])),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[600],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
            child: const Text('MeRemove'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await users
          .doc(widget.currentUserId)
          .collection('friends')
          .doc(friendId)
          .delete();
      await users
          .doc(friendId)
          .collection('friends')
          .doc(widget.currentUserId)
          .delete();

      setState(() {
        friendIds.remove(friendId);
        friendDataMap.remove(friendId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('MeFriend removed from MeWorld.'),
          backgroundColor: Colors.teal[600],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to remove MeFriend: $e'),
          backgroundColor: Colors.red[600],
        ),
      );
    }
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollEndNotification &&
        notification.metrics.extentAfter < 300) {
      // Load more if near the bottom
      _paginateFriends();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cachedVisibility = widget.cachedVisibility;

    return Scaffold(
      backgroundColor: Colors.teal[50],
      appBar: AppBar(
        backgroundColor: Colors.teal[50],
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: Colors.grey[700]),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'M E I E N D S',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.teal[800],
          ),
        ),
        centerTitle: true,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.teal[100],
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.person_add_rounded,
                  color: Colors.teal[700],
                  size: 20,
                ),
              ),
              tooltip: 'MeRequests',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        FriendRequestsPage(currentUserId: widget.currentUserId, currentUserName: '',),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
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
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.teal[100],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.people_rounded,
                      size: 30,
                      color: Colors.teal[700],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your MeWorld',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'People who can see your Meon status',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Friends list
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: friendIds.isEmpty
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.emoji_people_outlined,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No MeFriends yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Add friends using their MeCode below!',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        _onScrollNotification(notification);
                        return false;
                      },
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: friendIds.length + (_hasMore ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          if (index == friendIds.length) {
                            // Loading indicator at the bottom for pagination
                            if (_isPaginating) {
                              return Container(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.teal,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            } else {
                              return const SizedBox.shrink();
                            }
                          }

                          final friendId = friendIds[index];
                          final friendUserData = friendDataMap[friendId];
                          final friendName =
                              friendUserData?['name'] ?? 'Unknown';
                          final canSeeStatusCached =
                              cachedVisibility[friendId] ?? false;

                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: Colors.teal[50],
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    Icons.person_rounded,
                                    color: Colors.teal[600],
                                    size: 22,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        friendName,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        canSeeStatusCached
                                            ? 'Can see your Meon'
                                            : 'Hidden from Meon',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: canSeeStatusCached
                                              ? Colors.teal[600]
                                              : Colors.grey[500],
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(
                                    Icons.radio_button_checked,
                                    color: Colors.teal[400],
                                    size: 20,
                                  ),
                                  onPressed: () => widget.setMorseReceiver(
                                    friendId,
                                    friendName,
                                  ),
                                  tooltip: 'Select for Morse',
                                ),
                                Switch(
                                  value: canSeeStatusCached,
                                  onChanged: (val) {
                                    widget.toggleVisibilityCallback(
                                      friendId,
                                      canSeeStatusCached,
                                    );
                                  },
                                  activeColor: Colors.teal,
                                  inactiveThumbColor: Colors.grey[300],
                                  inactiveTrackColor: Colors.grey[200],
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: Icon(
                                    Icons.person_remove_outlined,
                                    color: Colors.red[400],
                                    size: 20,
                                  ),
                                  onPressed: () => removeFriend(friendId),
                                  tooltip: 'Remove MeFriend',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
            ),

            const SizedBox(height: 32),

            // Add friend section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.teal[100],
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.teal[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.qr_code_rounded,
                          color: Colors.teal[700],
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Add a MeFriend',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enter their MeCode to send a friend request',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            labelText: 'MeCode',
                            hintText: 'ABC123',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontStyle: FontStyle.italic,
                            ),
                            prefixIcon: Icon(
                              Icons.tag_rounded,
                              color: Colors.teal[600],
                            ),
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
                              borderSide: BorderSide(
                                color: Colors.teal,
                                width: 2,
                              ),
                            ),
                            floatingLabelStyle: TextStyle(
                              color: Colors.teal,
                              fontWeight: FontWeight.w500,
                            ),
                            filled: true,
                            fillColor: Colors.grey[50],
                          ),
                          enabled: !_isSendingRequest,
                          textCapitalization: TextCapitalization.characters,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isSendingRequest
                              ? null
                              : () => sendFriendRequestByCode(_controller.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: _isSendingRequest
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'MeSend',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
