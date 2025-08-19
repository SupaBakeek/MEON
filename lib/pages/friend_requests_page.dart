import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';

class FriendRequestsPage extends StatefulWidget {
  final String currentUserId;
  final String currentUserName;

  const FriendRequestsPage({
    super.key,
    required this.currentUserId,
    required this.currentUserName,
  });

  @override
  State<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends State<FriendRequestsPage> {
  final CollectionReference users = FirebaseFirestore.instance.collection(
    'users',
  );
  final Set<String> _loadingRequests = {};
  bool _loadingError = false;

  // Fetch the user's unique MeCode (one per user)
  Future<String> _getMeCode() async {
    final namePart = widget.currentUserName.length >= 3
        ? widget.currentUserName.substring(0, 3)
        : widget.currentUserName; // take full name if <3 chars

    final idPart = widget.currentUserId.length >= 3
        ? widget.currentUserId.substring(0, 3)
        : widget.currentUserId;
    final doc = await users.doc(widget.currentUserId).get();
    final data = doc.data() as Map<String, dynamic>?;
    final code = data?['meCode'] as String?;
    if (code != null && code is String) return code;
    // Generate and save if not exist
    final newCode = (namePart + idPart).toUpperCase();
    await users.doc(widget.currentUserId).set({
      'meCode': newCode,
    }, SetOptions(merge: true));
    return newCode;
  }

  bool _isCopying = false;
  Future<void> _copyMeCode() async {
    if (_isCopying) return;
    _isCopying = true;

    final code = await _getMeCode();
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${widget.currentUserName}, your MeCode "$code" copied to clipboard!',
        ),
        backgroundColor: Colors.teal[600],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
    await Future.delayed(Duration(seconds: 1));
    _isCopying = false;
  }

  Future<void> _acceptRequest(String fromUserId, String fromName) async {
    setState(() => _loadingRequests.add(fromUserId));
    try {
      await users
          .doc(widget.currentUserId)
          .collection('friends')
          .doc(fromUserId)
          .set({'canSeeStatus': true});
      await users
          .doc(fromUserId)
          .collection('friends')
          .doc(widget.currentUserId)
          .set({'canSeeStatus': true});
      await users
          .doc(widget.currentUserId)
          .collection('friendRequests')
          .doc(fromUserId)
          .delete();

      // Add friend request back to the requester (if you want them to know)
      await users
          .doc(fromUserId)
          .collection('friendRequests')
          .doc(widget.currentUserId)
          .set({'name': widget.currentUserName, 'status': 'pending'});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$fromName joined ${widget.currentUserName}\'s MeWorld!',
          ),
          backgroundColor: Colors.teal[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept MeRequest: $e'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loadingRequests.remove(fromUserId));
    }
  }

  Future<void> _rejectRequest(String fromUserId, String fromName) async {
    setState(() => _loadingRequests.add(fromUserId));
    try {
      await users
          .doc(widget.currentUserId)
          .collection('friendRequests')
          .doc(fromUserId)
          .delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('MeRequest from $fromName declined.'),
          backgroundColor: Colors.orange[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to decline MeRequest: $e'),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _loadingRequests.remove(fromUserId));
    }
  }

  Future<void> _onRefresh() async {
    setState(() => _loadingError = false);
    await Future.delayed(const Duration(milliseconds: 300));
  }

  @override
  Widget build(BuildContext context) {
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
          'M E Q U E S T S',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Colors.teal[800],
          ),
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: Colors.teal,
        child: StreamBuilder<QuerySnapshot>(
          stream: users
              .doc(widget.currentUserId)
              .collection('friendRequests')
              .where('status', isEqualTo: 'pending')
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError || _loadingError) {
              return _ErrorWidget(
                onRetry: () => setState(() => _loadingError = false),
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return _LoadingWidget();
            }

            final requests = snapshot.data?.docs ?? [];
            if (requests.isEmpty) {
              return _EmptyWidget(
                userName: widget.currentUserName,
                onShareMeCode: _copyMeCode,
              );
            }

            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeaderWidget(requestsCount: requests.length),
                  const SizedBox(height: 24),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final req = requests[index];
                      final fromId = req.id;
                      final fromName =
                          (req.data() as Map<String, dynamic>?)?['name'] ??
                          'Unknown';
                      final isLoading = _loadingRequests.contains(fromId);

                      return _RequestCard(
                        fromName: fromName,
                        isLoading: isLoading,
                        userName: widget.currentUserName,
                        onAccept: () => _acceptRequest(fromId, fromName),
                        onReject: () => _rejectRequest(fromId, fromName),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// =======================
/// WIDGETS
/// =======================

class _HeaderWidget extends StatelessWidget {
  final int requestsCount;

  const _HeaderWidget({required this.requestsCount});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.teal[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.notifications_active_rounded,
              size: 26,
              color: Colors.teal[700],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$requestsCount Pending MeRequest${requestsCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'People wanting to join your MeWorld',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final String fromName;
  final bool isLoading;
  final String userName;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _RequestCard({
    required this.fromName,
    required this.isLoading,
    required this.userName,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.teal[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                fromName.isNotEmpty ? fromName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: Colors.teal[700],
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fromName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'wants to join $userName\'s MeWorld',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          isLoading
              ? SizedBox(
                  width: 80,
                  height: 32,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey[500],
                    ),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ActionButton(
                      icon: Icons.check_rounded,
                      color: Colors.green,
                      onPressed: onAccept,
                    ),
                    const SizedBox(width: 8),
                    _ActionButton(
                      icon: Icons.close_rounded,
                      color: Colors.red,
                      onPressed: onReject,
                    ),
                  ],
                ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, color: color, size: 18),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _LoadingWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.teal, strokeWidth: 3),
          const SizedBox(height: 24),
          Text(
            'Loading your MeRequests...',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorWidget extends StatelessWidget {
  final VoidCallback onRetry;

  const _ErrorWidget({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: Colors.red[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Oops! MeTrouble Loading',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Failed to load your MeRequests. Please try again.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              child: const Text(
                'MeRetry',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWidget extends StatelessWidget {
  final String userName;
  final VoidCallback onShareMeCode;

  const _EmptyWidget({required this.userName, required this.onShareMeCode});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                Icons.inbox_rounded,
                size: 60,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'No MeRequests',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'When someone wants to join your MeWorld,\ntheir requests will appear here!',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextButton.icon(
              onPressed: onShareMeCode,
              icon: Icon(Icons.share_rounded, color: Colors.teal[700]),
              label: Text(
                'Share your MeCode to connect!',
                style: TextStyle(
                  color: Colors.teal[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
