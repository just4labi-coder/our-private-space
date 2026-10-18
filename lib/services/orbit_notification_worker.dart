import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Calls the Cloudflare Worker after a message is saved to Firestore.
/// The Worker independently verifies the Firebase ID token and message sender.
class OrbitNotificationWorker {
  OrbitNotificationWorker._();

  static const String _workerUrl = String.fromEnvironment(
    'ORBIT_WORKER_URL',
    defaultValue: 'https://orbit-two-notifications.just4labi.workers.dev',
  );

  static Future<void> notifyNewMessage({
    required String spaceId,
    required String messageId,
  }) async {
    final baseUrl = _workerUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (baseUrl.isEmpty) {
      debugPrint('Orbit notification Worker URL is not configured.');
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) return;

      final response = await http
          .post(
            Uri.parse('$baseUrl/notify-message'),
            headers: {
              'authorization': 'Bearer $idToken',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'spaceId': spaceId,
              'messageId': messageId,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Orbit notification Worker returned ${response.statusCode}.',
        );
      }
    } catch (error) {
      // A notification outage must never make a successfully saved message fail.
      debugPrint('Orbit notification request failed: $error');
    }
  }
}
