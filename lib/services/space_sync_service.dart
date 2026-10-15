import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  static const int _maxUploadBytes = 150 * 1024 * 1024;
  static const int _minChunkSize = 1 * 1024 * 1024;
  static const int _initialChunkSize = 4 * 1024 * 1024;
  static const int _maxChunkSize = 10 * 1024 * 1024;

  static const String _pendingUploadsKey = 'pendingDriveUploads';

  static Future<List<Map<String, dynamic>>> _readPendingUploads() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingUploadsKey);

    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (error) {
      debugPrint('Pending upload read error: $error');
      return [];
    }
  }

  static Future<void> _savePendingUploads(
    List<Map<String, dynamic>> uploads,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingUploadsKey, jsonEncode(uploads));
  }

  static Future<void> _upsertPendingUpload(
    Map<String, dynamic> upload,
  ) async {
    final uploads = await _readPendingUploads();
    final id = upload['id']?.toString() ?? '';

    final index = uploads.indexWhere(
      (item) => item['id']?.toString() == id,
    );

    if (index == -1) {
      uploads.add(Map<String, dynamic>.from(upload));
    } else {
      uploads[index] = {
        ...uploads[index],
        ...upload,
      };
    }

    await _savePendingUploads(uploads);
  }

  static Future<void> _removePendingUpload(String id) async {
    final uploads = await _readPendingUploads()
      ..removeWhere(
        (item) => item['id']?.toString() == id,
      );

    await _savePendingUploads(uploads);
  }

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
    required Map<String, dynamic> pending,
  }) async {
    if (!await file.exists()) {
      throw Exception('ফাইলটি এই ফোনে পাওয়া যায়নি।');
    }

    final length = await file.length();

    if (length <= 0) {
      throw Exception('ফাইলটি খালি।');
    }

    if (length > _maxUploadBytes) {
      throw Exception('একটি ফাইল সর্বোচ্চ ১৫০ MB হতে পারবে।');
    }

    final name = pending['fileName']?.toString() ??
        file.uri.pathSegments.last;
    final mime = pending['mimeType']?.toString() ?? _mimeType(name);

    final client = http.Client();

    try {
      var sessionUrl = pending['sessionUrl']?.toString() ?? '';
      var offset = 0;
      Map<String, dynamic>? uploaded;
      var retryCount = 0;

      Future<void> createSession() async {
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

        final url = session['sessionUrl']?.toString() ?? '';
        if (url.isEmpty) {
          throw Exception('Google Drive upload session তৈরি হয়নি।');
        }

        final uri = Uri.tryParse(url);
        if (uri == null ||
            uri.scheme != 'https' ||
            !(uri.host.endsWith('googleapis.com') ||
                uri.host.endsWith('googleusercontent.com'))) {
          throw Exception('Google Drive upload ঠিকানা যাচাই করা যায়নি।');
        }

        sessionUrl = url;
        offset = 0;

        pending['sessionUrl'] = sessionUrl;
        pending['offset'] = 0;
        await _upsertPendingUpload(pending);
      }

      Future<int> queryServerOffset(Uri uri) async {
        final request = http.Request('PUT', uri)
          ..followRedirects = false
          ..headers['Content-Length'] = '0'
          ..headers['Content-Range'] = 'bytes */$length';

        final streamed = await client
            .send(request)
            .timeout(const Duration(minutes: 2));

        final response = await http.Response.fromStream(streamed)
            .timeout(const Duration(minutes: 2));

        if (response.statusCode == 200 ||
            response.statusCode == 201) {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map) {
            throw Exception('Google Drive-এর চূড়ান্ত উত্তর সঠিক নয়।');
          }

          uploaded = Map<String, dynamic>.from(decoded);
          return length;
        }

        if (response.statusCode == 308) {
          final range = response.headers['range'];
          if (range == null || range.isEmpty) return 0;

          final match = RegExp(r'bytes=0-(\d+)').firstMatch(range);
          if (match == null) {
            throw Exception('আপলোডের অবস্থান যাচাই করা যায়নি।');
          }

          final confirmed = int.parse(match.group(1)!) + 1;
          if (confirmed < 0 || confirmed > length) {
            throw Exception('Google Drive-এর আপলোড অবস্থান সঠিক নয়।');
          }

          return confirmed;
        }

        if (response.statusCode == 404 ||
            response.statusCode == 410) {
          return -1;
        }

        throw Exception(
          'Google Drive-এর সেশন যাচাই ব্যর্থ হয়েছে '
          '(${response.statusCode})।',
        );
      }

      final hadSession = sessionUrl.isNotEmpty;

      if (!hadSession) {
        await createSession();
      } else {
        final oldUri = Uri.tryParse(sessionUrl);

        if (oldUri == null ||
            oldUri.scheme != 'https' ||
            !(oldUri.host.endsWith('googleapis.com') ||
                oldUri.host.endsWith('googleusercontent.com'))) {
          await createSession();
        } else {
          final confirmed = await queryServerOffset(oldUri);

          if (confirmed == -1) {
            await createSession();
          } else {
            offset = confirmed;
            pending['offset'] = offset;
            await _upsertPendingUpload(pending);
          }
        }
      }

      var currentChunkSize = _initialChunkSize;

      void adjustChunkSize(int acknowledgedBytes, int elapsedMs) {
        if (acknowledgedBytes <= 0) {
          currentChunkSize = currentChunkSize ~/ 2;
          if (currentChunkSize < _minChunkSize) {
            currentChunkSize = _minChunkSize;
          }
          return;
        }

        final safeElapsedMs = elapsedMs > 0 ? elapsedMs : 1;
        final bytesPerSecond =
            acknowledgedBytes * 1000 / safeElapsedMs;

        if (bytesPerSecond >= 2 * 1024 * 1024) {
          currentChunkSize += 2 * 1024 * 1024;
          if (currentChunkSize > _maxChunkSize) {
            currentChunkSize = _maxChunkSize;
          }
        } else if (bytesPerSecond < 512 * 1024) {
          currentChunkSize = currentChunkSize ~/ 2;
          if (currentChunkSize < _minChunkSize) {
            currentChunkSize = _minChunkSize;
          }
        }
      }

      final handle = await file.open(mode: FileMode.read);
      final clock = Stopwatch()..start();

      try {
        while (offset < length && uploaded == null) {
          final amount = (length - offset) < currentChunkSize
              ? length - offset
              : currentChunkSize;

          await handle.setPosition(offset);
          final chunk = await handle.read(amount);

          if (chunk.length != amount) {
            throw Exception('ফাইলের অংশ পড়া যায়নি।');
          }

          final chunkStartOffset = offset;
          final chunkClock = Stopwatch()..start();
          final end = offset + chunk.length - 1;

          final request = http.Request('PUT', Uri.parse(sessionUrl))
            ..followRedirects = false
            ..headers['Content-Type'] = mime
            ..headers['Content-Length'] = '${chunk.length}'
            ..headers['Content-Range'] = 'bytes $offset-$end/$length'
            ..bodyBytes = chunk;

          final streamed = await client
              .send(request)
              .timeout(const Duration(minutes: 2));

          final response = await http.Response.fromStream(streamed)
              .timeout(const Duration(minutes: 2));

          if (response.statusCode == 308) {
            final range = response.headers['range'];
            int confirmed;

            if (range == null || range.isEmpty) {
              confirmed = await queryServerOffset(Uri.parse(sessionUrl));

              if (confirmed == -1) {
                await createSession();
                retryCount = 0;
                continue;
              }
            } else {
              final match = RegExp(r'bytes=0-(\d+)').firstMatch(range);

              if (match == null) {
                throw Exception('আপলোডের অবস্থান যাচাই করা যায়নি।');
              }

              confirmed = int.parse(match.group(1)!) + 1;

              if (confirmed < 0 || confirmed > length) {
                throw Exception('Google Drive-এর আপলোড অবস্থান সঠিক নয়।');
              }
            }

            if (confirmed <= chunkStartOffset) {
              adjustChunkSize(0, chunkClock.elapsedMilliseconds);
              retryCount++;

              if (retryCount > 3) {
                throw Exception('Google Drive আপলোড এগোচ্ছে না। আবার চেষ্টা করো।');
              }
            } else {
              adjustChunkSize(
                confirmed - chunkStartOffset,
                chunkClock.elapsedMilliseconds,
              );
              offset = confirmed;
              retryCount = 0;
            }

            pending['offset'] = offset;
            await _upsertPendingUpload(pending);

            final seconds = clock.elapsedMilliseconds / 1000;
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
              throw Exception('Google Drive-এর চূড়ান্ত উত্তর সঠিক নয়।');
            }

            uploaded = Map<String, dynamic>.from(decoded);
            offset = length;
            pending['offset'] = length;
            await _upsertPendingUpload(pending);

            final seconds = clock.elapsedMilliseconds / 1000;
            _updateUpload(
              uploadId,
              progress: 1,
              bytesPerSecond: seconds > 0 ? length / seconds : 0,
            );

            break;
          }

          if (response.statusCode == 404 ||
              response.statusCode == 410) {
            await createSession();
            retryCount = 0;
            continue;
          }

          throw Exception(
            'Google Drive আপলোড ব্যর্থ হয়েছে '
            '(${response.statusCode})।',
          );
        }
      } finally {
        await handle.close();
      }

      if (uploaded == null) {
        final confirmed = await queryServerOffset(Uri.parse(sessionUrl));

        if (confirmed == -1) {
          throw Exception('Google Drive upload session শেষ হয়ে গেছে।');
        }

        if (confirmed != length) {
          throw Exception('আপলোড সম্পূর্ণ হয়েছে কি না নিশ্চিত করা যায়নি।');
        }
      }

      final fileId = uploaded?['id']?.toString();
      if (fileId == null || fileId.isEmpty) {
        throw Exception('আপলোড সম্পূর্ণ হয়েছে, কিন্তু File ID পাওয়া যায়নি।');
      }

      final result = <String, String>{
        'fileId': fileId,
        'driveFileId': fileId,
        'driveFileName': uploaded?['name']?.toString() ?? name,
        'driveFolderId': '',
        'mimeType': uploaded?['mimeType']?.toString() ?? mime,
        'size': uploaded?['size']?.toString() ?? '$length',
        'createdAt': uploaded?['createdTime']?.toString() ?? '',
        'storage': shared ? 'shared' : 'personal',
        '_uploadTaskId': uploadId,
      };

      pending['status'] = 'completed';
      pending['result'] = result;
      pending['offset'] = length;
      await _upsertPendingUpload(pending);

      return result;
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
    Map<String, dynamic>? metadata,
  }) async {
    final id = '${DateTime.now().microsecondsSinceEpoch}_${uploadProgress.value.length}';

    if (!await file.exists()) {
      throw Exception('আপলোড করার ফাইলটি পাওয়া যায়নি।');
    }

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'media';

    final length = await file.length();
    if (length <= 0) throw Exception('ফাইলটি খালি।');
    if (length > _maxUploadBytes) {
      throw Exception('একটি ফাইল সর্বোচ্চ ৩০ MB হতে পারবে।');
    }

    final support = await getApplicationSupportDirectory();
    final pendingDir = Directory('${support.path}/pending_drive_uploads');
    await pendingDir.create(recursive: true);

    final safeName = name.replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_');
    final durableFile = File('${pendingDir.path}/${id}_$safeName');

    await file.copy(durableFile.path);

    final pending = <String, dynamic>{
      'id': id,
      'filePath': durableFile.path,
      'fileName': safeName,
      'shared': shared,
      'size': length,
      'mimeType': _mimeType(safeName),
      'sessionUrl': '',
      'offset': 0,
      'status': 'uploading',
      'metadata': metadata ?? <String, dynamic>{},
      'createdAt': DateTime.now().toIso8601String(),
    };

    await _upsertPendingUpload(pending);

    uploadProgress.value = [
      ...uploadProgress.value,
      UploadProgress(
        id: id,
        fileName: safeName,
        progress: 0,
        bytesPerSecond: 0,
        isUploading: true,
      ),
    ];

    try {
      return await _uploadFile(
        durableFile,
        shared: shared,
        uploadId: id,
        pending: pending,
      );
    } finally {
      _updateUpload(id, isUploading: false);
      _removeUpload(id);
    }
  }

  static Future<Map<String, String>> uploadMedia(File file) =>
      _upload(file, shared: true);

  static Future<Map<String, String>> uploadSharedMedia(
    File file, {
    Map<String, dynamic>? metadata,
  }) =>
      _upload(
        file,
        shared: true,
        metadata: metadata,
      );

  static Future<Map<String, String>> uploadPersonalMedia(File file) =>
      _upload(file, shared: false);

  static Future<List<Map<String, dynamic>>> getPendingUploads() =>
      _readPendingUploads();

  static Future<void> acknowledgeUpload(String id) async {
    final uploads = await _readPendingUploads();
    final matches = uploads.where(
      (item) => item['id']?.toString() == id,
    );

    for (final item in matches) {
      final path = item['filePath']?.toString() ?? '';
      if (path.isNotEmpty) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (error) {
          debugPrint('Pending upload cleanup error: $error');
        }
      }
    }

    await _removePendingUpload(id);
  }

  static Future<void> resumePendingUploads() async {
    final uploads = await _readPendingUploads();

    for (final item in uploads) {
      if (item['status'] == 'completed') continue;

      final id = item['id']?.toString() ?? '';
      final path = item['filePath']?.toString() ?? '';
      if (id.isEmpty || path.isEmpty) continue;

      final file = File(path);
      if (!await file.exists()) {
        debugPrint('Pending upload file missing: $path');
        continue;
      }

      final shared = item['shared'] == true;
      final name = item['fileName']?.toString() ?? 'media';

      uploadProgress.value = [
        ...uploadProgress.value.where((u) => u.id != id),
        UploadProgress(
          id: id,
          fileName: name,
          progress: (item['offset'] is num &&
                  (item['size'] is num) &&
                  (item['size'] as num) > 0)
              ? ((item['offset'] as num) / (item['size'] as num))
                  .clamp(0.0, 1.0)
                  .toDouble()
              : 0,
          bytesPerSecond: 0,
          isUploading: true,
        ),
      ];

      try {
        await _uploadFile(
          file,
          shared: shared,
          uploadId: id,
          pending: item,
        );
      } catch (error) {
        debugPrint('Resume upload failed ($id): $error');
      } finally {
        _updateUpload(id, isUploading: false);
        _removeUpload(id);
      }
    }
  }

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
