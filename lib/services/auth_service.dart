
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _trialKey = 'eternal_space_trial_mode';

  static User? get currentUser => _auth.currentUser;

  static Future<bool> isTrialMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_trialKey) ?? false;
  }

  static Future<void> startTrial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trialKey, true);
  }

  static Future<void> endTrial() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_trialKey, false);
  }

  static Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    await endTrial();
    await _saveProfile(result.user);
    return result;
  }

  static Future<UserCredential> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = result.user;
    if (user != null) {
      await user.updateDisplayName(name.trim());
      await user.reload();
      await _db.collection('users').doc(user.uid).set({
        'name': name.trim(),
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await endTrial();
    return result;
  }

  static Future<UserCredential> signInWithGoogle() async {
    final google = GoogleSignIn();
    final account = await google.signIn();

    if (account == null) {
      throw FirebaseAuthException(
        code: 'google-sign-in-cancelled',
        message: 'Google সাইন-ইন বাতিল হয়েছে।',
      );
    }

    final googleAuth = await account.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final result = await _auth.signInWithCredential(credential);
    await endTrial();
    await _saveProfile(result.user);
    return result;
  }

  static Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  static Future<void> _saveProfile(User? user) async {
    if (user == null) return;

    final doc = _db.collection('users').doc(user.uid);
    final snapshot = await doc.get();
    final oldName = snapshot.data()?['name'] as String?;

    final name = oldName?.trim().isNotEmpty == true
        ? oldName!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Eternal Space User');

    await doc.set({
      'name': name,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {
      // Google সাইন-আউট ব্যর্থ হলেও Firebase সাইন-আউট চলবে।
    }

    await _auth.signOut();
    await endTrial();
  }

  static String friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'সঠিক ইমেইল ঠিকানা দাও।';
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
          return 'ইমেইল বা পাসওয়ার্ড সঠিক নয়।';
        case 'email-already-in-use':
          return 'এই ইমেইলে অ্যাকাউন্ট আছে। লগইন করো।';
        case 'weak-password':
          return 'পাসওয়ার্ড অন্তত ৬ অক্ষরের দাও।';
        case 'network-request-failed':
          return 'ইন্টারনেট সংযোগ পরীক্ষা করো।';
        case 'google-sign-in-cancelled':
          return 'Google লগইন বাতিল হয়েছে।';
      }
    }

    return 'সমস্যা হয়েছে। আবার চেষ্টা করো।';
  }
}
