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
      if (user == null) {
        debugPrint('Orbit push skipped: no signed-in user.');
        return;
      }

      final idToken = await user.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        debugPrint('Orbit push skipped: Firebase ID token is empty.');
        return;
      }

      // Retry transient Worker errors and the explicit retryable response used
      // when the partner device has not registered its FCM token yet.
      for (var attempt = 0; attempt < 3; attempt++) {
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

        Map<String, dynamic> result = <String, dynamic>{};
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is Map<String, dynamic>) result = decoded;
        } catch (_) {}

        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (result['retryable'] != true) return;
          debugPrint('Orbit push is retryable; no partner device token was reached yet.');
        } else {
          debugPrint(
            'Orbit notification Worker returned ${response.statusCode}.',
          );
          if (response.statusCode < 500 && response.statusCode != 429) return;
        }

        if (attempt < 2) {
          await Future<void>.delayed(
            Duration(milliseconds: 700 * (attempt + 1)),
          );
        }
      }
      debugPrint('Orbit push delivery did not confirm after retries.');
    } catch (error) {
      // A notification outage must never make a successfully saved message fail.
      debugPrint('Orbit notification request failed: $error');
    }
  }
}
