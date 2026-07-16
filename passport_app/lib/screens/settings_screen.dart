import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/ads_service.dart';
import '../services/billing_service.dart';
import '../state/app_state.dart';

/// Placeholder — must point at a live public HTTPS privacy policy before store
/// submission (store compliance spec item 2).
const _privacyPolicyUrl = 'https://etechflow.com/passport-photo/privacy';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  BannerAd? _banner;
  bool _bannerLoaded = false;

  @override
  void initState() {
    super.initState();
    // Banner only on this non-capture screen (never on capture/checking).
    _banner = BannerAd(
      adUnitId: AdsService.bannerUnit,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _bannerLoaded = true);
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  Future<void> _openPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the policy link.')));
      }
    }
  }

  Future<void> _restore() async {
    await BillingService.instance.restore();
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    final unlocked = context.read<AppState>().unlocked;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(unlocked
            ? 'Purchase restored.'
            : 'No previous purchase found.')));
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = context.watch<AppState>().unlocked;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _NoteCard(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: _openPolicy,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore Purchases'),
            subtitle: Text(unlocked ? 'Unlocked' : 'Not unlocked'),
            onTap: _restore,
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0 (MVP)'),
          ),
        ],
      ),
      bottomNavigationBar: (_banner != null && _bannerLoaded)
          ? SafeArea(
              child: SizedBox(
                height: _banner!.size.height.toDouble(),
                width: _banner!.size.width.toDouble(),
                child: AdWidget(ad: _banner!),
              ),
            )
          : null,
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.all(16),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.lock_outline, color: Colors.green),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'All photo processing happens on this device. Your photos are '
                'never uploaded. There is no account and no sign-in.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
