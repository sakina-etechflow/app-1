import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/check_tile.dart';

class ResultsScreen extends StatelessWidget {
  const ResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final report = appState.report;
    final doc = appState.doc;
    if (report == null || doc == null) {
      return const Scaffold(body: Center(child: Text('No result.')));
    }

    final errors = report.results
        .where((r) => r.severity == Severity.error)
        .toList();
    final warnings = report.results
        .where((r) => r.severity == Severity.warning)
        .toList();
    final pass = report.pass;

    return Scaffold(
      appBar: AppBar(title: Text('${doc.displayName} · Check')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        children: [
          _Banner(pass: pass),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                children: [
                  const _SectionLabel('Requirements'),
                  ...errors.map((r) => CheckTile(result: r)),
                ],
              ),
            ),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    const _SectionLabel('Guidance'),
                    ...warnings.map((r) => CheckTile(result: r)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Formatted to official specifications for ${doc.displayName}. '
            'This is not a guarantee of acceptance.',
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/capture'),
                  child: const Text('Retake'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: () => Navigator.pushNamed(context, '/preview'),
                  child: Text(pass ? 'Continue' : 'See preview'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.pass});
  final bool pass;

  @override
  Widget build(BuildContext context) {
    final color = pass ? AppTheme.ok : AppTheme.err;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(pass ? Icons.verified : Icons.report_gmailerrorred,
              color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pass
                  ? 'All requirements met. Ready to export.'
                  : 'Some requirements need fixing. Adjust and retake.',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: color, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.black54)),
      ),
    );
  }
}
