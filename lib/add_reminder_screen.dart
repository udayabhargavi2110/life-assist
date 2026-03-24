import 'package:flutter/material.dart';
import 'reminder.dart';

class AddReminderScreen extends StatefulWidget {
  final Reminder? existingReminder; // ← NEW: optional for edit mode

  const AddReminderScreen({super.key, this.existingReminder});

  @override
  State<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends State<AddReminderScreen> {
  late TextEditingController _titleController;
  late String _category;
  late String _priority;
  DateTime? _dueDate;
  late String _repeat;

  @override
  void initState() {
    super.initState();

    // Pre-fill if editing an existing reminder
    if (widget.existingReminder != null) {
      final r = widget.existingReminder!;
      _titleController = TextEditingController(text: r.title);
      _category = r.category;
      _priority = r.priority;
      _dueDate = r.dueDate;
      _repeat = r.repeat;
    } else {
      _titleController = TextEditingController();
      _category = 'personal';
      _priority = 'medium';
      _dueDate = null;
      _repeat = 'none';
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.existingReminder != null;
    final title = isEditMode ? 'Edit Reminder' : 'Add Reminder';

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: ['health', 'medication', 'work', 'personal', 'critical']
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v!),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _priority,
                decoration: const InputDecoration(
                  labelText: 'Priority',
                  border: OutlineInputBorder(),
                ),
                items: ['low', 'medium', 'high', 'critical']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v!),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _repeat,
                decoration: const InputDecoration(
                  labelText: 'Repeat',
                  border: OutlineInputBorder(),
                ),
                items: ['none', 'daily', 'weekly', 'monthly', 'yearly']
                    .map(
                      (repeat) => DropdownMenuItem(
                        value: repeat,
                        child: Text(
                          repeat[0].toUpperCase() + repeat.substring(1),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _repeat = value!),
              ),
              const SizedBox(height: 24),

              ListTile(
                title: Text(
                  _dueDate == null
                      ? 'Select Date & Time'
                      : 'Due: ${_dueDate!.toString().substring(0, 16)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final pickedDate = await showDatePicker(
                    context: context,
                    initialDate: _dueDate ?? DateTime.now(),
                    firstDate: DateTime.now(),
                    lastDate: DateTime(2100),
                  );
                  if (pickedDate == null) return;

                  final pickedTime = await showTimePicker(
                    context: context,
                    initialTime: _dueDate != null
                        ? TimeOfDay.fromDateTime(_dueDate!)
                        : TimeOfDay.now(),
                  );
                  if (pickedTime == null) return;

                  setState(() {
                    _dueDate = DateTime(
                      pickedDate.year,
                      pickedDate.month,
                      pickedDate.day,
                      pickedTime.hour,
                      pickedTime.minute,
                    );
                  });
                },
              ),

              if (_dueDate == null)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 16.0),
                  child: Text(
                    'Date and time are required',
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                ),

              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (_titleController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Title is required'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }

                    if (_dueDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Date and time are required'),
                          backgroundColor: Colors.red,
                          duration: Duration(seconds: 2),
                        ),
                      );
                      return;
                    }

                    final reminder = Reminder(
                      id:
                          widget.existingReminder?.id ??
                          DateTime.now().millisecondsSinceEpoch.toString(),
                      title: _titleController.text.trim(),
                      category: _category,
                      priority: _priority,
                      dueDate: _dueDate,
                      repeat: _repeat,
                      skips: widget.existingReminder?.skips ?? 0,
                    );

                    Navigator.pop(context, reminder);
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(
                    isEditMode ? 'Update Reminder' : 'Save Reminder',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
