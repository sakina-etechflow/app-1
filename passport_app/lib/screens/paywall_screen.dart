import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../legal.dart';
import '../services/ads_service.dart';
import '../services/billing_service.dart';
import '../state/app_state.dart';
import '../theme.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  bool _busy = false;

  Future<void> _buy() async {
    setState(() => _busy = true);
    final ok = await BillingService.instance.buy();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      _snack('Store purchase is unavailable right now. '
          'Use the ad option, or Restore if you already bought it.');
    }
    // Entitlement arrives via the billing stream -> AppState.setUnlocked.
    // If it flips, leave to export.
    if (context.read<AppState>().unlocked) {
      Navigator.pushReplacementNamed(context, '/export');
    }
  }

  Future<void> _watchAd() async {
    setState(() => _busy = true);
    final earned = await AdsService.instance.showRewarded();
    if (!mounted) return;
    setState(() => _busy = false);
    if (earned) {
      context.read<AppState>().grantRewardedExport();
      Navigator.pushReplacementNamed(context, '/export');
    } else {
      _snack('No ad was available. Please try again in a moment.');
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    await BillingService.instance.restore();
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _busy = false);
    if (context.read<AppState>().unlocked) {
      Navigator.pushReplacementNamed(context, '/export');
    } else {
      _snack('No previous purchase found to restore.');
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final price = BillingService.instance.price;
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          const Icon(Icons.workspace_premium_outlined,
              size: 56, color: AppTheme.seed),
          const SizedBox(height: 12),
          const Center(
            child: Text('Export without a watermark',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('One-time purchase. No subscription.',
                style: TextStyle(color: Colors.black54)),
          ),
          const SizedBox(height: 24),
          _Feature('Unlimited exports, no watermark'),
          _Feature('Print sheet (4×6) and PDF'),
          _Feature('All document formats'),
          const SizedBox(height: 24),
          // Full price shown before confirmation (acceptance criterion). The
          // store sheet re-confirms it; this makes the amount explicit up front.
          Center(
            child: Text('One-time payment of $price',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text('Charged once to your store account. Not a subscription.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _buy,
            child: Text('Unlock everything — $price'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _watchAd,
            icon: const Icon(Icons.smart_display_outlined),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52)),
            label: const Text('Watch a short ad to export once'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : _restore,
            child: const Text('Restore Purchases'),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          const _LegalFooter(),
        ],
      ),
    );
  }
}

/// Terms of Service / Privacy Policy links — required on the paywall (S7) and by
/// both stores on any purchase surface.
class _LegalFooter extends StatelessWidget {
  const _LegalFooter();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(
            onPressed: () => openLegalUrl(context, kTermsOfServiceUrl),
            child: const Text('Terms of Service'),
          ),
          const Text('·', style: TextStyle(color: Colors.black38)),
          TextButton(
            onPressed: () => openLegalUrl(context, kPrivacyPolicyUrl),
            child: const Text('Privacy Policy'),
          ),
        ],
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppTheme.ok, size: 22),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
