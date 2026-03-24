import 'dart:async';
import 'dart:io' show Platform, Process;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'reminder.dart';
import 'add_reminder_screen.dart';

// Global plugin instance
FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tz.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Asia/Kolkata'));

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const LinuxInitializationSettings linuxSettings = LinuxInitializationSettings(
    defaultActionName: 'Open notification',
  );
  const InitializationSettings initSettings = InitializationSettings(
    android: androidSettings,
    linux: linuxSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(settings: initSettings);

  await Hive.initFlutter('/home/bhargavi/reminder_data');
  if (!Hive.isAdapterRegistered(ReminderAdapter().typeId)) {
    Hive.registerAdapter(ReminderAdapter());
  }

  final remindersBox = await Hive.openBox<Reminder>('reminders');
  final skippedBox = await Hive.openBox<Reminder>('skipped_reminders');
  final completedBox = await Hive.openBox<Reminder>('completed_history');

  runApp(
    MyApp(
      remindersBox: remindersBox,
      skippedBox: skippedBox,
      completedBox: completedBox,
    ),
  );
}

class MyApp extends StatelessWidget {
  final Box<Reminder> remindersBox;
  final Box<Reminder> skippedBox;
  final Box<Reminder> completedBox;

  const MyApp({
    super.key,
    required this.remindersBox,
    required this.skippedBox,
    required this.completedBox,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IMLRE - PERF',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F7FB),
      ),
      home: HomeScreen(
        remindersBox: remindersBox,
        skippedBox: skippedBox,
        completedBox: completedBox,
      ),
    );
  }
}

enum ViewMode { active, skipped, completed }

class HomeScreen extends StatefulWidget {
  final Box<Reminder> remindersBox;
  final Box<Reminder> skippedBox;
  final Box<Reminder> completedBox;

  const HomeScreen({
    super.key,
    required this.remindersBox,
    required this.skippedBox,
    required this.completedBox,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, Timer> _linuxTimers = {};
  final Map<int, Timer> _linuxSnoozeTimers = {};

  bool _noReminderMode = false;
  bool _quietMode = false;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchText = '';

  String _priorityFilter = 'All';
  String _categoryFilter = 'All';

  ViewMode _viewMode = ViewMode.active;

  DateTime _summaryMonth = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    1,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _rescheduleAllActiveRemindersOnStartup();
    });
  }

  @override
  void dispose() {
    for (final t in _linuxTimers.values) {
      t.cancel();
    }
    for (final t in _linuxSnoozeTimers.values) {
      t.cancel();
    }
    _linuxTimers.clear();
    _linuxSnoozeTimers.clear();
    _searchController.dispose();
    super.dispose();
  }

  bool _isHighOrCritical(Reminder r) {
    final p = r.priority.toLowerCase();
    return p == 'high' || p == 'critical';
  }

  bool _canNotify(Reminder r) {
    if (_noReminderMode) return false;
    if (_quietMode && !_isHighOrCritical(r)) return false;
    return true;
  }

  int _snoozeMinutes(Reminder r) {
    final p = r.priority.toLowerCase();
    if (p == 'critical') return 5;
    if (p == 'high') return 10;
    if (p == 'medium') return 20;
    return 30;
  }

  int _snoozeNotifId(Reminder r) {
    final base = int.parse(r.id) % 1000000;
    return base + 8000000;
  }

  Future<void> _snoozeReminder(Reminder reminder) async {
    if (!_canNotify(reminder)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Blocked by No Reminder / Quiet Mode')),
      );
      return;
    }

    final mins = _snoozeMinutes(reminder);
    final snoozeTime = DateTime.now().add(Duration(minutes: mins));
    final snoozeId = _snoozeNotifId(reminder);

    _linuxSnoozeTimers[snoozeId]?.cancel();
    await flutterLocalNotificationsPlugin.cancel(id: snoozeId);

    if (Platform.isLinux) {
      final delay = snoozeTime.difference(DateTime.now());

      _linuxSnoozeTimers[snoozeId] = Timer(delay, () async {
        Process.run('paplay', [
          '/usr/share/sounds/freedesktop/stereo/complete.oga',
        ]);

        await flutterLocalNotificationsPlugin.show(
          id: snoozeId,
          title: reminder.title,
          body: 'Snoozed reminder!',
          notificationDetails: const NotificationDetails(
            linux: LinuxNotificationDetails(),
            android: AndroidNotificationDetails(
              'reminder_channel',
              'Reminders',
              channelDescription: 'Notifications for reminders',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      });
    } else {
      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: snoozeId,
        title: reminder.title,
        body: 'Snoozed reminder!',
        scheduledDate: tz.TZDateTime.from(snoozeTime, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminder_channel',
            'Reminders',
            channelDescription: 'Notifications for reminders',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Snoozed for $mins minutes'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color getColor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.yellow;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  double calculateRiskScore(Reminder r) {
    double risk = 0.2;

    if (r.dueDate != null && r.dueDate!.isBefore(DateTime.now())) {
      risk += 0.3;
    }

    risk += r.skips * 0.1;
    if (risk > 0.6) risk = 0.6;

    switch (r.priority.toLowerCase()) {
      case 'high':
        risk += 0.1;
        break;
      case 'critical':
        risk += 0.2;
        break;
    }

    return risk.clamp(0.0, 1.0);
  }

  Color getRiskColor(double score) {
    if (score < 0.3) return Colors.green;
    if (score < 0.6) return Colors.yellow;
    if (score < 0.8) return Colors.orange;
    return Colors.red;
  }

  Future<void> _showTestNotificationNow() async {
    final fake = Reminder(
      id: '999999',
      title: 'Test Notification',
      category: 'Test',
      priority: 'critical',
      dueDate: DateTime.now().add(const Duration(seconds: 1)),
      repeat: 'none',
      skips: 0,
    );

    if (!_canNotify(fake)) return;

    await flutterLocalNotificationsPlugin.show(
      id: 999999,
      title: 'Test Notification',
      body: _quietMode
          ? 'Quiet Mode ON → only High/Critical will notify ✅'
          : 'Flutter notification is working ✅',
      notificationDetails: const NotificationDetails(
        linux: LinuxNotificationDetails(),
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Reminders',
          channelDescription: 'Notifications for reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> _rescheduleAllActiveRemindersOnStartup() async {
    final now = DateTime.now();
    final all = widget.remindersBox.values.toList();

    for (final r in all) {
      if (r.dueDate == null) continue;

      await _cancelNotification(r.id);

      if (r.dueDate!.isBefore(now)) continue;
      if (!_canNotify(r)) continue;

      await _scheduleNotification(r);
    }
  }

  Future<void> _scheduleNotification(Reminder reminder) async {
    if (!_canNotify(reminder)) {
      await _cancelNotification(reminder.id);
      return;
    }

    if (reminder.dueDate == null) return;
    final now = DateTime.now();
    if (reminder.dueDate!.isBefore(now)) return;

    final int id = int.parse(reminder.id) % 1000000;

    if (Platform.isLinux) {
      final delay = reminder.dueDate!.difference(now);

      _linuxTimers[reminder.id]?.cancel();
      _linuxTimers[reminder.id] = Timer(delay, () async {
        if (!_canNotify(reminder)) return;

        Process.run('paplay', [
          '/usr/share/sounds/freedesktop/stereo/complete.oga',
        ]);

        await flutterLocalNotificationsPlugin.show(
          id: id,
          title: reminder.title,
          body: 'Reminder time!',
          notificationDetails: const NotificationDetails(
            linux: LinuxNotificationDetails(),
            android: AndroidNotificationDetails(
              'reminder_channel',
              'Reminders',
              channelDescription: 'Notifications for reminders',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
        );
      });

      return;
    }

    await flutterLocalNotificationsPlugin.zonedSchedule(
      id: id,
      title: reminder.title,
      body: 'Reminder time!',
      scheduledDate: tz.TZDateTime.from(reminder.dueDate!, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'reminder_channel',
          'Reminders',
          channelDescription: 'Notifications for reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> _cancelNotification(String reminderId) async {
    final int notificationId = int.parse(reminderId) % 1000000;

    _linuxTimers[reminderId]?.cancel();
    _linuxTimers.remove(reminderId);

    await flutterLocalNotificationsPlugin.cancel(id: notificationId);
  }

  Future<void> _toggleNoReminderMode() async {
    setState(() => _noReminderMode = !_noReminderMode);

    if (_noReminderMode) {
      for (final t in _linuxTimers.values) {
        t.cancel();
      }
      for (final t in _linuxSnoozeTimers.values) {
        t.cancel();
      }
      _linuxTimers.clear();
      _linuxSnoozeTimers.clear();
      await flutterLocalNotificationsPlugin.cancelAll();
    } else {
      await _rescheduleAllActiveRemindersOnStartup();
    }
  }

  Future<void> _toggleQuietMode() async {
    setState(() => _quietMode = !_quietMode);
    await _rescheduleAllActiveRemindersOnStartup();
  }

  void _saveToSkipped(Reminder reminder) {
    final key = '${reminder.id}_${DateTime.now().millisecondsSinceEpoch}';
    widget.skippedBox.put(key, reminder);
  }

  void _saveToCompleted(Reminder reminder) {
    final key = '${reminder.id}_${DateTime.now().millisecondsSinceEpoch}';
    widget.completedBox.put(key, reminder);
  }

  void _skipReminder(Reminder reminder) {
    reminder.skips += 1;

    String originalPriority = reminder.priority;
    String newPriority = reminder.priority;

    if (reminder.skips >= 6) {
      newPriority = 'critical';
    } else if (reminder.skips >= 3) {
      switch (originalPriority.toLowerCase()) {
        case 'low':
          newPriority = 'medium';
          break;
        case 'medium':
          newPriority = 'high';
          break;
        case 'high':
          newPriority = 'critical';
          break;
      }
    }

    reminder.priority = newPriority;
    widget.remindersBox.put(reminder.id, reminder);

    _cancelNotification(reminder.id);
    _scheduleNotification(reminder);

    _saveToSkipped(reminder);
  }

  void _deleteReminder(Reminder reminder) {
    widget.remindersBox.delete(reminder.id);
    _cancelNotification(reminder.id);
  }

  void _markAsDone(Reminder reminder) {
    _saveToCompleted(reminder);

    if (reminder.repeat.toLowerCase() == 'none') {
      widget.remindersBox.delete(reminder.id);
      _cancelNotification(reminder.id);
      return;
    }

    DateTime? nextDate;
    if (reminder.dueDate != null) {
      switch (reminder.repeat.toLowerCase()) {
        case 'daily':
          nextDate = reminder.dueDate!.add(const Duration(days: 1));
          break;
        case 'weekly':
          nextDate = reminder.dueDate!.add(const Duration(days: 7));
          break;
        case 'monthly':
          nextDate = DateTime(
            reminder.dueDate!.year,
            reminder.dueDate!.month + 1,
            reminder.dueDate!.day,
            reminder.dueDate!.hour,
            reminder.dueDate!.minute,
          );
          break;
        case 'yearly':
          nextDate = DateTime(
            reminder.dueDate!.year + 1,
            reminder.dueDate!.month,
            reminder.dueDate!.day,
            reminder.dueDate!.hour,
            reminder.dueDate!.minute,
          );
          break;
      }
    }

    if (nextDate != null) {
      reminder.dueDate = nextDate;
      reminder.skips = 0;
      widget.remindersBox.put(reminder.id, reminder);
      _cancelNotification(reminder.id);
      _scheduleNotification(reminder);
    }
  }

  Future<void> _confirmDelete(Reminder reminder) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Reminder'),
        content: Text(
          'Are you sure you want to delete "${reminder.title}"?\nThis cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _deleteReminder(reminder);
    }
  }

  void _openFilterSheet(List<String> categories) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        String tempPriority = _priorityFilter;
        String tempCategory = _categoryFilter;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Filter Reminders',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Expanded(child: Text('Priority')),
                      DropdownButton<String>(
                        value: tempPriority,
                        items:
                            const ['All', 'Low', 'Medium', 'High', 'Critical']
                                .map(
                                  (p) => DropdownMenuItem(
                                    value: p,
                                    child: Text(p),
                                  ),
                                )
                                .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setSheetState(() => tempPriority = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Expanded(child: Text('Category')),
                      DropdownButton<String>(
                        value: tempCategory,
                        items: ['All', ...categories]
                            .toSet()
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setSheetState(() => tempCategory = v);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _priorityFilter = 'All';
                              _categoryFilter = 'All';
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _priorityFilter = tempPriority;
                              _categoryFilter = tempCategory;
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --------- polished preface UI helpers ----------
  Widget _buildHeroSection({
    required int total,
    required int highCritical,
    required int overdue,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Intelligent Reminder Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Adaptive reminders with risk tracking and smart escalation',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _buildTopStatCard(
                  icon: Icons.list_alt_rounded,
                  label: 'Total',
                  value: '$total',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTopStatCard(
                  icon: Icons.priority_high_rounded,
                  label: 'High/Critical',
                  value: '$highCritical',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildTopStatCard(
                  icon: Icons.warning_amber_rounded,
                  label: 'Overdue',
                  value: '$overdue',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        children: [
          const Icon(Icons.dashboard_customize_rounded, color: Colors.indigo),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // --------- monthly summary ----------
  String _monthLabel(DateTime m) {
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${names[m.month - 1]} ${m.year}';
  }

  Widget _kpiCard({
    required IconData icon,
    required String title,
    required String value,
    Color? valueColor,
  }) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: valueColor ?? Colors.black87,
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

  void _openMonthlySummary(
    List<Reminder> activeReminders,
    List<Reminder> skippedHistory,
    List<Reminder> completedHistory,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        final start = DateTime(_summaryMonth.year, _summaryMonth.month, 1);
        final end = DateTime(_summaryMonth.year, _summaryMonth.month + 1, 1);

        bool inMonth(DateTime? d) {
          if (d == null) return false;
          return (d.isAtSameMomentAs(start) || d.isAfter(start)) &&
              d.isBefore(end);
        }

        final monthActive = activeReminders
            .where((r) => inMonth(r.dueDate))
            .toList();
        final monthSkipped = skippedHistory
            .where((r) => inMonth(r.dueDate))
            .toList();
        final monthCompleted = completedHistory
            .where((r) => inMonth(r.dueDate))
            .toList();

        final completedCount = monthCompleted.length;
        final skippedCount = monthSkipped.length;

        final denom = completedCount + skippedCount;
        final completionRate = denom == 0 ? 0.0 : (completedCount / denom);

        final now = DateTime.now();
        final overdue = monthActive
            .where((r) => (r.dueDate != null && r.dueDate!.isBefore(now)))
            .length;
        final upcoming = monthActive.length - overdue;

        double avgRisk = 0;
        for (final r in monthActive) {
          avgRisk += calculateRiskScore(r);
        }
        if (monthActive.isNotEmpty) avgRisk /= monthActive.length;

        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Monthly Summary • ${_monthLabel(_summaryMonth)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.event_note,
                      title: 'Scheduled',
                      value: '${monthActive.length}',
                    ),
                  ),
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.schedule,
                      title: 'Upcoming',
                      value: '$upcoming',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.warning,
                      title: 'Overdue',
                      value: '$overdue',
                      valueColor: overdue > 0 ? Colors.red : Colors.black87,
                    ),
                  ),
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.shield,
                      title: 'Avg Risk',
                      value: avgRisk.toStringAsFixed(2),
                      valueColor: getRiskColor(avgRisk),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.check_circle,
                      title: 'Completed',
                      value: '$completedCount',
                      valueColor: completedCount > 0
                          ? Colors.green
                          : Colors.black87,
                    ),
                  ),
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.skip_next,
                      title: 'Skipped',
                      value: '$skippedCount',
                      valueColor: skippedCount > 0
                          ? Colors.orange
                          : Colors.black87,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _kpiCard(
                      icon: Icons.percent,
                      title: 'Completion rate',
                      value: '${(completionRate * 100).toStringAsFixed(0)}%',
                      valueColor: completionRate >= 0.7
                          ? Colors.green
                          : completionRate >= 0.4
                          ? Colors.orange
                          : Colors.red,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _quietMode
                    ? 'Quiet Mode ON: Only High/Critical reminders can notify.'
                    : 'Quiet Mode OFF: All priorities can notify.',
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<Reminder>>(
      valueListenable: widget.remindersBox.listenable(),
      builder: (context, activeBox, _) {
        return ValueListenableBuilder<Box<Reminder>>(
          valueListenable: widget.skippedBox.listenable(),
          builder: (context, skippedBox, __) {
            return ValueListenableBuilder<Box<Reminder>>(
              valueListenable: widget.completedBox.listenable(),
              builder: (context, completedBox, ___) {
                List<Reminder> baseList;
                String title;

                if (_viewMode == ViewMode.active) {
                  baseList = activeBox.values.toList();
                  title = 'Intelligent Reminder Engine';
                } else if (_viewMode == ViewMode.skipped) {
                  baseList = skippedBox.values.toList();
                  title = 'Skipped History';
                } else {
                  baseList = completedBox.values.toList();
                  title = 'Completed History';
                }

                final categories =
                    baseList
                        .map((r) => r.category.trim())
                        .where((c) => c.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();

                final filtered = baseList.where((r) {
                  final titleText = r.title.toLowerCase();
                  final cat = r.category.toLowerCase();
                  final pri = r.priority.toLowerCase();

                  final matchesSearch =
                      _searchText.isEmpty ||
                      titleText.contains(_searchText) ||
                      cat.contains(_searchText);

                  final matchesPriority =
                      _priorityFilter == 'All' ||
                      pri == _priorityFilter.toLowerCase();

                  final matchesCategory =
                      _categoryFilter == 'All' ||
                      r.category.trim() == _categoryFilter;

                  return matchesSearch && matchesPriority && matchesCategory;
                }).toList();

                final activeList = activeBox.values.toList();
                final highCriticalCount = activeList
                    .where(
                      (r) =>
                          r.priority.toLowerCase() == 'high' ||
                          r.priority.toLowerCase() == 'critical',
                    )
                    .length;
                final overdueCount = activeList
                    .where(
                      (r) =>
                          r.dueDate != null &&
                          r.dueDate!.isBefore(DateTime.now()),
                    )
                    .length;

                return Scaffold(
                  backgroundColor: const Color(0xFFF5F7FB),
                  appBar: AppBar(
                    backgroundColor: Colors.white,
                    surfaceTintColor: Colors.white,
                    elevation: 0,
                    title: _isSearching
                        ? TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              hintText: 'Search title / category...',
                              border: InputBorder.none,
                            ),
                            onChanged: (v) {
                              setState(() {
                                _searchText = v.trim().toLowerCase();
                              });
                            },
                          )
                        : Text(title),
                    centerTitle: true,
                    actions: [
                      IconButton(
                        icon: Icon(_isSearching ? Icons.close : Icons.search),
                        onPressed: () {
                          setState(() {
                            _isSearching = !_isSearching;
                            if (!_isSearching) {
                              _searchController.clear();
                              _searchText = '';
                            }
                          });
                        },
                        tooltip: _isSearching ? 'Close search' : 'Search',
                      ),
                      IconButton(
                        icon: const Icon(Icons.filter_list),
                        onPressed: () => _openFilterSheet(categories),
                        tooltip: 'Filter',
                      ),
                      if (_viewMode == ViewMode.active)
                        IconButton(
                          icon: const Icon(Icons.analytics_outlined),
                          onPressed: () => _openMonthlySummary(
                            activeBox.values.toList(),
                            skippedBox.values.toList(),
                            completedBox.values.toList(),
                          ),
                          tooltip: 'Monthly summary',
                        ),
                      IconButton(
                        icon: Icon(
                          Icons.do_not_disturb_on,
                          color: _quietMode ? Colors.orange : null,
                        ),
                        tooltip: 'Quiet/DND Mode (only High+Critical)',
                        onPressed: _toggleQuietMode,
                      ),
                      IconButton(
                        icon: Icon(
                          _noReminderMode
                              ? Icons.notifications_off
                              : Icons.notifications,
                          color: _noReminderMode ? Colors.red : null,
                        ),
                        tooltip: 'No Reminder Mode (block all)',
                        onPressed: _toggleNoReminderMode,
                      ),
                      PopupMenuButton<ViewMode>(
                        icon: const Icon(Icons.view_list),
                        tooltip: 'Switch view',
                        onSelected: (v) {
                          setState(() {
                            _viewMode = v;
                            _searchController.clear();
                            _searchText = '';
                            _isSearching = false;
                            _priorityFilter = 'All';
                            _categoryFilter = 'All';
                          });
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: ViewMode.active,
                            child: Text('Active'),
                          ),
                          PopupMenuItem(
                            value: ViewMode.skipped,
                            child: Text('Skipped History'),
                          ),
                          PopupMenuItem(
                            value: ViewMode.completed,
                            child: Text('Completed History'),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.notifications_active),
                        onPressed: _showTestNotificationNow,
                        tooltip: 'Test Notification',
                      ),
                    ],
                  ),
                  body: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                  size: 52,
                                  color: Colors.indigo,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'No reminders to show',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Create your first reminder to start tracking tasks smartly.',
                                style: TextStyle(color: Colors.black54),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeroSection(
                                total: activeList.length,
                                highCritical: highCriticalCount,
                                overdue: overdueCount,
                              ),
                              _buildSectionTitle(
                                _viewMode == ViewMode.active
                                    ? 'Your Smart Reminders'
                                    : _viewMode == ViewMode.skipped
                                    ? 'Skipped Reminder History'
                                    : 'Completed Reminder History',
                              ),
                              ListView.builder(
                                itemCount: filtered.length,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemBuilder: (context, index) {
                                  final r = filtered[index];
                                  final riskScore = calculateRiskScore(r);
                                  final riskColor = getRiskColor(riskScore);

                                  dynamic skippedKey;
                                  if (_viewMode == ViewMode.skipped) {
                                    for (final k in skippedBox.keys) {
                                      final rr = skippedBox.get(k);
                                      if (rr != null &&
                                          rr.id == r.id &&
                                          rr.title == r.title &&
                                          rr.dueDate == r.dueDate) {
                                        skippedKey = k;
                                        break;
                                      }
                                    }
                                  }

                                  return Container(
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(18),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 8,
                                          ),
                                      leading: Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          color: getColor(r.priority),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      title: Text(
                                        r.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 14,
                                            ),
                                            children: [
                                              TextSpan(
                                                text: '${r.category} • ',
                                              ),
                                              TextSpan(
                                                text: r.priority,
                                                style: TextStyle(
                                                  color: getColor(r.priority),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              TextSpan(
                                                text:
                                                    '${r.skips >= 3 ? ' (Escalated)' : ''} • ',
                                              ),
                                              TextSpan(
                                                text:
                                                    'Due: ${r.dueDate != null ? r.dueDate!.toString().substring(0, 16) : 'No date'} • ',
                                              ),
                                              TextSpan(
                                                text:
                                                    'Repeat: ${r.repeat[0].toUpperCase() + r.repeat.substring(1)} • ',
                                              ),
                                              TextSpan(
                                                text: 'Skips: ${r.skips} • ',
                                              ),
                                              TextSpan(
                                                text:
                                                    'Risk: ${riskScore.toStringAsFixed(1)}',
                                                style: TextStyle(
                                                  color: riskColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _viewMode == ViewMode.active
                                            ? [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    color: Colors.blue,
                                                  ),
                                                  onPressed: () async {
                                                    final updated =
                                                        await Navigator.push<
                                                          Reminder
                                                        >(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (context) =>
                                                                AddReminderScreen(
                                                                  existingReminder:
                                                                      r,
                                                                ),
                                                          ),
                                                        );
                                                    if (updated != null) {
                                                      await activeBox.put(
                                                        updated.id,
                                                        updated,
                                                      );
                                                      await _cancelNotification(
                                                        updated.id,
                                                      );
                                                      await _scheduleNotification(
                                                        updated,
                                                      );
                                                    }
                                                  },
                                                  tooltip: 'Edit',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  onPressed: () =>
                                                      _confirmDelete(r),
                                                  tooltip: 'Delete',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.snooze,
                                                    color: Colors.purple,
                                                  ),
                                                  onPressed: () =>
                                                      _snoozeReminder(r),
                                                  tooltip: 'Snooze',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.skip_next,
                                                    color: Colors.orange,
                                                  ),
                                                  onPressed: () =>
                                                      _skipReminder(r),
                                                  tooltip: 'Skip',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.check_circle_outline,
                                                    color: Colors.green,
                                                  ),
                                                  onPressed: () =>
                                                      _markAsDone(r),
                                                  tooltip: 'Done',
                                                ),
                                              ]
                                            : _viewMode == ViewMode.skipped
                                            ? [
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.restore,
                                                    color: Colors.green,
                                                  ),
                                                  onPressed: () async {
                                                    await widget.remindersBox
                                                        .put(r.id, r);
                                                    await _cancelNotification(
                                                      r.id,
                                                    );
                                                    await _scheduleNotification(
                                                      r,
                                                    );
                                                    if (skippedKey != null) {
                                                      await widget.skippedBox
                                                          .delete(skippedKey);
                                                    }
                                                  },
                                                  tooltip: 'Restore',
                                                ),
                                                IconButton(
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    color: Colors.red,
                                                  ),
                                                  onPressed: () async {
                                                    if (skippedKey != null) {
                                                      await widget.skippedBox
                                                          .delete(skippedKey);
                                                    }
                                                  },
                                                  tooltip:
                                                      'Delete from skipped',
                                                ),
                                              ]
                                            : [],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
                  floatingActionButton: _viewMode == ViewMode.active
                      ? FloatingActionButton(
                          onPressed: () async {
                            final newReminder = await Navigator.push<Reminder>(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const AddReminderScreen(),
                              ),
                            );
                            if (newReminder != null) {
                              await widget.remindersBox.put(
                                newReminder.id,
                                newReminder,
                              );
                              await _cancelNotification(newReminder.id);
                              await _scheduleNotification(newReminder);
                            }
                          },
                          tooltip: 'Add Reminder',
                          child: const Icon(Icons.add),
                        )
                      : null,
                );
              },
            );
          },
        );
      },
    );
  }
}
