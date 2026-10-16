import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-device FCM registration. Privacy choice is stored per installation,
/// not as a shared app-space preference.
class PushNotificationService {
  PushNotificationService._();

  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static StreamSubscription<String>? _tokenSubscription;
  static StreamSubscription<User?>? _authSubscription;
  static bool _hideDetails = false;
  static const String _privacyKey = 'hideNotificationDetails';

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _hideDetails = prefs.getBool(_privacyKey) ?? false;

    // Notification permission can be denied or temporarily unavailable.
    // Do not let that prevent the app from opening or Firebase Auth from working.
    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } catch (error) {
      debugPrint('Notification permission request failed: $error');
    }

    _authSubscription ??= FirebaseAuth.instance.authStateChanges().listen(
      (user) {
        if (user == null) {
          return;
        }
        unawaited(_registerCurrentToken());
      },
    );

    _tokenSubscription ??= _messaging.onTokenRefresh.listen((token) {
      unawaited(_saveToken(token));
    });

    await _registerCurrentToken();
  }

  static Future<void> setHideDetails(bool value) async {
    _hideDetails = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_privacyKey, value);
    await _registerCurrentToken();
  }

  static Future<void> unregisterCurrentToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      final safeId = token.replaceAll('/', '_').replaceAll('.', '_');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('pushTokens')
          .doc(safeId)
          .delete();
    } catch (error) {
      debugPrint('FCM token removal failed: $error');
    }
  }

  static Future<void> _registerCurrentToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final token = await _messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
    } catch (error) {
      debugPrint('FCM token registration failed: $error');
    }
  }

  static Future<void> _saveToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || token.isEmpty) return;

    try {
      final safeId = token.replaceAll('/', '_').replaceAll('.', '_');
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('pushTokens')
          .doc(safeId)
          .set({
        'token': token,
        'hideNotificationDetails': _hideDetails,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('FCM token save failed: $error');
    }
  }
}
