import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/export_service.dart';
import '../state/app_state.dart';
import '../theme.dart';

class ExportScreen extends StatelessWidget {
  const ExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final clean = appState.formattedClean;
    final doc = appState.doc;

    // Guard: only reachable once unlocked or after a rewarded view.
    if (!appState.canExportWithoutWatermark || clean == null || doc == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Export')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Unlock first to export without a watermark.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/paywall'),
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFFECEFF3),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(clean),
                ),
              ),
            ),
          ),
          Container(
            color: Colors.white,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: AppTheme.ok, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text('Unaltered, formatted for ${doc.displayName}.',
                          style: const TextStyle(color: Colors.black54)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text('Save / share photo'),
                  onPressed: () =>
                      ExportService.shareDigital(clean, doc.id),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: const Icon(Icons.grid_on),
                  label: const Text('Print sheet (4×6 PDF)'),
                  onPressed: () => ExportService.printSheet(clean, doc),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
