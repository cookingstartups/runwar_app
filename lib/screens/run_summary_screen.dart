import 'package:flutter/material.dart';

import '../models/run_summary.dart';
import '../widgets/run_metrics_card.dart';

/// Thin post-run recap screen. Hands its constructor-provided [summary]
/// straight through to [RunMetricsCard] - never reconstructs it, never reads
/// live recorder-provider state.
class RunSummaryScreen extends StatelessWidget {
  const RunSummaryScreen({required this.summary, super.key});

  final RunSummary summary;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: RunMetricsCard(
              summary: summary,
              onClosePressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}
