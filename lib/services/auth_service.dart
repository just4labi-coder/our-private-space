import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_functions/firebase_functions.dart';
import 'package:flutter/foundation.dart';
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

  // Login সফল হওয়ার পর Trial বন্ধ করতে সমস্যা হলেও
  // সফল Authentication-কে ব্যর্থ দেখানো হবে না।
  static Future<void> _clearTrialSafely() async {
    try {
      await endTrial();
    } catch (error) {
      debugPrint('Clear trial mode error: $error');
    }
  }

  static Future<void> _cacheDisplayName(String? name) async {
    final cleaned = name?.trim() ?? '';

    if (cleaned.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('myDisplayName', cleaned);
    } catch (error) {
      debugPrint('Cache display name error: $error');
    }
  }

  static Future<String?> _getSavedProfileName(User? user) async {
    if (user == null) return null;

    try {
      final snapshot =
          await _db.collection('users').doc(user.uid).get();

      final value = snapshot.data()?['name'];

      if (value is String &&
          value.trim().isNotEmpty &&
          value.trim() != 'Orbit Two User' &&
          value.trim() != 'Orbit Two User') {
        return value.trim();
      }
    } catch (error) {
      debugPrint('Read profile name error: $error');
    }

    final displayName = user.displayName?.trim() ?? '';

    if (displayName.isNotEmpty) return displayName;

    final emailPrefix = user.email?.split('@').first.trim() ?? '';

    return emailPrefix.isNotEmpty ? emailPrefix : null;
  }

  static Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) async {
    // Authentication ব্যর্থ হলে Firebase-এর মূল error
    // AuthScreen-এ দেখানো হবে।
    final result = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    // নিচের কাজগুলো ব্যর্থ হলেও Login সফল থাকবে।
    await _clearTrialSafely();

    try {
      await _saveProfile(result.user);
    } catch (error, stackTrace) {
      debugPrint('Email profile save error: $error');
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

    // এই ধাপ সফল হলে Firebase অ্যাকাউন্ট তৈরি হয়ে গেছে।
    final result = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = result.user;

    if (user != null) {
      // Firebase Auth-এ নাম আপডেট করার চেষ্টা।
      try {
        await user.updateDisplayName(cleanedName);
        await user.reload();
      } catch (error) {
        debugPrint('Update account display name error: $error');
      }

      // Firestore-এ নাম সংরক্ষণের চেষ্টা।
      // এটি ব্যর্থ হলেও অ্যাকাউন্ট তৈরি সফল থাকবে।
      try {
        await _db.collection('users').doc(user.uid).set({
          'name': cleanedName,
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (error, stackTrace) {
        debugPrint('Create account profile save error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      // স্থানীয়ভাবে নাম সংরক্ষণের চেষ্টা।
      await _cacheDisplayName(cleanedName);
    }

    await _clearTrialSafely();

    // Firestore-এ সমস্যা হলেও AuthScreen সফল Login-এর
    // পরবর্তী ধাপে যেতে পারবে।
    return result;
  }

  static Future<void> resetPassword(String email) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || !normalizedEmail.contains('@')) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Enter a valid email address.',
      );
    }

    // Use the server-side SMTP template so the email can include Orbit Two
    // branding and its hosted logo without exposing SMTP credentials in the app.
    final callable = FirebaseFunctions.instance.httpsCallable(
      'sendBrandedPasswordResetEmail',
    );
    await callable.call<void>({'email': normalizedEmail});
  }

  static Future<void> _saveProfile(User? user) async {
    if (user == null) return;

    final doc = _db.collection('users').doc(user.uid);
    final snapshot = await doc.get();

    final savedValue = snapshot.data()?['name'];
    final oldName = savedValue is String ? savedValue.trim() : '';

    final displayName = user.displayName?.trim() ?? '';
    final emailPrefix = user.email?.split('@').first.trim() ?? '';

    // আগে থেকে সেভ করা বৈধ নাম অকারণে পরিবর্তন করা হবে না।
    final String name;

    if (oldName.isNotEmpty &&
        oldName != 'Orbit Two User' &&
        oldName != 'Orbit Two User') {
      name = oldName;
    } else if (displayName.isNotEmpty) {
      name = displayName;
    } else if (emailPrefix.isNotEmpty) {
      name = emailPrefix;
    } else {
      name = 'Orbit Two User';
    }

    await doc.set({
      'name': name,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> signOut() async {
    await _auth.signOut();
    await endTrial();

    // Shared-space cache is account/partner scoped. Clear it on logout so
    // another account on this phone cannot see the previous couple's data.
    final prefs = await SharedPreferences.getInstance();
    for (final key in const [
      'loveNotes',
      'specialDates',
      'galleryMedia',
      'galleryFolders',
      'spaceComplaints',
      'relationshipStartAt',
      'chatDraft',
      'chatMessages',
      'pendingDriveUploads',
      'myDisplayName',
      'partnerOne',
      'partnerTwo',
      'eternal_space_id',
      'eternal_space_invite_code',
    ]) {
      await prefs.remove(key);
    }
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

        case 'invalid-display-name':
          return 'নাম লিখতে হবে।';
      }
    }

    return 'সমস্যা হয়েছে। আবার চেষ্টা করো।';
  }
}
