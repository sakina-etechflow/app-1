import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';

/// S2 Home (ticket A1-02).
///
/// Country search -> document-type list -> spec preview -> Start. The picked
/// [DocumentConfig] is the target spec for the whole flow, carried forward via
/// [AppState.selectDoc] into capture (unchanged downstream contract).
///
/// Compliance:
///   * US document types flag the verify-and-format-only, no-AI-alteration path
///     (spec 4). The flag is driven by the config, not decorative copy.
///   * No guaranteed-acceptance wording appears anywhere on this screen
///     (spec 5): we say "formatted to official specifications", never
///     "guaranteed accepted".
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  /// Countries in picker order (deduped, order preserved from the config).
  static final List<String> _countries = () {
    final seen = <String>[];
    for (final d in mvpDocuments) {
      if (!seen.contains(d.country)) seen.add(d.country);
    }
    return seen;
  }();

  final _searchController = TextEditingController();
  String _query = '';
  String? _country;
  DocumentConfig? _doc;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _matchingCountries {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _countries;
    return _countries.where((c) => c.toLowerCase().contains(q)).toList();
  }

  List<DocumentConfig> get _docsForCountry =>
      mvpDocuments.where((d) => d.country == _country).toList();

  void _selectCountry(String country) {
    setState(() {
      _country = country;
      _doc = null; // spec must be re-picked for the new country
    });
  }

  void _selectDoc(DocumentConfig doc) {
    setState(() => _doc = doc);
  }

  void _start() {
    final doc = _doc;
    if (doc == null) return;
    context.read<AppState>().selectDoc(doc);
    Navigator.pushNamed(context, '/capture');
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    final matches = _matchingCountries;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a document'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // Spec-5-safe positioning copy: "official specifications", on-device.
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

          // 1. Country selector with search.
          _SectionLabel('1 · Country'),
          const SizedBox(height: 8),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Search country',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Clear',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (matches.isEmpty)
            // Search-empty state.
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No countries match "$_query".',
                  style: const TextStyle(color: Colors.black54)),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < matches.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _SelectTile(
                      label: matches[i],
                      selected: _country == matches[i],
                      onTap: () => _selectCountry(matches[i]),
                    ),
                  ],
                ],
              ),
            ),

          // 2. Document-type list for the chosen country.
          if (_country != null) ...[
            const SizedBox(height: 20),
            _SectionLabel('2 · Document type'),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _docsForCountry.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _DocTile(
                      doc: _docsForCountry[i],
                      selected: _doc?.id == _docsForCountry[i].id,
                      onTap: () => _selectDoc(_docsForCountry[i]),
                    ),
                  ],
                ],
              ),
            ),
          ],

          // 3. Spec preview for the chosen document.
          if (doc != null) ...[
            const SizedBox(height: 20),
            _SectionLabel('3 · Spec preview'),
            const SizedBox(height: 8),
            _SpecPreview(doc: doc),
          ],
        ],
      ),

      // 4. Start button — enabled only once a spec is fully selected.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton(
          onPressed: doc == null ? null : _start,
          child: Text(doc == null ? 'Select a document' : 'Start'),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text.toUpperCase(),
        style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            fontSize: 12,
            color: Colors.black54));
  }
}

/// A single-select row used for the country list.
class _SelectTile extends StatelessWidget {
  const _SelectTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? AppTheme.seed : Colors.black26,
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({
    required this.doc,
    required this.selected,
    required this.onTap,
  });

  final DocumentConfig doc;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = '${doc.outputSizeMm.width.toStringAsFixed(0)}'
        '×${doc.outputSizeMm.height.toStringAsFixed(0)} mm';
    final bg = doc.backgroundRule == BackgroundRule.whiteRequired
        ? 'white bg'
        : 'light bg';
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Icon(Icons.credit_card_outlined,
          color: selected ? AppTheme.seed : null),
      title: Text(doc.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('$size · $bg · '
          '${doc.glassesRule == GlassesRule.banned ? "no glasses" : "glasses ok"}'),
      trailing: Icon(
        selected ? Icons.check_circle : Icons.radio_button_unchecked,
        color: selected ? AppTheme.seed : Colors.black26,
      ),
      onTap: onTap,
    );
  }
}

/// Read-only preview of the selected spec, plus the US verify-and-format-only
/// flag (spec 4). Wording stays spec-5-safe: no acceptance guarantees.
class _SpecPreview extends StatelessWidget {
  const _SpecPreview({required this.doc});
  final DocumentConfig doc;

  bool get _isUs => doc.country == 'US';

  @override
  Widget build(BuildContext context) {
    final size = '${doc.outputSizeMm.width.toStringAsFixed(0)} × '
        '${doc.outputSizeMm.height.toStringAsFixed(0)} mm';
    final res = '${doc.minResolutionPx.width}×${doc.minResolutionPx.height} to '
        '${doc.maxResolutionPx.width}×${doc.maxResolutionPx.height} px';
    final bg = doc.backgroundRule == BackgroundRule.whiteRequired
        ? 'White / off-white'
        : 'Light (not white)';
    final glasses = switch (doc.glassesRule) {
      GlassesRule.banned => 'Not allowed',
      GlassesRule.allowedNoGlare => 'Allowed if no glare',
      GlassesRule.discouraged => 'Discouraged',
    };
    final expression = doc.expressionRule == ExpressionRule.neutralStrict
        ? 'Neutral, no smile'
        : 'Neutral or closed-mouth smile';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(doc.displayName,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Sized correctly for ${doc.country}',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 14),
            _SpecRow(label: 'Print size', value: size),
            _SpecRow(label: 'Resolution', value: res),
            _SpecRow(label: 'Background', value: bg),
            _SpecRow(label: 'Glasses', value: glasses),
            _SpecRow(label: 'Expression', value: expression),
            if (_isUs) ...[
              const SizedBox(height: 14),
              _VerifyFormatOnlyFlag(),
            ],
          ],
        ),
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

/// The US no-alteration flag (spec 4). Presence of this banner is what the
/// A1-02 acceptance criterion "US passport is flagged for the no-alteration
/// path" checks for.
class _VerifyFormatOnlyFlag extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.seed.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: AppTheme.seed, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Verify & format only — no AI alteration. For US documents we '
              'crop, resize, and check against the official spec on-device. '
              'Your photo is never retouched or uploaded.',
              style: TextStyle(height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}
