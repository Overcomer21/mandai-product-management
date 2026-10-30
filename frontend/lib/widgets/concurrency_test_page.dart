import 'package:flutter/material.dart';

/// Displays backend-observed integration test results. Never generates PASS locally.
class ConcurrentTransactionTestPage extends StatefulWidget {
  const ConcurrentTransactionTestPage({super.key, required this.runTests});
  final Future<Map<String, dynamic>> Function() runTests;

  @override
  State<ConcurrentTransactionTestPage> createState() =>
      _ConcurrentTransactionTestPageState();
}

class _ConcurrentTransactionTestPageState
    extends State<ConcurrentTransactionTestPage> {
  bool running = false;
  String? error;
  Map<String, dynamic>? report;

  Future<void> _run() async {
    if (running) return;
    setState(() {
      running = true;
      error = null;
      report = null;
    });
    try {
      final result = await widget.runTests();
      if (mounted) setState(() => report = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => running = false);
    }
  }

  Widget _field(String label, Object? value) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: SelectableText('$label: ${value ?? 'N/A'}',
            style: const TextStyle(fontSize: 12)),
      );

  @override
  Widget build(BuildContext context) {
    final results = (report?['results'] as List<dynamic>? ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Concurrent Transaction Test Results')),
      body: ListView(padding: const EdgeInsets.all(18), children: [
        const Text('Development diagnostics — isolated SQL Server test data',
            style: TextStyle(color: Color(0xFF607B6D))),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: running ? null : _run,
            icon: Icon(running ? Icons.hourglass_top : Icons.play_arrow),
            label: Text(running
                ? 'Executing Tests…'
                : 'Run Concurrent Transaction Tests')),
        if (running)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: LinearProgressIndicator()),
        if (error != null)
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Test execution error: $error',
                  style: const TextStyle(color: Colors.red))),
        if (report != null) ...[
          const SizedBox(height: 12),
          _field('Test Run ID', report!['run_id']),
          _field('Executed At (UTC)', report!['executed_at']),
          _field('Testing Status', report!['testing_status']),
          _field('Passed', report!['passed']),
          _field('Failed', report!['failed']),
          const Divider(),
          for (final raw in results)
            Builder(builder: (_) {
              final item = Map<String, dynamic>.from(raw as Map);
              final passed = item['testing_status'] == 'PASS';
              return Card(
                  child: Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${item['test_case']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 16)),
                            const SizedBox(height: 9),
                            Text('Testing Status: ${item['testing_status']}',
                                style: TextStyle(
                                    color: passed
                                        ? Colors.green.shade800
                                        : Colors.red.shade800,
                                    fontWeight: FontWeight.bold)),
                            _field('Transaction', item['transaction_status']),
                            _field('Transaction ID / Idempotency Key',
                                item['transaction_id']),
                            _field('Order ID', item['order_id']),
                            _field('Executed At (UTC)', item['executed_at']),
                            _field('Duration (ms)', item['duration_ms']),
                            _field('Expected Result', item['expected_result']),
                            _field('Actual Details', item['details']),
                          ])));
            }),
        ],
      ]),
    );
  }
}
