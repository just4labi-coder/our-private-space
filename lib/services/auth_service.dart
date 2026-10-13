
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  static Future<void> _cacheDisplayName(String? name) async {
    final cleaned = name?.trim() ?? '';

    if (cleaned.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('myDisplayName', cleaned);
  }

  static Future<String?> _getSavedProfileName(User? user) async {
    if (user == null) return null;

    try {
      final snapshot =
          await _db.collection('users').doc(user.uid).get();

      final value = snapshot.data()?['name'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } catch (error) {
      debugPrint('Read profile name error: $error');
    }

    final displayName = user.displayName?.trim() ?? '';
    if (displayName.isNotEmpty) return displayName;

    return null;
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

    try {
      await _saveProfile(result.user);
    } catch (error, stackTrace) {
      debugPrint('Profile save error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    final name = await _getSavedProfileName(result.user);
    await _cacheDisplayName(name);

    return result;
  }

  static Future<UserCredential> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final cleanedName = name.trim();

    if (cleanedName.isEmpty) {
      throw FirebaseAuthException(
        code: 'invalid-display-name',
        message: 'নাম লিখতে হবে।',
      );
    }

    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = result.user;

    if (user != null) {
      await user.updateDisplayName(cleanedName);
      await user.reload();

      await _db.collection('users').doc(user.uid).set({
        'name': cleanedName,
        'email': user.email,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _cacheDisplayName(cleanedName);
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

    final googleName = result.user?.displayName?.trim() ?? '';

    if (googleName.isNotEmpty) {
      await _cacheDisplayName(googleName);
    }

    try {
      await _saveProfile(result.user);
    } catch (error, stackTrace) {
      debugPrint('Google profile save error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

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
    final displayName = user.displayName?.trim() ?? '';
    final emailPrefix = user.email?.split('@').first.trim() ?? '';

    final name = oldName?.trim().isNotEmpty == true &&
            oldName!.trim() != 'Eternal Space User'
        ? oldName.trim()
        : displayName.isNotEmpty
            ? displayName
            : emailPrefix.isNotEmpty
                ? emailPrefix
                : 'Eternal Space User';

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
