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
  static bool _notificationsEnabled = true;
  static const String _privacyKey = 'hideNotificationDetails';
  static const String _notificationsKey = 'notificationsEnabled';
  static const String _permissionAskedKey = 'notificationPermissionAsked';

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _hideDetails = prefs.getBool(_privacyKey) ?? false;
    _notificationsEnabled = prefs.getBool(_notificationsKey) ?? true;

    // Ask on the first run only. The system may not show another prompt after
    // denial; users can re-enable permission in Android App info settings.
    final permissionAsked = prefs.getBool(_permissionAskedKey) ?? false;
    if (!permissionAsked) {
      try {
        await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        await prefs.setBool(_permissionAskedKey, true);
      } catch (error) {
        debugPrint('Notification permission request failed: $error');
      }
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

  static Future<void> setNotificationsEnabled(bool value) async {
    _notificationsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, value);
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
        'notificationsEnabled': _notificationsEnabled,
        'platform': defaultTargetPlatform.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('FCM token save failed: $error');
    }
  }
}
