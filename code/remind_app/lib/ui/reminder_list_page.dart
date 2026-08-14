import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:remind_core/remind_core.dart';

import '../runtime/remind_runtime.dart';
import 'formatting.dart';
import 'plan_page.dart';
import 'reminder_edit_page.dart';

/// The main screen: every reminder, what it does, and when it fires next.
class ReminderListPage extends StatefulWidget {
  /// Creates the list.
  const ReminderListPage({
    required this.runtime,
    required this.plugin,
    required this.details,
    super.key,
  });

  /// The wiring of store, reconciler and backends.
  final RemindRuntime runtime;

  /// The notification plugin, threaded through for the diagnostics self-test.
  final FlutterLocalNotificationsPlugin plugin;

  /// The details scheduled reminders are delivered with.
  final NotificationDetails details;

  @override
  State<ReminderListPage> createState() => _ReminderListPageState();
}

class _ReminderListPageState extends State<ReminderListPage> {
  RemindRuntime get _runtime => widget.runtime;

  Future<void> _reconcileAndReport() async {
    final result = await _runtime.reconcile();
    if (!mounted) return;

    final plan = result.plan;
    final parts = [
      if (plan.toRegister.isNotEmpty) '+${plan.toRegister.length}',
      if (plan.toCancel.isNotEmpty) '-${plan.toCancel.length}',
      if (plan.retained.isNotEmpty) '${plan.retained.length} kept',
    ];
    final message =
        parts.isEmpty ? 'Already up to date' : 'Scheduled: ${parts.join(', ')}';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.unroutable.isEmpty
              ? message
              : '$message — ${result.unroutable.length} could not be '
                  'delivered by any installed backend',
        ),
      ),
    );
  }

  Future<void> _edit([Reminder? existing]) async {
    final edited = await Navigator.of(context).push<Reminder>(
      MaterialPageRoute(
        builder: (_) =>
            ReminderEditPage(runtime: _runtime, existing: existing),
      ),
    );
    if (edited == null) return;
    await _runtime.store.save(edited);
    await _reconcileAndReport();
  }

  /// Schedules something two minutes out, so that the real device can be
  /// checked without waiting until tomorrow morning.
  Future<void> _scheduleSmokeTest() async {
    final soon = DateTime.now().add(const Duration(minutes: 2));
    final reminder = Reminder(
      id: 'smoke-${DateTime.now().microsecondsSinceEpoch}',
      title: 'Smoke test',
      body: 'Scheduled two minutes ago from remind_app',
      triggers: [
        OneShotTrigger(
          date: CalendarDate(soon.year, soon.month, soon.day),
          time: LocalTime(soon.hour, soon.minute),
        ),
      ],
    );
    await _runtime.store.save(reminder);
    await _reconcileAndReport();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('remind'),
          actions: [
            IconButton(
              tooltip: 'Reconciliation plan',
              icon: const Icon(Icons.fact_check_outlined),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => PlanPage(
                    runtime: _runtime,
                    plugin: widget.plugin,
                    details: widget.details,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Reconcile now',
              icon: const Icon(Icons.sync),
              onPressed: _reconcileAndReport,
            ),
          ],
        ),
        body: StreamBuilder<List<Reminder>>(
          stream: _runtime.store.watch(),
          builder: (context, snapshot) {
            final reminders = snapshot.data;
            if (reminders == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (reminders.isEmpty) return const _EmptyState();

            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: reminders.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final reminder = reminders[index];
                return _ReminderTile(
                  reminder: reminder,
                  upcoming: _runtime.upcoming(reminder, limit: 3),
                  onToggle: (enabled) async {
                    await _runtime.store
                        .save(reminder.copyWith(enabled: enabled));
                    await _reconcileAndReport();
                  },
                  onEdit: () => _edit(reminder),
                  onDelete: () async {
                    await _runtime.store.delete(reminder.id);
                    await _reconcileAndReport();
                  },
                );
              },
            );
          },
        ),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            FloatingActionButton.small(
              heroTag: 'smoke',
              tooltip: 'Fire in two minutes',
              onPressed: _scheduleSmokeTest,
              child: const Icon(Icons.timer_outlined),
            ),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'add',
              onPressed: _edit,
              icon: const Icon(Icons.add),
              label: const Text('Reminder'),
            ),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.notifications_none,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No reminders yet',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Add one, or use the timer button to schedule a smoke test two '
                'minutes from now.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
}

class _ReminderTile extends StatelessWidget {
  const _ReminderTile({
    required this.reminder,
    required this.upcoming,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final Reminder reminder;
  final List<Occurrence> upcoming;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      leading: Switch(value: reminder.enabled, onChanged: onToggle),
      title: Text(
        reminder.title,
        style: TextStyle(
          decoration: reminder.enabled ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(describeTriggers(context, reminder)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Next occurrences', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              if (upcoming.isEmpty)
                Text(
                  reminder.enabled
                      ? 'Nothing upcoming — every occurrence is in the past or '
                          'excluded by a condition.'
                      : 'Disabled, so nothing is scheduled.',
                  style: theme.textTheme.bodySmall,
                )
              else
                for (final occurrence in upcoming)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatInstantWithOffset(context, occurrence.instant),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (occurrence.dstAnomaly != null)
                          Tooltip(
                            message: describeAnomaly(occurrence.dstAnomaly!),
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        if (occurrence.isConditional)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.place_outlined, size: 18),
                          ),
                      ],
                    ),
                  ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Edit'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
