import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SettingsPage extends StatefulWidget {
  final String userId;

  const SettingsPage({
    super.key,
    required this.userId,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _loading = true;
  int _offlineReminderMinutes = 5;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _screenLightEnabled = true;
  bool _offlineReminderEnabled = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final sound = prefs.getBool('notif_sound_${widget.userId}');
      final vibration = prefs.getBool('notif_vibration_${widget.userId}');
      final screenLight = prefs.getBool('notif_screen_light_${widget.userId}');
      final offlineReminderMinutes = prefs.getInt('offline_reminder_minutes_${widget.userId}');
      final offlineReminderOn = prefs.getBool('offline_reminder_enabled_${widget.userId}');

      final doc = await _firestore.collection('users').doc(widget.userId).get();
      final data = doc.data();

      if (mounted) {
        setState(() {
          _soundEnabled = data?['notifSound'] ?? sound ?? true;
          _vibrationEnabled = data?['notifVibration'] ?? vibration ?? true;
          _screenLightEnabled = data?['notifScreenLight'] ?? screenLight ?? true;
          _offlineReminderMinutes = data?['offlineReminderMinutes'] ?? offlineReminderMinutes ?? 5;
          _offlineReminderEnabled = data?['offlineReminderEnabled'] ?? offlineReminderOn ?? true;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
      if (mounted) {
        setState(() {
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load settings')),
        );
      }
    }
  }

  Future<void> _saveOfflineReminderMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('offline_reminder_minutes_${widget.userId}', minutes);

      await _firestore.collection('users').doc(widget.userId).set(
        {'offlineReminderMinutes': minutes},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Failed to save offline reminder time: $e');
    }
  }

  Future<void> _toggleOfflineReminder(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('offline_reminder_enabled_${widget.userId}', enabled);

      await _firestore.collection('users').doc(widget.userId).set(
        {'offlineReminderEnabled': enabled},
        SetOptions(merge: true),
      );

      if (mounted) {
        setState(() {
          _offlineReminderEnabled = enabled;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? 'Offline reminders enabled' : 'Offline reminders disabled'),
            backgroundColor: enabled ? Colors.orange : Colors.grey[600],
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to toggle offline reminder: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('${key}_${widget.userId}', value);

      final firestoreKey = _getFirestoreKey(key);
      if (firestoreKey.isNotEmpty) {
        await _firestore.collection('users').doc(widget.userId).set(
          {firestoreKey: value},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('Failed to save $key: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save setting')),
        );
      }
    }
  }

  String _getFirestoreKey(String key) {
    switch (key) {
      case 'notif_sound':
        return 'notifSound';
      case 'notif_vibration':
        return 'notifVibration';
      case 'notif_screen_light':
        return 'notifScreenLight';
      default:
        return '';
    }
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Color? iconColor,
  }) {
    final color = iconColor ?? Colors.teal[600]!;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: color,
            inactiveThumbColor: Colors.grey[300],
            inactiveTrackColor: Colors.grey[200],
            trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineReminderCard() {
    final isEnabled = _offlineReminderEnabled;
    final iconColor = isEnabled ? Colors.orange[600]! : Colors.grey[400]!;
    final containerColor = isEnabled ? Colors.orange[50]! : Colors.grey[100]!;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Column(
        children: [
          // Toggle switch row
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: containerColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Remind Me to Go Offline",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isEnabled 
                          ? 'Get reminded to go offline after $_offlineReminderMinutes min online'
                          : 'Offline reminders are disabled',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: _toggleOfflineReminder,
                activeColor: Colors.orange,
                inactiveThumbColor: Colors.grey[300],
                inactiveTrackColor: Colors.grey[200],
                trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
              ),
            ],
          ),
          
          // Interval selector (only show when enabled)
          if (isEnabled) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[100]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_rounded,
                    color: Colors.orange[600],
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remind me after:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.orange[700],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.orange[200]!),
                    ),
                    child: DropdownButton<int>(
                      value: _offlineReminderMinutes,
                      underline: const SizedBox(),
                      isDense: true,
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _offlineReminderMinutes = val);
                          _saveOfflineReminderMinutes(val);
                        }
                      },
                      items: [1, 5, 10, 15, 30, 60].map((minutes) {
                        return DropdownMenuItem(
                          value: minutes,
                          child: Text(
                            '$minutes min',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.orange[700],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required String content,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: color.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
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
          icon: Icon(
            Icons.arrow_back_rounded,
            color: Colors.grey[700],
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'M E T T I N G S',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: tealColor[800],
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: tealColor),
                  const SizedBox(height: 16),
                  Text(
                    'Loading your MeSettings...',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                            color: tealColor[100],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 30,
                            color: tealColor[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Notification MePrefs',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[800],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Customize how MeWorld keeps you connected',
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

                  _buildSettingCard(
                    icon: Icons.volume_up_rounded,
                    title: 'MeSound',
                    subtitle: 'Play notification sounds',
                    value: _soundEnabled,
                    onChanged: (val) {
                      setState(() => _soundEnabled = val);
                      _saveSetting('notif_sound', val);
                    },
                  ),
                  _buildSettingCard(
                    icon: Icons.vibration_rounded,
                    title: 'MeVibe',
                    subtitle: 'Feel notification vibrations',
                    value: _vibrationEnabled,
                    onChanged: (val) {
                      setState(() => _vibrationEnabled = val);
                      _saveSetting('notif_vibration', val);
                    },
                  ),
                  _buildSettingCard(
                    icon: Icons.lightbulb_rounded,
                    title: 'MeLight',
                    subtitle: 'Light up screen on notifications',
                    value: _screenLightEnabled,
                    onChanged: (val) {
                      setState(() => _screenLightEnabled = val);
                      _saveSetting('notif_screen_light', val);
                    },
                  ),
                  
                  const SizedBox(height: 24),

                  // Offline reminder setting
                  _buildOfflineReminderCard(),

                  const SizedBox(height: 24),

                  // Social notifications info
                  _buildInfoCard(
                    icon: Icons.people_rounded,
                    title: 'Social Features',
                    content: '• Get notified when friends come online\n• Let friends know you see them with "I see you" button\n• Quick offline toggle without opening the app',
                    color: Colors.green,
                  ),

                  const SizedBox(height: 16),

                  // Classic notifications info
                  _buildInfoCard(
                    icon: Icons.info_outline_rounded,
                    title: 'About MeNotifications',
                    content: 'These settings control sound, vibration, and screen lighting for all your MeWorld notifications including Morse signals and friend interactions.',
                    color: tealColor,
                  ),
                ],
              ),
            ),
    );
  }
}