import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final report = appState.report;
    final blocked = report != null && !report.pass;

    // S6 shows exactly what the user would export: the clean (no-watermark)
    // render once unlocked (paid or a rewarded view), the watermarked render in
    // the free state. This is the same image the export step writes, so the
    // preview never over- or under-promises the output.
    final unlocked = appState.canExportWithoutWatermark;
    final preview =
        unlocked ? appState.formattedClean : appState.formattedPreview;

    return Scaffold(
      appBar: AppBar(title: const Text('Preview')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              color: const Color(0xFFECEFF3),
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              child: preview == null
                  ? const Center(child: Text('No preview'))
                  : Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(preview),
                      ),
                    ),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.water_drop_outlined,
                        size: 18, color: Colors.black45),
                    const SizedBox(width: 6),
                    Text(
                      unlocked
                          ? 'Unlocked — export without watermark.'
                          : 'Free preview includes a watermark.',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export photo'),
                  onPressed: blocked
                      ? null
                      : () {
                          if (unlocked) {
                            Navigator.pushNamed(context, '/export');
                          } else {
                            Navigator.pushNamed(context, '/paywall');
                          }
                        },
                ),
                if (blocked)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Resolve the failed requirements before exporting.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
