import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:passport_app/legal.dart';

/// A1-11 acceptance coverage. The privacy manifest, the Info.plist strings and
/// the Android manifest are three files that must agree with each other and
/// with the store forms in docs/A11-privacy-manifest-and-labels.md. They are
/// edited by hand and never exercised by a Dart build, so nothing else would
/// notice a silent regression — hence these guards.
///
/// What this cannot check: that the archive validates cleanly and that the
/// submitted nutrition labels / Data Safety answers match. Those are console
/// steps, listed as the manual checklist in the doc.

File _repoFile(String relative) {
  // Tests run with the package root as cwd.
  final f = File(relative);
  expect(f.existsSync(), isTrue, reason: 'missing file: $relative');
  return f;
}

void main() {
  group('iOS privacy manifest', () {
    late String manifest;

    setUpAll(() {
      manifest = _repoFile('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
    });

    test('is bundled as a Runner resource', () {
      // A manifest that is not in the Resources build phase ships as a no-op:
      // the archive would validate, but the privacy report would be empty.
      final pbxproj =
          _repoFile('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbxproj, contains('PrivacyInfo.xcprivacy in Resources'));
      expect(
        pbxproj,
        contains('path = PrivacyInfo.xcprivacy'),
        reason: 'file reference missing from the project',
      );
    });

    test('declares tracking with AdMob domains', () {
      expect(manifest, contains('<key>NSPrivacyTracking</key>'));
      // The app requests ATT and serves AdMob, so this must stay true.
      final trackingBlock =
          manifest.split('<key>NSPrivacyTracking</key>')[1].trimLeft();
      expect(trackingBlock.startsWith('<true/>'), isTrue);

      expect(manifest, contains('<key>NSPrivacyTrackingDomains</key>'));
      for (final domain in const [
        'googleads.g.doubleclick.net',
        'www.googleadservices.com',
        'pagead2.googlesyndication.com',
      ]) {
        expect(manifest, contains('<string>$domain</string>'));
      }
    });

    test('declares every data type the app actually collects', () {
      // Mirrors AuthService (email + uid), SyncService (settings/history) and
      // the Ads SDK (IDFA). Adding a collection path to the app means adding
      // it here, in the nutrition labels and in the Data Safety form.
      for (final type in const [
        'NSPrivacyCollectedDataTypeEmailAddress',
        'NSPrivacyCollectedDataTypeUserID',
        'NSPrivacyCollectedDataTypeOtherUsageData',
        'NSPrivacyCollectedDataTypeDeviceID',
      ]) {
        expect(manifest, contains('<string>$type</string>'),
            reason: '$type not declared');
      }
    });

    test('does not declare photos as collected', () {
      // Spec item 4: photos are processed on-device and never uploaded. If this
      // ever fails, either the manifest is wrong or the app started uploading.
      expect(manifest, isNot(contains('NSPrivacyCollectedDataTypePhotosorVideos')));
    });

    test('has the required top-level keys for archive validation', () {
      for (final key in const [
        'NSPrivacyTracking',
        'NSPrivacyTrackingDomains',
        'NSPrivacyCollectedDataTypes',
        'NSPrivacyAccessedAPITypes',
      ]) {
        expect(manifest, contains('<key>$key</key>'), reason: '$key missing');
      }
    });
  });

  group('cross-file consistency', () {
    test('Info.plist carries the usage strings the labels promise', () {
      final plist = _repoFile('ios/Runner/Info.plist').readAsStringSync();
      for (final key in const [
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSPhotoLibraryAddUsageDescription',
        // Required before the Ads SDK may read the IDFA the manifest declares.
        'NSUserTrackingUsageDescription',
      ]) {
        expect(plist, contains('<key>$key</key>'), reason: '$key missing');
      }
    });

    test('Android declares AD_ID to match the DeviceID collection', () {
      final androidManifest =
          _repoFile('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(androidManifest,
          contains('com.google.android.gms.permission.AD_ID'));
    });

    test('legal URLs are public https links', () {
      // Both stores and the privacy manifest point at these; a non-https or
      // localhost URL fails review.
      for (final url in const [kPrivacyPolicyUrl, kTermsOfServiceUrl]) {
        final uri = Uri.parse(url);
        expect(uri.scheme, 'https', reason: '$url must be https');
        expect(uri.host, isNotEmpty);
        expect(uri.host, isNot(contains('localhost')));
      }
    });
  });
}
