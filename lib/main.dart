import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'screens/partner_connection_page.dart';
import 'services/space_sync_service.dart';
import 'services/chat_sync_service.dart';
import 'screens/auth_screen.dart';
import 'services/relationship_service.dart';
import 'services/private_space_service.dart';

const Color backgroundColor = Color(0xFF070513);
const Color surfaceColor = Color(0xFF111026);
const Color blueColor = Color(0xFF172554);
const Color pinkColor = Color(0xFFFF2E93);
const Color purpleColor = Color(0xFF8B5CF6);

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  await DataSaverSettings.load();

  tz_data.initializeTimeZones();

  const androidSettings =
      AndroidInitializationSettings('@android:drawable/sym_def_app_icon');

  const initializationSettings = InitializationSettings(
    android: androidSettings,
  );

  await notifications.initialize(initializationSettings);
  await SpaceStore.init();

  runApp(const EternalSpaceApp());
}

class DataSaverSettings {
  DataSaverSettings._();

  static const String _key = 'dataSaverEnabled';

  static final ValueNotifier<bool> enabled =
      ValueNotifier<bool>(false);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_key) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_key, value);
    enabled.value = value;
  }
}

class FirebaseServices {
  static final auth = FirebaseAuth.instance;
  static final firestore = FirebaseFirestore.instance;

  static User? get currentUser => auth.currentUser;

  static Future<void> saveUserProfile({
    required String name,
  }) async {
    final user = auth.currentUser;
    if (user == null) return;

    await firestore.collection('users').doc(user.uid).set({
      'name': name,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

class EternalSpaceApp extends StatelessWidget {
  const EternalSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Couple Zone',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: blueColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.055),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============================================================
// LOCAL STORAGE WITH FIREBASE SYNC
// ============================================================

class SpaceStore {
  static SharedPreferences? _prefs;
  static StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _syncSubscription;

  static final ValueNotifier<int> syncVersion = ValueNotifier<int>(0);
  static bool _applyingRemoteData = false;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static List<Map<String, dynamic>> readList(String key) {
    final raw = _prefs?.getString(key);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveList(
    String key,
    List<Map<String, dynamic>> value,
  ) async {
    await init();
    await _prefs!.setString(key, jsonEncode(value));
    syncVersion.value++;

    if (!_applyingRemoteData) {
      await _syncKey(key, value);
    }
  }

  static String readString(String key, [String fallback = '']) {
    return _prefs?.getString(key) ?? fallback;
  }

  static Future<void> saveString(String key, String value) async {
    await init();
    await _prefs!.setString(key, value);
    syncVersion.value++;

    if (!_applyingRemoteData) {
      await _syncKey(key, value);
    }
  }

  static Future<String?> _getSpaceId() async {
    return PrivateSpaceService.getSavedSpaceId();
  }

  static Future<String?> _getConnectedSpaceId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final spaceId = await _getSpaceId();
    if (spaceId == null || spaceId.isEmpty) return null;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('privateSpaces')
          .doc(spaceId)
          .get();

      if (!snapshot.exists) return null;

      final data = snapshot.data();
      if (data == null) return null;

      final members = data['memberUids'];

      if (members is! List ||
          members.length != 2 ||
          !members.contains(user.uid)) {
        return null;
      }

      final status = data['connectionStatus'] ?? 'connected';
      if (status != 'connected') return null;

      return spaceId;
    } catch (e) {
      debugPrint('Connection check error: $e');
      return null;
    }
  }

  static Future<void> _syncKey(String key, dynamic value) async {
    if (key == 'partnerOne' || key == 'partnerTwo') return;
    if (_applyingRemoteData) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final spaceId = await _getConnectedSpaceId();
      if (spaceId == null) return;

      await FirebaseFirestore.instance
          .collection('privateSpaces')
          .doc(spaceId)
          .collection('syncData')
          .doc('appState')
          .set({
        key: value,
        'updatedBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firebase sync error: $e');
    }
  }

  static Future<void> syncAllToFirebase() async {
    final spaceId = await _getConnectedSpaceId();
    if (spaceId == null) return;

    await init();

    final data = <String, dynamic>{
      'chatMessages': readList('chatMessages'),
      'loveNotes': readList('loveNotes'),
      'specialDates': readList('specialDates'),
      'spaceComplaints': readList('spaceComplaints'),
      'galleryFolders': readList('galleryFolders'),
      'galleryMedia': readList('galleryMedia'),
    };

    for (final entry in data.entries) {
      if (await _getConnectedSpaceId() != spaceId) return;
      await _syncKey(entry.key, entry.value);
    }
  }

  static Future<void> syncFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final spaceId = await _getConnectedSpaceId();
      if (spaceId == null) return;

      final snapshot = await FirebaseFirestore.instance
          .collection('privateSpaces')
          .doc(spaceId)
          .collection('syncData')
          .doc('appState')
          .get();

      if (await _getConnectedSpaceId() != spaceId) return;
      if (!snapshot.exists) return;
      await _applyRemoteData(snapshot.data());
    } catch (e) {
      debugPrint('Firebase download error: $e');
    }
  }

  static Future<void> _applyRemoteData(
    Map<String, dynamic>? data,
  ) async {
    if (data == null) return;

    await init();
    _applyingRemoteData = true;

    try {
      for (final entry in data.entries) {
        final value = entry.value;

        if (entry.key == 'partnerOne' ||
            entry.key == 'partnerTwo') {
          continue;
        }

        if (entry.key == 'galleryMedia' && value is List) {
          final safeMedia = value.whereType<Map>().map((rawItem) {
            final item = Map<String, dynamic>.from(rawItem);
            item.remove('path');
            return item;
          }).toList();

          await _prefs!.setString(entry.key, jsonEncode(safeMedia));
          continue;
        }

        if (entry.key == 'updatedBy' ||
            entry.key == 'updatedAt') {
          continue;
        }

        if (value is List) {
          await _prefs!.setString(entry.key, jsonEncode(value));
        } else if (value is String) {
          await _prefs!.setString(entry.key, value);
        }
      }

      syncVersion.value++;
    } finally {
      _applyingRemoteData = false;
    }
  }

  static Future<void> startRealtimeSync() async {
    await stopRealtimeSync();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final spaceId = await _getConnectedSpaceId();
    if (spaceId == null) return;

    final reference = FirebaseFirestore.instance
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('syncData')
        .doc('appState');

    _syncSubscription = reference.snapshots().listen(
      (snapshot) async {
        final activeSpaceId = await _getConnectedSpaceId();
        if (activeSpaceId != spaceId) {
          await stopRealtimeSync();
          return;
        }

        if (!snapshot.exists) return;

        final data = snapshot.data();
        if (data == null) return;
        if (data['updatedBy'] == user.uid) return;

        await _applyRemoteData(data);
      },
      onError: (Object error) {
        debugPrint('Realtime sync error: $error');
      },
    );
  }

  static Future<void> stopRealtimeSync() async {
    await _syncSubscription?.cancel();
    _syncSubscription = null;
  }
}

// ============================================================
// SPLASH SCREEN
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await SpaceStore.init();
    await Future.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;

    if (user != null) {
      try {
        await SpaceStore.syncFromFirebase();
      } catch (error) {
        debugPrint('Startup sync error: $error');
      }

      try {
        await SpaceStore.startRealtimeSync();
      } catch (error) {
        debugPrint('Startup realtime sync error: $error');
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MainScreen(),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AuthScreen(
            onSuccess: () async {
              rootNavigatorKey.currentState?.pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const MainScreen(),
                ),
                (route) => false,
              );

              try {
                await SpaceStore.syncFromFirebase();
              } catch (error) {
                debugPrint('Login sync error: $error');
              }

              try {
                await SpaceStore.startRealtimeSync();
              } catch (error) {
                debugPrint('Login realtime sync error: $error');
              }
            },
            onTrial: () async {},
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: GlowBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.favorite_rounded, size: 64, color: pinkColor),
              SizedBox(height: 18),
              Text(
                'Couple Zone',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'A little universe for two',
                style: TextStyle(color: Colors.white60),
              ),
              SizedBox(height: 28),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class GlowBackground extends StatefulWidget {
  final Widget child;

  const GlowBackground({
    super.key,
    required this.child,
  });

  @override
  State<GlowBackground> createState() => _GlowBackgroundState();
}

class _GlowBackgroundState extends State<GlowBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color,
              color.withValues(alpha: 0.55),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.38, 1.0],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070513),
            Color(0xFF10071D),
            Color(0xFF190D2C),
            Color(0xFF070513),
          ],
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final phase = _controller.value * 2 * pi;
          final waveA = sin(phase);
          final waveB = cos(phase);
          final waveC = sin(phase + 1.7);

          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: -125 + (waveA * 42),
                left: -115 + (waveB * 48),
                child: _glow(
                  340,
                  const Color(0xFF8B1D62).withValues(alpha: 0.34),
                ),
              ),
              Positioned(
                bottom: -145 + (waveB * 45),
                right: -120 + (waveC * 55),
                child: _glow(
                  370,
                  const Color(0xFF6826A8).withValues(alpha: 0.34),
                ),
              ),
              Positioned(
                top: 210 + (waveC * 95),
                right: -165 + (waveA * 55),
                child: _glow(
                  310,
                  const Color(0xFFB51E72).withValues(alpha: 0.22),
                ),
              ),
              Positioned(
                bottom: 70 + (waveA * 75),
                left: -175 + (waveC * 65),
                child: _glow(
                  300,
                  const Color(0xFF5424B8).withValues(alpha: 0.24),
                ),
              ),
              SafeArea(
                child: widget.child,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// UPLOAD FLOATING INDICATOR
// ============================================================

class UploadFloatingIndicator extends StatelessWidget {
  const UploadFloatingIndicator({super.key});

  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  IconData _fileIcon(String fileName) {
    final name = fileName.toLowerCase();

    if (name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.mkv') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi')) {
      return Icons.videocam_rounded;
    }

    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp') ||
        name.endsWith('.gif') ||
        name.endsWith('.heic')) {
      return Icons.image_rounded;
    }

    return Icons.upload_file_rounded;
  }

  void _showUploadDetails(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ValueListenableBuilder<List<UploadProgress>>(
              valueListenable: SpaceSyncService.uploadProgress,
              builder: (context, uploads, _) {
                final activeUploads = uploads
                    .where((upload) => upload.isUploading)
                    .toList();

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(
                          Icons.cloud_upload_rounded,
                          color: pinkColor,
                          size: 25,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ফাইল আপলোড হচ্ছে (${activeUploads.length})',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    if (activeUploads.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'এখন কোনো ফাইল আপলোড হচ্ছে না।',
                          style: TextStyle(color: Colors.white70),
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const ClampingScrollPhysics(),
                          itemCount: activeUploads.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 14),
                          itemBuilder: (context, index) {
                            final upload = activeUploads[index];
                            final progress =
                                upload.progress.clamp(0.0, 1.0);

                            return Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: purpleColor.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    _fileIcon(upload.fileName),
                                    color: pinkColor,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        upload.fileName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        _formatSpeed(upload.bytesPerSecond),
                                        style: const TextStyle(
                                          color: Colors.white60,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                SizedBox(
                                  width: 46,
                                  height: 46,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: CircularProgressIndicator(
                                          value: progress,
                                          strokeWidth: 4,
                                          backgroundColor: Colors.white12,
                                          valueColor:
                                              const AlwaysStoppedAnimation<
                                                  Color>(pinkColor),
                                        ),
                                      ),
                                      Text(
                                        '${(progress * 100).round()}%',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<UploadProgress>>(
      valueListenable: SpaceSyncService.uploadProgress,
      builder: (context, uploads, _) {
        final count =
            uploads.where((upload) => upload.isUploading).length;

        if (count == 0) {
          return const SizedBox.shrink();
        }

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showUploadDetails(context),
            customBorder: const CircleBorder(),
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: surfaceColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: pinkColor.withValues(alpha: 0.8),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: pinkColor.withValues(alpha: 0.25),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(
                    Icons.cloud_upload_rounded,
                    color: Colors.white,
                    size: 27,
                  ),
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 23,
                        minHeight: 23,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: pinkColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// MAIN SCREEN AND NAVIGATION
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver {
  int selectedIndex = 0;
  String partnerOne = '';
  String partnerTwo = '';
  bool hasUnreadChat = false;

  StreamSubscription<List<Map<String, dynamic>>>? _unreadSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _connectionSubscription;
  String? _watchedSpaceId;
  bool _connectionSyncBusy = false;
  bool _connectionSyncReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadPartnerNames();
    _startUnreadWatcher();
    _updatePresence(true);
    _startConnectionWatcher();
    _recoverPendingUploads();
  }

  Future<void> _recoverPendingUploads() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await SpaceSyncService.resumePendingUploads();

      final pending = await SpaceSyncService.getPendingUploads();

      for (final task in pending) {
        if (task['status'] != 'completed') continue;

        final taskId = '${task['id'] ?? ''}';
        final rawMetadata = task['metadata'];
        final rawResult = task['result'];

        if (taskId.isEmpty ||
            rawMetadata is! Map ||
            rawResult is! Map) {
          continue;
        }

        final metadata = Map<String, dynamic>.from(rawMetadata);
        final uploaded = Map<String, dynamic>.from(rawResult);

        if ('${metadata['senderUid'] ?? ''}' != user.uid &&
            metadata['purpose'] == 'chat') {
          continue;
        }

        final fileId =
            '${uploaded['fileId'] ?? uploaded['driveFileId'] ?? ''}';
        if (fileId.isEmpty) continue;

        final purpose = '${metadata['purpose'] ?? ''}';

        try {
          if (purpose == 'chat') {
            final messageId = '${metadata['messageId'] ?? ''}';
            if (messageId.isEmpty) continue;

            await ChatSyncService.sendMessage({
              'id': messageId,
              'senderUid': user.uid,
              'text': '${task['filePath'] ?? ''}',
              'type': metadata['type'] ?? 'image',
              'fileId': fileId,
              'driveFileId': fileId,
              'driveFileName':
                  uploaded['driveFileName'] ?? metadata['fileName'] ?? 'media',
              'mimeType': uploaded['mimeType'] ?? '',
              'size': uploaded['size'] ?? '',
              'storage': 'shared',
              if ('${metadata['replyToId'] ?? ''}'.isNotEmpty) ...{
                'replyToId': metadata['replyToId'],
                'replyToText': metadata['replyToText'] ?? '',
                'replyToSenderUid': metadata['replyToSenderUid'] ?? '',
                'replyToSenderName': metadata['replyToSenderName'] ?? '',
              },
              'mine': true,
              'unsent': false,
              'time': metadata['createdAt'] ??
                  DateTime.now().toIso8601String(),
            });
          } else if (purpose == 'gallery') {
            final galleryItems = SpaceStore.readList('galleryMedia');
            final itemId = '${metadata['itemId'] ?? ''}';

            final alreadySaved = galleryItems.any((item) =>
                '${item['id'] ?? ''}' == itemId ||
                '${item['fileId'] ?? item['driveFileId'] ?? ''}' ==
                    fileId);

            if (!alreadySaved) {
              final item = <String, dynamic>{
                'id': itemId.isNotEmpty ? itemId : 'drive_$fileId',
                'type': metadata['type'] ?? 'image',
                'folderId': metadata['folderId'] ?? 'all',
                'createdByUid': metadata['createdByUid'] ?? user.uid,
                'createdByName': metadata['createdByName'] ?? '',
                'createdAt': metadata['createdAt'] ??
                    DateTime.now().toIso8601String(),
                'storage': 'shared',
                ...uploaded.map(
                  (key, value) => MapEntry(key, value),
                ),
              };

              item.remove('_uploadTaskId');
              galleryItems.add(item);
              await SpaceStore.saveList('galleryMedia', galleryItems);
            }
          } else {
            continue;
          }

          await SpaceSyncService.acknowledgeUpload(taskId);
        } catch (error) {
          debugPrint('Pending upload recovery failed ($taskId): $error');
        }
      }
    } catch (error) {
      debugPrint('Upload recovery error: $error');
    }
  }

  Future<void> _loadPartnerNames() async {
    await SpaceStore.init();
    final user = FirebaseAuth.instance.currentUser;
    final savedName = SpaceStore.readString('myDisplayName').trim();
    final accountName = user?.displayName?.trim() ?? '';
    final emailName = user?.email?.split('@').first.trim() ?? '';
    final ownName = savedName.isNotEmpty
        ? savedName
        : accountName.isNotEmpty
            ? accountName
            : emailName;
    final first = SpaceStore.readString('partnerOne').trim();
    final second = SpaceStore.readString('partnerTwo').trim();
    if (!mounted) return;
    setState(() {
      partnerOne = first.isNotEmpty ? first : ownName;
      partnerTwo = second;
    });
  }

  Future<void> _updatePresence(bool online) async {
    try {
      await ChatSyncService.setPresence(isOnline: online);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updatePresence(true);
      _startConnectionWatcher();
    } else {
      _updatePresence(false);
    }
  }

  Future<void> _startConnectionWatcher() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final spaceId = prefs.getString('eternal_space_id');
      if (!mounted) return;
      if (spaceId == null || spaceId.isEmpty) {
        await _connectionSubscription?.cancel();
        _connectionSubscription = null;
        _watchedSpaceId = null;
        _connectionSyncReady = false;
        return;
      }
      if (_watchedSpaceId == spaceId && _connectionSubscription != null) {
        return;
      }
      await _connectionSubscription?.cancel();
      _watchedSpaceId = spaceId;
      _connectionSyncReady = false;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;
      _connectionSubscription = FirebaseFirestore.instance
          .collection('privateSpaces')
          .doc(spaceId)
          .snapshots()
          .listen(
        (snapshot) async {
          if (!mounted) return;
          final data = snapshot.data();
          final members = data?['memberUids'];
          final status = data?['connectionStatus'] ?? 'connected';
          final isConnected = snapshot.exists &&
              members is List &&
              members.length == 2 &&
              members.contains(uid) &&
              status == 'connected';
          if (!isConnected) {
            _connectionSyncReady = false;
            await SpaceStore.stopRealtimeSync();
            return;
          }
          if (_connectionSyncBusy || _connectionSyncReady) {
            return;
          }
          _connectionSyncBusy = true;
          try {
            await SpaceStore.syncFromFirebase();
            if (!mounted) return;
            await SpaceStore.startRealtimeSync();
            if (mounted) {
              _connectionSyncReady = true;
            }
          } catch (error) {
            debugPrint('Connection sync error: $error');
          } finally {
            _connectionSyncBusy = false;
          }
        },
        onError: (Object error) {
          debugPrint('Connection watcher error: $error');
        },
      );
    } catch (error) {
      debugPrint('Start connection watcher error: $error');
    }
  }

  void _startUnreadWatcher() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _unreadSubscription = ChatSyncService.watchMessages().listen(
      (messages) {
        final unread = messages.any((message) {
          final senderUid = '${message['senderUid'] ?? ''}';
          final seenBy = message['seenBy'];
          final alreadySeen = seenBy is Map && seenBy[uid] == true;

          return senderUid.isNotEmpty &&
              senderUid != uid &&
              !alreadySeen &&
              message['unsent'] != true;
        });

        if (!mounted) return;

        setState(() {
          hasUnreadChat = selectedIndex == 1 ? false : unread;
        });
      },
      onError: (_) {},
    );
  }

  Widget _chatIcon(IconData iconData) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(iconData),
        if (hasUnreadChat)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: surfaceColor,
                  width: 1.5,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadSubscription?.cancel();
    _connectionSubscription?.cancel();
    _updatePresence(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        partnerOne: partnerOne,
        partnerTwo: partnerTwo,
        onNavigate: (index) {
          setState(() {
            selectedIndex = index;
            if (index == 1) hasUnreadChat = false;
          });
        },
        onOpenPartnerConnection: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const PartnerConnectionPage(),
            ),
          );

          if (!context.mounted) return;

          await _startConnectionWatcher();
          await SpaceStore.syncFromFirebase();
          await SpaceStore.startRealtimeSync();

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Partner Connection যাচাই করা হয়েছে।',
                ),
              ),
            );
          }
        },
      ),
      const ChatPage(),
      const GalleryPage(),
      SettingsPage(
        partnerOne: partnerOne,
        partnerTwo: partnerTwo,
        onSave: (first, second) {
          setState(() {
            partnerOne = first;
            partnerTwo = second;
          });
        },
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GlowBackground(
              child: pages[selectedIndex],
            ),
          ),
          if (selectedIndex == 2)
            const Positioned(
              right: 16,
              bottom: 16,
              child: UploadFloatingIndicator(),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: surfaceColor,
        indicatorColor: blueColor.withValues(alpha: 0.25),
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            selectedIndex = index;
            if (index == 1) hasUnreadChat = false;
          });
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: _chatIcon(
              Icons.chat_bubble_outline_rounded,
            ),
            selectedIcon: _chatIcon(
              Icons.chat_bubble_rounded,
            ),
            label: 'Chat',
          ),
          const NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Gallery',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

// ============================================================
// PROFILE AVATAR WIDGET
// ============================================================

class ProfileAvatar extends StatelessWidget {
  final String name;
  final String photoBase64;
  final double radius;
  final Color color;

  const ProfileAvatar({
    super.key,
    required this.name,
    this.photoBase64 = '',
    this.radius = 25,
    this.color = purpleColor,
  });

  Widget _letterAvatar() {
    final cleanName = name.trim();

    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withValues(alpha: 0.23),
      child: Text(
        cleanName.isEmpty ? '?' : cleanName[0].toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Uint8List? bytes;

    try {
      if (photoBase64.trim().isNotEmpty) {
        bytes = base64Decode(photoBase64.trim());
      }
    } catch (_) {
      bytes = null;
    }

    if (bytes == null || bytes.isEmpty) {
      return _letterAvatar();
    }

    return ClipOval(
      child: Image.memory(
        bytes,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _letterAvatar(),
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatelessWidget {
  final String partnerOne;
  final String partnerTwo;
  final ValueChanged<int> onNavigate;
  final VoidCallback onOpenPartnerConnection;

  const HomePage({
    super.key,
    required this.partnerOne,
    required this.partnerTwo,
    required this.onNavigate,
    required this.onOpenPartnerConnection,
  });

  void _open(BuildContext context, Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OUR PRIVATE SPACE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                      letterSpacing: 2.5,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Couple Zone',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.favorite_rounded,
              color: pinkColor,
              size: 28,
            ),
          ],
        ),
        const SizedBox(height: 26),
        _RelationshipHomeHeader(
          fallbackName: partnerOne,
        ),
        const SizedBox(height: 18),
        Card(
          color: surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x338B5CF6),
              child: Icon(
                Icons.people_alt_rounded,
                color: purpleColor,
              ),
            ),
            title: const Text(
              'Partner Connection',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              'Create or join our private space',
              style: TextStyle(color: Colors.white54),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onOpenPartnerConnection,
          ),
        ),
        const SizedBox(height: 18),
        Card(
          color: surfaceColor,
          margin: const EdgeInsets.only(bottom: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0x338B5CF6),
              child: Icon(Icons.forum_rounded, color: purpleColor),
            ),
            title: const Text(
              'Complaints Box',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${SpaceStore.readList('spaceComplaints').length} complaints',
              style: const TextStyle(color: Colors.white54),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ComplaintsPage(),
                ),
              );
              if (context.mounted) {
                (context as Element).markNeedsBuild();
              }
            },
          ),
        ),
        const SizedBox(height: 16),
        const SectionHeading(title: 'Our little universe'),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.32,
          children: [
            FeatureCard(
              icon: Icons.event_rounded,
              title: 'Special Dates',
              subtitle: 'Our important days',
              color: purpleColor,
              onTap: () => _open(context, const SpecialDatesPage()),
            ),
            FeatureCard(
              icon: Icons.favorite_rounded,
              title: 'Love Notes',
              subtitle: 'Words from the heart',
              color: pinkColor,
              onTap: () => _open(context, const LoveNotesPage()),
            ),
          ],
        ),
      ],
    );
  }
}

class _RelationshipHomeHeader extends StatefulWidget {
  final String fallbackName;

  const _RelationshipHomeHeader({
    required this.fallbackName,
  });

  @override
  State<_RelationshipHomeHeader> createState() =>
      _RelationshipHomeHeaderState();
}

class _RelationshipHomeHeaderState
    extends State<_RelationshipHomeHeader> {
  Future<String?>? _spaceIdFuture;
  late final Stream<List<Map<String, dynamic>>> _profilesStream;

  @override
  void initState() {
    super.initState();
    _spaceIdFuture = _getSpaceId();
    _profilesStream = ChatSyncService.watchMemberProfiles();
  }

  Future<String?> _getSpaceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('eternal_space_id');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _spaceIdFuture,
      builder: (context, idSnapshot) {
        final spaceId = idSnapshot.data;
        if (spaceId == null || spaceId.isEmpty) {
          return Column(
            children: [
              _CoupleCard(
                first: widget.fallbackName,
                second: 'No one',
              ),
              const SizedBox(height: 18),
              const LoveCounterCard(),
            ],
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('privateSpaces')
              .doc(spaceId)
              .snapshots(),
          builder: (context, snapshot) {
            final data = snapshot.data?.data();
            final user = FirebaseAuth.instance.currentUser;
            final members = List<String>.from(
              data?['memberUids'] ?? [],
            );

            final connected = data != null &&
                user != null &&
                members.length == 2 &&
                members.contains(user.uid) &&
                (data['connectionStatus'] ?? 'connected') ==
                    'connected';

            var ownName = widget.fallbackName;
            var partnerName = 'No one';
            DateTime? startAt;
            var ownUid = '';
            var partnerUid = '';

            if (connected) {
              final rawNames = data['memberNames'];
              final names = rawNames is Map
                  ? Map<String, dynamic>.from(rawNames)
                  : <String, dynamic>{};

              ownName = '${names[user.uid] ?? widget.fallbackName}';
              ownUid = user.uid;
              partnerUid = members.firstWhere((uid) => uid != user.uid);
              partnerName = '${names[partnerUid] ?? 'Partner'}';

              final rawStart = data['relationshipStartAt'];
              if (rawStart is Timestamp) {
                startAt = rawStart.toDate();
              }
            }

            return StreamBuilder<List<Map<String, dynamic>>>(
              stream: _profilesStream,
              builder: (context, profileSnapshot) {
                final profiles = profileSnapshot.data ?? [];

                String photoFor(String uid) {
                  for (final profile in profiles) {
                    if ('${profile['uid'] ?? ''}' == uid) {
                      return '${profile['photoBase64'] ?? ''}';
                    }
                  }
                  return '';
                }

                return Column(
                  children: [
                    _CoupleCard(
                      first: ownName,
                      second: partnerName,
                      firstPhotoBase64: photoFor(ownUid),
                      secondPhotoBase64: photoFor(partnerUid),
                    ),
                    const SizedBox(height: 18),
                    LoveCounterCard(
                      connected: connected,
                      startDate: startAt,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CoupleCard extends StatelessWidget {
  final String first;
  final String second;
  final String firstPhotoBase64;
  final String secondPhotoBase64;

  const _CoupleCard({
    required this.first,
    required this.second,
    this.firstPhotoBase64 = '',
    this.secondPhotoBase64 = '',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        gradient: LinearGradient(
          colors: [
            blueColor.withValues(alpha: 0.22),
            pinkColor.withValues(alpha: 0.16),
          ],
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          ProfileAvatar(
            name: first,
            photoBase64: firstPhotoBase64,
            color: blueColor,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13),
            child: Icon(
              Icons.favorite_rounded,
              color: pinkColor,
              size: 27,
            ),
          ),
          ProfileAvatar(
            name: second,
            photoBase64: secondPhotoBase64,
            color: pinkColor,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$first & $second',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Two hearts, one little world',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white60,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOVE COUNTER
// ============================================================

class LoveCounterCard extends StatefulWidget {
  final bool connected;
  final DateTime? startDate;

  const LoveCounterCard({
    super.key,
    this.connected = false,
    this.startDate,
  });

  @override
  State<LoveCounterCard> createState() => _LoveCounterCardState();
}

class _LoveCounterCardState extends State<LoveCounterCard> {
  Timer? timer;
  DateTime now = DateTime.now();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => now = DateTime.now());
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _selectDateTime() async {
    if (!widget.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('আগে Partner Connection চালু করো।'),
        ),
      );
      return;
    }

    final initial = widget.startDate ?? DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(DateTime.now())
          ? DateTime.now()
          : initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'একসঙ্গে থাকার শুরুর তারিখ',
    );

    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'শুরুর সময় বেছে নাও',
    );

    if (time == null || !mounted) return;

    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    if (selected.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ভবিষ্যতের তারিখ ও সময় নির্বাচন করা যাবে না।'),
        ),
      );
      return;
    }

    setState(() => saving = true);
    try {
      await RelationshipService.saveRelationshipStart(selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('তারিখ ও সময় সংরক্ষণ হয়েছে।')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('সংরক্ষণ করা যায়নি: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _clearDateTime() async {
    if (!widget.connected || widget.startDate == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('তারিখ মুছে ফেলবে?'),
        content: const Text(
          'দুই ফোন থেকেই Together for-এর তারিখ মুছে যাবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('না'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('মুছে ফেলো'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => saving = true);
    try {
      await RelationshipService.clearRelationshipStart();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('মুছতে পারিনি: $e')),
      );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  String _two(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final start = widget.startDate;
    final totalSeconds = start == null
        ? 0
        : max(0, now.difference(start).inSeconds);
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    return Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: surfaceColor.withValues(alpha: 0.86),
        border: Border.all(
          color: pinkColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        children: [
          const Icon(Icons.favorite, color: pinkColor, size: 26),
          const SizedBox(height: 8),
          const Text(
            'Together for',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          if (!widget.connected)
            const Text(
              'Partner-এর সঙ্গে যুক্ত হও',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            )
          else if (start == null)
            const Text(
              'Time select',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: pinkColor,
              ),
            )
          else
            Row(
              children: [
                _TimePart(value: '$days', label: 'DAYS'),
                _TimePart(value: _two(hours), label: 'HOURS'),
                _TimePart(value: _two(minutes), label: 'MINUTES'),
                _TimePart(value: _two(seconds), label: 'SECONDS'),
              ],
            ),
          if (widget.connected && start != null) ...[
            const SizedBox(height: 12),
            Text(
              'Since ${start.day}/${start.month}/${start.year} '
              '${_two(start.hour)}:${_two(start.minute)}',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: saving ? null : _selectDateTime,
                icon: Icon(
                  start == null
                      ? Icons.calendar_month
                      : Icons.edit_calendar,
                ),
                label: Text(
                  start == null ? 'Time select' : 'Edit',
                ),
              ),
              if (widget.connected && start != null)
                TextButton.icon(
                  onPressed: saving ? null : _clearDateTime,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear'),
                ),
            ],
          ),
          if (saving)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimePart extends StatelessWidget {
  final String value;
  final String label;

  const _TimePart({
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.white54,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// COMMON WIDGETS
// ============================================================

class SectionHeading extends StatelessWidget {
  final String title;

  const SectionHeading({
    super.key,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }
}

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: surfaceColor.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(21),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(21),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.055),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 27),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// CHAT
// ============================================================

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  StreamSubscription<List<Map<String, dynamic>>>? _chatSubscription;
  final Map<String, Future<String?>> _mediaPathFutures = {};
  final Set<String> _requestedMediaDownloads = {};

  bool _isTypingSent = false;
  Timer? _typingHeartbeatTimer;
  Map<String, dynamic>? _replyToMessage;

  String? _pendingMediaName;
  bool _pendingMediaVideo = false;
  double _pendingMediaProgress = 0;
  double _pendingMediaSpeed = 0;

  late final Stream<Map<String, dynamic>?> _spaceStream;
  late final Stream<List<Map<String, dynamic>>> _profilesStream;

  List<Map<String, dynamic>> _memberProfiles = [];
  StreamSubscription<List<Map<String, dynamic>>>? _profilesSubscription;

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  String _photoBase64ForUid(String uid) {
    if (uid.isEmpty) return '';

    for (final profile in _memberProfiles) {
      if ('${profile['uid'] ?? ''}' == uid) {
        return '${profile['photoBase64'] ?? ''}';
      }
    }

    return '';
  }

  String _profileNameForUid(String uid, String fallback) {
    for (final profile in _memberProfiles) {
      if ('${profile['uid'] ?? ''}' == uid) {
        final name = '${profile['name'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
      }
    }

    return fallback;
  }

  @override
  void initState() {
    super.initState();
    SpaceSyncService.uploadProgress.addListener(
      _handleUploadProgressChanged,
    );
    _spaceStream = ChatSyncService.watchSpaceData().asBroadcastStream();
    _profilesStream = ChatSyncService.watchMemberProfiles();

    _profilesSubscription = _profilesStream.listen(
      (profiles) {
        if (!mounted) return;

        setState(() {
          _memberProfiles = profiles;
        });
      },
      onError: (Object error) {
        debugPrint('Profile sync skipped: $error');
      },
    );

    _startChatSync();
    _saveOwnProfile();
  }

  void _handleUploadProgressChanged() {
    final name = _pendingMediaName;
    if (!mounted || name == null) return;

    for (final upload in SpaceSyncService.uploadProgress.value) {
      if (upload.fileName == name && upload.isUploading) {
        final progress = upload.progress.clamp(0.0, 1.0).toDouble();

        if (_pendingMediaProgress != progress ||
            _pendingMediaSpeed != upload.bytesPerSecond) {
          setState(() {
            _pendingMediaProgress = progress;
            _pendingMediaSpeed = upload.bytesPerSecond;
          });
        }
        return;
      }
    }
  }

  void _handleTypingChanged(String value) {
    final shouldType = value.trim().isNotEmpty;

    if (shouldType) {
      // প্রথম অক্ষর লেখার সঙ্গে সঙ্গেই Typing চালু হবে।
      if (!_isTypingSent) {
        _isTypingSent = true;

        unawaited(
          ChatSyncService.setTyping(isTyping: true).catchError(
            (Object error) {
              debugPrint('Typing status update failed: $error');
            },
          ),
        );
      }

      // লেখা চলাকালীন নিয়মিত heartbeat পাঠাবে।
      _typingHeartbeatTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          if (!mounted || controller.text.trim().isEmpty) {
            return;
          }

          unawaited(
            ChatSyncService.setTyping(isTyping: true).catchError(
              (Object error) {
                debugPrint('Typing heartbeat failed: $error');
              },
            ),
          );
        },
      );
    } else {
      // ইনপুট খালি হলে সঙ্গে সঙ্গে Typing বন্ধ করবে।
      _typingHeartbeatTimer?.cancel();
      _typingHeartbeatTimer = null;

      if (_isTypingSent) {
        _isTypingSent = false;

        unawaited(
          ChatSyncService.clearTyping().catchError(
            (Object error) {
              debugPrint('Typing status clear failed: $error');
            },
          ),
        );
      }
    }
  }

  Future<void> _stopTyping() async {
    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    if (!_isTypingSent) return;
    _isTypingSent = false;
    try {
      await ChatSyncService.clearTyping();
    } catch (error) {
      debugPrint('Typing status clear failed: $error');
    }
  }

  Future<void> _saveOwnProfile() async {
    try {
      await ChatSyncService.saveMyProfileFromSpace();
    } catch (error) {
      debugPrint('Chat profile save skipped: $error');
    }
  }

  Future<void> _startChatSync() async {
    try {
      final stream = ChatSyncService.watchMessages();

      _chatSubscription = stream.listen(
        (latestMessages) {
          if (!mounted) return;

          setState(() {
            messages = latestMessages;
          });

          unawaited(
            ChatSyncService.markMessagesSeen(latestMessages).catchError(
              (Object error) {
                debugPrint('Mark seen skipped: $error');
              },
            ),
          );

          _scrollToBottom();
        },
        onError: (Object error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('চ্যাট সিঙ্ক সমস্যা: $error')),
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('চ্যাট চালু হয়নি: $error')),
      );
    }
  }

  @override
  void dispose() {
    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;

    if (_isTypingSent) {
      _isTypingSent = false;
      unawaited(
        ChatSyncService.clearTyping().catchError(
          (Object error) {
            debugPrint('Typing status clear on dispose failed: $error');
          },
        ),
      );
    }

    SpaceSyncService.uploadProgress.removeListener(
      _handleUploadProgressChanged,
    );
    _profilesSubscription?.cancel();
    _chatSubscription?.cancel();
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  bool _isMine(Map<String, dynamic> message) {
    final senderUid = '${message['senderUid'] ?? ''}';

    if (senderUid.isNotEmpty && _currentUid.isNotEmpty) {
      return senderUid == _currentUid;
    }

    return message['mine'] == true;
  }

  int get _lastOwnMessageIndex {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (_isMine(messages[i]) && messages[i]['unsent'] != true) {
        return i;
      }
    }
    return -1;
  }

  Future<void> _sendText() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    await _stopTyping();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('আগে Partner Space-এ যুক্ত হয়ে নাও।'),
        ),
      );
      return;
    }

    final replyTo = _replyToMessage;
    final message = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'senderUid': user.uid,
      'text': text,
      'type': 'text',
      if (replyTo != null) ...{
        'replyToId': '${replyTo['id'] ?? ''}',
        'replyToText': '${replyTo['type'] ?? 'text'}' == 'text'
            ? '${replyTo['text'] ?? ''}'
            : ('${replyTo['type'] ?? 'media'}' == 'video' ? 'ভিডিও' : 'ছবি'),
        'replyToSenderUid': '${replyTo['senderUid'] ?? ''}',
        'replyToSenderName': _profileNameForUid(
          '${replyTo['senderUid'] ?? ''}',
          _isMine(replyTo) ? 'তুমি' : 'সঙ্গী',
        ),
      },
      'mine': true,
      'unsent': false,
      'time': DateTime.now().toIso8601String(),
    };

    controller.clear();

    try {
      await ChatSyncService.sendMessage(message);
      if (mounted) {
        setState(() {
          if (_replyToMessage?['id'] == replyTo?['id']) {
            _replyToMessage = null;
          }
        });
      }
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('মেসেজ পাঠানো যায়নি। আবার চেষ্টা করুন।'),
        ),
      );
    }
  }

  Future<void> _sendMedia(bool video) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('আগে Partner Space-এ যুক্ত হও।'),
        ),
      );
      return;
    }

    if (_pendingMediaName != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('আগের ফাইলটির আপলোড শেষ হলে আবার চেষ্টা করো।'),
        ),
      );
      return;
    }

    final picker = ImagePicker();
    final picked = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);

    if (picked == null || !mounted) return;

    final file = File(picked.path);
    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'chat_media';

    final messageId =
        DateTime.now().microsecondsSinceEpoch.toString();
    final uploadCreatedAt = DateTime.now().toIso8601String();
    final replyTo = _replyToMessage;

    setState(() {
      _pendingMediaName = fileName;
      _pendingMediaVideo = video;
      _pendingMediaProgress = 0;
      _pendingMediaSpeed = 0;
    });

    _scrollToBottom();

    try {
      final uploaded = await SpaceSyncService.uploadSharedMedia(
        file,
        metadata: {
          'purpose': 'chat',
          'messageId': messageId,
          'senderUid': user.uid,
          'type': video ? 'video' : 'image',
          'fileName': fileName,
          'createdAt': uploadCreatedAt,
          if (replyTo != null) ...{
            'replyToId': '${replyTo['id'] ?? ''}',
            'replyToText': '${replyTo['type'] ?? 'text'}' == 'text'
                ? '${replyTo['text'] ?? ''}'
                : ('${replyTo['type'] ?? 'media'}' == 'video' ? 'ভিডিও' : 'ছবি'),
            'replyToSenderUid': '${replyTo['senderUid'] ?? ''}',
            'replyToSenderName': _profileNameForUid(
              '${replyTo['senderUid'] ?? ''}',
              _isMine(replyTo) ? 'তুমি' : 'সঙ্গী',
            ),
          },
        },
      );

      final fileId =
          (uploaded['fileId'] ?? uploaded['driveFileId'] ?? '').trim();

      if (fileId.isEmpty) {
        throw Exception('আপলোড করা ফাইলের ID পাওয়া যায়নি।');
      }

      final message = <String, dynamic>{
        'id': messageId,
        'senderUid': user.uid,
        'text': picked.path,
        'type': video ? 'video' : 'image',
        'fileId': fileId,
        'driveFileId': fileId,
        'driveFileName': uploaded['driveFileName'] ?? fileName,
        'mimeType': uploaded['mimeType'] ?? '',
        'size': uploaded['size'] ?? '',
        'storage': 'shared',
        if (replyTo != null) ...{
          'replyToId': '${replyTo['id'] ?? ''}',
          'replyToText': '${replyTo['type'] ?? 'text'}' == 'text'
              ? '${replyTo['text'] ?? ''}'
              : ('${replyTo['type'] ?? 'media'}' == 'video' ? 'ভিডিও' : 'ছবি'),
          'replyToSenderUid': '${replyTo['senderUid'] ?? ''}',
          'replyToSenderName': _profileNameForUid(
            '${replyTo['senderUid'] ?? ''}',
            _isMine(replyTo) ? 'তুমি' : 'সঙ্গী',
          ),
        },
        'mine': true,
        'unsent': false,
        'time': uploadCreatedAt,
      };

      if (mounted) {
        setState(() {
          _pendingMediaProgress = 1;
        });
      }

      Object? sendError;

      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          await ChatSyncService.sendMessage(message);
          sendError = null;
          break;
        } catch (error) {
          sendError = error;

          if (attempt < 2) {
            await Future.delayed(
              Duration(milliseconds: 500 * (attempt + 1)),
            );
          }
        }
      }

      if (sendError != null) {
        throw Exception('মেসেজ পাঠানো যায়নি। আবার চেষ্টা করো।');
      }
      
      if (mounted) {
        setState(() {
          if (_replyToMessage?['id'] == replyTo?['id']) {
            _replyToMessage = null;
          }
        });
      }

      final taskId = uploaded['_uploadTaskId'] ?? '';
      if (taskId.isNotEmpty) {
        await SpaceSyncService.acknowledgeUpload(taskId);
      }

      _scrollToBottom();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            video ? 'ভিডিও পাঠানো হয়েছে।' : 'ছবি পাঠানো হয়েছে।',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('মিডিয়া পাঠানো যায়নি। আবার চেষ্টা করুন।'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _pendingMediaName = null;
          _pendingMediaProgress = 0;
          _pendingMediaSpeed = 0;
        });
      }
    }
  }

  String _formatChatUploadSpeed(double bytesPerSecond) {
    if (bytesPerSecond >= 1024 * 1024) {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }

    if (bytesPerSecond >= 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }

    return '${bytesPerSecond.toStringAsFixed(0)} B/s';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;

      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String _formatTime(dynamic value) {
    final date = DateTime.tryParse('${value ?? ''}');
    if (date == null) return '';

    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDay = DateTime(local.year, local.month, local.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final time = '$hour:$minute $period';

    if (messageDay == today) return 'Today • $time';
    if (messageDay == yesterday) return 'Yesterday • $time';

    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${local.day} ${months[local.month - 1]} ${local.year} • $time';
  }

  void _setReplyTo(Map<String, dynamic> message) {
    if (message['unsent'] == true) return;
    setState(() => _replyToMessage = Map<String, dynamic>.from(message));
  }

  Widget _buildReplyQuote(Map<String, dynamic> message) {
    final replyId = '${message['replyToId'] ?? ''}';
    if (replyId.isEmpty) return const SizedBox.shrink();

    final senderName = '${message['replyToSenderName'] ?? 'সঙ্গী'}';
    final preview = '${message['replyToText'] ?? ''}';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(9, 6, 9, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: const Border(left: BorderSide(color: pinkColor, width: 3)),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(senderName, style: const TextStyle(color: pinkColor, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Future<void> _showMessageOptions(int index) async {
    if (index < 0 || index >= messages.length) return;

    final message = Map<String, dynamic>.from(messages[index]);
    final messageId = '${message['id'] ?? ''}';
    final mine = _isMine(message);
    final unsent = message['unsent'] == true;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(22),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: pinkColor),
                title: const Text('Reply / উত্তর দাও'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _setReplyTo(message);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: pinkColor,
                ),
                title: const Text('মেসেজের বিবরণ'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDetails(message);
                },
              ),
              if (!unsent &&
                  ('${message['type'] ?? ''}' == 'image' ||
                      '${message['type'] ?? ''}' == 'video'))
                ListTile(
                  leading: const Icon(
                    Icons.save_alt_rounded,
                    color: pinkColor,
                  ),
                  title: const Text('গ্যালারিতে সংরক্ষণ'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _saveChatMediaToGallery(message);
                  },
                ),
              if (mine && !unsent)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text('সবার জন্য Unsend'),
                  onTap: () async {
                    Navigator.pop(sheetContext);

                    try {
                      // আগে Firestore-এ মেসেজটি সরাও, যাতে চ্যাট সঙ্গে সঙ্গে আপডেট হয়।
                      await ChatSyncService.unsendMessage(messageId);

                      final mediaType = '${message['type'] ?? ''}';
                      final fileId = (
                        message['fileId'] ??
                        message['driveFileId'] ??
                        ''
                      ).toString().trim();

                      if ((mediaType == 'image' || mediaType == 'video') &&
                          fileId.isNotEmpty) {
                        // গ্যালারিতে একই Drive ফাইল রেফারেন্স থাকলে সেটি অকারণে ভাঙবে না।
                        final linkedInGallery = SpaceStore
                            .readList('galleryMedia')
                            .any((item) =>
                                '${item['fileId'] ?? item['driveFileId'] ?? ''}' ==
                                fileId);

                        if (!linkedInGallery) {
                          unawaited(
                            SpaceSyncService.deleteSharedMedia(fileId).catchError(
                              (Object error) {
                                debugPrint('Chat media Drive cleanup failed: $error');
                              },
                            ),
                          );
                        }
                      }
                    } catch (error) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('আনসেন্ড করা যায়নি: $error')),
                      );
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveChatMediaToGallery(
    Map<String, dynamic> message,
  ) async {
    final type = '${message['type'] ?? ''}';
    final fileId = (
      message['fileId'] ??
      message['driveFileId'] ??
      ''
    ).toString().trim();

    if (fileId.isEmpty ||
        (type != 'image' && type != 'video')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('এই ছবি/ভিডিও গ্যালারিতে সংরক্ষণ করা যাচ্ছে না।'),
        ),
      );
      return;
    }

    final galleryItems = SpaceStore.readList('galleryMedia');

    final alreadySaved = galleryItems.any((item) {
      final savedId = (
        item['fileId'] ??
        item['driveFileId'] ??
        ''
      ).toString().trim();

      return savedId == fileId;
    });

    if (alreadySaved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('এই ছবি/ভিডিও আগে থেকেই গ্যালারিতে আছে।'),
        ),
      );
      return;
    }

    final item = <String, dynamic>{
      'id': 'chat_$fileId',
      'fileId': fileId,
      'driveFileId': fileId,
      'driveFileName':
          message['driveFileName'] ?? 'chat_media',
      'mimeType': message['mimeType'] ?? '',
      'type': type,
      'folderId': 'all',
      'storage': 'shared',
      'source': 'chat',
      'createdAt': DateTime.now().toIso8601String(),
    };

    galleryItems.add(item);
    await SpaceStore.saveList('galleryMedia', galleryItems);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('গ্যালারিতে সংরক্ষণ করা হয়েছে।'),
      ),
    );
  }

  void _showDetails(Map<String, dynamic> message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('মেসেজের বিবরণ'),
        content: Text(
          'প্রেরক: ${_isMine(message) ? 'তুমি' : 'সঙ্গী'}\n'
          'ধরন: ${message['type'] ?? 'text'}\n'
          'সময়: ${_formatTime(message['time'])}\n'
          'অবস্থা: ${message['unsent'] == true ? 'Unsent' : 'পাঠানো হয়েছে'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বন্ধ করো'),
          ),
        ],
      ),
    );
  }

  String _formatMediaSize(dynamic value) {
    final bytes = int.tryParse('${value ?? ''}') ?? 0;

    if (bytes <= 0) return 'ফাইলের সাইজ জানা নেই';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<String?> _resolveMediaPath(
    Map<String, dynamic> media,
  ) {
    final isMine = _isMine(media);
    final localPath = '${media['text'] ?? media['path'] ?? ''}'.trim();
    final fileId = '${media['fileId'] ?? media['driveFileId'] ?? ''}'.trim();
    // নিজের ফোনের লোকাল পথ শুধু নিজের পাঠানো মেসেজে ব্যবহার হবে।
    final usableLocalPath = isMine ? localPath : '';
    final key = fileId.isNotEmpty ? fileId : usableLocalPath;
    final existing = _mediaPathFutures[key];
    if (existing != null) return existing;
    late final Future<String?> future;
    future = Future<String?>.microtask(() async {
      try {
        if (usableLocalPath.isNotEmpty) {
          try {
            if (await File(usableLocalPath).exists()) {
              return usableLocalPath;
            }
          } catch (_) {}
        }
        if (fileId.isEmpty) return null;
        // আগে ডাউনলোড করা ফাইল থাকলে সেটিই ব্যবহার করবে।
        final cachedPath = await SpaceSyncService.getCachedMediaPath(
          fileId,
          shared: true,
        );
        if (cachedPath != null) {
          try {
            if (await File(cachedPath).exists()) {
              return cachedPath;
            }
          } catch (_) {}
        }
        final name = '${media['driveFileName'] ?? 'chat_media'}';
        final result = await SpaceSyncService.downloadMedia(
          fileId,
          saveAs: '${fileId}_$name',
        );
        if (await File(result).exists()) {
          return result;
        }
        return null;
      } catch (error) {
        debugPrint('Chat media download error: $error');
        return null;
      }
    });
    _mediaPathFutures[key] = future;
    future.then((path) {
      if (path == null && identical(_mediaPathFutures[key], future)) {
        _mediaPathFutures.remove(key);
      }
    });
    return future;
  }

  Widget _messageContent(Map<String, dynamic> message) {
    if (message['unsent'] == true) {
      return const Text(
        'Unsent a message',
        style: TextStyle(
          color: Colors.white60,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final type = '${message['type'] ?? 'text'}';
    final path = '${message['text'] ?? ''}';

    if (type == 'image' || type == 'video') {
      final fileId =
          '${message['fileId'] ?? message['driveFileId'] ?? ''}'.trim();

      final mediaKey = fileId.isNotEmpty ? fileId : path;

      return ValueListenableBuilder<bool>(
        valueListenable: DataSaverSettings.enabled,
        builder: (context, dataSaverEnabled, _) {
          final localMediaPath =
              '${message['text'] ?? message['path'] ?? ''}'.trim();

          final senderHasLocalFile = _isMine(message) &&
              localMediaPath.isNotEmpty &&
              File(localMediaPath).existsSync();

          final shouldDownload = senderHasLocalFile ||
              !dataSaverEnabled ||
              _requestedMediaDownloads.contains(mediaKey);

          return FutureBuilder<String?>(
            future: shouldDownload ? _resolveMediaPath(message) : null,
            builder: (context, snapshot) {
              final resolvedPath = snapshot.data;

              if (!shouldDownload) {
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _requestedMediaDownloads.add(mediaKey);
                    });
                  },
                  child: Container(
                    width: 210,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type == 'image'
                              ? Icons.image_outlined
                              : Icons.play_circle_outline_rounded,
                          size: 36,
                          color: pinkColor,
                        ),
                        const SizedBox(height: 8),
                        const Text('ডাউনলোড করতে ট্যাপ করো'),
                        const SizedBox(height: 4),
                        Text(
                          _formatMediaSize(message['size']),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (snapshot.connectionState == ConnectionState.waiting) {
                return SizedBox(
                  width: 210,
                  height: 120,
                  child: ValueListenableBuilder<List<DownloadProgress>>(
                    valueListenable: SpaceSyncService.downloadProgress,
                    builder: (context, downloads, _) {
                      DownloadProgress? current;
                      for (final item in downloads) {
                        if (item.fileId == fileId) {
                          current = item;
                          break;
                        }
                      }
                      final progress = current;

                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              LinearProgressIndicator(
                                value: progress?.progress,
                                backgroundColor: Colors.white12,
                                color: pinkColor,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                progress == null
                                    ? 'ডাউনলোড শুরু হচ্ছে...'
                                    : '${(progress.progress * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              if (progress != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  '${(progress.downloadedBytes / (1024 * 1024)).toStringAsFixed(1)}'
                                  ' / '
                                  '${(progress.totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                                Text(
                                  '${(progress.bytesPerSecond / (1024 * 1024)).toStringAsFixed(2)} MB/s',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              }

              if (snapshot.hasError ||
                  resolvedPath == null ||
                  !File(resolvedPath).existsSync()) {
                return InkWell(
                  onTap: () {
                    _mediaPathFutures.remove(mediaKey);
                    setState(() {
                      _requestedMediaDownloads.add(mediaKey);
                    });
                  },
                  child: Container(
                    width: 210,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh_rounded, color: pinkColor, size: 32),
                        SizedBox(height: 8),
                        Text('ডাউনলোড হয়নি — আবার চেষ্টা করো'),
                      ],
                    ),
                  ),
                );
              }

              if (type == 'image') {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ImageViewerPage(path: resolvedPath),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      File(resolvedPath),
                      width: 210,
                      height: 210,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 210,
                        height: 100,
                        child: Center(
                          child: Text('ছবিটি খোলা যায়নি'),
                        ),
                      ),
                    ),
                  ),
                );
              }

              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => VideoViewerPage(path: resolvedPath),
                    ),
                  );
                },
                child: Container(
                  width: 210,
                  height: 130,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.play_circle_fill_rounded,
                        size: 45,
                        color: pinkColor,
                      ),
                      SizedBox(height: 6),
                      Text('ভিডিও চালাও'),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    }

    return Text(
      path,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        height: 1.45,
      ),
    );
  }

  Widget _buildPendingMediaMessage() {
    final fileName = _pendingMediaName ?? 'মিডিয়া ফাইল';
    final progress =
        _pendingMediaProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.72,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF453078),
                border: Border.all(
                  color: pinkColor.withValues(alpha: 0.35),
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _pendingMediaVideo
                            ? Icons.videocam_rounded
                            : Icons.image_rounded,
                        color: pinkColor,
                        size: 25,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$percent%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(pinkColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'আপলোড হচ্ছে...',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _formatChatUploadSpeed(_pendingMediaSpeed),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> message, int index) {
    final mine = _isMine(message);
    final senderUid = '${message['senderUid'] ?? ''}';

    return GestureDetector(
      onLongPress: () => _showMessageOptions(index),
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity > 250) _setReplyTo(message);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              ProfileAvatar(
                name: _profileNameForUid(senderUid, 'Partner'),
                photoBase64: _photoBase64ForUid(senderUid),
                radius: 16,
                color: purpleColor,
              ),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment:
                    mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                    ),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: mine
                          ? const Color(0xFF453078)
                          : surfaceColor,
                      border: Border.all(
                        color: mine
                            ? pinkColor.withValues(alpha: 0.25)
                            : Colors.white10,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(mine ? 18 : 5),
                        bottomRight: Radius.circular(mine ? 5 : 18),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildReplyQuote(message),
                        _messageContent(message),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message['time']),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                        ),
                      ),
                      if (mine && index == _lastOwnMessageIndex) ...[
                        const SizedBox(width: 6),
                        Builder(
                          builder: (context) {
                            final rawSeenBy = message['seenBy'];
                            final wasSeen = rawSeenBy is Map &&
                                rawSeenBy.entries.any(
                                  (entry) =>
                                      '${entry.key}' != _currentUid &&
                                      entry.value == true,
                                );

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  wasSeen
                                      ? Icons.done_all_rounded
                                      : Icons.done_rounded,
                                  size: 13,
                                  color: wasSeen
                                      ? const Color(0xFF53D9FF)
                                      : Colors.white54,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  wasSeen ? 'Seen' : 'Sent',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: wasSeen
                                        ? const Color(0xFF53D9FF)
                                        : Colors.white54,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (mine) ...[
              const SizedBox(width: 7),
              ProfileAvatar(
                name: _profileNameForUid(
                  _currentUid,
                  FirebaseAuth.instance.currentUser?.displayName ??
                      FirebaseAuth.instance.currentUser?.email
                          ?.split('@')
                          .first ??
                      'You',
                ),
                photoBase64: _photoBase64ForUid(_currentUid),
                radius: 16,
                color: pinkColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatHeader() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _spaceStream,
      builder: (context, spaceSnapshot) {
        final space = spaceSnapshot.data ?? <String, dynamic>{};
        final rawMembers = space['memberUids'];
        final members = rawMembers is List
            ? rawMembers.whereType<String>().toList()
            : <String>[];
        String partnerUid = '';
        for (final uid in members) {
          if (uid != _currentUid) {
            partnerUid = uid;
            break;
          }
        }
        if (partnerUid.isEmpty) {
          return _chatHeaderContent(
            name: 'Partner',
            photoBase64: '',
            isOnline: false,
            isTyping: false,
            lastSeen: null,
          );
        }
        return StreamBuilder<Map<String, dynamic>?>(
          stream: ChatSyncService.watchPresence(partnerUid),
          builder: (context, presenceSnapshot) {
            final presence = presenceSnapshot.data;
            final isOnline = presence?['isOnline'] == true;
            return StreamBuilder<Map<String, dynamic>?>(
              stream: ChatSyncService.watchMemberTyping(partnerUid),
              builder: (context, typingSnapshot) {
                final isTyping = typingSnapshot.data?['isTyping'] == true;
                return _chatHeaderContent(
                  name: _profileNameForUid(partnerUid, 'Partner'),
                  photoBase64: _photoBase64ForUid(partnerUid),
                  isOnline: isOnline,
                  isTyping: isTyping,
                  lastSeen: presence?['lastSeen'],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _chatHeaderContent({
    required String name,
    required String photoBase64,
    required bool isOnline,
    required bool isTyping,
    dynamic lastSeen,
  }) {
    final avatar = ProfileAvatar(
      name: name,
      photoBase64: photoBase64,
      radius: 23,
      color: purpleColor,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: isOnline
                        ? Colors.greenAccent
                        : Colors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: backgroundColor,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                PresenceStatusLabel(
                  isTyping: isTyping,
                  isOnline: isOnline,
                  lastSeen: lastSeen,
                ),
              ],
            ),
          ),
          const Icon(
            Icons.lock_outline_rounded,
            color: pinkColor,
            size: 21,
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _spaceStream,
      builder: (context, spaceSnapshot) {
        final rawMembers = spaceSnapshot.data?['memberUids'];
        final members = rawMembers is List ? rawMembers.whereType<String>().toList() : <String>[];
        String partnerUid = '';
        for (final uid in members) {
          if (uid != _currentUid) {
            partnerUid = uid;
            break;
          }
        }
        if (partnerUid.isEmpty) {
          return const SizedBox.shrink();
        }
        return StreamBuilder<Map<String, dynamic>?>(
          stream: ChatSyncService.watchMemberTyping(partnerUid),
          builder: (context, snapshot) {
            if (snapshot.data?['isTyping'] != true) {
              return const SizedBox.shrink();
            }
            return const Padding(
              padding: EdgeInsets.only(
                left: 18,
                right: 18,
                top: 2,
                bottom: 8,
              ),
              child: Row(
                children: [
                  TypingDotsIndicator(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildChatHeader(),
        const Divider(height: 1, color: Colors.white10),
        Expanded(
          child: messages.isEmpty && _pendingMediaName == null
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 48,
                        color: Colors.white30,
                      ),
                      SizedBox(height: 12),
                      Text(
                        'একটি সুন্দর কথোপকথন শুরু করো ❤️',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount:
                      messages.length + (_pendingMediaName != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= messages.length) {
                      return _buildPendingMediaMessage();
                    }

                    return _buildMessage(messages[index], index);
                  },
                ),
        ),
        _buildTypingIndicator(),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(7, 8, 7, 8),
            decoration: BoxDecoration(
              color: backgroundColor,
              border: Border(
                top: BorderSide(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_replyToMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, right: 8, bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.reply_rounded, color: pinkColor, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Reply: ${_replyToMessage!['type'] == 'text' ? (_replyToMessage!['text'] ?? '') : (_replyToMessage!['type'] == 'video' ? 'ভিডিও' : 'ছবি')}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Reply বাতিল',
                          onPressed: () => setState(() => _replyToMessage = null),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                IconButton(
                  tooltip: 'ছবি পাঠাও',
                  onPressed: () => _sendMedia(false),
                  icon: const Icon(
                    Icons.image_outlined,
                    color: pinkColor,
                  ),
                ),
                IconButton(
                  tooltip: 'ভিডিও পাঠাও',
                  onPressed: () => _sendMedia(true),
                  icon: const Icon(
                    Icons.videocam_outlined,
                    color: purpleColor,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _handleTypingChanged,
                    onSubmitted: (_) => _sendText(),
                    decoration: InputDecoration(
                      hintText: 'মেসেজ লেখো...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 11,
                      ),
                      filled: true,
                      fillColor: surfaceColor,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 5),
                IconButton.filled(
                  tooltip: 'পাঠাও',
                  onPressed: _sendText,
                  style: IconButton.styleFrom(
                    backgroundColor: pinkColor,
                  ),
                  icon: const Icon(Icons.send_rounded),
                ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// GALLERY
// ============================================================

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  List<Map<String, dynamic>> folders = [];
  List<Map<String, dynamic>> media = [];

  @override
  void initState() {
    super.initState();
    SpaceStore.syncVersion.addListener(_handleGallerySyncChanged);

    folders = SpaceStore.readList('galleryFolders');
    media = SpaceStore.readList('galleryMedia');

    if (folders.isEmpty) {
      folders = [
        {'id': 'all', 'name': 'All Memories'},
        {'id': 'favorites', 'name': 'Favorites'},
      ];

      SpaceStore.saveList('galleryFolders', folders);
    }
  }

  void _handleGallerySyncChanged() {
    if (!mounted) return;

    final latestFolders = SpaceStore.readList('galleryFolders');
    final latestMedia = SpaceStore.readList('galleryMedia');

    setState(() {
      folders = latestFolders;
      media = latestMedia;
    });
  }

  @override
  void dispose() {
    SpaceStore.syncVersion.removeListener(_handleGallerySyncChanged);
    super.dispose();
  }

  String _currentCreatorName() {
    final user = FirebaseAuth.instance.currentUser;
    final savedName = SpaceStore.readString('myDisplayName').trim();
    final displayName = user?.displayName?.trim() ?? '';
    final emailName = user?.email?.split('@').first.trim() ?? '';

    if (savedName.isNotEmpty) return savedName;
    if (displayName.isNotEmpty) return displayName;
    if (emailName.isNotEmpty) return emailName;

    return 'অজানা';
  }

  Future<void> _save() async {
    final foldersToSave = folders
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    final mediaToSave = media
        .map((item) => Map<String, dynamic>.from(item))
        .toList();

    await SpaceStore.saveList('galleryMedia', mediaToSave);
    await SpaceStore.saveList('galleryFolders', foldersToSave);
  }

  Future<void> _createFolder() async {
    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name == null || name.isEmpty) return;

    setState(() {
      folders.add({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'name': name,
        'createdByUid': FirebaseAuth.instance.currentUser?.uid ?? '',
        'createdByName': _currentCreatorName(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    });

    await _save();
  }

  Future<void> _showFolderMenu(Map<String, dynamic> folder) async {
    final id = '${folder['id']}';
    final isDefault = id == 'all' || id == 'favorites';

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              onTap: () => Navigator.pop(sheetContext, 'details'),
            ),
            if (!isDefault)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(sheetContext, 'rename'),
              ),
            if (!isDefault)
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(sheetContext, 'delete'),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'details') {
      final count = _itemsForFolder(id).length;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: surfaceColor,
          title: const Text('Folder details'),
          content: Text(
            'Name: ${folder['name']}\n'
            'Items: $count\n'
            'Created by: ${folder['createdByName'] ?? 'অজানা (পুরোনো ফোল্ডার)'}\n'
            'Created: ${folder['createdAt'] ?? 'Unknown'}\n'
            'Folder ID: $id',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } else if (action == 'rename') {
      await _renameFolder(folder);
    } else if (action == 'delete') {
      await _deleteFolder(folder);
    }
  }

  Future<void> _renameFolder(Map<String, dynamic> folder) async {
    final id = '${folder['id']}';

    if (id == 'all' || id == 'favorites') return;

    final controller = TextEditingController(
      text: '${folder['name'] ?? ''}',
    );

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Rename folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Folder name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (name == null || name.isEmpty || !mounted) return;

    setState(() {
      final index = folders.indexWhere((item) => '${item['id']}' == id);

      if (index != -1) {
        folders[index]['name'] = name;
      }
    });

    await _save();
  }

  Future<void> _deleteFolder(Map<String, dynamic> folder) async {
    final id = '${folder['id']}';

    if (id == 'all' || id == 'favorites') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Delete folder?'),
        content: Text(
          '“${folder['name']}” ফোল্ডারটি মুছে যাবে। '
          'এর ছবি ও ভিডিও All Memories-এ থাকবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      for (final item in media) {
        if ('${item['folderId']}' == id) {
          item['folderId'] = 'all';
        }
      }

      folders.removeWhere((item) => '${item['id']}' == id);
    });

    await _save();
  }

  Future<Map<String, dynamic>?> _addMedia(
    String folderId,
    bool video,
  ) async {
    final picker = ImagePicker();

    final picked = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);

    if (picked == null) return null;
    if (!mounted) return null;

    final itemId = DateTime.now().microsecondsSinceEpoch.toString();
    final uploadCreatedAt = DateTime.now().toIso8601String();
    final creatorUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';
    final creatorName = _currentCreatorName();

    Map<String, String> uploaded;

    try {
      uploaded = await SpaceSyncService.uploadSharedMedia(
        File(picked.path),
        metadata: {
          'purpose': 'gallery',
          'itemId': itemId,
          'type': video ? 'video' : 'image',
          'folderId': folderId,
          'createdByUid': creatorUid,
          'createdByName': creatorName,
          'createdAt': uploadCreatedAt,
          'fileName': picked.name,
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Drive-এ আপলোড হয়নি: $e')),
        );
      }
      return null;
    }

    // Upload সফল হলে picker-এর অস্থায়ী path-এর ওপর নির্ভর না করে
    // একই ফাইলকে স্থায়ী media cache-এ রাখো।
    var galleryLocalPath = picked.path;
    try {
      final fileId = (
        uploaded['fileId'] ??
        uploaded['driveFileId'] ??
        ''
      ).toString().trim();

      final sourceFile = File(picked.path);

      if (fileId.isNotEmpty &&
          await sourceFile.exists() &&
          await sourceFile.length() > 0) {
        final size = await sourceFile.length();
        final support = await getApplicationSupportDirectory();
        final cacheDirectory = Directory(
          '${support.path}/eternal_space_media',
        );
        await cacheDirectory.create(recursive: true);

        final safeId = fileId.replaceAll(
          RegExp(r'[^A-Za-z0-9_-]'),
          '_',
        );
        final dot = picked.name.lastIndexOf('.');
        final extension = dot > 0 && picked.name.length - dot <= 10
            ? picked.name.substring(dot).toLowerCase()
            : '';

        final cachedFile = File(
          '${cacheDirectory.path}/media_shared_${safeId}__${extension}',
        );
        final tempFile = File('${cachedFile.path}.part');
        final marker = File('${cachedFile.path}.complete');

        if (await marker.exists()) await marker.delete();
        if (await tempFile.exists()) await tempFile.delete();

        await sourceFile.copy(tempFile.path);

        if (await tempFile.length() != size) {
          throw Exception('লোকাল ক্যাশ যাচাই করা যায়নি।');
        }

        if (await cachedFile.exists()) await cachedFile.delete();
        await tempFile.rename(cachedFile.path);
        await marker.writeAsString('$size', flush: true);

        galleryLocalPath = cachedFile.path;
      }
    } catch (error) {
      // লোকাল ক্যাশে ব্যর্থ হলেও সফল Drive upload নষ্ট করবে না।
      debugPrint('Gallery local cache copy failed: $error');
    }

    final item = <String, dynamic>{
      'id': itemId,
      'path': galleryLocalPath,
      'type': video ? 'video' : 'image',
      'folderId': folderId,
      'createdAt': uploadCreatedAt,
      'createdByUid': creatorUid,
      'createdByName': creatorName,
      ...uploaded,
    };

    setState(() {
      media.add(item);
    });

    await _save();
    
    final taskId = uploaded['_uploadTaskId'] ?? '';
    if (taskId.isNotEmpty) {
      await SpaceSyncService.acknowledgeUpload(taskId);
    }

    return item;
  }

  Future<void> _deleteMediaItem(
    Map<String, dynamic> item, {
    bool fromFavorites = false,
  }) async {
    final driveId = (
      item['fileId'] ??
      item['driveFileId'] ??
      ''
    ).toString().trim();

    final itemId = '${item['id'] ?? ''}';
    final originalIndex = media.indexWhere(
      (m) => '${m['id'] ?? ''}' == itemId,
    );

    if (originalIndex == -1) return;

    final removedItem = Map<String, dynamic>.from(
      media[originalIndex],
    );

    // পছন্দের ছবি অন্য ফোল্ডার থেকে সরালে Drive ফাইল মুছবে না;
    // সেটি Favorites-এ রেখে দেবে।
    if (removedItem['favorite'] == true && !fromFavorites) {
      setState(() {
        media[originalIndex]['folderId'] = 'favorites';
      });
      await _save();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ছবিটি Favorites-এ রাখা হয়েছে।')),
        );
      }
      return;
    }

    // আগে গ্যালারি থেকে সরিয়ে দাও।
    setState(() {
      media.removeAt(originalIndex);
    });

    try {
      await _save();

      // Drive-এ থাকা ফাইলটি পেছনে মুছে ফেলো।
      if (driveId.isNotEmpty) {
        await SpaceSyncService.deleteSharedMedia(driveId);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('গ্যালারি থেকে সরানো হয়েছে।'),
        ),
      );
    } catch (error) {
      debugPrint('Gallery delete failed: $error');

      // সার্ভারে মুছতে ব্যর্থ হলে আইটেমটি ফিরিয়ে দাও।
      if (!mounted) return;

      setState(() {
        if (!media.any((m) => '${m['id'] ?? ''}' == itemId)) {
          final insertIndex = originalIndex.clamp(0, media.length);
          media.insert(insertIndex, removedItem);
        }
      });

      try {
        await _save();
      } catch (saveError) {
        debugPrint('Gallery restore failed: $saveError');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ফাইলটি মুছতে সমস্যা হয়েছে। ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করো।',
          ),
        ),
      );
    }
  }

  Future<void> _toggleFavorite(Map<String, dynamic> item) async {
    final id = '${item['id'] ?? ''}';
    final index = media.indexWhere((entry) => '${entry['id'] ?? ''}' == id);
    if (index < 0) return;

    final wasFavorite = media[index]['favorite'] == true;
    setState(() {
      media[index]['favorite'] = !wasFavorite;
      if (wasFavorite && media[index]['folderId'] == 'favorites') {
        media[index]['folderId'] = 'all';
      }
    });
    await _save();
  }

  Future<void> _showMediaMenu(Map<String, dynamic> item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(
                item['favorite'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                color: Colors.redAccent,
              ),
              title: Text(item['favorite'] == true ? 'Remove from Favorites' : 'Add to Favorites'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _toggleFavorite(item);
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Details'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showMediaDetails(item);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.redAccent,
              ),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(sheetContext);

                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: surfaceColor,
                    title: const Text('Delete memory?'),
                    content: const Text(
                      'This item will be removed from this gallery.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, false);
                        },
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.pop(dialogContext, true);
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await _deleteMediaItem(item);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMediaDetails(Map<String, dynamic> item) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Memory details'),
        content: Text(
          'Type: ${item['type']}\n'
          'Added: ${item['createdAt'] ?? 'Unknown'}\n'
          'Added by: ${item['createdByName'] ?? 'অজানা (পুরোনো ফাইল)'}\n'
          'Folder: ${_folderName('${item['folderId']}')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _folderName(String id) {
    return folders.firstWhere(
      (folder) => folder['id'] == id,
      orElse: () => {'name': 'Unknown'},
    )['name'] as String;
  }

  Future<void> _openFolder(Map<String, dynamic> folder) async {
    final id = '${folder['id']}';

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GalleryFolderPage(
          title: '${folder['name']}',
          folderId: id,
          initialItems: _itemsForFolder(id),
          onAdd: (video) => _addMedia(id, video),
          onDelete: (item) async {
            await _deleteMediaItem(item, fromFavorites: id == 'favorites');
          },
          onDetails: _showMediaDetails,
          onFavorite: _toggleFavorite,
          onLongPress: _showMediaMenu,
        ),
      ),
    );

    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _itemsForFolder(String id) {
    if (id == 'all') {
      return media
          .where((item) => item['folderId'] != 'favorites')
          .toList();
    }

    if (id == 'favorites') {
      return media
          .where((item) =>
              item['favorite'] == true || item['folderId'] == 'favorites')
          .toList();
    }

    return media.where((item) => item['folderId'] == id).toList();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Our Memories',
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: _createFolder,
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Keep the little moments that mean everything.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 22),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: folders.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.15,
          ),
          itemBuilder: (context, index) {
            final folder = folders[index];
            final count = _itemsForFolder('${folder['id']}').length;

            return Material(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _openFolder(folder),
                onLongPress: () => _showFolderMenu(folder),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.folder_rounded,
                            size: 42,
                            color: purpleColor,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${folder['name']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '$count items',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton(
                        tooltip: 'Folder options',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showFolderMenu(folder),
                        icon: const Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class GalleryFolderPage extends StatefulWidget {
  final String title;
  final String folderId;
  final List<Map<String, dynamic>> initialItems;
  final Future<Map<String, dynamic>?> Function(bool video) onAdd;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final void Function(Map<String, dynamic>) onDetails;
  final Future<void> Function(Map<String, dynamic>) onFavorite;
  final Future<void> Function(Map<String, dynamic>) onLongPress;

  const GalleryFolderPage({
    super.key,
    required this.title,
    required this.folderId,
    required this.initialItems,
    required this.onAdd,
    required this.onDelete,
    required this.onDetails,
    required this.onFavorite,
    required this.onLongPress,
  });

  @override
  State<GalleryFolderPage> createState() => _GalleryFolderPageState();
}

class _GalleryFolderPageState extends State<GalleryFolderPage> {
  late List<Map<String, dynamic>> items;
  final Map<String, Future<String?>> _pathFutures = {};
  final Set<String> _selectedIds = <String>{};
  bool _selectionMode = false;

  final Map<String, Future<String?>> _videoThumbnailFutures = {};

  Future<String?> _resolveCachedVideoPath(
    Map<String, dynamic> item,
  ) async {
    try {
      final localPath = '${item['path'] ?? ''}'.trim();

      if (localPath.isNotEmpty &&
          await _isUsableGalleryPath(localPath)) {
        return localPath;
      }

      final fileId = (
        item['fileId'] ??
        item['driveFileId'] ??
        ''
      ).toString().trim();

      if (fileId.isEmpty) return null;

      final prefs = await SharedPreferences.getInstance();
      final savedPaths = prefs.getString('galleryLocalPaths');

      if (savedPaths != null && savedPaths.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedPaths);

          if (decoded is Map) {
            final savedPath = '${decoded[fileId] ?? ''}'.trim();

            if (savedPath.isNotEmpty &&
                await _isUsableGalleryPath(savedPath)) {
              return savedPath;
            }
          }
        } catch (_) {}
      }

      final safeId = fileId.replaceAll(
        RegExp(r'[^A-Za-z0-9_-]'),
        '_',
      );

      final isPersonal = item['storage'] == 'personal';
      final prefix =
          'media_${isPersonal ? 'personal' : 'shared'}_${safeId}__';

      final support = await getApplicationSupportDirectory();
      final directory = Directory(
        '${support.path}/eternal_space_media',
      );

      if (!await directory.exists()) return null;

      await for (final entity in directory.list()) {
        if (entity is! File) continue;

        final name = entity.uri.pathSegments.last;

        if (!name.startsWith(prefix) ||
            name.endsWith('.part') ||
            name.endsWith('.complete')) {
          continue;
        }

        final marker = File('${entity.path}.complete');

        try {
          if (!await marker.exists()) continue;

          final length = await entity.length();
          final recordedLength = int.tryParse(
            (await marker.readAsString()).trim(),
          );

          if (length > 0 && recordedLength == length) {
            return entity.path;
          }
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('Cached video lookup error: $error');
    }

    // ক্যাশে না থাকলে ডাউনলোড শুরু করবে না।
    return null;
  }

  Future<String?> _resolveVideoThumbnailPath(
    Map<String, dynamic> item,
  ) {
    final fileId = (
      item['fileId'] ??
      item['driveFileId'] ??
      item['id'] ??
      ''
    ).toString().trim();

    final existing = _videoThumbnailFutures[fileId];
    if (existing != null) return existing;

    late final Future<String?> future;

    future = Future<String?>.microtask(() async {
      try {
        final videoPath = await _resolveCachedVideoPath(item);
        if (videoPath == null) return null;

        final videoFile = File(videoPath);
        if (!await videoFile.exists()) return null;

        // Temporary directory পরিষ্কার হয়ে যেতে পারে, তাই
        // thumbnail স্থায়ী app-support directory-তে রাখো।
        final support = await getApplicationSupportDirectory();
        final safeId = fileId.replaceAll(
          RegExp(r'[^A-Za-z0-9_-]'),
          '_',
        );
        final thumbnailDirectory = Directory(
          '${support.path}/eternal_space_video_thumbnails',
        );
        await thumbnailDirectory.create(recursive: true);

        final thumbnailFile = File(
          '${thumbnailDirectory.path}/video_thumb_$safeId.jpg',
        );

        if (await thumbnailFile.exists() &&
            await thumbnailFile.length() > 0) {
          return thumbnailFile.path;
        }

        final generatedPath = await VideoThumbnail.thumbnailFile(
          video: videoPath,
          thumbnailPath: thumbnailFile.path,
          imageFormat: ImageFormat.JPEG,
          maxHeight: 320,
          quality: 70,
        );

        if (generatedPath == null || generatedPath.isEmpty) {
          return null;
        }

        final generatedFile = File(generatedPath);

        if (await generatedFile.exists() &&
            await generatedFile.length() > 0) {
          return generatedFile.path;
        }
      } catch (error) {
        debugPrint('Video thumbnail error: $error');
      }

      return null;
    });

    _videoThumbnailFutures[fileId] = future;

    future.then((path) {
      if (path == null &&
          identical(_videoThumbnailFutures[fileId], future)) {
        _videoThumbnailFutures.remove(fileId);
      }
    });

    return future;
  }

  String _mediaKey(Map<String, dynamic> item) {
    return '${item['id'] ?? item['fileId'] ?? item['driveFileId'] ?? ''}';
  }

  void _toggleSelection(Map<String, dynamic> item) {
    final key = _mediaKey(item);
    if (key.isEmpty) return;

    setState(() {
      _selectionMode = true;

      if (_selectedIds.contains(key)) {
        _selectedIds.remove(key);
      } else {
        _selectedIds.add(key);
      }

      if (_selectedIds.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  Future<void> _deleteSelectedItems() async {
    final selectedItems = items
        .where((item) => _selectedIds.contains(_mediaKey(item)))
        .toList();

    if (selectedItems.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('নির্বাচিত ফাইল মুছবে?'),
        content: Text(
          '${selectedItems.length}টি ছবি/ভিডিও গ্যালারি থেকে মুছে ফেলা হবে।',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('মুছে ফেলো'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    for (final item in selectedItems) {
      try {
        await widget.onDelete(item);
      } catch (error) {
        debugPrint('Multi-delete failed: $error');
      }
    }

    if (!mounted) return;

    setState(() {
      _selectedIds.clear();
      _selectionMode = false;
    });
  }

  @override
  void initState() {
    super.initState();
    items = List<Map<String, dynamic>>.from(widget.initialItems);
    SpaceStore.syncVersion.addListener(_handleFolderSyncChanged);
  }

  void _handleFolderSyncChanged() {
    if (!mounted) return;

    final latestMedia = SpaceStore.readList('galleryMedia');

    final List<Map<String, dynamic>> updatedItems;

    if (widget.folderId == 'all') {
      updatedItems = latestMedia
          .where((item) => item['folderId'] != 'favorites')
          .toList();
    } else if (widget.folderId == 'favorites') {
      updatedItems = latestMedia
          .where((item) =>
              item['favorite'] == true || item['folderId'] == 'favorites')
          .toList();
    } else {
      updatedItems = latestMedia
          .where((item) => item['folderId'] == widget.folderId)
          .toList();
    }

    setState(() {
      items = List<Map<String, dynamic>>.from(updatedItems);
    });
  }

  @override
  void dispose() {
    SpaceStore.syncVersion.removeListener(_handleFolderSyncChanged);
    super.dispose();
  }

  Future<bool> _isUsableGalleryPath(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;

      final length = await file.length();
      if (length <= 0) return false;

      // App-এর স্থায়ী media cache হলে .complete marker-ও যাচাই করো।
      // পুরোনো picker path-এ marker না থাকলেও সেটি গ্রহণযোগ্য।
      if (path.contains('/eternal_space_media/')) {
        final marker = File('$path.complete');
        if (!await marker.exists()) return false;

        final recordedLength = int.tryParse(
          (await marker.readAsString()).trim(),
        );

        return recordedLength == length;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _resolveLocalPath(
    Map<String, dynamic> item,
  ) {
    final fileId =
        (item['fileId'] ?? item['driveFileId'] ?? '').toString().trim();

    final key = fileId.isNotEmpty
        ? fileId
        : (item['path'] ?? item['id'] ?? '').toString();

    final existing = _pathFutures[key];
    if (existing != null) return existing;

    late final Future<String?> future;

    future = Future<String?>.microtask(() async {
      try {
        // ১. আগে item-এর নিজের local path পরীক্ষা করো।
        final localPath = (item['path'] ?? '').toString().trim();

        if (localPath.isNotEmpty &&
            await _isUsableGalleryPath(localPath)) {
          return localPath;
        }

        if (fileId.isEmpty) return null;

        final isPersonal = item['storage'] == 'personal';
        final isShared = !isPersonal;

        final prefs = await SharedPreferences.getInstance();
        final savedPaths = prefs.getString('galleryLocalPaths');

        Map<String, dynamic> pathMap = {};

        if (savedPaths != null && savedPaths.isNotEmpty) {
          try {
            final decoded = jsonDecode(savedPaths);

            if (decoded is Map) {
              pathMap = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }

        // ২. SharedPreferences-এ সংরক্ষিত path পরীক্ষা করো।
        final savedPath = (pathMap[fileId] ?? '').toString().trim();

        if (savedPath.isNotEmpty &&
            await _isUsableGalleryPath(savedPath)) {
          return savedPath;
        }

        if (savedPath.isNotEmpty) {
          pathMap.remove(fileId);
        }

        // ৩. আগের ডাউনলোডের স্থায়ী cache খোঁজো।
        final cachedPath = await SpaceSyncService.getCachedMediaPath(
          fileId,
          shared: isShared,
        );

        if (cachedPath != null && cachedPath.isNotEmpty) {
          final cachedFile = File(cachedPath);

          if (await cachedFile.exists() &&
              await cachedFile.length() > 0) {
            pathMap[fileId] = cachedPath;
            await prefs.setString(
              'galleryLocalPaths',
              jsonEncode(pathMap),
            );

            return cachedPath;
          }
        }

        // ৪. Cache না থাকলেই শুধু ডাউনলোড করো।
        final originalName =
            (item['driveFileName'] ?? item['name'] ?? 'memory')
                .toString();

        final safeName = '${item['id'] ?? fileId}_$originalName';

        final downloadedPath = isPersonal
            ? await SpaceSyncService.downloadPersonalMedia(
                fileId,
                saveAs: safeName,
              )
            : await SpaceSyncService.downloadMedia(
                fileId,
                saveAs: safeName,
              );

        final downloadedFile = File(downloadedPath);

        if (!await downloadedFile.exists() ||
            await downloadedFile.length() == 0) {
          throw Exception('ডাউনলোড করা ফাইল পাওয়া যায়নি।');
        }

        // ৫. ভবিষ্যতে পুনরায় ব্যবহার করার জন্য path সংরক্ষণ করো।
        pathMap[fileId] = downloadedPath;

        await prefs.setString(
          'galleryLocalPaths',
          jsonEncode(pathMap),
        );

        return downloadedPath;
      } catch (error) {
        debugPrint('Gallery download error: $error');
        return null;
      }
    });

    // সফল Future ক্যাশে রাখো, যাতে একই পেজ rebuild হলে আবার
    // path lookup/download শুরু না হয়। ব্যর্থ হলে retry করার সুযোগ থাকবে।
    future.then((path) {
      if (path == null && identical(_pathFutures[key], future)) {
        _pathFutures.remove(key);
      }
    });

    _pathFutures[key] = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: Text(widget.title),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: 'নির্বাচিত ফাইল মুছুন',
              onPressed: _selectedIds.isEmpty ? null : _deleteSelectedItems,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          TextButton.icon(
            onPressed: () {
              setState(() {
                _selectionMode = !_selectionMode;
                _selectedIds.clear();
              });
            },
            icon: Icon(
              _selectionMode
                  ? Icons.close_rounded
                  : Icons.checklist_rounded,
              color: pinkColor,
            ),
            label: Text(
              _selectionMode ? 'বাতিল' : 'নির্বাচন',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          IconButton(
            onPressed: _chooseAddType,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(
              child: Text(
                'No memories here yet.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: items.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                final video = item['type'] == 'video';

                return FutureBuilder<String?>(
                  future: video
                      ? Future<String?>.value(null)
                      : _resolveLocalPath(item),
                  builder: (context, snapshot) {
                    final path = snapshot.data;

                    return GestureDetector(
                      onLongPress: () {
                        if (!_selectionMode) {
                          widget.onLongPress(item);
                        }
                      },
                      onTap: () async {
                        if (_selectionMode) {
                          _toggleSelection(item);
                          return;
                        }

                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GalleryMediaViewerPage(
                              items: List<Map<String, dynamic>>.from(items),
                              initialIndex: index,
                              resolvePath: _resolveLocalPath,
                              onFavorite: widget.onFavorite,
                              onDelete: widget.onDelete,
                              onDetails: widget.onDetails,
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (video)
                              FutureBuilder<String?>(
                                future: _resolveVideoThumbnailPath(item),
                                builder: (context, snapshot) {
                                  final thumbnailPath = snapshot.data;

                                  return Container(
                                    color: surfaceColor,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      alignment: Alignment.center,
                                      children: [
                                        if (thumbnailPath != null)
                                          Image.file(
                                            File(thumbnailPath),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) {
                                              return const ColoredBox(
                                                color: surfaceColor,
                                                child: Icon(
                                                  Icons.videocam_rounded,
                                                  size: 42,
                                                ),
                                              );
                                            },
                                          )
                                        else
                                          const Center(
                                            child: Icon(
                                              Icons.videocam_rounded,
                                              size: 42,
                                              color: Colors.white54,
                                            ),
                                          ),
                                        const Center(
                                          child: Icon(
                                            Icons.play_circle_fill_rounded,
                                            size: 50,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              )
                            else if (path == null)
                              Container(
                                color: surfaceColor,
                                child: Center(
                                  child: snapshot.connectionState ==
                                          ConnectionState.waiting
                                      ? const CircularProgressIndicator()
                                      : const Icon(
                                          Icons.cloud_download_outlined,
                                          size: 42,
                                        ),
                                ),
                              )
                            else
                              Image.file(
                                File(path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) {
                                  return const ColoredBox(
                                    color: surfaceColor,
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                    ),
                                  );
                                },
                              ),
                            if (video)
                              const Align(
                                alignment: Alignment.bottomRight,
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.videocam_rounded),
                                ),
                              ),
                            if (_selectionMode)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: _selectedIds.contains(_mediaKey(item))
                                        ? pinkColor
                                        : Colors.black54,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white70),
                                  ),
                                  child: Icon(
                                    _selectedIds.contains(_mediaKey(item))
                                        ? Icons.check_rounded
                                        : Icons.circle_outlined,
                                    size: 22,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  Future<void> _chooseAddType() async {
    final video = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: surfaceColor,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Add image'),
              onTap: () => Navigator.pop(sheetContext, false),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Add video'),
              onTap: () => Navigator.pop(sheetContext, true),
            ),
          ],
        ),
      ),
    );

    if (video == null) return;

    final item = await widget.onAdd(video);

    if (item != null && mounted) {
      setState(() {
        items.add(item);
      });
    }
  }
}

// ============================================================
// GALLERY MEDIA VIEWER & PLAYERS
// ============================================================

class GalleryMediaViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> items;
  final int initialIndex;
  final Future<String?> Function(Map<String, dynamic>) resolvePath;
  final Future<void> Function(Map<String, dynamic>) onFavorite;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final void Function(Map<String, dynamic>) onDetails;

  const GalleryMediaViewerPage({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.resolvePath,
    required this.onFavorite,
    required this.onDelete,
    required this.onDetails,
  });

  @override
  State<GalleryMediaViewerPage> createState() =>
      _GalleryMediaViewerPageState();
}

class _GalleryMediaViewerPageState
    extends State<GalleryMediaViewerPage> {
  late final PageController _pageController;
  late int currentIndex;

  @override
  void initState() {
    super.initState();
    currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: currentIndex);
  }

  int? _previousVideoIndex(int from) {
    for (var i = from - 1; i >= 0; i--) {
      if (widget.items[i]['type'] == 'video') return i;
    }
    return null;
  }

  int? _nextVideoIndex(int from) {
    for (var i = from + 1; i < widget.items.length; i++) {
      if (widget.items[i]['type'] == 'video') return i;
    }
    return null;
  }

  void _goTo(int? index) {
    if (index == null) return;

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text('${currentIndex + 1} / ${widget.items.length}'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: widget.items[currentIndex]['favorite'] == true
                ? 'Remove from Favorites'
                : 'Add to Favorites',
            onPressed: () => widget.onFavorite(widget.items[currentIndex]),
            icon: Icon(
              widget.items[currentIndex]['favorite'] == true
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: widget.items[currentIndex]['favorite'] == true
                  ? Colors.redAccent
                  : Colors.white,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              final item = widget.items[currentIndex];
              if (action == 'details') {
                widget.onDetails(item);
              } else if (action == 'delete') {
                await widget.onDelete(item);
                if (mounted) Navigator.pop(context);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'details', child: Text('Details')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.items.length,
        onPageChanged: (index) {
          setState(() => currentIndex = index);
        },
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final isVideo = item['type'] == 'video';

          return FutureBuilder<String?>(
            future: widget.resolvePath(item),
            builder: (context, snapshot) {
              final path = snapshot.data;

              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (path == null) {
                return const Center(
                  child: Text(
                    'ফাইল পাওয়া যায়নি। ইন্টারনেট ও Drive পরীক্ষা করো।',
                    textAlign: TextAlign.center,
                  ),
                );
              }

              if (!isVideo) {
                return Center(
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) {
                        return const Text('ছবিটি খোলা যাচ্ছে না।');
                      },
                    ),
                  ),
                );
              }

              return _GalleryVideoPlayer(
                key: ValueKey(path),
                path: path,
                onPrevious: () => _goTo(_previousVideoIndex(index)),
                onNext: () => _goTo(_nextVideoIndex(index)),
              );
            },
          );
        },
      ),
    );
  }
}

class _GalleryVideoPlayer extends StatefulWidget {
  final String path;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _GalleryVideoPlayer({
    super.key,
    required this.path,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  State<_GalleryVideoPlayer> createState() =>
      _GalleryVideoPlayerState();
}

class _GalleryVideoPlayerState extends State<_GalleryVideoPlayer> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final video = VideoPlayerController.file(File(widget.path));
    _controller = video;

    try {
      await video.initialize();

      if (!mounted) {
        await video.dispose();
        return;
      }

      setState(() {});
      await video.play();
    } catch (error) {
      await video.dispose();

      if (mounted) {
        setState(() {
          _controller = null;
          _error = 'ভিডিও খোলা যাচ্ছে না। আবার চেষ্টা করো।';
        });
      }
    }
  }

  Future<void> _togglePlayback() async {
    final video = _controller;
    if (video == null || !video.value.isInitialized) return;

    if (video.value.isPlaying) {
      await video.pause();
    } else {
      await video.play();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _controller;

    if (_error != null) {
      return Center(child: Text(_error!));
    }

    if (video == null || !video.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: video.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(video),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'আগের ভিডিও',
                      onPressed: widget.onPrevious,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    Expanded(
                      child: VideoProgressIndicator(
                        video,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 4,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: video,
                      builder: (context, value, child) {
                        return IconButton(
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
                          onPressed: _togglePlayback,
                          icon: Icon(
                            value.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: 'পরের ভিডিও',
                      onPressed: widget.onNext,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ImageViewerPage extends StatelessWidget {
  final String path;

  const ImageViewerPage({
    super.key,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Text('ছবিটি পাওয়া যাচ্ছে না।');
            },
          ),
        ),
      ),
    );
  }
}

class VideoViewerPage extends StatelessWidget {
  final String path;

  const VideoViewerPage({
    super.key,
    required this.path,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: _GalleryVideoPlayer(
        path: path,
        onPrevious: null,
        onNext: null,
      ),
    );
  }
}

// ============================================================
// SPECIAL DATES
// ============================================================

class SpecialDatesPage extends StatefulWidget {
  const SpecialDatesPage({super.key});

  @override
  State<SpecialDatesPage> createState() => _SpecialDatesPageState();
}

class _SpecialDatesPageState extends State<SpecialDatesPage> {
  List<Map<String, dynamic>> dates = [];

  @override
  void initState() {
    super.initState();
    dates = SpaceStore.readList('specialDates');
    SpaceStore.syncVersion.addListener(_handleSyncVersionChanged);
  }

  void _handleSyncVersionChanged() {
    if (!mounted) return;

    final latestDates = SpaceStore.readList('specialDates');

    setState(() {
      dates = latestDates;
    });
  }

  @override
  void dispose() {
    SpaceStore.syncVersion.removeListener(_handleSyncVersionChanged);
    super.dispose();
  }

  Future<void> _save() {
    return SpaceStore.saveList('specialDates', dates);
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final titleController =
        TextEditingController(text: '${existing?['title'] ?? ''}');
    final noteController =
        TextEditingController(text: '${existing?['note'] ?? ''}');

    DateTime selectedDate =
        DateTime.tryParse('${existing?['date'] ?? ''}') ?? DateTime.now();

    bool yearly = existing?['yearly'] != false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: surfaceColor,
          title: Text(existing == null ? 'Add special date' : 'Edit date'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Event name',
                    hintText: 'Our anniversary',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_rounded),
                  label: Text(
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );

                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: yearly,
                  onChanged: (value) {
                    setDialogState(() => yearly = value ?? true);
                  },
                  title: const Text('Repeat every year'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;

                Navigator.pop(dialogContext, {
                  'title': title,
                  'note': noteController.text.trim(),
                  'date': selectedDate.toIso8601String(),
                  'yearly': yearly,
                });
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    titleController.dispose();
    noteController.dispose();

    if (result == null) return;

    final id =
        '${existing?['id'] ?? DateTime.now().microsecondsSinceEpoch}';

    result['id'] = id;

    setState(() {
      final index = dates.indexWhere((d) => d['id'] == id);

      if (index >= 0) {
        dates[index] = result;
      } else {
        dates.add(result);
      }
    });

    await _save();
    await _scheduleReminder(result);
  }

  Future<void> _scheduleReminder(Map<String, dynamic> item) async {
    final date = DateTime.tryParse('${item['date']}');
    if (date == null) return;

    final now = DateTime.now();
    final yearly = item['yearly'] != false;

    DateTime reminderDate = DateTime(
      yearly ? now.year : date.year,
      date.month,
      date.day,
      9,
    );

    if (yearly) {
      if (!reminderDate.isAfter(now)) {
        reminderDate = DateTime(
          now.year + 1,
          date.month,
          date.day,
          9,
        );
      }
    } else if (!reminderDate.isAfter(now)) {
      return;
    }

    final id = '${item['id']}'.hashCode & 0x7fffffff;

    await notifications.cancel(id);

    await notifications.zonedSchedule(
      id,
      'A special day is coming 💗',
      '${item['title']} — ${item['note'] ?? ''}',
      tz.TZDateTime.from(reminderDate, tz.local),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'special_dates',
          'Special Dates',
          channelDescription: 'Reminders for your special days',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents:
          yearly ? DateTimeComponents.dateAndTime : null,
    );
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final id = '${item['id']}'.hashCode & 0x7fffffff;

    await notifications.cancel(id);

    setState(() {
      dates.removeWhere((d) => d['id'] == item['id']);
    });

    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...dates]
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: const Text('Special Dates'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEdit(),
        child: const Icon(Icons.add_rounded),
      ),
      body: sorted.isEmpty
          ? const Center(
              child: Text(
                'Add the dates that mean the most to you.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sorted.length,
              itemBuilder: (context, index) {
                final item = sorted[index];
                final date = DateTime.tryParse('${item['date']}');
                final note = '${item['note'] ?? ''}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0x33FF5FA2),
                      child: Icon(
                        Icons.favorite_rounded,
                        color: pinkColor,
                      ),
                    ),
                    title: Text('${item['title']}'),
                    subtitle: Text(
                      '${date?.day}/${date?.month}/${date?.year}'
                      '${item['yearly'] == true ? ' • Every year' : ''}'
                      '${note.isNotEmpty ? '\n$note' : ''}',
                    ),
                    isThreeLine: note.isNotEmpty,
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _addOrEdit(existing: item);
                        } else if (value == 'delete') {
                          _delete(item);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================
// LOVE NOTES
// ============================================================

class LoveNotesPage extends StatefulWidget {
  const LoveNotesPage({super.key});

  @override
  State<LoveNotesPage> createState() => _LoveNotesPageState();
}

class _LoveNotesPageState extends State<LoveNotesPage> {
  List<Map<String, dynamic>> notes = [];

  @override
  void initState() {
    super.initState();
    notes = SpaceStore.readList('loveNotes');
    SpaceStore.syncVersion.addListener(_handleSyncVersionChanged);
  }

  void _handleSyncVersionChanged() {
    if (!mounted) return;

    final latestNotes = SpaceStore.readList('loveNotes');

    setState(() {
      notes = latestNotes;
    });
  }

  @override
  void dispose() {
    SpaceStore.syncVersion.removeListener(_handleSyncVersionChanged);
    super.dispose();
  }

  Future<void> _addNote() async {
    final controller = TextEditingController();

    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Write a love note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Write from your heart...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, controller.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (text == null || text.isEmpty) return;

    setState(() {
      notes.insert(0, {
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'text': text,
        'date': DateTime.now().toIso8601String(),
      });
    });

    await SpaceStore.saveList('loveNotes', notes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: const Text('Love Notes'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNote,
        child: const Icon(Icons.edit_rounded),
      ),
      body: notes.isEmpty
          ? const Center(
              child: Text(
                'Save little words of love here.',
                style: TextStyle(color: Colors.white54),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: notes.length,
              itemBuilder: (context, index) {
                final note = notes[index];

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: pinkColor.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.favorite, color: pinkColor),
                      const SizedBox(width: 12),
                      Expanded(child: Text('${note['text']}')),
                      IconButton(
                        onPressed: () async {
                          setState(() => notes.removeAt(index));
                          await SpaceStore.saveList('loveNotes', notes);
                        },
                        icon: const Icon(Icons.delete_outline, size: 20),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================
// SETTINGS
// ============================================================

class SettingsPage extends StatefulWidget {
  final String partnerOne;
  final String partnerTwo;
  final void Function(String first, String second) onSave;

  const SettingsPage({
    super.key,
    required this.partnerOne,
    required this.partnerTwo,
    required this.onSave,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController firstController;

  @override
  void initState() {
    super.initState();
    firstController = TextEditingController(text: widget.partnerOne);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.partnerOne != widget.partnerOne) {
      firstController.text = widget.partnerOne;
    }
  }

  @override
  void dispose() {
    firstController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final ownName = firstController.text.trim();

    if (ownName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('নিজের নাম লিখতে হবে।')),
      );
      return;
    }

    try {
      await RelationshipService.saveOwnName(ownName);
      await SpaceStore.saveString('partnerOne', ownName);

      widget.onSave(ownName, widget.partnerTwo);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('নিজের নাম সংরক্ষণ হয়েছে।')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('নাম সংরক্ষণ করা যায়নি: $e')),
      );
    }
  }

  Future<void> _pickProfilePhoto() async {
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('আগে অ্যাকাউন্টে সাইন ইন করো।'),
        ),
      );
      return;
    }

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1000,
        maxHeight: 1000,
      );

      if (!mounted || picked == null) return;

      final sourceFile = File(picked.path);

      if (!await sourceFile.exists() ||
          await sourceFile.length() == 0) {
        throw Exception('নির্বাচিত ছবিটি পাওয়া যায়নি।');
      }

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        aspectRatio: const CropAspectRatio(
          ratioX: 1,
          ratioY: 1,
        ),
        maxWidth: 384,
        maxHeight: 384,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 70,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'প্রোফাইল ছবি ঠিক করো',
            toolbarColor: const Color(0xFF111026),
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: pinkColor,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            cropStyle: CropStyle.circle,
            showCropGrid: true,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: 'প্রোফাইল ছবি ঠিক করো',
            aspectRatioLockEnabled: true,
            resetAspectRatioEnabled: false,
            cropStyle: CropStyle.circle,
          ),
        ],
      );

      if (!mounted || cropped == null) return;

      final croppedFile = File(cropped.path);

      if (!await croppedFile.exists()) {
        throw Exception('ক্রপ করা ছবিটি পাওয়া যায়নি।');
      }

      final bytes = await croppedFile.readAsBytes();

      if (bytes.isEmpty || bytes.length > 500 * 1024) {
        throw Exception(
          'ছবিটি ৫০০ KB-এর বেশি। ছোট ছবি দিয়ে আবার চেষ্টা করো।',
        );
      }

      final name = firstController.text.trim().isNotEmpty
          ? firstController.text.trim()
          : 'User';

      await ChatSyncService.saveMyProfile(
        name: name,
        photoBase64: base64Encode(bytes),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('প্রোফাইল ছবি সংরক্ষণ হয়েছে।'),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('Profile photo error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'প্রোফাইল ছবি সংরক্ষণ করা যায়নি: $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Settings',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Make your little space feel like yours.',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 25),
        const SectionHeading(title: 'Couple profile'),
        const SizedBox(height: 12),
        TextField(
          controller: firstController,
          decoration: const InputDecoration(
            labelText: 'Your name',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _saveProfile,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save profile'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _pickProfilePhoto,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('প্রোফাইল ছবি সেট করো'),
        ),
        const SizedBox(height: 24),
        const SectionHeading(title: 'Data & downloads'),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: DataSaverSettings.enabled,
          builder: (context, enabled, _) {
            return Card(
              color: surfaceColor,
              child: SwitchListTile(
                secondary: Icon(
                  enabled
                      ? Icons.cloud_download_outlined
                      : Icons.touch_app_outlined,
                  color: pinkColor,
                ),
                title: const Text('Data Saver'),
                subtitle: Text(
                  enabled
                      ? 'Disable auto-download for chat photos/videos'
                      : 'Chat photos/videos will be downloaded automatically',
                ),
                value: enabled,
                activeColor: pinkColor,
                onChanged: (value) async {
                  try {
                    await DataSaverSettings.setEnabled(value);
                  } catch (error) {
                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Data Saver সেটিং সংরক্ষণ করা যায়নি।',
                        ),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        const SectionHeading(title: 'App information'),
        const SizedBox(height: 10),
        const Card(
          color: surfaceColor,
          child: ListTile(
            leading: Icon(Icons.lock_outline, color: blueColor),
            title: Text('Private by design'),
            subtitle: Text(
              'This version stores supported app data locally on this device.',
            ),
          ),
        ),
        const Card(
          color: surfaceColor,
          child: ListTile(
            leading: Icon(Icons.cloud_outlined, color: purpleColor),
            title: Text('Firebase Sync'),
            subtitle: Text(
              'Firebase sync is active with partner connection.',
            ),
          ),
        ),
        const Card(
          color: surfaceColor,
          child: ListTile(
            leading: Icon(
              Icons.notifications_active_outlined,
              color: pinkColor,
            ),
            title: Text('Special date reminders'),
            subtitle: Text(
              'Reminders can be scheduled for dates you add.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Center(
          child: Text(
            'Couple Zone • Made with love',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ETERNAL SPACE - COMPLAINT MODEL
// ============================================================

class SpaceComplaint {
  final String id;
  final String author;
  final String title;
  final String details;
  final String createdAt;

  const SpaceComplaint({
    required this.id,
    required this.author,
    required this.title,
    required this.details,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'author': author,
        'title': title,
        'details': details,
        'createdAt': createdAt,
      };

  factory SpaceComplaint.fromMap(Map<String, dynamic> map) {
    return SpaceComplaint(
      id: map['id']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      createdAt: map['createdAt']?.toString() ?? '',
    );
  }
}

// ============================================================
// ETERNAL SPACE - COMPLAINTS PAGE
// ============================================================

class ComplaintsPage extends StatefulWidget {
  const ComplaintsPage({super.key});

  @override
  State<ComplaintsPage> createState() => _ComplaintsPageState();
}

class _ComplaintsPageState extends State<ComplaintsPage> {
  List<SpaceComplaint> complaints = [];

  @override
  void initState() {
    super.initState();
    _loadComplaints();
    SpaceStore.syncVersion.addListener(_handleSyncVersionChanged);
  }

  void _loadComplaints() {
    final data = SpaceStore.readList('spaceComplaints');
    complaints = data.map(SpaceComplaint.fromMap).toList();
  }

  void _handleSyncVersionChanged() {
    if (!mounted) return;

    final data = SpaceStore.readList('spaceComplaints');
    final latestComplaints = data.map(SpaceComplaint.fromMap).toList();

    setState(() {
      complaints = latestComplaints;
    });
  }

  @override
  void dispose() {
    SpaceStore.syncVersion.removeListener(_handleSyncVersionChanged);
    super.dispose();
  }

  Future<void> _saveComplaints() async {
    await SpaceStore.saveList(
      'spaceComplaints',
      complaints.map((item) => item.toMap()).toList(),
    );
  }

  Future<void> _editComplaint({SpaceComplaint? existing}) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final detailsController =
        TextEditingController(text: existing?.details ?? '');
    String author = existing?.author ?? 'You';

    final result = await showDialog<SpaceComplaint>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: surfaceColor,
              title: Text(
                existing == null ? 'New Complaint' : 'Edit Complaint',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: author,
                      decoration: const InputDecoration(
                        labelText: 'Complaint by',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'You',
                          child: Text('You'),
                        ),
                        DropdownMenuItem(
                          value: 'Partner',
                          child: Text('Partner'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() => author = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Complaint title',
                        hintText: 'What happened?',
                      ),
                      maxLength: 80,
                    ),
                    TextField(
                      controller: detailsController,
                      decoration: const InputDecoration(
                        labelText: 'Details',
                        hintText: 'Explain the complaint...',
                      ),
                      maxLines: 4,
                      maxLength: 1000,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final details = detailsController.text.trim();

                    if (title.isEmpty || details.isEmpty) return;

                    Navigator.pop(
                      dialogContext,
                      SpaceComplaint(
                        id: existing?.id ??
                            DateTime.now()
                                .microsecondsSinceEpoch
                                .toString(),
                        author: author,
                        title: title,
                        details: details,
                        createdAt: existing?.createdAt ??
                            DateTime.now().toIso8601String(),
                      ),
                    );
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    titleController.dispose();
    detailsController.dispose();

    if (result == null) return;

    setState(() {
      final index = complaints.indexWhere((c) => c.id == result.id);
      if (index == -1) {
        complaints.insert(0, result);
      } else {
        complaints[index] = result;
      }
    });

    await _saveComplaints();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: const Text('Complaints Box'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editComplaint(),
        icon: const Icon(Icons.add),
        label: const Text('New Complaint'),
      ),
      body: complaints.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No complaints yet',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Share what is bothering you and talk it out together.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: complaints.length,
              itemBuilder: (context, index) {
                final complaint = complaints[index];

                return Card(
                  color: surfaceColor,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0x33FF5FA2),
                      child: Icon(
                        complaint.author == 'You'
                            ? Icons.person
                            : Icons.favorite_outline,
                        color: pinkColor,
                      ),
                    ),
                    title: Text(
                      complaint.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${complaint.author} • ${complaint.details}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: surfaceColor,
                          title: Text(complaint.title),
                          content: SingleChildScrollView(
                            child: Text(
                              'By: ${complaint.author}\n\n'
                              '${complaint.details}',
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _editComplaint(existing: complaint);
                              },
                              child: const Text('Edit'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
            ),
    );
  }
}

// ============================================================
// FIREBASE COMPLAINT STORAGE
// ============================================================

class FirebaseComplaintStore {
  static const String spaceId = 'REPLACE_WITH_SHARED_SPACE_ID';

  static CollectionReference<Map<String, dynamic>> get complaintsRef =>
      FirebaseFirestore.instance
          .collection('privateSpaces')
          .doc(spaceId)
          .collection('complaints');

  static Future<void> addComplaint(
    SpaceComplaint complaint,
  ) async {
    await complaintsRef.doc(complaint.id).set({
      ...complaint.toMap(),
      'createdAt': complaint.createdAt,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateComplaint(
    SpaceComplaint complaint,
  ) async {
    await complaintsRef.doc(complaint.id).update({
      ...complaint.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteComplaint(String id) async {
    await complaintsRef.doc(id).delete();
  }

  static Stream<List<SpaceComplaint>> watchComplaints() {
    return complaintsRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => SpaceComplaint.fromMap({
                  ...doc.data(),
                  'id': doc.id,
                }),
              )
              .toList(),
        );
  }
}

// ============================================================
// TYPING DOTS INDICATOR WIDGET
// ============================================================


class PresenceStatusLabel extends StatefulWidget {
  const PresenceStatusLabel({
    super.key,
    required this.isTyping,
    required this.isOnline,
    this.lastSeen,
  });

  final bool isTyping;
  final bool isOnline;
  final dynamic lastSeen;

  @override
  State<PresenceStatusLabel> createState() => _PresenceStatusLabelState();
}

class _PresenceStatusLabelState extends State<PresenceStatusLabel> {
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !widget.isOnline && !widget.isTyping) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PresenceStatusLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lastSeen != widget.lastSeen ||
        oldWidget.isOnline != widget.isOnline ||
        oldWidget.isTyping != widget.isTyping) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  DateTime? _lastSeenDate() {
    final value = widget.lastSeen;
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse('${value ?? ''}')?.toLocal();
  }

  String _label() {
    if (widget.isTyping) return 'Typing...';
    if (widget.isOnline) return 'Active now';

    final lastSeen = _lastSeenDate();
    if (lastSeen == null) return 'Offline';

    final seconds = DateTime.now().difference(lastSeen).inSeconds;
    if (seconds < 60) return 'Active ${seconds < 0 ? 0 : seconds} sec ago';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return 'Active ${minutes} min ago';
    final hours = minutes ~/ 60;
    if (hours < 24) return 'Active ${hours} hr ago';
    final days = hours ~/ 24;
    return 'Active ${days} day${days == 1 ? '' : 's'} ago';
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label(),
      style: TextStyle(
        fontSize: 11,
        color: widget.isTyping
            ? pinkColor
            : (widget.isOnline ? Colors.greenAccent : Colors.white54),
      ),
    );
  }
}

class TypingDotsIndicator extends StatefulWidget {
  const TypingDotsIndicator({super.key});

  @override
  State<TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: AnimatedBuilder(
          animation: _controller,
          child: const SizedBox.shrink(),
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                final phase = _controller.value * 2 * pi - index * (2 * pi / 3);
                final lift = (sin(phase) + 1) / 2;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Transform.translate(
                    offset: Offset(0, -4 * lift),
                    child: Opacity(
                      opacity: 0.4 + 0.6 * lift,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: pinkColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
