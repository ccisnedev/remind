import 'package:flutter/material.dart';
import 'package:remind_core/remind_core.dart';

/// The kinds of schedule this demo lets you build.
///
/// A deliberate subset: it covers what an ordinary alarm clock offers, which
/// is what the core was built to model. `DateListTrigger` and `LocationTrigger`
/// exist in the model but have no editor here.
enum _Kind { daily, weekly, onceOnADate }

/// Creates or edits a reminder.
class ReminderEditPage extends StatefulWidget {
  /// Creates the editor, optionally over an [existing] reminder.
  const ReminderEditPage({this.existing, super.key});

  /// The reminder being edited, or `null` when creating one.
  final Reminder? existing;

  @override
  State<ReminderEditPage> createState() => _ReminderEditPageState();
}

class _ReminderEditPageState extends State<ReminderEditPage> {
  late final TextEditingController _title;
  late final TextEditingController _body;

  _Kind _kind = _Kind.daily;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  Set<Weekday> _days = {...Weekday.workdays};
  DateTime _date = DateTime.now().add(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _body = TextEditingController(text: existing?.body ?? '');

    final trigger = existing?.triggers.first;
    switch (trigger) {
      case DailyTrigger(:final time):
        _kind = _Kind.daily;
        _time = TimeOfDay(hour: time.hour, minute: time.minute);
      case WeeklyTrigger(:final days, :final time):
        _kind = _Kind.weekly;
        _days = {...days};
        _time = TimeOfDay(hour: time.hour, minute: time.minute);
      case OneShotTrigger(:final date, :final time):
        _kind = _Kind.onceOnADate;
        _date = DateTime(date.year, date.month, date.day);
        _time = TimeOfDay(hour: time.hour, minute: time.minute);
      case _:
        break;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  LocalTime get _localTime => LocalTime(_time.hour, _time.minute);

  Trigger get _trigger => switch (_kind) {
        _Kind.daily => DailyTrigger(time: _localTime),
        _Kind.weekly => WeeklyTrigger(days: _days, time: _localTime),
        _Kind.onceOnADate => OneShotTrigger(
            date: CalendarDate(_date.year, _date.month, _date.day),
            time: _localTime,
          ),
      };

  bool get _isValid =>
      _title.text.trim().isNotEmpty &&
      (_kind != _Kind.weekly || _days.isNotEmpty);

  void _save() {
    final existing = widget.existing;
    Navigator.of(context).pop(
      Reminder(
        id: existing?.id ?? 'r-${DateTime.now().microsecondsSinceEpoch}',
        title: _title.text.trim(),
        body: _body.text.trim().isEmpty ? null : _body.text.trim(),
        enabled: existing?.enabled ?? true,
        triggers: [_trigger],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title:
              Text(widget.existing == null ? 'New reminder' : 'Edit reminder'),
          actions: [
            TextButton(
              onPressed: _isValid ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              decoration: const InputDecoration(
                labelText: 'Body (optional)',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 24),
            SegmentedButton<_Kind>(
              segments: const [
                ButtonSegment(value: _Kind.daily, label: Text('Daily')),
                ButtonSegment(value: _Kind.weekly, label: Text('Weekly')),
                ButtonSegment(value: _Kind.onceOnADate, label: Text('Date')),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) =>
                  setState(() => _kind = selection.first),
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Time'),
              trailing: Text(
                _time.format(context),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: _time,
                );
                if (picked != null) setState(() => _time = picked);
              },
            ),
            if (_kind == _Kind.weekly) ...[
              const Divider(),
              const SizedBox(height: 8),
              Text('Repeat on', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final day in _orderedWeekdays)
                    FilterChip(
                      label: Text(_shortName(day)),
                      selected: _days.contains(day),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _days.add(day);
                        } else {
                          _days.remove(day);
                        }
                      }),
                    ),
                ],
              ),
              if (_days.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Pick at least one day — a weekly reminder with no days would '
                    'never fire.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
            if (_kind == _Kind.onceOnADate) ...[
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Date'),
                trailing: Text(
                  '${_date.year}-${_two(_date.month)}-${_two(_date.day)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
            ],
          ],
        ),
      );

  static const List<Weekday> _orderedWeekdays = [
    Weekday.monday,
    Weekday.tuesday,
    Weekday.wednesday,
    Weekday.thursday,
    Weekday.friday,
    Weekday.saturday,
    Weekday.sunday,
  ];

  static String _shortName(Weekday day) => switch (day) {
        Weekday.monday => 'Mon',
        Weekday.tuesday => 'Tue',
        Weekday.wednesday => 'Wed',
        Weekday.thursday => 'Thu',
        Weekday.friday => 'Fri',
        Weekday.saturday => 'Sat',
        Weekday.sunday => 'Sun',
      };

  static String _two(int n) => n.toString().padLeft(2, '0');
}
