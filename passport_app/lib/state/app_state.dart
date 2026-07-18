import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/sync_service.dart';

/// Single source of truth for the capture -> check -> export flow.
class AppState extends ChangeNotifier {
  // Optional cloud sync (non-image data only). Null/no-op when Firebase is
  // unconfigured. Photos are never written to the cloud.
  AuthService? _auth;
  SyncService? _sync;

  DocumentConfig? _doc;
  String? _normalizedPhotoPath; // upright JPEG both ML Kit and pixels read
  ComplianceReport? _report;
  Uint8List? _formattedClean; // output at doc spec, no watermark
  Uint8List? _formattedPreview; // same, watermarked for the free tier
  bool _wearsGlasses = false;
  bool _unlocked = false;
  bool _rewardUsed = false;

  DocumentConfig? get doc => _doc;
  String? get normalizedPhotoPath => _normalizedPhotoPath;
  ComplianceReport? get report => _report;
  Uint8List? get formattedClean => _formattedClean;
  Uint8List? get formattedPreview => _formattedPreview;
  bool get wearsGlasses => _wearsGlasses;

  /// Paid unlock (persisted by the billing service) OR a single rewarded-video
  /// unlock for the current photo.
  bool get unlocked => _unlocked;
  bool get canExportWithoutWatermark => _unlocked || _rewardUsed;

  void selectDoc(DocumentConfig d) {
    _doc = d;
    notifyListeners();
  }

  void setWearsGlasses(bool v) {
    _wearsGlasses = v;
    notifyListeners();
    _pushSettings();
  }

  // --- Cloud sync (settings + history metadata only; never images) ---------

  /// Wire in the auth + sync services (called once at startup).
  void attachSync({required AuthService auth, required SyncService sync}) {
    _auth = auth;
    _sync = sync;
  }

  bool get _cloudReady => (_auth?.cloudEnabled ?? false);

  /// Load previously-synced preferences for the signed-in account, if any.
  Future<void> hydrateFromCloud() async {
    if (!_cloudReady) return;
    final data = await _sync?.fetchSettings(_auth?.uid);
    if (data == null) return;
    final g = data['wearsGlasses'];
    if (g is bool) _wearsGlasses = g;
    notifyListeners();
  }

  void _pushSettings() {
    if (!_cloudReady) return;
    // Preferences only. Entitlements (unlocked) stay billing-driven per store,
    // not synced, so a purchase must be restored through the store on a new
    // device.
    _sync?.saveSettings(_auth?.uid, {'wearsGlasses': _wearsGlasses});
  }

  void setNormalizedPhoto(String path) {
    _normalizedPhotoPath = path;
    _report = null;
    _formattedClean = null;
    _formattedPreview = null;
    _rewardUsed = false;
    notifyListeners();
  }

  void setResult({
    required ComplianceReport report,
    required Uint8List clean,
    required Uint8List preview,
  }) {
    _report = report;
    _formattedClean = clean;
    _formattedPreview = preview;
    notifyListeners();

    // History log: metadata only — document, verdict, time. No image, no path.
    if (_cloudReady) {
      _sync?.addHistory(_auth?.uid, {
        'documentId': report.documentId,
        'document': _doc?.displayName,
        'passed': report.pass,
      });
    }
  }

  /// Set once at startup and after a purchase/restore.
  void setUnlocked(bool v) {
    _unlocked = v;
    notifyListeners();
  }

  /// Called after a rewarded video completes: unlocks this one export.
  void grantRewardedExport() {
    _rewardUsed = true;
    notifyListeners();
  }

  /// Start a fresh photo but keep the selected document.
  void resetPhoto() {
    _normalizedPhotoPath = null;
    _report = null;
    _formattedClean = null;
    _formattedPreview = null;
    _rewardUsed = false;
    notifyListeners();
  }
}
