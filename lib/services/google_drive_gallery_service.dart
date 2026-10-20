
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GoogleDriveGalleryService {
  GoogleDriveGalleryService._();

  static const String _endpoint =
      'https://script.google.com/macros/s/AKfycbw5JDObuu19_VQQ1ytXsA2Bav2M_szPSoiARCrc5KvNZYKm-RoDr1lwUiy14s3nsnzSoQ/exec';

  static const int maxFileSize = 30 * 1024 * 1024;

  static Future<Map<String, dynamic>> _request(
    Map<String, dynamic> data,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('গ্যালারি ব্যবহার করতে আগে অ্যাকাউন্টে প্রবেশ করুন।');
    }

    final prefs = await SharedPreferences.getInstance();
    final spaceId = prefs.getString('eternal_space_id');

    if (spaceId == null || spaceId.isEmpty) {
      throw Exception('আগে Partner Connection সম্পন্ন করো।');
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('অ্যাকাউন্ট যাচাই করা যায়নি। আবার প্রবেশ করে চেষ্টা করুন।');
    }

    final payload = <String, dynamic>{
      ...data,
      'idToken': token,
      'spaceId': spaceId,
    };

    final response = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 120));

    Map<String, dynamic> result;

    try {
      result = Map<String, dynamic>.from(
        jsonDecode(response.body) as Map,
      );
    } catch (_) {
      throw Exception(
        'সার্ভারের উত্তর পড়া যায়নি। '
        'Web App deployment ও URL পরীক্ষা করো। '
        'HTTP: ${response.statusCode}',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw Exception(
        'সার্ভার অনুরোধ গ্রহণ করেনি: ${response.statusCode}',
      );
    }

    if (result['ok'] != true) {
      throw Exception(
        result['error']?.toString() ?? 'অনুরোধ ব্যর্থ হয়েছে।',
      );
    }

    return result;
  }

  static String _mimeType(String path) {
    final name = path.toLowerCase();

    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.heic')) return 'image/heic';
    if (name.endsWith('.mp4')) return 'video/mp4';
    if (name.endsWith('.mov')) return 'video/quicktime';
    if (name.endsWith('.3gp')) return 'video/3gpp';
    if (name.endsWith('.mkv')) return 'video/x-matroska';

    return 'application/octet-stream';
  }

  static Future<Map<String, dynamic>> uploadFile({
    required String path,
    required String folderId,
    String? fileName,
  }) async {
    final file = File(path);

    if (!await file.exists()) {
      throw Exception('নির্বাচিত ফাইলটি ফোনে পাওয়া যায়নি।');
    }

    final size = await file.length();

    if (size == 0) {
      throw Exception('ফাইলটি খালি।');
    }

    if (size > maxFileSize) {
      throw Exception('একটি ফাইল সর্বোচ্চ ৩০ MB হতে পারবে।');
    }

    final bytes = await file.readAsBytes();
    final name = fileName ??
        file.uri.pathSegments.last;

    return _request({
      'action': 'upload',
      'fileName': name,
      'mimeType': _mimeType(name),
      'folderId': folderId,
      'base64Data': base64Encode(bytes),
    });
  }

  static Future<List<Map<String, dynamic>>> listFiles() async {
    final result = await _request({
      'action': 'list',
    });

    final files = result['files'];

    if (files is! List) return [];

    return files
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  static Future<Uint8List> downloadFile(String fileId) async {
    final result = await _request({
      'action': 'download',
      'fileId': fileId,
    });

    final file = Map<String, dynamic>.from(result['file'] as Map);
    final encoded = file['base64Data']?.toString();

    if (encoded == null || encoded.isEmpty) {
      throw Exception('ডাউনলোড করা ফাইলের ডেটা পাওয়া যায়নি।');
    }

    return base64Decode(encoded);
  }

  static Future<void> deleteFile(String fileId) async {
    await _request({
      'action': 'delete',
      'fileId': fileId,
    });
  }
}
