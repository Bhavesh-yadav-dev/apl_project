import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  static final _auth = FirebaseAuth.instance;

  // On web, google_sign_in needs the OAuth client ID explicitly.
  // On Android it reads from google-services.json automatically.
  static final _googleSignIn = GoogleSignIn(
    clientId: kIsWeb
        ? '189192017588-YOUR_WEB_CLIENT_ID.apps.googleusercontent.com'
        : null,
    scopes: ['email'],
  );

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ── Google ────────────────────────────────────────────────────────────────
  static Future<User?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web: use Firebase's built-in Google popup — no google_sign_in needed
        final provider = GoogleAuthProvider()
          ..addScope('email')
          ..setCustomParameters({'prompt': 'select_account'});
        final result = await _auth.signInWithPopup(provider);
        return result.user;
      } else {
        // Android / iOS: use google_sign_in package
        final googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null;
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        final result = await _auth.signInWithCredential(credential);
        return result.user;
      }
    } on FirebaseAuthException catch (e) {
      // popup closed by user — treat as cancel, not error
      if (e.code == 'popup-closed-by-user' ||
          e.code == 'cancelled-popup-request') return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }

  // ── Email / Password ──────────────────────────────────────────────────────

  /// Returns the signed-in User or throws a readable [AuthException].
  static Future<User?> signInWithEmail(String email, String password) async {
    final result = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    return result.user;
  }

  /// Creates a new account. Returns the User or throws [AuthException].
  static Future<User?> registerWithEmail(String email, String password) async {
    final result = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    return result.user;
  }

  /// Sends a password-reset email.
  static Future<void> sendPasswordReset(String email) =>
      _auth.sendPasswordResetEmail(email: email.trim());

  // ── Sign out ──────────────────────────────────────────────────────────────
  static Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }

  /// Converts a [FirebaseAuthException] code into a human-readable message.
  static String friendlyError(String code) {
    switch (code) {
      case 'user-not-found':      return 'No account found for that email.';
      case 'wrong-password':      return 'Incorrect password.';
      case 'email-already-in-use': return 'An account already exists for that email.';
      case 'weak-password':       return 'Password must be at least 6 characters.';
      case 'invalid-email':       return 'Please enter a valid email address.';
      case 'too-many-requests':   return 'Too many attempts. Try again later.';
      case 'network-request-failed': return 'Network error. Check your connection.';
      default:                    return 'Something went wrong. Please try again.';
    }
  }
}
