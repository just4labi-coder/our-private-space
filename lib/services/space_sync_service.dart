
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'private_space_service.dart';

class SpaceSyncService {
  SpaceSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<DocumentReference<Map<String, dynamic>>>
      _syncDocument() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('আগে Firebase-এ সংযুক্ত হতে হবে।');
    }

    final spaceId = await PrivateSpaceService.getSavedSpaceId();
    if (spaceId == null || spaceId.isEmpty) {
      throw Exception('আগে Partner Connection তৈরি বা Join করো।');
    }

    return _db
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('syncData')
        .doc('appState');
  }

  /// অ্যাপের JSON ডেটা Firebase-এ সংরক্ষণ
  static Future<void> uploadToFirebase(
    Map<String, dynamic> data,
  ) async {
    final ref = await _syncDocument();

    await ref.set({
      'data': data,
      'updatedBy': FirebaseAuth.instance.currentUser!.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Firebase থেকে সর্বশেষ JSON ডেটা পড়া
  static Future<Map<String, dynamic>?> downloadFromFirebase() async {
    final ref = await _syncDocument();
    final snapshot = await ref.get();

    if (!snapshot.exists) return null;

    final data = snapshot.data()?['data'];
    if (data is! Map) return null;

    return Map<String, dynamic>.from(data);
  }

  /// দুই ফোনে Firebase ডেটার পরিবর্তন সরাসরি শোনা
  static Future<Stream<Map<String, dynamic>?>>
      watchFirebaseData() async {
    final ref = await _syncDocument();

    return ref.snapshots().map((snapshot) {
      final data = snapshot.data()?['data'];

      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    });
  }

  /// Google Drive-এ JSON ব্যাকআপ ফাইল তৈরি বা আপডেট
  static Future<void> backupToGoogleDrive(
    Map<String, dynamic> data,
  ) async {
    final signIn = GoogleSignIn(
      scopes: [drive.DriveApi.driveFileScope],
    );

    final account = await signIn.signIn();
    if (account == null) {
      throw Exception('Google Drive অনুমতি দেওয়া হয়নি।');
    }

    final headers = await account.authHeaders;
    final client = _GoogleAuthClient(headers);
    final api = drive.DriveApi(client);

    try {
      final result = await api.files.list(
        q: "name = 'EternalSpaceBackup.json' and trashed = false",
        spaces: 'drive',
        $fields: 'files(id,name)',
        pageSize: 10,
      );

      final bytes = utf8.encode(jsonEncode({
        'app': 'Eternal Space',
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'data': data,
      }));

      final media = drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
        contentType: 'application/json',
      );

      final existing = result.files?.firstOrNull;

      if (existing?.id != null) {
        await api.files.update(
          drive.File()..name = 'EternalSpaceBackup.json',
          existing!.id!,
          uploadMedia: media,
        );
      } else {
        await api.files.create(
          drive.File()
            ..name = 'EternalSpaceBackup.json'
            ..mimeType = 'application/json',
          uploadMedia: media,
        );
      }
    } finally {
      client.close();
    }
  }
}

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(
    http.BaseRequest request,
  ) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}
