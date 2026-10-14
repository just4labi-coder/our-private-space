import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'private_space_service.dart';

class UploadProgress {
  final String id;
  final String fileName;
  final double progress;
  final double bytesPerSecond;
  final bool isUploading;

  const UploadProgress({
    required this.id,
    required this.fileName,
    required this.progress,
    required this.bytesPerSecond,
    required this.isUploading,
  });

  UploadProgress copyWith({
    double? progress,
    double? bytesPerSecond,
    bool? isUploading,
  }) {
    return UploadProgress(
      id: id,
      fileName: fileName,
      progress: progress ?? this.progress,
      bytesPerSecond: bytesPerSecond ?? this.bytesPerSecond,
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

class SpaceSyncService {
  SpaceSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _apiUrl =
      'https://script.google.com/macros/s/AKfycbw5JDObuu19_VQQ1ytXsA2Bav2M_szPSoiARCrc5KvNZYKm-RoDr1lwUiy14s3nsnzSoQ/exec';

  static const int _maxUploadBytes = 30 * 1024 * 1024;
  static const int _chunkSize = 1024 * 1024;

  static final ValueNotifier<List<UploadProgress>> uploadProgress =
      ValueNotifier<List<UploadProgress>>([]);

  static void _updateUpload(
    String id, {
    double? progress,
    double? bytesPerSecond,
    bool? isUploading,
  }) {
    uploadProgress.value = [
      for (final item in uploadProgress.value)
        if (item.id == id)
          item.copyWith(
            progress: progress,
            bytesPerSecond: bytesPerSecond,
            isUploading: isUploading,
          )
        else
          item,
    ];
  }

  static void _removeUpload(String id) {
    uploadProgress.value = [
      for (final item in uploadProgress.value)
        if (item.id != id) item,
    ];
  }

  static final Map<String, Future<String>> _activeDownloads = {};

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
    final token = await (await _requireUser()).getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Firebase পরিচয় যাচাই করা যায়নি।');
    }
    return token;
  }

  static Future<Map<String, dynamic>> _request(
    String action, {
    Map<String, dynamic> data = const {},
    bool needsSpace = false,
  }) async {
    final payload = <String, dynamic>{
      'action': action,
      'idToken': await _getIdToken(),
      ...data,
    };

    if (needsSpace && !payload.containsKey('spaceId')) {
      payload['spaceId'] = await _getSpaceId();
    }

    final client = http.Client();

    try {
      final request = http.Request('POST', Uri.parse(_apiUrl))
        ..followRedirects = false
        ..headers['Content-Type'] = 'application/json'
        ..headers['Accept'] = 'application/json'
        ..body = jsonEncode(payload);

      var response = await client
          .send(request)
          .timeout(const Duration(seconds: 90));

      var result = await http.Response.fromStream(response)
          .timeout(const Duration(seconds: 90));

      if ([301, 302, 303, 307, 308].contains(result.statusCode)) {
        final location = result.headers['location'];
        if (location == null) {
          throw Exception('সার্ভারের Redirect ঠিকানা পাওয়া যায়নি।');
        }

        final uri = Uri.parse(location);
        if (uri.scheme != 'https' ||
            !uri.host.endsWith('googleusercontent.com')) {
          throw Exception('সার্ভারের Redirect ঠিকানা নিরাপদ নয়।');
        }

        result = await client.get(uri).timeout(
              const Duration(seconds: 90),
            );
      }

      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw Exception('সার্ভার ত্রুটি: ${result.statusCode}');
      }

      final decoded = jsonDecode(result.body);
      if (decoded is! Map) {
        throw Exception('সার্ভারের উত্তর সঠিক নয়।');
      }

      if (decoded['ok'] != true) {
        throw Exception(_errorMessage(
          decoded['error']?.toString() ?? 'REQUEST_FAILED',
        ));
      }

      final dataResult = decoded['data'];
      if (dataResult is Map) {
        return Map<String, dynamic>.from(dataResult);
      }

      return {};
    } on TimeoutException {
      throw Exception('সার্ভারে উত্তর পেতে দেরি হচ্ছে। আবার চেষ্টা করো।');
    } finally {
      client.close();
    }
  }

  static String _errorMessage(String error) {
    switch (error) {
      case 'AUTH_REQUIRED':
        return 'সাইন-ইন প্রয়োজন।';
      case 'AUTH_INVALID':
        return 'সাইন-ইন যাচাই ব্যর্থ হয়েছে। আবার চেষ্টা করো।';
      case 'SPACE_ACCESS_DENIED':
        return 'এই Private Space ব্যবহারের অনুমতি নেই।';
      case 'SPACE_DISCONNECTED':
        return 'Partner Connection বিচ্ছিন্ন।';
      case 'INVALID_SPACE_ID':
        return 'Private Space ID সঠিক নয়।';
      case 'FILE_DATA_REQUIRED':
        return 'আপলোড করার ফাইল পাওয়া যায়নি।';
      case 'FILE_TOO_LARGE':
        return 'ফাইলটি ৩০ MB সীমা অতিক্রম করেছে।';
      case 'DOWNLOAD_TOO_LARGE':
        return 'ফাইলটি বর্তমান ডাউনলোড সীমার চেয়ে বড়।';
      case 'INVALID_FILE_ID':
        return 'ফাইলের ID সঠিক নয়।';
      case 'FILE_NOT_FOUND':
        return 'ফাইলটি পাওয়া যায়নি।';
      case 'INVALID_ACTION':
        return 'API অনুরোধ সঠিক নয়।';
      default:
        return error;
    }
  }

  static Future<Map<String, dynamic>> initialize() async {
    return _request('initialize');
  }

  static Future<String> getOrCreateMediaFolder() async {
    final result = await initialize();
    final id = result['personalFolderId']?.toString();

    if (id == null || id.isEmpty) {
      throw Exception('ব্যক্তিগত Drive ফোল্ডার পাওয়া যায়নি।');
    }
    return id;
  }

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

  static Future<Map<String, String>> _uploadFile(
    File file, {
    required bool shared,
    required String uploadId,
  }) async {
    if (!await file.exists()) {
      throw Exception('ফাইলটি এই ফোনে পাওয়া যায়নি।');
    }

    final length = await file.length();

    if (length <= 0) {
      throw Exception('ফাইলটি খালি।');
    }

    if (length > _maxUploadBytes) {
      throw Exception('একটি ফাইল সর্বোচ্চ ৩০ MB হতে পারবে।');
    }

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'media_${DateTime.now().millisecondsSinceEpoch}';

    final mime = _mimeType(name);

    final session = await _request(
      shared ? 'beginUploadShared' : 'beginUploadPersonal',
      data: {
        'name': name,
        'mimeType': mime,
        'size': length,
        'folderId': 'all',
      },
      needsSpace: shared,
    );

    final sessionUrl = session['sessionUrl']?.toString() ?? '';

    if (sessionUrl.isEmpty) {
      throw Exception('Google Drive upload session তৈরি হয়নি।');
    }

    final uri = Uri.parse(sessionUrl);

    if (uri.scheme != 'https' ||
        !(uri.host.endsWith('googleapis.com') ||
            uri.host.endsWith('googleusercontent.com'))) {
      throw Exception('Google Drive upload ঠিকানা যাচাই করা যায়নি।');
    }

    final client = http.Client();

    try {
      final handle = await file.open(mode: FileMode.read);

      var offset = 0;
      Map<String, dynamic>? uploaded;
      var retryCount = 0;
      final uploadClock = Stopwatch()..start();

      try {
        while (offset < length) {
          final remaining = length - offset;
          final amount =
              remaining < _chunkSize ? remaining : _chunkSize;

          await handle.setPosition(offset);
          final chunk = await handle.read(amount);

          if (chunk.length != amount) {
            throw Exception('ফাইলের অংশ পড়া যায়নি।');
          }

          final end = offset + chunk.length - 1;

          final request = http.Request('PUT', uri)
            ..followRedirects = false
            ..headers['Content-Type'] = mime
            ..headers['Content-Length'] = '${chunk.length}'
            ..headers['Content-Range'] =
                'bytes $offset-$end/$length'
            ..bodyBytes = chunk;

          final streamed = await client
              .send(request)
              .timeout(const Duration(minutes: 2));

          final response = await http.Response.fromStream(streamed)
              .timeout(const Duration(minutes: 2));

          if (response.statusCode == 308) {
            final range = response.headers['range'];

            if (range == null || range.isEmpty) {
              retryCount++;

              if (retryCount > 3) {
                throw Exception(
                  'Google Drive আপলোড এগোচ্ছে না। আবার চেষ্টা করো।',
                );
              }

              continue;
            }

            final match =
                RegExp(r'bytes=0-(\d+)').firstMatch(range);

            if (match == null) {
              throw Exception(
                'Google Drive-এর আপলোড অগ্রগতি যাচাই করা যায়নি।',
              );
            }

            final lastReceived = int.parse(match.group(1)!);
            final nextOffset = lastReceived + 1;

            if (nextOffset <= offset || nextOffset > length) {
              throw Exception(
                'Google Drive-এর আপলোড অবস্থান সঠিক নয়।',
              );
            }

            offset = nextOffset;
            retryCount = 0;

            final seconds = uploadClock.elapsedMilliseconds / 1000;
            _updateUpload(
              uploadId,
              progress: offset / length,
              bytesPerSecond: seconds > 0 ? offset / seconds : 0,
            );

            continue;
          }

          if (response.statusCode == 200 ||
              response.statusCode == 201) {
            final decoded = jsonDecode(response.body);

            if (decoded is! Map) {
              throw Exception(
                'Google Drive-এর চূড়ান্ত উত্তর সঠিক নয়।',
              );
            }

            uploaded = Map<String, dynamic>.from(decoded);
            offset = length;

            final seconds = uploadClock.elapsedMilliseconds / 1000;
            _updateUpload(
              uploadId,
              progress: 1,
              bytesPerSecond: seconds > 0 ? length / seconds : 0,
            );

            break;
          }

          throw Exception(
            'Google Drive আপলোড ব্যর্থ হয়েছে '
            '(${response.statusCode})।',
          );
        }
      } finally {
        await handle.close();
      }

      final fileId = uploaded?['id']?.toString();

      if (fileId == null || fileId.isEmpty) {
        throw Exception(
          'আপলোড সম্পূর্ণ হয়েছে কি না নিশ্চিত করা যায়নি।',
        );
      }

      return {
        'fileId': fileId,
        'driveFileId': fileId,
        'driveFileName': uploaded?['name']?.toString() ?? name,
        'driveFolderId': '',
        'mimeType': uploaded?['mimeType']?.toString() ?? mime,
        'size': uploaded?['size']?.toString() ?? '$length',
        'createdAt': uploaded?['createdTime']?.toString() ?? '',
        'storage': shared ? 'shared' : 'personal',
      };
    } on TimeoutException {
      throw Exception(
        'আপলোডে সময় বেশি লাগছে। ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করো।',
      );
    } finally {
      client.close();
    }
  }

  static Future<Map<String, String>> _upload(
    File file, {
    required bool shared,
  }) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString() +
        '_${uploadProgress.value.length}';

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'media';

    uploadProgress.value = [
      ...uploadProgress.value,
      UploadProgress(
        id: id,
        fileName: name,
        progress: 0,
        bytesPerSecond: 0,
        isUploading: true,
      ),
    ];

    try {
      return await _uploadFile(
        file,
        shared: shared,
        uploadId: id,
      );
    } finally {
      _updateUpload(id, isUploading: false);
      _removeUpload(id);
    }
  }

  static Future<Map<String, String>> uploadMedia(File file) =>
      _upload(file, shared: true);

  static Future<Map<String, String>> uploadSharedMedia(File file) =>
      _upload(file, shared: true);

  static Future<Map<String, String>> uploadPersonalMedia(File file) =>
      _upload(file, shared: false);

  static Future<List<Map<String, dynamic>>> listSharedMedia() async {
    final result = await _request('listShared', needsSpace: true);
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

  static Future<String> _download({
    required String fileId,
    required bool shared,
    String? saveAs,
  }) async {
    final id = fileId.trim();
    if (id.isEmpty) {
      throw Exception('ফাইলের ID পাওয়া যায়নি।');
    }

    final key = '${shared ? 'shared' : 'personal'}:$id';

    final active = _activeDownloads[key];
    if (active != null) {
      return active;
    }

    final future = _downloadAndCache(
      fileId: id,
      shared: shared,
      saveAs: saveAs,
    );

    _activeDownloads[key] = future;

    try {
      return await future;
    } finally {
      if (identical(_activeDownloads[key], future)) {
        _activeDownloads.remove(key);
      }
    }
  }

  static Future<String> _downloadAndCache({
    required String fileId,
    required bool shared,
    String? saveAs,
  }) async {
    final safeId = fileId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final prefix = 'media_${shared ? 'shared' : 'personal'}_${safeId}__';

    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      '${supportDirectory.path}/eternal_space_media',
    );
    await directory.create(recursive: true);

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix)) continue;

      try {
        if (await entity.exists() && await entity.length() > 0) {
          return entity.path;
        }
        await entity.delete();
      } catch (_) {}
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
    if (bytes.isEmpty) {
      throw Exception('ডাউনলোড করা ফাইল খালি।');
    }

    var name = saveAs?.trim().isNotEmpty == true
        ? saveAs!.trim()
        : (result['name']?.toString() ?? 'media_$fileId');

    name = name.replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_');

    final lastDot = name.lastIndexOf('.');
    var extension = '';
    if (lastDot > 0 && name.length - lastDot <= 10) {
      extension = name.substring(lastDot).toLowerCase();
    }

    final file = File('${directory.path}/$prefix$extension');
    await file.writeAsBytes(bytes, flush: true);

    if (!await file.exists() || await file.length() == 0) {
      throw Exception('ডাউনলোড করা ফাইল সংরক্ষণ করা যায়নি।');
    }

    return file.path;
  }

  static Future<String> downloadMedia(
    String fileId, {
    String? saveAs,
  }) =>
      _download(fileId: fileId, shared: true, saveAs: saveAs);

  static Future<String> downloadPersonalMedia(
    String fileId, {
    String? saveAs,
  }) =>
      _download(fileId: fileId, shared: false, saveAs: saveAs);

  static Future<void> _clearCachedMedia(
    String fileId, {
    required bool shared,
  }) async {
    final id = fileId.trim();
    if (id.isEmpty) return;

    final safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final prefix = 'media_${shared ? 'shared' : 'personal'}_${safeId}__';

    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory(
      '${supportDirectory.path}/eternal_space_media',
    );

    if (!await directory.exists()) return;

    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith(prefix)) continue;

      try {
        await entity.delete();
      } catch (error) {
        debugPrint('Media cache delete error: $error');
      }
    }
  }

  static Future<void> deleteSharedMedia(String fileId) async {
    await _request(
      'deleteShared',
      data: {'fileId': fileId},
      needsSpace: true,
    );
    await _clearCachedMedia(fileId, shared: true);
  }

  static Future<void> deletePersonalMedia(String fileId) async {
    await _request(
      'deletePersonal',
      data: {'fileId': fileId},
    );
    await _clearCachedMedia(fileId, shared: false);
  }

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

  static Future<Stream<Map<String, dynamic>?>> watchFirebaseData() async {
    final ref = await _syncDocument();

    return ref.snapshots().map((snapshot) {
      final data = snapshot.data()?['data'];
      if (data is! Map) return null;

      return Map<String, dynamic>.from(data);
    });
  }

  static Future<void> backupToGoogleDrive(
    Map<String, dynamic> data,
  ) async {
    final bytes = utf8.encode(jsonEncode({
      'app': 'Eternal Space',
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'data': data,
    }));

    if (bytes.length > _maxUploadBytes) {
      throw Exception('ব্যাকআপটি ৩০ MB সীমা অতিক্রম করেছে।');
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

  static Future<void> shareMediaFolder(String email) async {
    throw UnsupportedError(
      'ইমেইল দিয়ে Drive ফোল্ডার শেয়ার বন্ধ। '
      'Eternal Space-এর shared folder ব্যবহার করো।',
    );
  }
}
