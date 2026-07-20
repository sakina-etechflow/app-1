import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Public legal URLs, shared by the paywall (S7) and Settings. These MUST
/// resolve to live public HTTPS pages before store submission (store compliance
/// spec item 2) — both stores require a Privacy Policy and Terms of Use to be
/// linked from the purchase surface and the listing.
const kPrivacyPolicyUrl = 'https://etechflow.com/passport-photo/privacy';
const kTermsOfServiceUrl = 'https://etechflow.com/passport-photo/terms';

/// Open a legal URL in the external browser. Shows a snackbar on failure so a
/// dead link never silently no-ops. Safe to call from any screen with a context.
Future<void> openLegalUrl(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not open the link.')));
  }
}
