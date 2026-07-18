import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Thin wrapper over FirebaseAuth. Everything is guarded so the app works even
/// when Firebase is not configured (placeholder options) or offline: in that
/// case [available] is false and every call is a safe no-op.
///
/// On startup, if Firebase is configured, we bootstrap an anonymous account so
/// settings/history sync works immediately with no sign-in friction. The user
/// can later upgrade to an email account (their anonymous data is linked, so
/// nothing is lost).
class AuthService extends ChangeNotifier {
  AuthService({this.available = true});

  /// False when Firebase never initialised (placeholder config / init failure).
  final bool available;

  FirebaseAuth? get _auth => available ? FirebaseAuth.instance : null;

  User? _user;
  User? get user => _user;

  bool get signedIn => _user != null;
  bool get isAnonymous => _user?.isAnonymous ?? false;
  String? get uid => _user?.uid;
  String? get email => _user?.email;

  /// True only when a real, configured backend is reachable to use.
  bool get cloudEnabled =>
      available && !DefaultFirebaseOptions.isPlaceholder;

  /// Call once after Firebase.initializeApp succeeded. Listens for auth changes
  /// and bootstraps an anonymous session.
  Future<void> init() async {
    final auth = _auth;
    if (auth == null || !cloudEnabled) return;
    auth.authStateChanges().listen((u) {
      _user = u;
      notifyListeners();
    });
    try {
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      } else {
        _user = auth.currentUser;
        notifyListeners();
      }
    } catch (e) {
      // Anonymous sign-in can fail if the provider is disabled in the console
      // or the device is offline; sync just stays off until next launch.
      debugPrint('AuthService: anonymous sign-in failed: $e');
    }
  }

  /// Sign in with email/password, creating the account if it does not exist.
  /// Returns null on success or a user-facing error message on failure.
  Future<String?> signInOrRegister(String email, String password) async {
    final auth = _auth;
    if (auth == null || !cloudEnabled) return 'Cloud sync is not configured.';
    try {
      // If currently anonymous, link so existing local data keeps its uid.
      final current = auth.currentUser;
      final cred = EmailAuthProvider.credential(
          email: email.trim(), password: password);
      if (current != null && current.isAnonymous) {
        try {
          await current.linkWithCredential(cred);
          return null;
        } on FirebaseAuthException catch (e) {
          // Account already exists: fall through to a normal sign-in.
          if (e.code != 'email-already-in-use' &&
              e.code != 'credential-already-in-use') {
            rethrow;
          }
        }
      }
      try {
        await auth.signInWithEmailAndPassword(
            email: email.trim(), password: password);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found') {
          await auth.createUserWithEmailAndPassword(
              email: email.trim(), password: password);
        } else {
          rethrow;
        }
      }
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Could not sign in (${e.code}).';
    } catch (e) {
      return 'Could not sign in: $e';
    }
  }

  /// Sign out and return to a fresh anonymous session so local sync keeps
  /// working (photos are never in the cloud, so nothing is exposed).
  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null || !cloudEnabled) return;
    try {
      await auth.signOut();
      await auth.signInAnonymously();
    } catch (e) {
      debugPrint('AuthService: sign-out failed: $e');
    }
  }
}
