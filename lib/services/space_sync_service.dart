import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'private_space_service.dart';

class SpaceSyncService {
  SpaceSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _apiUrl =
      'https://script.google.com/macros/s/AKfycbw5JDObuu19_VQQ1ytXsA2Bav2M_szPSoiARCrc5KvNZYKm-RoDr1lwUiy14s3nsnzSoQ/exec';

  static const int _maxUploadBytes = 30 * 1024 * 1024;

  // --------------------------------------------------
  // AUTHENTICATION AND SPACE
  // --------------------------------------------------

  static Future<User> _requireUser() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('আগে অ্যাকাউন্টে সাইন ইন করো।');
    }

    return user;
  }

  static Future<String> _getSpaceId() async {
    await _requireUser();

    final id = await PrivateSpaceService.getSavedSpaceId();

    if (id == null || id.isEmpty) {
      throw Exception('আগে Partner Connection তৈরি করো।');
    }

    return id;
  }

  static Future<String> _getIdToken() async {
    final user = await _requireUser();
    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('Firebase পরিচয় যাচাই করা যায়নি। আবার চেষ্টা করো।');
    }

    return token;
  }

  // --------------------------------------------------
  // APPS SCRIPT API
  // --------------------------------------------------

  static Future<Map<String, dynamic>> _request(
    String action, {
    Map<String, dynamic> data = const {},
    bool needsSpace = false,
  }) async {
    final token = await _getIdToken();

    final payload = <String, dynamic>{
      'action': action,
      'idToken': token,
      ...data,
    };

    if (needsSpace && !payload.containsKey('spaceId')) {
      payload['spaceId'] = await _getSpaceId();
    }

    final client = http.Client();
    http.Response response;

    try {
      final request = http.Request(
        'POST',
        Uri.parse(_apiUrl),
      )
        ..followRedirects = false
        ..headers.addAll(const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        })
        ..body = jsonEncode(payload);

      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 90));

      response = await http.Response.fromStream(
        streamedResponse,
      ).timeout(const Duration(seconds: 90));

      // Google Apps Script-এর 302 Redirect আলাদাভাবে অনুসরণ করা।
      if (response.statusCode == 301 ||
          response.statusCode == 302 ||
          response.statusCode == 303 ||
          response.statusCode == 307 ||
          response.statusCode == 308) {
        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          throw Exception(
            'সার্ভার Redirect দিয়েছে, কিন্তু গন্তব্য পাওয়া যায়নি।',
          );
        }

        final redirectUri = Uri.parse(location);

        // নিরাপত্তার জন্য শুধু Google-এর ContentService
        // response domain-এ Redirect অনুসরণ করা হবে।
        if (redirectUri.scheme != 'https' ||
            !redirectUri.host.endsWith('googleusercontent.com')) {
          throw Exception(
            'সার্ভারের Redirect ঠিকানা যাচাই করা যায়নি।',
          );
        }

        response = await client
            .get(
              redirectUri,
              headers: const {
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 90));
      }
    } on Exception catch (error) {
      if (error.toString().contains('Redirect')) {
        rethrow;
      }
      throw Exception(
        'সার্ভারের সঙ্গে যোগাযোগ করা যায়নি। '
        'ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করো।',
      );
    } finally {
      client.close();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'সার্ভার অনুরোধ গ্রহণ করেনি (${response.statusCode})।',
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw Exception(
        'সার্ভারের উত্তর বোঝা যায়নি। '
        'Apps Script Web App deployment পরীক্ষা করো।',
      );
    }

    if (decoded is! Map) {
      throw Exception('সার্ভারের উত্তর সঠিক নয়।');
    }

    final result = Map<String, dynamic>.from(decoded);

    if (result['ok'] != true) {
      final error = result['error']?.toString() ?? 'REQUEST_FAILED';
      throw Exception(_errorMessage(error));
    }

    final responseData = result['data'];

    if (responseData is Map) {
      return Map<String, dynamic>.from(responseData);
    }

    return <String, dynamic>{};
  }

  static String _errorMessage(String error) {
    switch (error) {
      case 'AUTH_REQUIRED':
        return 'সাইন-ইন প্রয়োজন।';
      case 'AUTH_INVALID':
        return 'সাইন-ইন মেয়াদ শেষ বা পরিচয় যাচাই ব্যর্থ হয়েছে।';
      case 'SPACE_ACCESS_DENIED':
        return 'এই Private Space ব্যবহারের অনুমতি নেই।';
      case 'SPACE_DISCONNECTED':
        return 'Partner Connection বিচ্ছিন্ন। পুনরায় সংযোগ করো।';
      case 'INVALID_SPACE_ID':
        return 'Private Space ID সঠিক নয়।';
      case 'FILE_DATA_REQUIRED':
        return 'আপলোড করার ফাইল পাওয়া যায়নি।';
      case 'FILE_TOO_LARGE':
        return 'ফাইলটি সার্ভারের আপলোড সীমা অতিক্রম করেছে। ছোট ফাইল দিয়ে চেষ্টা করো।';
      case 'DOWNLOAD_TOO_LARGE':
        return 'ফাইলটি ডাউনলোডের নির্ধারিত সীমার চেয়ে বড়।';
      case 'INVALID_FILE_ID':
        return 'ফাইলের পরিচয় সঠিক নয়।';
      case 'FILE_NOT_FOUND':
        return 'ফাইলটি পাওয়া যায়নি।';
      case 'INVALID_ACTION':
        return 'API অনুরোধ সঠিক নয়।';
      case 'REQUEST_FAILED':
        return 'অনুরোধ সম্পন্ন হয়নি। আবার চেষ্টা করো।';
      default:
        return 'অনুরোধ সম্পন্ন হয়নি ($error)।';
    }
  }

  // --------------------------------------------------
  // INITIALIZE
  // --------------------------------------------------

  static Future<Map<String, dynamic>> initialize() async {
    return _request('initialize');
  }

  // পুরোনো কোডের সঙ্গে সামঞ্জস্য রাখার জন্য।
  // Apps Script-এর initialize ব্যক্তিগত ফোল্ডার তৈরি করে।
  static Future<String> getOrCreateMediaFolder() async {
    final result = await initialize();
    final folderId = result['personalFolderId']?.toString();

    if (folderId == null || folderId.isEmpty) {
      throw Exception('ব্যক্তিগত Drive ফোল্ডার তৈরি হয়নি।');
    }

    return folderId;
  }

  // --------------------------------------------------
  // FILE HELPERS
  // --------------------------------------------------

  static String _mimeType(String name) {
    final n = name.toLowerCase();

    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.3gp')) return 'video/3gpp';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.m4v')) return 'video/x-m4v';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    if (n.endsWith('.heic')) return 'image/heic';
    if (n.endsWith('.pdf')) return 'application/pdf';
    if (n.endsWith('.json')) return 'application/json';

    return 'image/jpeg';
  }

  static Future<Map<String, String>> _upload(
    File file, {
    required bool shared,
  }) async {
    if (!await file.exists()) {
      throw Exception('ফাইলটি এই ফোনে পাওয়া যায়নি।');
    }

    final length = await file.length();

    if (length <= 0) {
      throw Exception('ফাইলটি খালি।');
    }

    if (length > _maxUploadBytes) {
      throw Exception('ফাইলটি সার্ভারের আপলোড সীমা অতিক্রম করেছে।');
    }

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'media_${DateTime.now().millisecondsSinceEpoch}';

    final bytes = await file.readAsBytes();

    final data = <String, dynamic>{
      'name': name,
      'mimeType': _mimeType(name),
      'base64': base64Encode(bytes),
    };

    final result = await _request(
      shared ? 'uploadShared' : 'uploadPersonal',
      data: data,
      needsSpace: shared,
    );

    final fileId = result['fileId']?.toString();

    if (fileId == null || fileId.isEmpty) {
      throw Exception('আপলোড হয়েছে কি না নিশ্চিত করা যায়নি।');
    }

    // পুরোনো Chat/Gallery কোডের সঙ্গে সামঞ্জস্য রাখে।
    return {
      'fileId': fileId,
      'driveFileId': fileId,
      'driveFileName': result['name']?.toString() ?? name,
      'driveFolderId': '',
      'mimeType': result['mimeType']?.toString() ?? _mimeType(name),
      'size': result['size']?.toString() ?? '$length',
      'createdAt': result['createdAt']?.toString() ?? '',
      'storage': shared ? 'shared' : 'personal',
    };
  }

  /// Chat ও Gallery-তে ব্যবহারের জন্য shared upload।
  static Future<Map<String, String>> uploadMedia(File file) {
    return _upload(file, shared: true);
  }

  static Future<Map<String, String>> uploadSharedMedia(File file) {
    return _upload(file, shared: true);
  }

  static Future<Map<String, String>> uploadPersonalMedia(File file) {
    return _upload(file, shared: false);
  }

  // --------------------------------------------------
  // LIST FILES
  // --------------------------------------------------

  static Future<List<Map<String, dynamic>>> listSharedMedia() async {
    final result = await _request(
      'listShared',
      needsSpace: true,
    );

    final items = result['items'];

    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<List<Map<String, dynamic>>> listPersonalMedia() async {
    final result = await _request('listPersonal');

    final items = result['items'];

    if (items is! List) return [];

    return items
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  // --------------------------------------------------
  // DOWNLOAD
  // --------------------------------------------------

  static Future<String> _download({
    required String fileId,
    required bool shared,
    String? saveAs,
  }) async {
    if (fileId.trim().isEmpty) {
      throw Exception('ফাইলের ID পাওয়া যায়নি।');
    }

    final result = await _request(
      shared ? 'downloadShared' : 'downloadPersonal',
      data: {'fileId': fileId},
      needsSpace: shared,
    );

    final encoded = result['base64']?.toString() ?? '';

    if (encoded.isEmpty) {
      throw Exception('ডাউনলোড করার ফাইল পাওয়া যায়নি।');
    }

    final bytes = base64Decode(encoded);

    final directory = Directory(
      '${Directory.systemTemp.path}/eternal_space_media',
    );

    await directory.create(recursive: true);

    var safeName = (saveAs?.trim().isNotEmpty == true)
        ? saveAs!.trim()
        : (result['name']?.toString() ?? 'media_$fileId');

    safeName = safeName.replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_');

    final file = File('${directory.path}/$safeName');

    await file.writeAsBytes(bytes, flush: true);

    if (!await file.exists() || await file.length() == 0) {
      throw Exception('ডাউনলোড করা ফাইল খালি।');
    }

    return file.path;
  }

  static Future<String> downloadMedia(
    String fileId, {
    String? saveAs,
  }) {
    return _download(
      fileId: fileId,
      shared: true,
      saveAs: saveAs,
    );
  }

  static Future<String> downloadPersonalMedia(
    String fileId, {
    String? saveAs,
  }) {
    return _download(
      fileId: fileId,
      shared: false,
      saveAs: saveAs,
    );
  }

  // --------------------------------------------------
  // DELETE
  // --------------------------------------------------

  static Future<void> deleteSharedMedia(String fileId) async {
    await _request(
      'deleteShared',
      data: {'fileId': fileId},
      needsSpace: true,
    );
  }

  static Future<void> deletePersonalMedia(String fileId) async {
    await _request(
      'deletePersonal',
      data: {'fileId': fileId},
    );
  }

  // --------------------------------------------------
  // FIRESTORE APP-STATE SYNC
  // --------------------------------------------------

  static Future<DocumentReference<Map<String, dynamic>>>
      _syncDocument() async {
    final id = await _getSpaceId();

    return _db
        .collection('privateSpaces')
        .doc(id)
        .collection('syncData')
        .doc('appState');
  }

  static Future<void> uploadToFirebase(
    Map<String, dynamic> data,
  ) async {
    final ref = await _syncDocument();
    final user = await _requireUser();

    await ref.set({
      'data': data,
      'updatedBy': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<Map<String, dynamic>?> downloadFromFirebase() async {
    final snapshot = await (await _syncDocument()).get();

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

  // --------------------------------------------------
  // BACKUP
  // --------------------------------------------------

  static Future<void> backupToGoogleDrive(
    Map<String, dynamic> data,
  ) async {
    final bytes = utf8.encode(jsonEncode({
      'app': 'Eternal Space',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    }));

    if (bytes.length > _maxUploadBytes) {
      throw Exception('ব্যাকআপটি অ্যাপের নির্ধারিত সীমা অতিক্রম করেছে।');
    }

    final tempDir = await Directory.systemTemp.createTemp(
      'eternal_space_backup_',
    );

    try {
      final file = File('${tempDir.path}/EternalSpaceBackup.json');
      await file.writeAsBytes(bytes, flush: true);
      await uploadPersonalMedia(file);
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  // Apps Script API Google Drive-এর ফোল্ডার ইমেইলে শেয়ার করে না।
  // আগের method-এর নাম রেখে স্পষ্ট error দেওয়া হলো।
  static Future<void> shareMediaFolder(String email) async {
    throw UnsupportedError(
      'ইমেইল দিয়ে Drive ফোল্ডার শেয়ার বন্ধ। '
      'Eternal Space-এর shared folder ব্যবহার করো।',
    );
  }
}
