import 'dart:async';

import 'package:flutter/material.dart';

import '../runtime/remind_runtime.dart';
import 'reminder_list_page.dart';

/// The application shell.
///
/// Its one job beyond routing is to reconcile when the application comes back
/// to the foreground. Time has passed while it was away, occurrences have
/// fired and dropped out of the window, and the platform is holding less than
/// it should. Nothing else will notice.
class RemindApp extends StatefulWidget {
  /// Creates the app around [runtime].
  const RemindApp({required this.runtime, super.key});

  /// The wiring of store, reconciler and backends.
  final RemindRuntime runtime;

  @override
  State<RemindApp> createState() => _RemindAppState();
}

class _RemindAppState extends State<RemindApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.runtime.reconcile());
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'remind',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4C5FD5)),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4C5FD5),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: ReminderListPage(runtime: widget.runtime),
      );
}
