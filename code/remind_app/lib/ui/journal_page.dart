import 'package:flutter/material.dart';
import 'package:remind_geofence/remind_geofence.dart';

import 'formatting.dart';

/// Every region crossing, including the ones nobody was told about.
///
/// This screen is the answer to "I walked into the shop and nothing happened".
/// Without it, a reminder that was correctly suppressed by a condition looks
/// exactly like a geofence that is broken — and that ambiguity is the reason
/// every other product declines to offer conjunctive reminders at all.
class JournalPage extends StatefulWidget {
  /// Creates the journal screen.
  const JournalPage({required this.journal, super.key});

  /// Where crossing outcomes are recorded.
  final CrossingJournal journal;

  @override
  State<JournalPage> createState() => _JournalPageState();
}

class _JournalPageState extends State<JournalPage> {
  late Future<List<CrossingOutcome>> _entries;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      setState(() => _entries = widget.journal.recent(limit: 100));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Crossings'),
      actions: [
        IconButton(
          tooltip: 'Reload',
          icon: const Icon(Icons.refresh),
          onPressed: _reload,
        ),
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            await widget.journal.clear();
            _reload();
          },
        ),
      ],
    ),
    body: FutureBuilder<List<CrossingOutcome>>(
      future: _entries,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not read: ${snapshot.error}'));
        }
        final entries = snapshot.data;
        if (entries == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (entries.isEmpty) return const _Empty();

        return ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) => _OutcomeTile(outcome: entries[index]),
        );
      },
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.explore_off_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No crossings yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Every time a monitored region fires, what happened is recorded '
            'here — including the times nothing was shown, and why.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile({required this.outcome});

  final CrossingOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, colour) = switch (outcome) {
      Delivered() => (Icons.check_circle_outline, theme.colorScheme.primary),
      Suppressed() => (Icons.do_not_disturb_on_outlined, theme.colorScheme.outline),
      Undetermined() => (Icons.help_outline, theme.colorScheme.error),
    };

    return ListTile(
      leading: Icon(icon, color: colour),
      title: Text('${outcome.reminderId} · ${outcome.event.name} '
          '${outcome.region.id}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatInstant(context, outcome.at)),
          const SizedBox(height: 2),
          Text(outcome.explanation, style: theme.textTheme.bodySmall),
        ],
      ),
      isThreeLine: true,
    );
  }
}
