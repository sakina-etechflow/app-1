import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart' hide AppState;
import 'package:provider/provider.dart';
import '../legal.dart';
import '../services/ads_service.dart';
import '../services/auth_service.dart';
import '../services/billing_service.dart';
import '../state/app_state.dart';

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

  Future<void> _showSignIn(AuthService auth) async {
    final emailCtl = TextEditingController();
    final passCtl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign in to sync'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Syncs your settings and check history across devices. '
              'Your photos are never uploaded.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailCtl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: passCtl,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await auth.signInOrRegister(emailCtl.text, passCtl.text);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(err ?? 'Signed in — your settings now sync.')));
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = context.watch<AppState>().unlocked;
    final auth = context.watch<AuthService>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _NoteCard(),
          _accountTile(auth),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLegalUrl(context, kPrivacyPolicyUrl),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Terms of Service'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => openLegalUrl(context, kTermsOfServiceUrl),
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

  Widget _accountTile(AuthService auth) {
    if (!auth.cloudEnabled) {
      return const ListTile(
        leading: Icon(Icons.cloud_off_outlined),
        title: Text('Cloud sync'),
        subtitle: Text('Not configured on this build'),
      );
    }
    if (auth.signedIn && !auth.isAnonymous) {
      return ListTile(
        leading: const Icon(Icons.cloud_done_outlined, color: Colors.green),
        title: Text(auth.email ?? 'Signed in'),
        subtitle: const Text('Settings & history are syncing'),
        trailing: TextButton(
          onPressed: () async {
            await auth.signOut();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Signed out.')));
            }
          },
          child: const Text('Sign out'),
        ),
      );
    }
    return ListTile(
      leading: const Icon(Icons.cloud_upload_outlined),
      title: const Text('Sign in to sync'),
      subtitle: const Text('Sync settings & history across devices'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _showSignIn(auth),
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
                'All photo processing happens on this device and your photos '
                'are never uploaded. An optional account syncs only your '
                'settings and check history — no images.',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
