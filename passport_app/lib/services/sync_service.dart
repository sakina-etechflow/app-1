import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Cloud sync of NON-IMAGE data only: user preferences and a small history log
/// of past checks (document type, country, pass/fail, timestamp). The passport
/// / ID photos themselves are never written here — they stay on-device to keep
/// the app's Spec-item-4 "not collected" posture.
///
/// Every method is guarded: when [enabled] is false, or a call fails/offline,
/// it degrades to a safe no-op so the rest of the app is unaffected.
class SyncService {
  SyncService({this.enabled = true});

  /// False when Firebase is unconfigured or failed to init.
  final bool enabled;

  FirebaseFirestore? get _db => enabled ? FirebaseFirestore.instance : null;

  DocumentReference<Map<String, dynamic>>? _userDoc(String? uid) {
    final db = _db;
    if (db == null || uid == null || uid.isEmpty) return null;
    return db.collection('users').doc(uid);
  }

  /// Merge the user's preferences into their cloud profile.
  Future<void> saveSettings(String? uid, Map<String, dynamic> settings) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.set({
        ...settings,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('SyncService.saveSettings failed: $e');
    }
  }

  /// Read the user's cloud preferences, or null if none/unavailable.
  Future<Map<String, dynamic>?> fetchSettings(String? uid) async {
    final doc = _userDoc(uid);
    if (doc == null) return null;
    try {
      final snap = await doc.get();
      return snap.data();
    } catch (e) {
      debugPrint('SyncService.fetchSettings failed: $e');
      return null;
    }
  }

  /// Append one history entry (metadata only — never an image or file path).
  Future<void> addHistory(String? uid, Map<String, dynamic> entry) async {
    final doc = _userDoc(uid);
    if (doc == null) return;
    try {
      await doc.collection('history').add({
        ...entry,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('SyncService.addHistory failed: $e');
    }
  }

  /// Most-recent history entries (metadata only).
  Future<List<Map<String, dynamic>>> fetchHistory(String? uid,
      {int limit = 50}) async {
    final doc = _userDoc(uid);
    if (doc == null) return const [];
    try {
      final q = await doc
          .collection('history')
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      return q.docs.map((d) => d.data()).toList(growable: false);
    } catch (e) {
      debugPrint('SyncService.fetchHistory failed: $e');
      return const [];
    }
  }
}
