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
  int _remindOnlineMinutes = 5;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;
  bool _screenLightEnabled = true;

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
      final remindMinutes = prefs.getInt('remind_online_minutes_${widget.userId}');

      final doc = await _firestore.collection('users').doc(widget.userId).get();
      final data = doc.data();

      setState(() {
        _soundEnabled = data?['notifSound'] ?? sound ?? true;
        _vibrationEnabled = data?['notifVibration'] ?? vibration ?? true;
        _screenLightEnabled = data?['notifScreenLight'] ?? screenLight ?? true;
        _remindOnlineMinutes = data?['remindOnlineMinutes'] ?? remindMinutes ?? 5;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Failed to load settings: $e');
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load settings')),
      );
    }
  }

  Future<void> _saveRemindOnlineMinutes(int minutes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('remind_online_minutes_${widget.userId}', minutes);

      await _firestore.collection('users').doc(widget.userId).set(
        {'remindOnlineMinutes': minutes},
        SetOptions(merge: true),
      );
    } catch (e) {
      debugPrint('Failed to save remind time: $e');
    }
  }

  Future<void> _saveSetting(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$key${widget.userId}', value);

      String firestoreKey = '';
      if (key == 'notif_sound') {
        firestoreKey = 'notifSound';
      } else if (key == 'notif_vibration') firestoreKey = 'notifVibration';
      else if (key == 'notif_screen_light') firestoreKey = 'notifScreenLight';

      if (firestoreKey.isNotEmpty) {
        await _firestore.collection('users').doc(widget.userId).set(
          {firestoreKey: value},
          SetOptions(merge: true),
        );
      }
    } catch (e) {
      debugPrint('Failed to save $key: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save setting')),
      );
    }
  }

  Widget _buildSettingCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
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
              color: Colors.teal[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: Colors.teal[600],
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
            activeColor: Colors.teal,
            inactiveThumbColor: Colors.grey[300],
            inactiveTrackColor: Colors.grey[200],
            trackOutlineColor: WidgetStateProperty.all(Colors.white.withOpacity(0.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildRemindOnlineCard() {
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
              color: Colors.teal[50],
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.access_time_rounded,
              color: Colors.teal[600],
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Remind I'm Online",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Set how often to remind that you’re online',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          DropdownButton<int>(
            value: _remindOnlineMinutes,
            onChanged: (val) {
              if (val != null) {
                setState(() => _remindOnlineMinutes = val);
                _saveRemindOnlineMinutes(val);
              }
            },
            items: [1, 5, 10, 15, 30, 60].map((minutes) {
              return DropdownMenuItem(
                value: minutes,
                child: Text('$minutes min'),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal[50],
      appBar: AppBar(
        backgroundColor: Colors.teal[50],
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
            color: Colors.teal[800],
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.teal),
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
                            color: Colors.teal[100],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.tune_rounded,
                            size: 30,
                            color: Colors.teal[700],
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

                  // NEW "Remind I'm Online" setting
                  _buildRemindOnlineCard(),

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
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.teal[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.teal[100]!),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Colors.teal[600],
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'About MeNotifications',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.teal[800],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'These settings control how you receive notifications from your friends in MeWorld. You can customize sound, vibration, and screen lighting to match your preferences.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.teal[700],
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
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
