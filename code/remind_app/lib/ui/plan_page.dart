import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:remind_core/remind_core.dart';

import '../runtime/remind_runtime.dart';
import 'reminder_list_page.dart' show formatInstant;

/// Shows the reconciliation plan without applying it.
///
/// The reason the reconciler returns data instead of just doing the work: you
/// can look at what it intends to do. When a reminder does not arrive, this is
/// the screen that says whether it was ever scheduled, whether it fell off the
/// end of the budget, or whether nothing installed could deliver it.
class PlanPage extends StatelessWidget {
  /// Creates the diagnostics screen.
  const PlanPage({
    required this.runtime,
    required this.plugin,
    required this.details,
    super.key,
  });

  /// The wiring of store, reconciler and backends.
  final RemindRuntime runtime;

  /// The notification plugin, for the immediate self-test.
  final FlutterLocalNotificationsPlugin plugin;

  /// The details scheduled reminders are delivered with.
  final NotificationDetails details;

  /// Posts a notification right now, bypassing all scheduling.
  ///
  /// The discriminator when a reminder does not arrive: if this appears,
  /// notification setup is sound and the fault is in scheduling or delivery.
  /// If it does not, nothing about scheduling matters yet.
  Future<void> _postNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await plugin.show(
        id: 999999,
        title: 'Immediate test',
        body: 'Posted directly, with no alarm involved',
        notificationDetails: details,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Posted — check the shade')),
      );
    } on Object catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Reconciliation plan'),
          actions: [
            IconButton(
              tooltip: 'Post a notification now',
              icon: const Icon(Icons.notification_add_outlined),
              onPressed: () => _postNow(context),
            ),
          ],
        ),
        body: FutureBuilder<ReconciliationPlan>(
          future: runtime.preview(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(child: Text('Could not plan: ${snapshot.error}'));
            }
            final plan = snapshot.data;
            if (plan == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final budget =
                runtime.backends.isEmpty ? null : runtime.backends.first.budget;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Summary(plan: plan, zone: runtime.zone.name, budget: budget),
                const SizedBox(height: 8),
                _Section(
                  title: 'To register',
                  subtitle: 'The platform does not hold these yet',
                  icon: Icons.add_circle_outline,
                  children: [
                    for (final registration in plan.toRegister)
                      _RegistrationTile(registration: registration),
                  ],
                ),
                _Section(
                  title: 'Retained',
                  subtitle: 'Already in place, left alone',
                  icon: Icons.check_circle_outline,
                  children: [
                    for (final registration in plan.retained)
                      _RegistrationTile(registration: registration),
                  ],
                ),
                _Section(
                  title: 'To cancel',
                  subtitle: 'Held by the platform, no longer wanted',
                  icon: Icons.remove_circle_outline,
                  children: [
                    for (final key in plan.toCancel)
                      ListTile(
                        dense: true,
                        title: Text(key.value, style: _mono(context)),
                      ),
                  ],
                ),
                _Section(
                  title: 'Not ours',
                  subtitle: 'Scheduled by something else — never cancelled',
                  icon: Icons.help_outline,
                  children: [
                    for (final key in plan.unknown)
                      ListTile(
                        dense: true,
                        title: Text(key.value, style: _mono(context)),
                      ),
                  ],
                ),
                _Section(
                  title: 'Regions dropped',
                  subtitle: 'Beyond the platform budget',
                  icon: Icons.location_off_outlined,
                  children: [
                    for (final registration in plan.droppedRegions)
                      ListTile(
                        dense: true,
                        title: Text(registration.region.id),
                        subtitle: Text(registration.reminderId),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      );

  static TextStyle? _mono(BuildContext context) => Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
}

class _Summary extends StatelessWidget {
  const _Summary({required this.plan, required this.zone, this.budget});

  final ReconciliationPlan plan;
  final String zone;
  final SchedulingBudget? budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.isEmpty ? 'Settled' : 'Work pending',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              plan.isEmpty
                  ? 'The platform already holds exactly what it should.'
                  : '${plan.toRegister.length} to register, '
                      '${plan.toCancel.length} to cancel.',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 24),
            _Fact('Time zone', zone),
            _Fact('Desired total', '${plan.desiredCount}'),
            if (budget != null) ...[
              _Fact('Timed budget', '${budget!.maxTimed}'),
              _Fact('Region budget', '${budget!.maxRegions}'),
              _Fact('Horizon', '${budget!.horizon.inDays} days'),
            ],
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      leading: Icon(icon),
      title: Text('$title (${children.length})'),
      subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
      children: children.isEmpty
          ? [
              const ListTile(
                dense: true,
                title: Text(
                  'Nothing',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ]
          : children,
    );
  }
}

class _RegistrationTile extends StatelessWidget {
  const _RegistrationTile({required this.registration});

  final Registration registration;

  @override
  Widget build(BuildContext context) => switch (registration) {
        TimedRegistration(:final occurrence, :final reminder) => ListTile(
            dense: true,
            title: Text(reminder.title),
            subtitle: Text(formatInstant(occurrence.instant)),
            trailing: occurrence.dstAnomaly == null
                ? null
                : Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
          ),
        RegionRegistration(:final region, :final reminder, :final event) =>
          ListTile(
            dense: true,
            title: Text(reminder.title),
            subtitle: Text('${event.name} ${region.id}'),
          ),
      };
}
