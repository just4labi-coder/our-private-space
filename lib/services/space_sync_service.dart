import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import 'private_space_service.dart';

class SpaceSyncService {
  SpaceSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _folderName = 'Eternal Space Media';

  static GoogleSignIn _googleSignIn() {
    return GoogleSignIn(
      scopes: [
        drive.DriveApi.driveFileScope,
      ],
    );
  }

  static Future<drive.DriveApi> _driveApi() async {
    final signIn = _googleSignIn();

    var account = await signIn.signInSilently();
    account ??= await signIn.signIn();

    if (account == null) {
      throw Exception('Google Drive সাইন-ইন বাতিল করা হয়েছে।');
    }

    final headers = await account.authHeaders;
    return drive.DriveApi(_GoogleAuthClient(headers));
  }

  static Future<String> _getSpaceId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('আগে Partner Connection তৈরি করো।');
    }

    final spaceId = await PrivateSpaceService.getSavedSpaceId();
    if (spaceId == null || spaceId.isEmpty) {
      throw Exception('Partner Connection পাওয়া যায়নি।');
    }

    return spaceId;
  }

  static Future<DocumentReference<Map<String, dynamic>>>
      _syncDocument() async {
    final spaceId = await _getSpaceId();

    return _db
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('syncData')
        .doc('appState');
  }

  /// Google Drive-এ Eternal Space Media ফোল্ডার খোঁজা বা তৈরি করা
  static Future<String> getOrCreateMediaFolder() async {
    final api = await _driveApi();

    final result = await api.files.list(
      q: "name = '$_folderName' and mimeType = "
          "'application/vnd.google-apps.folder' and trashed = false",
      spaces: 'drive',
      $fields: 'files(id,name)',
      pageSize: 100,
    );

    final existing = result.files?.firstOrNull;
    if (existing?.id != null) {
      return existing!.id!;
    }

    final folder = await api.files.create(
      drive.File()
        ..name = _folderName
        ..mimeType = 'application/vnd.google-apps.folder',
      $fields: 'id,name',
    );

    final id = folder.id;
    if (id == null) {
      throw Exception('Drive ফোল্ডার তৈরি করা যায়নি।');
    }

    return id;
  }

  /// লোকাল ছবি বা ভিডিও Drive-এ আপলোড
  /// ফলাফল হিসেবে Drive file ID ও নাম পাওয়া যাবে
  static Future<Map<String, String>> uploadMedia(File file) async {
    if (!await file.exists()) {
      throw Exception('ফাইলটি এই ফোনে পাওয়া যায়নি।');
    }

    final api = await _driveApi();
    final folderId = await getOrCreateMediaFolder();
    final name = file.uri.pathSegments.isEmpty
        ? 'media_${DateTime.now().millisecondsSinceEpoch}'
        : file.uri.pathSegments.last;

    final extension = name.toLowerCase();
    final contentType = extension.endsWith('.mp4') ||
            extension.endsWith('.mov') ||
            extension.endsWith('.3gp')
        ? 'video/mp4'
        : extension.endsWith('.png')
            ? 'image/png'
            : extension.endsWith('.webp')
                ? 'image/webp'
                : 'image/jpeg';

    final length = await file.length();

    final uploaded = await api.files.create(
      drive.File()
        ..name = name
        ..parents = [folderId],
      uploadMedia: drive.Media(
        file.openRead(),
        length,
        contentType: contentType,
      ),
      $fields: 'id,name,mimeType',
    );

    if (uploaded.id == null) {
      throw Exception('Drive-এ ফাইল আপলোড ব্যর্থ হয়েছে।');
    }

    return {
      'driveFileId': uploaded.id!,
      'driveFileName': uploaded.name ?? name,
      'driveFolderId': folderId,
    };
  }

  /// Drive থেকে ফাইল নামিয়ে লোকাল ফাইলের পথ ফেরত দেয়
  static Future<String> downloadMedia(
    String fileId, {
    String? saveAs,
  }) async {
    final api = await _driveApi();

    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw Exception('Drive ফাইল ডাউনলোড করা যায়নি।');
    }

    final safeName = (saveAs ?? 'eternal_media_$fileId')
        .replaceAll(RegExp(r'[/\\]'), '_');

    final directory = Directory(
      '${Directory.systemTemp.path}/eternal_space_media',
    );

    await directory.create(recursive: true);

    final file = File('${directory.path}/$safeName');
    final sink = file.openWrite();

    try {
      await response.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      rethrow;
    }

    return file.path;
  }

  /// Drive ফোল্ডারটি পার্টনারের Google অ্যাকাউন্টের সঙ্গে শেয়ার
  static Future<void> shareMediaFolder(String email) async {
    final cleanedEmail = email.trim();

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
        .hasMatch(cleanedEmail)) {
      throw Exception('সঠিক Google ইমেইল দাও।');
    }

    final api = await _driveApi();
    final folderId = await getOrCreateMediaFolder();

    await api.permissions.create(
      drive.Permission()
        ..type = 'user'
        ..role = 'writer'
        ..emailAddress = cleanedEmail,
      folderId,
      sendNotificationEmail: true,
    );
  }

  static Future<void> uploadToFirebase(
    Map<String, dynamic> data,
  ) async {
    final ref = await _syncDocument();
    final user = FirebaseAuth.instance.currentUser!;

    await ref.set({
      'data': data,
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>?> downloadFromFirebase() async {
    final ref = await _syncDocument();
    final snapshot = await ref.get();

    if (!snapshot.exists) return null;

    final data = snapshot.data()?['data'];
    if (data is! Map) return null;

    return Map<String, dynamic>.from(data);
  }

  static Future<Stream<Map<String, dynamic>?>>
      watchFirebaseData() async {
    final ref = await _syncDocument();

    return ref.snapshots().map((snapshot) {
      final data = snapshot.data()?['data'];

      if (data is! Map) return null;
      return Map<String, dynamic>.from(data);
    });
  }

  /// Google Drive-এ JSON ব্যাকআপ
  static Future<void> backupToGoogleDrive(
    Map<String, dynamic> data,
  ) async {
    final api = await _driveApi();

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
  void close() => _client.close();
}
