import 'package:hive/hive.dart';

part 'reminder.g.dart';

@HiveType(typeId: 0)
class Reminder {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String category;

  @HiveField(3)
  String priority; // ← REMOVE 'final' here – now it can be updated

  @HiveField(4)
  DateTime? dueDate;

  @HiveField(5)
  final String repeat;

  @HiveField(6)
  int skips = 0;

  Reminder({
    required this.id,
    required this.title,
    this.category = 'personal',
    this.priority = 'medium', // default value
    this.dueDate,
    this.repeat = 'none',
    this.skips = 0,
  });

  @override
  String toString() {
    return 'Reminder(id: $id, title: "$title", category: $category, priority: $priority, dueDate: $dueDate, repeat: $repeat, skips: $skips)';
  }
}
