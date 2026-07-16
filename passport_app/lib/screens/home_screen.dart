import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Group the MVP documents by country for the picker.
    final byCountry = <String, List<DocumentConfig>>{};
    for (final d in mvpDocuments) {
      byCountry.putIfAbsent(d.country, () => []).add(d);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a document'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.verified_user_outlined,
                      color: AppTheme.seed, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Formatted to official specifications and checked '
                      'against each rule. Your photo never leaves this phone.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (final entry in byCountry.entries) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(entry.key.toUpperCase(),
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.black54)),
            ),
            ...entry.value.map((d) => _DocTile(doc: d)),
          ],
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc});
  final DocumentConfig doc;

  @override
  Widget build(BuildContext context) {
    final size = '${doc.outputSizeMm.width.toStringAsFixed(0)}'
        '×${doc.outputSizeMm.height.toStringAsFixed(0)} mm';
    final bg = doc.backgroundRule == BackgroundRule.whiteRequired
        ? 'white bg'
        : 'light bg';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: const Icon(Icons.credit_card_outlined),
          title: Text(doc.displayName,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$size · $bg · '
              '${doc.glassesRule == GlassesRule.banned ? "no glasses" : "glasses ok"}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            context.read<AppState>().selectDoc(doc);
            Navigator.pushNamed(context, '/capture');
          },
        ),
      ),
    );
  }
}
