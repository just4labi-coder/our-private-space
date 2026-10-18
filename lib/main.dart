import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:video_player/video_player.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'screens/partner_connection_page.dart';
import 'services/space_sync_service.dart';
import 'services/chat_sync_service.dart';
import 'screens/auth_screen.dart';
import 'services/auth_service.dart';
import 'services/relationship_service.dart';
import 'services/private_space_service.dart';
import 'services/push_notification_service.dart';

final ValueNotifier<String?> orbitSharedText = ValueNotifier<String?>(null);
const MethodChannel orbitShareChannel = MethodChannel('com.privatespace.ourspace/share_intent');

const Color backgroundColor = Color(0xFF070513);
const Color surfaceColor = Color(0xFF111026);
const Color blueColor = Color(0xFF172554);
Future<File> _makeCompatibleVideo(File source) async {
  if (!await source.exists() || await source.length() <= 0) {
    throw Exception('ভিডিও ফাইলটি পাওয়া যায়নি।');
  }

  // MP4/H.264 720p output is broadly supported on Android devices.
  final result = await VideoCompress.compressVideo(
    source.path,
    quality: VideoQuality.Res1280x720Quality,
    deleteOrigin: false,
    includeAudio: true,
  );
  final output = result?.file;
  if (output == null || !await output.exists() || await output.length() <= 0) {
    throw Exception('ভিডিও অপটিমাইজ করা যায়নি।');
  }
  return output;
}

const Color pinkColor = Color(0xFFFF2E93);
const Color purpleColor = Color(0xFF8B5CF6);
const String orbitNotificationChannelId = 'orbit_partner_updates_v7';
const String orbitMessageNotificationGroup = 'com.privatespace.ourspace.MESSAGE_GROUP';
const String orbitUpdateNotificationGroup = 'com.privatespace.ourspace.UPDATE_GROUP';
const int orbitMessageSummaryNotificationId = 7000;
bool orbitChatVisible = false;

@pragma('vm:entry-point')
Future<void> orbitFirebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Keep compatibility with the currently deployed Worker: Android already shows
  // notification-payload pushes. Data-only pushes use the grouped local handler below.
  if (message.notification != null) return;
  try {
    await Firebase.initializeApp();
    await NotificationPrivacySettings.load();
    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@drawable/ic_stat_orbit_custom'),
    );
    await notifications.initialize(initializationSettings);
    final androidNotifications = notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(
      AndroidNotificationChannel(
        orbitNotificationChannelId,
        'Orbit Two messages',
        description: 'Messages and updates from your partner',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 350, 180, 350]),
        showBadge: true,
      ),
    );
    final data = message.data;
    final kind = data['kind']?.toString() ?? 'message';
    final messageId = data['messageId']?.toString() ?? '';
    await NotificationPrivacySettings.showPartnerNotification(
      detailedTitle: data['detailedTitle']?.toString() ?? message.notification?.title ?? 'Orbit Two',
      detailedBody: data['detailedBody']?.toString() ?? message.notification?.body ?? 'You have a new message.',
      privateTitle: data['privateTitle']?.toString() ?? (kind == 'change' ? 'Check change' : 'Check message'),
      privateBody: data['privateBody']?.toString() ?? (kind == 'change' ? 'Your partner changed shared data.' : 'You have a new message.'),
      kind: kind,
      id: kind == 'message'
          ? NotificationPrivacySettings.notificationIdForMessage(messageId.isNotEmpty ? messageId : DateTime.now().microsecondsSinceEpoch.toString())
          : DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
    );
  } catch (error, stackTrace) {
    debugPrint('Background notification error: $error\n$stackTrace');
  }
}

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String? startupError;
  var firebaseReady = false;

  // Firebase failure must not leave the app stuck on a blank white screen.
  try {
    await Firebase.initializeApp();
    firebaseReady = true;
  } catch (error, stackTrace) {
    startupError = error.toString();
    debugPrint('Firebase initialization failed: $error\n$stackTrace');
  }

  try {
    await DataSaverSettings.load();
  } catch (error) {
    debugPrint('Data saver settings load failed: $error');
  }

  try {
    await InteractionFeedbackSettings.load();
  } catch (error) {
    debugPrint('Interaction feedback settings load failed: $error');
  }

  try {
    await NotificationPrivacySettings.load();
  } catch (error) {
    debugPrint('Notification privacy settings load failed: $error');
  }

  try {
    tz_data.initializeTimeZones();
  } catch (error) {
    debugPrint('Timezone initialization failed: $error');
  }

  try {
    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_stat_orbit');
    const initializationSettings = InitializationSettings(
      android: androidSettings,
    );
    await notifications.initialize(initializationSettings);
    final androidNotifications = notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidNotifications?.createNotificationChannel(
      AndroidNotificationChannel(
        orbitNotificationChannelId,
        'Orbit Two messages',
        description: 'Messages and updates from your partner',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 350, 180, 350]),
        showBadge: true,
      ),
    );
  } catch (error) {
    debugPrint('Local notification initialization failed: $error');
  }

  if (firebaseReady) {
    FirebaseMessaging.onBackgroundMessage(orbitFirebaseMessagingBackgroundHandler);
    try {
      await PushNotificationService.initialize().timeout(
        const Duration(seconds: 4),
      );
    } on TimeoutException {
      debugPrint('Push notification initialization timed out; continuing startup.');
    } catch (error) {
      debugPrint('Push notification initialization failed: $error');
    }

    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      final kind = data['kind']?.toString() ?? 'message';
      if (kind == 'message' && orbitChatVisible) {
        unawaited(NotificationPrivacySettings.clearMessageNotifications());
        return;
      }
      final messageId = data['messageId']?.toString() ?? '';
      // Older deployed Worker versions omit messageId; Firestore's real-time
      // listener supplies the same notification with a stable ID instead.
      if (kind == 'message' && messageId.isEmpty) return;
      unawaited(NotificationPrivacySettings.showPartnerNotification(
        detailedTitle: data['detailedTitle']?.toString() ?? message.notification?.title ?? 'Orbit Two',
        detailedBody: data['detailedBody']?.toString() ?? message.notification?.body ?? 'You have an update.',
        privateTitle: data['privateTitle']?.toString() ?? (kind == 'change' ? 'Check change' : 'Check message'),
        privateBody: data['privateBody']?.toString() ?? (kind == 'change' ? 'Your partner changed shared data.' : 'You have a new message.'),
        kind: kind,
        id: kind == 'message' ? NotificationPrivacySettings.notificationIdForMessage(messageId.isNotEmpty ? messageId : DateTime.now().microsecondsSinceEpoch.toString()) : DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      ));
    });

  }

  try {
    await SpaceStore.init();
  } catch (error) {
    debugPrint('Local storage initialization failed: $error');
  }

  runApp(EternalSpaceApp(startupError: startupError));
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

class InteractionFeedbackSettings {
  InteractionFeedbackSettings._();

  static const String _hapticsKey = 'interactionHapticsEnabled';
  static const String _soundsKey = 'interactionSoundsEnabled';
  static final ValueNotifier<bool> hapticsEnabled = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> soundsEnabled = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hapticsEnabled.value = prefs.getBool(_hapticsKey) ?? true;
    soundsEnabled.value = prefs.getBool(_soundsKey) ?? true;
  }

  static Future<void> setHapticsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hapticsKey, value);
    hapticsEnabled.value = value;
  }

  static Future<void> setSoundsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundsKey, value);
    soundsEnabled.value = value;
  }

  static Future<void> vibrate() async {
    if (!hapticsEnabled.value) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (error) {
      debugPrint('Interaction haptic feedback unavailable: $error');
    }
  }

  static Future<void> _playAssetSound(String asset) async {
    if (!soundsEnabled.value) return;
    final player = AudioPlayer();
    try {
      await player.play(AssetSource(asset));
      unawaited(
        player.onPlayerComplete.first.then<void>((_) async {
          await player.dispose();
        }).catchError((Object error) {
          debugPrint('Feedback sound cleanup failed: $error');
        }),
      );
    } catch (error) {
      await player.dispose();
      debugPrint('Feedback sound unavailable: $error');
    }
  }

  static Future<void> playTypingSound() =>
      _playAssetSound('sounds/orbit_typing.wav');

  static Future<void> playSeenSound() =>
      _playAssetSound('sounds/orbit_seen.wav');

  // Use a dedicated bundled sound; Android system clicks can be silent.
  static Future<void> playSentSound() =>
      _playAssetSound('sounds/orbit_sent.wav');
}

class NotificationPrivacySettings {
  NotificationPrivacySettings._();
  static const String _key = 'hideNotificationDetails';
  static const String _notificationsKey = 'notificationsEnabled';
  static const String _messageIdsKey = 'orbitMessageNotificationIds';
  static const String _messageLinesKey = 'orbitMessageNotificationLines';
  static final ValueNotifier<bool> hideDetails = ValueNotifier<bool>(false);
  static final ValueNotifier<bool> notificationsEnabled = ValueNotifier<bool>(true);
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    hideDetails.value = prefs.getBool(_key) ?? false;
    notificationsEnabled.value = prefs.getBool(_notificationsKey) ?? true;
  }
  static int notificationIdForMessage(String messageId) {
    var hash = 0;
    for (final unit in messageId.codeUnits) { hash = (hash * 31 + unit) & 0x7fffffff; }
    return hash == 0 ? 7001 : hash;
  }
  static Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, value);
    notificationsEnabled.value = value;
    await PushNotificationService.setNotificationsEnabled(value);
    if (!value) await clearMessageNotifications();
  }
  static Future<void> setHideDetails(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
    hideDetails.value = value;
    await PushNotificationService.setHideDetails(value);
  }
  static Future<void> clearMessageNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_messageIdsKey) ?? <String>[];
    for (final value in ids) {
      final id = int.tryParse(value);
      if (id != null && id != orbitMessageSummaryNotificationId) await notifications.cancel(id);
    }
    await notifications.cancel(orbitMessageSummaryNotificationId);
    await prefs.remove(_messageIdsKey);
    await prefs.remove(_messageLinesKey);
  }
  static Future<void> showPartnerNotification({
    required String detailedTitle, required String detailedBody,
    required String privateTitle, required String privateBody,
    int id = 7001, String kind = 'message',
  }) async {
    if (!notificationsEnabled.value) return;
    final hidden = hideDetails.value;
    final title = hidden ? privateTitle : detailedTitle;
    final body = hidden ? privateBody : detailedBody;
    final isMessage = kind == 'message';
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_messageIdsKey) ?? <String>[];
    final lines = prefs.getStringList(_messageLinesKey) ?? <String>[];
    if (isMessage) {
      final idText = '$id';
      final existingIndex = ids.indexOf(idText);
      final line = hidden ? 'নতুন মেসেজ' : '$title: $body';
      if (existingIndex >= 0) { if (existingIndex < lines.length) lines[existingIndex] = line; }
      else { ids.add(idText); lines.add(line); }
      while (ids.length > 20) { ids.removeAt(0); if (lines.isNotEmpty) lines.removeAt(0); }
      await prefs.setStringList(_messageIdsKey, ids);
      await prefs.setStringList(_messageLinesKey, lines);
      await notifications.show(id, title, body, NotificationDetails(android: AndroidNotificationDetails(
        orbitNotificationChannelId, 'Orbit Two messages',
        channelDescription: 'Messages from your partner', importance: Importance.max, priority: Priority.max,
        playSound: true, enableVibration: true, vibrationPattern: Int64List.fromList([0, 350, 180, 350]),
        enableLights: true, ledColor: pinkColor, ledOnMs: 1000, ledOffMs: 500, color: pinkColor,
        category: AndroidNotificationCategory.message,
        visibility: hidden ? NotificationVisibility.private : NotificationVisibility.public,
        styleInformation: BigTextStyleInformation(body, contentTitle: title, summaryText: 'Orbit Two'),
        groupKey: orbitMessageNotificationGroup, setAsGroupSummary: false, onlyAlertOnce: false, number: ids.length,
      )));
      final visibleLines = hidden ? List<String>.filled(lines.length, 'নতুন মেসেজ') : lines;
      final summaryTitle = hidden ? 'Orbit Two' : 'Orbit Two • ${ids.length}টি মেসেজ';
      final summaryBody = hidden ? '${ids.length}টি নতুন মেসেজ' : '${ids.length}টি মেসেজ এসেছে';
      await notifications.show(orbitMessageSummaryNotificationId, summaryTitle, summaryBody, NotificationDetails(android: AndroidNotificationDetails(
        orbitNotificationChannelId, 'Orbit Two messages',
        channelDescription: 'Grouped messages from your partner', importance: Importance.max, priority: Priority.max,
        playSound: false, enableVibration: false, enableLights: false, color: pinkColor,
        category: AndroidNotificationCategory.message,
        visibility: hidden ? NotificationVisibility.private : NotificationVisibility.public,
        styleInformation: InboxStyleInformation(visibleLines, contentTitle: summaryTitle, summaryText: summaryBody),
        groupKey: orbitMessageNotificationGroup, setAsGroupSummary: true, onlyAlertOnce: true, number: ids.length,
      )));
      return;
    }
    await notifications.show(id, title, body, NotificationDetails(android: AndroidNotificationDetails(
      orbitNotificationChannelId, 'Orbit Two updates',
      channelDescription: 'Changes and downloads', importance: Importance.max, priority: Priority.max,
      playSound: true, enableVibration: true, vibrationPattern: Int64List.fromList([0, 350, 180, 350]), color: purpleColor,
      category: AndroidNotificationCategory.status,
      visibility: hidden ? NotificationVisibility.private : NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(body, contentTitle: title, summaryText: 'Orbit Two updates'),
      groupKey: orbitUpdateNotificationGroup, setAsGroupSummary: false, onlyAlertOnce: true,
    )));
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
  const EternalSpaceApp({super.key, this.startupError});

  final String? startupError;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Orbit Two',
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
      home: startupError == null ? const SplashScreen() : StartupErrorScreen(message: startupError!),
    );
  }
}

class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/branding/orbit_two_logo_artwork.png',
                  width: 100,
                  height: 100,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.favorite_rounded,
                    color: pinkColor,
                    size: 64,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Orbit Two চালু করা যায়নি',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Firebase সংযোগে সমস্যা হয়েছে। ইন্টারনেট সংযোগ পরীক্ষা করে অ্যাপটি আবার খুলুন।',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ),
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
      if (status != 'connected') {
        if (status == 'disconnected') {
          final cleared = await PrivateSpaceService.clearCachedSpaceData();
          if (cleared) syncVersion.value++;
        }
        return null;
      }

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
      await _applyRemoteData(snapshot.data(), notifyChanges: false);
    } catch (e) {
      debugPrint('Firebase download error: $e');
    }
  }

  static Future<void> _applyRemoteData(
    Map<String, dynamic>? data, {
    bool notifyChanges = true,
  }) async {
    if (data == null) return;

    await init();
    final changedKeys = <String>[];
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    for (final entry in data.entries) {
      final key = entry.key;
      if (key == 'updatedBy' || key == 'updatedAt' ||
          key == 'partnerOne' || key == 'partnerTwo') {
        continue;
      }
      final oldRaw = _prefs!.getString(key);
      final nextValue = entry.value;
      final normalizedNext = nextValue is List
          ? jsonEncode(nextValue)
          : nextValue is String
              ? nextValue
              : null;
      if (notifyChanges &&
          normalizedNext != null &&
          key != 'chatMessages' &&
          (oldRaw == null || oldRaw != normalizedNext)) {
        changedKeys.add(key);
      }
    }

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

    if (changedKeys.isNotEmpty && currentUid.isNotEmpty) {
      final labels = <String, String>{
        'loveNotes': 'Love Notes',
        'specialDates': 'Special Dates',
        'spaceComplaints': 'Complaints Box',
        'galleryMedia': 'Gallery',
        'galleryFolders': 'Gallery folders',
        'relationshipStartAt': 'Together For',
      };
      final readable = changedKeys.map((key) => labels[key] ?? 'Shared data').toSet().join(', ');
      NotificationPrivacySettings.showPartnerNotification(
        detailedTitle: 'Partner update',
        detailedBody: 'Changed: $readable',
        privateTitle: 'Check change',
        privateBody: 'Your partner changed shared data.',
        kind: 'change',
        id: DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
      ).catchError((Object error) {
        debugPrint('Shared change notification error: $error');
      });
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
  bool _networkUnavailable = false;

  Future<bool> _hasNetworkConnection() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await client
          .getUrl(Uri.parse('https://www.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      final response =
          await request.close().timeout(const Duration(seconds: 4));
      await response.drain<void>();
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_networkUnavailable && mounted) {
      setState(() => _networkUnavailable = false);
    }
    await SpaceStore.init();
    if (!await _hasNetworkConnection()) {
      if (mounted) setState(() => _networkUnavailable = true);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 1500));

    if (!mounted) return;

    var user = FirebaseAuth.instance.currentUser;

    // Cached Firebase sessions must also pass email verification.
    if (user != null && user.email != null) {
      try {
        await user.reload();
        user = FirebaseAuth.instance.currentUser;
      } catch (error) {
        debugPrint('Email verification status check failed: $error');
      }

      if (user != null && !user.emailVerified) {
        await FirebaseAuth.instance.signOut();
        user = null;
      }
    }

    if (!mounted) return;

    if (user != null) {
      try {
        await SpaceStore.syncFromFirebase().timeout(
          const Duration(seconds: 6),
        );
      } on TimeoutException {
        if (mounted) setState(() => _networkUnavailable = true);
        return;
      } catch (error) {
        debugPrint('Startup sync error: $error');
      }

      try {
        await SpaceStore.startRealtimeSync().timeout(
          const Duration(seconds: 6),
        );
      } on TimeoutException {
        if (mounted) setState(() => _networkUnavailable = true);
        return;
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
    if (_networkUnavailable) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.wifi_off_rounded,
                    size: 68,
                    color: pinkColor,
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Check Your Network Connection',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'ইন্টারনেট সংযোগ চালু করে আবার চেষ্টা করুন।',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: GlowBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 152,
                height: 152,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF171026),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: pinkColor.withValues(alpha: 0.55), width: 1.5),
                  boxShadow: [
                    BoxShadow(color: pinkColor.withValues(alpha: 0.28), blurRadius: 28, spreadRadius: 2),
                    BoxShadow(color: purpleColor.withValues(alpha: 0.22), blurRadius: 42, spreadRadius: 4),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.asset(
                    'assets/branding/orbit_two_logo.jpg',
                    width: 132,
                    height: 132,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.favorite_rounded,
                      size: 72,
                      color: pinkColor,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 18),
              const AnimatedOrbitTitle(
                fontSize: 30,
                splash: true,
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

class AnimatedOrbitTitle extends StatefulWidget {
  final double fontSize;
  final bool splash;

  const AnimatedOrbitTitle({
    super.key,
    required this.fontSize,
    this.splash = false,
  });

  @override
  State<AnimatedOrbitTitle> createState() => _AnimatedOrbitTitleState();
}

class _AnimatedOrbitTitleState extends State<AnimatedOrbitTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final hue = (_controller.value * 360) % 360;
        final first = HSVColor.fromAHSV(1, hue, 0.42, 1).toColor();
        final second =
            HSVColor.fromAHSV(1, (hue + 95) % 360, 0.48, 1).toColor();
        final third =
            HSVColor.fromAHSV(1, (hue + 190) % 360, 0.38, 1).toColor();

        return ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: [first, second, third],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ).createShader(bounds),
          child: Text(
            'Orbit Two',
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'serif',
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: widget.splash ? 1.1 : 0.4,
            ),
          ),
        );
      },
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color,
                  color.withValues(alpha: 0.48),
                  color.withValues(alpha: 0),
                ],
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
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
        child: SafeArea(child: RepaintBoundary(child: widget.child)),
        builder: (context, child) {
          final phase = _controller.value * 2 * pi;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                top: -125 + sin(phase) * 30,
                left: -115 + cos(phase) * 28,
                child: _glow(340, const Color(0xFF8B1D62).withValues(alpha: 0.34)),
              ),
              Positioned(
                bottom: -145 + cos(phase) * 34,
                right: -120 + sin(phase) * 30,
                child: _glow(370, const Color(0xFF6826A8).withValues(alpha: 0.34)),
              ),
              Positioned(
                top: 210 + cos(phase * 2) * 25,
                right: -165 + sin(phase * 2) * 24,
                child: _glow(310, const Color(0xFFB51E72).withValues(alpha: 0.22)),
              ),
              Positioned(
                bottom: 70 + sin(phase * 2) * 26,
                left: -175 + cos(phase * 2) * 25,
                child: _glow(300, const Color(0xFF5424B8).withValues(alpha: 0.24)),
              ),
              if (child != null) Positioned.fill(child: child),
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
    orbitShareChannel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        final shared = '${call.arguments ?? ''}'.trim();
        if (shared.isNotEmpty && mounted) unawaited(_handleIncomingSharedText(shared));
      }
    });
    unawaited(_loadInitialSharedText());
    _loadPartnerNames();
    _startUnreadWatcher();
    _updatePresence(true);
    _startConnectionWatcher();
    _recoverPendingUploads();
  }

  Future<void> _loadInitialSharedText() async {
    try {
      final shared = await orbitShareChannel.invokeMethod<String>('getInitialSharedText');
      if (shared != null && shared.trim().isNotEmpty && mounted) await _handleIncomingSharedText(shared.trim());
    } catch (error) { debugPrint('Initial shared text unavailable: $error'); }
  }

  Future<void> _handleIncomingSharedText(String shared) async {
    // Check the actual Firebase space connection, not just a cached partner name.
    final connectedSpaceId = await SpaceStore._getConnectedSpaceId();
    if (!mounted) return;
    if (connectedSpaceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('লিংক শেয়ার করতে আগে Partner-এর সঙ্গে Connect করো।'),
        ),
      );
      return;
    }
    if (partnerTwo.trim().isEmpty) await _loadPartnerNames();
    if (!mounted) return;
    orbitSharedText.value = shared;
    setState(() {
      selectedIndex = 1;
      hasUnreadChat = false;
    });
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
            if (snapshot.exists && status == 'disconnected') {
              final cleared = await PrivateSpaceService.clearCachedSpaceData();
              if (cleared) {
                SpaceStore.syncVersion.value++;
                await _loadPartnerNames();
              }
            }
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
    var receivedInitialSnapshot = false;
    final knownMessageIds = <String>{};

    _unreadSubscription = ChatSyncService.watchMessages().listen(
      (messages) {
        final incoming = <Map<String, dynamic>>[];
        for (final message in messages) {
          final id = '${message['id'] ?? ''}';
          if (id.isNotEmpty && !knownMessageIds.contains(id)) {
            final senderUid = '${message['senderUid'] ?? ''}';
            if (receivedInitialSnapshot &&
                senderUid.isNotEmpty &&
                senderUid != uid &&
                message['unsent'] != true) {
              incoming.add(message);
            }
            knownMessageIds.add(id);
          }
        }
        receivedInitialSnapshot = true;

        if (!orbitChatVisible) {
          for (final message in incoming) {
            final text = '${message['text'] ?? ''}'.trim();
            final type = '${message['type'] ?? 'text'}';
            final sender = '${message['senderName'] ?? 'Partner'}';
            final content = text.isNotEmpty
                ? text
                : (type == 'voice' ? 'Voice message' : 'Sent a media file');
            NotificationPrivacySettings.showPartnerNotification(
              detailedTitle: sender,
              detailedBody: content,
              privateTitle: 'Check message',
              privateBody: 'You have a new message.',
              kind: 'message',
              id: NotificationPrivacySettings.notificationIdForMessage('${message['id'] ?? ''}'),
            ).catchError((Object error) {
              debugPrint('Message notification error: $error');
            });
          }
        }

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
          hasUnreadChat = orbitChatVisible ? false : unread;
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
            orbitChatVisible = index == 1;
            if (index == 1) hasUnreadChat = false;
          });
          if (index == 1) {
            unawaited(NotificationPrivacySettings.clearMessageNotifications());
          }
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

    return PopScope(
      canPop: selectedIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || selectedIndex == 0 || !mounted) return;
        setState(() {
          selectedIndex = 0;
          orbitChatVisible = false;
        });
      },
      child: Scaffold(
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
            orbitChatVisible = index == 1;
            if (index == 1) hasUnreadChat = false;
          });
          if (index == 1) {
            unawaited(NotificationPrivacySettings.clearMessageNotifications());
          }
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

  // Profile photos arrive as Base64 strings in chat snapshots. Keep a small
  // decoded cache so scrolling does not repeatedly decode the same photo.
  static final Map<String, Uint8List> _decodedPhotoCache =
      <String, Uint8List>{};

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
    final raw = photoBase64.trim();

    if (raw.isNotEmpty) {
      final cacheKey = '${raw.length}:${raw.hashCode}';
      bytes = _decodedPhotoCache[cacheKey];
      if (bytes == null) {
        try {
          bytes = base64Decode(raw);
          if (bytes.isNotEmpty) {
            if (_decodedPhotoCache.length >= 48) {
              _decodedPhotoCache.remove(_decodedPhotoCache.keys.first);
            }
            _decodedPhotoCache[cacheKey] = bytes;
          }
        } catch (_) {
          bytes = null;
        }
      }
    }

    if (bytes == null || bytes.isEmpty) {
      return _letterAvatar();
    }

    final pixelSize = (radius * 2 * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(1, 512)
        .toInt();

    return ClipOval(
      child: Image.memory(
        bytes,
        width: radius * 2,
        height: radius * 2,
        cacheWidth: pixelSize,
        cacheHeight: pixelSize,
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
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final hasUnreadComplaint = SpaceStore.readList('spaceComplaints').any((item) {
      final authorUid = '${item['authorUid'] ?? ''}';
      final readBy = item['readBy'];
      final hasRead = readBy is List && readBy.contains(currentUid);
      return currentUid.isNotEmpty &&
          authorUid.isNotEmpty &&
          authorUid != currentUid &&
          !hasRead;
    });
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
                  const AnimatedOrbitTitle(fontSize: 29),
                ],
              ),
            ),
            Container(
              width: 72,
              height: 72,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF8B5CF6), Color(0xFFFF2E93)],
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: pinkColor.withValues(alpha: 0.28),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: ColoredBox(
                  color: const Color(0xFF070513),
                  child: Image.asset(
                    'assets/branding/orbit_two_app_icon_new.jpg',
                    width: 64,
                    height: 64,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(
                        Icons.favorite_rounded,
                        color: pinkColor,
                        size: 38,
                      ),
                    ),
                  ),
                ),
              ),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasUnreadComplaint)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                const Icon(Icons.chevron_right),
              ],
            ),
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

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  StreamSubscription<List<Map<String, dynamic>>>? _chatSubscription;
  final Map<String, Future<String?>> _mediaPathFutures = {};
  final Map<String, Map<String, dynamic>> _failedMediaMessages = {};
  final Map<String, Future<String?>> _chatVideoThumbnailFutures = {};
  final Map<String, Uint8List> _embeddedVideoThumbnails = {};
  final Map<String, GlobalKey> _messageKeys = {};
  final Set<String> _requestedMediaDownloads = {};
  String? _highlightedMessageId;
  Timer? _messageHighlightTimer;
  bool _hasLoadedInitialMessages = false;
  bool _isNearChatBottom = true;
  bool _showJumpToBottom = false;
  bool _userHasScrolledAwayFromBottom = false;
  bool _userIsScrolling = false;
  int _scrollRequestToken = 0;
  int _cachedLastOwnMessageIndex = -1;

  bool _isTypingSent = false;
  Timer? _typingHeartbeatTimer;
  Timer? _typingSoundTimer;
  Timer? _typingIdleTimer;
  Timer? _draftSaveTimer;
  Map<String, dynamic>? _replyToMessage;
  final Set<String> _expandedMessageTimes = <String>{};
  final Set<String> _seenSoundPlayedFor = <String>{};
  final Set<String> _locallyDeletedMessageIds = <String>{};
  final Map<String, double> _replyDragOffsets = <String, double>{};
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _voicePreviewPlayer = AudioPlayer();
  StreamSubscription<PlayerState>? _voicePreviewStateSubscription;
  bool _isVoicePreviewPlaying = false;
  bool _isSendingRecordedVoice = false;
  bool _isRecordingVoice = false;
  bool _attachmentMenuOpen = false;
  bool _appIsResumed = true;
  bool _draftLoaded = false;
  String? _recordingPath;
  String? _recordedVoicePath;
  DateTime? _recordingStartedAt;
  Duration _recordingElapsed = Duration.zero;
  Timer? _recordingTimer;

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
    orbitChatVisible = true;
    unawaited(NotificationPrivacySettings.clearMessageNotifications());
    WidgetsBinding.instance.addObserver(this);
    scrollController.addListener(_updateChatScrollPosition);
    _appIsResumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(_restoreDraft());
    SpaceSyncService.uploadProgress.addListener(
      _handleUploadProgressChanged,
    );
    _spaceStream = ChatSyncService.watchSpaceData().asBroadcastStream();
    _profilesStream = ChatSyncService.watchMemberProfiles();

    _voicePreviewStateSubscription = _voicePreviewPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.playing && !_isVoicePreviewPlaying) {
        unawaited(InteractionFeedbackSettings.vibrate());
      }
      setState(() => _isVoicePreviewPlaying = state == PlayerState.playing);
    });

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

    unawaited(_loadLocallyDeletedMessageIds());
    _startChatSync();
    orbitSharedText.addListener(_handleSharedTextDraft);
    _handleSharedTextDraft();
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

  String get _draftKey => 'chatDraft_${_currentUid.isEmpty ? 'guest' : _currentUid}';

  void _handleSharedTextDraft() {
    final shared = orbitSharedText.value;
    if (shared == null || shared.trim().isEmpty || !mounted) return;
    controller.text = shared;
    controller.selection = TextSelection.collapsed(offset: controller.text.length);
    orbitSharedText.value = null;
    _scheduleDraftSave(controller.text);
    unawaited(_persistDraft(controller.text));
  }

  Future<void> _restoreDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final draft = prefs.getString(_draftKey) ?? '';
      if (mounted && controller.text.isEmpty && draft.isNotEmpty) {
        controller.value = TextEditingValue(
          text: draft,
          selection: TextSelection.collapsed(offset: draft.length),
        );
      }
    } catch (error) {
      debugPrint('Chat draft restore skipped: $error');
    } finally {
      _draftLoaded = true;
    }
  }

  Future<void> _persistDraft(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey, value);
    } catch (error) {
      debugPrint('Chat draft save skipped: $error');
    }
  }

  void _scheduleDraftSave(String value) {
    if (!_draftLoaded) return;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(_persistDraft(value));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsResumed = state == AppLifecycleState.resumed;
    if (_appIsResumed) {
      _retryFailedMediaDownloads();
      // অ্যাপ Recents/background থেকে ফিরলে ব্যর্থ মিডিয়া FutureBuilder-গুলো
      // আবার চেষ্টা করতে পারবে; চলমান ডাউনলোড সার্ভিসে deduplicate হয়।
      if (mounted) setState(() {});
      if (messages.isNotEmpty) {
        unawaited(ChatSyncService.markMessagesSeen(messages).catchError(
          (Object error) {
            debugPrint('Mark seen after resume skipped: $error');
          },
        ));
      }
    } else {
      _typingIdleTimer?.cancel();
      _typingIdleTimer = null;
      unawaited(_stopTyping());
    }
  }

  void _handleTypingChanged(String value) {
    _scheduleDraftSave(value);
    final shouldType = value.trim().isNotEmpty;

    if (shouldType) {
      if (!_isTypingSent) {
        _isTypingSent = true;
        _typingSoundTimer?.cancel();
        unawaited(ChatSyncService.setTyping(isTyping: true).catchError(
          (Object error) {
            debugPrint('Typing status update failed: $error');
          },
        ));
      }

      _typingIdleTimer?.cancel();
      _typingIdleTimer = Timer(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        unawaited(_stopTyping());
      });

      _typingHeartbeatTimer ??= Timer.periodic(
        const Duration(seconds: 2),
        (_) {
          if (!mounted ||
              !_appIsResumed ||
              controller.text.trim().isEmpty ||
              _typingIdleTimer == null) {
            return;
          }
          unawaited(ChatSyncService.setTyping(isTyping: true).catchError(
            (Object error) {
              debugPrint('Typing heartbeat failed: $error');
            },
          ));
        },
      );
    } else {
      _typingSoundTimer?.cancel();
      _typingSoundTimer = null;
      _typingIdleTimer?.cancel();
      _typingIdleTimer = null;
      _typingHeartbeatTimer?.cancel();
      _typingHeartbeatTimer = null;
      if (_isTypingSent) {
        _isTypingSent = false;
        unawaited(ChatSyncService.clearTyping().catchError(
          (Object error) {
            debugPrint('Typing status clear failed: $error');
          },
        ));
      }
    }
  }

  Future<void> _stopTyping() async {
    _typingSoundTimer?.cancel();
    _typingSoundTimer = null;
    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
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

  Future<void> _loadLocallyDeletedMessageIds() async {
    final prefs = await SharedPreferences.getInstance();
    _locallyDeletedMessageIds.addAll(prefs.getStringList('orbitDeletedForMeMessageIds') ?? const <String>[]);
    if (mounted) setState(() {
      messages.removeWhere((item) => _locallyDeletedMessageIds.contains('${item['id'] ?? ''}'));
    });
  }

  Future<void> _startChatSync() async {
    try {
      final stream = ChatSyncService.watchMessages();

      _chatSubscription = stream.listen(
        (latestMessages) {
          if (!mounted) return;

          final firstSnapshot = !_hasLoadedInitialMessages;
          final previousCount = messages.length;
          final previousLastId =
              messages.isEmpty ? '' : '${messages.last['id'] ?? ''}';
          final nextLastId = latestMessages.isEmpty
              ? ''
              : '${latestMessages.last['id'] ?? ''}';
          final hasNewTailMessage = latestMessages.length > previousCount ||
              (latestMessages.isNotEmpty && nextLastId != previousLastId);
          final shouldFollowTail = firstSnapshot ||
              (!_userHasScrolledAwayFromBottom &&
                  _isNearChatBottom &&
                  hasNewTailMessage);

          // Compute this once per Firestore snapshot instead of rescanning the
          // complete message list while each visible row is being built.
          var nextLastOwnMessageIndex = -1;
          final currentUid = _currentUid;
          for (var i = latestMessages.length - 1; i >= 0; i--) {
            final item = latestMessages[i];
            final senderUid = '${item['senderUid'] ?? ''}';
            final mine = senderUid.isNotEmpty && currentUid.isNotEmpty
                ? senderUid == currentUid
                : item['mine'] == true;
            if (mine && item['unsent'] != true) {
              nextLastOwnMessageIndex = i;
              break;
            }
          }

          final previouslySeenIds = <String>{
            for (final item in messages)
              if (_isMine(item) && _isSeenByPartner(item))
                '${item['id'] ?? ''}',
          };
          if (firstSnapshot) {
            for (final item in latestMessages) {
              if (_isMine(item) && _isSeenByPartner(item)) {
                _seenSoundPlayedFor.add('${item['id'] ?? ''}');
              }
            }
          } else {
            for (final item in latestMessages) {
              final id = '${item['id'] ?? ''}';
              if (id.isNotEmpty &&
                  _isMine(item) &&
                  _isSeenByPartner(item) &&
                  !previouslySeenIds.contains(id) &&
                  _seenSoundPlayedFor.add(id)) {
                unawaited(InteractionFeedbackSettings.playSeenSound());
              }
            }
          }

          setState(() {
            messages = latestMessages.where((item) => !_locallyDeletedMessageIds.contains('${item['id'] ?? ''}')).toList();
            _cachedLastOwnMessageIndex = nextLastOwnMessageIndex;
          });
          _hasLoadedInitialMessages = true;

          if (_appIsResumed) {
            unawaited(
              ChatSyncService.markMessagesSeen(latestMessages).catchError(
                (Object error) {
                  debugPrint('Mark seen skipped: $error');
                },
              ),
            );
          }

          // শুধু প্রথম লোড বা নতুন মেসেজ এলে—প্রতিটি Seen/metadata আপডেটে নয়।
          if (shouldFollowTail) {
            // Directly settle to the final extent instead of animating a changing
            // text/emoji/link layout; this prevents the chat list from shaking.
            _scrollToBottom(animate: false, settle: true);
          }
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
    orbitChatVisible = false;
    orbitSharedText.removeListener(_handleSharedTextDraft);
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(_updateChatScrollPosition);
    _messageHighlightTimer?.cancel();
    _typingHeartbeatTimer?.cancel();
    _typingHeartbeatTimer = null;
    _typingIdleTimer?.cancel();
    _typingIdleTimer = null;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    unawaited(_persistDraft(controller.text));
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (_isRecordingVoice) unawaited(_voiceRecorder.stop().then<void>((_) {}));

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
    _voicePreviewStateSubscription?.cancel();
    unawaited(_voicePreviewPlayer.dispose());
    controller.dispose();
    scrollController.dispose();
    unawaited(_voiceRecorder.dispose());
    super.dispose();
  }

  bool _isMine(Map<String, dynamic> message) {
    final senderUid = '${message['senderUid'] ?? ''}';

    if (senderUid.isNotEmpty && _currentUid.isNotEmpty) {
      return senderUid == _currentUid;
    }

    return message['mine'] == true;
  }

  bool _isSeenByPartner(Map<String, dynamic> message) {
    final seenBy = message['seenBy'];
    if (seenBy is! Map) return false;
    return seenBy.entries.any(
      (entry) => '${entry.key}' != _currentUid && entry.value == true,
    );
  }

  int get _lastOwnMessageIndex => _cachedLastOwnMessageIndex;

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
    _scheduleDraftSave('');
    unawaited(_persistDraft(''));

    try {
      await ChatSyncService.sendMessage(message);
      unawaited(InteractionFeedbackSettings.playSentSound());
      if (mounted) {
        setState(() {
          if (_replyToMessage?['id'] == replyTo?['id']) {
            _replyToMessage = null;
          }
        });
      }
      // The Firestore message listener scrolls when the new tail message arrives.
      // Do not start a second scroll animation here: competing animations make
      // long text and emoji messages visibly jump/shake.
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('মেসেজ পাঠানো যায়নি। আবার চেষ্টা করুন।'),
        ),
      );
    }
  }

  Future<void> _sendMedia(
    bool video, {
    ImageSource source = ImageSource.gallery,
  }) async {
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
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(source: source, imageQuality: 88, maxWidth: 2560, maxHeight: 2560);

    if (picked == null || !mounted) return;

    File file = File(picked.path);
    String fileName = file.uri.pathSegments.isNotEmpty
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

    String? videoThumbnailBase64;
    try {
      if (video) {
        try {
          file = await _makeCompatibleVideo(file);
          fileName = file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'orbit_video.mp4';
        } catch (error) {
          debugPrint('Video compatibility optimization failed: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('ভিডিও অপটিমাইজ করা যায়নি; অন্য ভিডিও দিয়ে চেষ্টা করুন।')),
            );
          }
          return;
        }
        try {
          final thumbnailBytes = await VideoThumbnail.thumbnailData(
            video: file.path,
            imageFormat: ImageFormat.JPEG,
            maxHeight: 240,
            quality: 45,
          );
          // Firestore-এর 1 MiB document limit নিরাপদ রাখতে thumbnail ছোট রাখি।
          if (thumbnailBytes != null &&
              thumbnailBytes.isNotEmpty &&
              thumbnailBytes.length <= 180 * 1024) {
            videoThumbnailBase64 = base64Encode(thumbnailBytes);
          }
        } catch (error) {
          debugPrint('Video preview generation skipped: $error');
        }
      }

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
        'text': file.path,
        'type': video ? 'video' : 'image',
        'fileId': fileId,
        'driveFileId': fileId,
        'driveFileName': uploaded['driveFileName'] ?? fileName,
        'mimeType': uploaded['mimeType'] ?? '',
        'size': uploaded['size'] ?? '',
        'storage': 'shared',
        if (videoThumbnailBase64 != null)
          'thumbnailBase64': videoThumbnailBase64,
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
      unawaited(InteractionFeedbackSettings.playSentSound());
      
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

  String _formatRecordingDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _startVoiceRecording() async {
    if (_isRecordingVoice || _recordedVoicePath != null) return;
    if (FirebaseAuth.instance.currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('আগে Partner Space-এ যুক্ত হও।')),
      );
      return;
    }
    if (_pendingMediaName != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('আগের ফাইলটির আপলোড শেষ হলে আবার চেষ্টা করো।')),
      );
      return;
    }
    try {
      if (!await _voiceRecorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ভয়েস পাঠাতে Microphone permission দিতে হবে।')),
          );
        }
        return;
      }
      final support = await getApplicationSupportDirectory();
      final voiceDirectory = Directory('${support.path}/chat_voice');
      await voiceDirectory.create(recursive: true);
      final path = '${voiceDirectory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (mounted) {
        setState(() {
          _recordingPath = path;
          _recordedVoicePath = null;
          _recordingStartedAt = DateTime.now();
          _recordingElapsed = Duration.zero;
          _isRecordingVoice = true;
        });
      }
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
        final started = _recordingStartedAt;
        if (!mounted || !_isRecordingVoice || started == null) return;
        setState(() {
          _recordingElapsed = DateTime.now().difference(started);
        });
      });
    } catch (error) {
      debugPrint('Voice recording start failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ভয়েস রেকর্ড শুরু হয়নি: $error')),
        );
      }
    }
  }

  Future<void> _stopVoiceRecording() async {
    if (!_isRecordingVoice) return;
    try {
      final path = await _voiceRecorder.stop();
      _recordingTimer?.cancel();
      _recordingTimer = null;
      if (path == null || path.isEmpty) {
        if (mounted) setState(() => _isRecordingVoice = false);
        return;
      }
      final file = File(path);
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('রেকর্ড করা ভয়েস পাওয়া যায়নি।');
      }
      await _voicePreviewPlayer.stop();
      if (mounted) {
        setState(() {
          _isVoicePreviewPlaying = false;
          _isRecordingVoice = false;
          _recordingPath = path;
          _recordedVoicePath = path;
        });
      }
    } catch (error) {
      debugPrint('Voice recording stop failed: $error');
      _recordingTimer?.cancel();
      _recordingTimer = null;
      if (mounted) {
        setState(() => _isRecordingVoice = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ভয়েস রেকর্ড বন্ধ হয়নি: $error')),
        );
      }
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    } else if (_recordedVoicePath == null) {
      await _startVoiceRecording();
    }
  }

  Future<void> _toggleVoicePreview() async {
    final path = _recordedVoicePath;
    if (_isRecordingVoice || path == null || !await File(path).exists()) return;
    try {
      if (_voicePreviewPlayer.state == PlayerState.playing) {
        await _voicePreviewPlayer.pause();
      } else if (_voicePreviewPlayer.state == PlayerState.paused) {
        await _voicePreviewPlayer.resume();
      } else {
        await _voicePreviewPlayer.play(DeviceFileSource(path));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ভয়েস চালানো যায়নি: $error')));
    }
  }

  Future<void> _sendVoiceImmediately() async {
    if (_isSendingRecordedVoice) return;
    if (_isRecordingVoice) await _stopVoiceRecording();
    if (!mounted || _recordedVoicePath == null) return;
    await _sendRecordedVoice();
  }

  Future<void> _resetVoiceRecording() async {
    await _voicePreviewPlayer.stop();
    final oldPath = _recordedVoicePath ?? _recordingPath;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (oldPath != null) {
      try {
        final oldFile = File(oldPath);
        if (await oldFile.exists()) await oldFile.delete();
      } catch (error) {
        debugPrint('Old voice recording cleanup skipped: $error');
      }
    }
    if (!mounted) return;
    setState(() {
      _recordingPath = null;
      _recordedVoicePath = null;
      _recordingStartedAt = null;
      _recordingElapsed = Duration.zero;
      _isRecordingVoice = false;
    });
    await _startVoiceRecording();
  }

  Future<void> _deleteVoiceRecording() async {
    await _voicePreviewPlayer.stop();
    String? path = _recordedVoicePath ?? _recordingPath;
    if (_isRecordingVoice) {
      try {
        path = await _voiceRecorder.stop() ?? path;
      } catch (_) {}
    }
    _recordingTimer?.cancel();
    _recordingTimer = null;
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (error) {
        debugPrint('Voice recording delete skipped: $error');
      }
    }
    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _recordingPath = null;
        _recordedVoicePath = null;
        _recordingStartedAt = null;
        _recordingElapsed = Duration.zero;
      });
    }
  }

  Future<void> _sendRecordedVoice() async {
    if (_isSendingRecordedVoice) return;
    final path = _recordedVoicePath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      await _deleteVoiceRecording();
      return;
    }
    if (mounted) setState(() => _isSendingRecordedVoice = true);
    await _voicePreviewPlayer.stop();
    try {
      await _sendVoiceFile(file);
    } finally {
      if (mounted) setState(() => _isSendingRecordedVoice = false);
    }
  }

  Widget _buildVoiceRecordingPanel() {
    if (!_isRecordingVoice && _recordedVoicePath == null) {
      return const SizedBox.shrink();
    }
    final elapsed = _recordingElapsed;
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: pinkColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(
            _isRecordingVoice ? Icons.fiber_manual_record_rounded : Icons.mic_rounded,
            color: _isRecordingVoice ? Colors.redAccent : pinkColor,
            size: 19,
          ),
          const SizedBox(width: 8),
          Text(
            _formatRecordingDuration(elapsed),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 28,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(28, (index) {
                  final phase = (elapsed.inMilliseconds ~/ 120 + index * 7) % 19;
                  final height = 5.0 + (phase % 13);
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 2.5,
                    height: height,
                    decoration: BoxDecoration(
                      color: _isRecordingVoice ? pinkColor : Colors.white54,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ),
          if (_isRecordingVoice) ...[
            IconButton(
              tooltip: 'রেকর্ড বন্ধ করে শুনুন',
              visualDensity: VisualDensity.compact,
              onPressed: _stopVoiceRecording,
              icon: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent),
            ),
            IconButton(
              tooltip: 'শুনে পরীক্ষা না করেই সরাসরি পাঠান',
              visualDensity: VisualDensity.compact,
              onPressed: _isSendingRecordedVoice ? null : _sendVoiceImmediately,
              icon: const Icon(Icons.send_rounded, color: pinkColor),
            ),
          ] else ...[
            IconButton(
              tooltip: _isVoicePreviewPlaying ? 'শোনা থামাও / Pause' : 'পাঠানোর আগে Play করে শুনুন',
              visualDensity: VisualDensity.compact,
              onPressed: _toggleVoicePreview,
              icon: Icon(_isVoicePreviewPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: pinkColor),
            ),
            IconButton(
              tooltip: 'রিসেট করে নতুন করে রেকর্ড',
              visualDensity: VisualDensity.compact,
              onPressed: _resetVoiceRecording,
              icon: const Icon(Icons.replay_rounded, color: pinkColor),
            ),
            IconButton(
              tooltip: 'রেকর্ড করা ভয়েস ডিলিট',
              visualDensity: VisualDensity.compact,
              onPressed: _deleteVoiceRecording,
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            ),
            IconButton(
              tooltip: _isVoicePreviewPlaying ? 'শোনা থামাতে হবে না — পাঠান' : 'না শুনেও সরাসরি পাঠান',
              visualDensity: VisualDensity.compact,
              onPressed: _isSendingRecordedVoice ? null : _sendRecordedVoice,
              icon: _isSendingRecordedVoice ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: pinkColor)) : const Icon(Icons.send_rounded, color: pinkColor),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _sendVoiceFile(File file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_pendingMediaName != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('আগের ফাইলটির আপলোড শেষ হলে আবার চেষ্টা করো।')),
        );
      }
      return;
    }
    final fileName = file.uri.pathSegments.last;
    final messageId = DateTime.now().microsecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();
    final replyTo = _replyToMessage;
    if (mounted) {
      setState(() {
        _pendingMediaName = 'Voice message';
        _pendingMediaVideo = false;
        _pendingMediaProgress = 0;
        _pendingMediaSpeed = 0;
      });
    }
    try {
      final uploaded = await SpaceSyncService.uploadSharedMedia(
        file,
        metadata: {
          'purpose': 'chat',
          'messageId': messageId,
          'senderUid': user.uid,
          'type': 'voice',
          'fileName': fileName,
          'durationMs': _recordingElapsed.inMilliseconds,
          'createdAt': createdAt,
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
      final fileId = '${uploaded['fileId'] ?? uploaded['driveFileId'] ?? ''}'.trim();
      if (fileId.isEmpty) throw Exception('ভয়েস ফাইলের ID পাওয়া যায়নি।');
      await ChatSyncService.sendMessage({
        'id': messageId,
        'senderUid': user.uid,
        'text': file.path,
        'type': 'voice',
        'durationMs': _recordingElapsed.inMilliseconds,
        'fileId': fileId,
        'driveFileId': fileId,
        'driveFileName': uploaded['driveFileName'] ?? fileName,
        'mimeType': uploaded['mimeType'] ?? 'audio/mp4',
        'size': uploaded['size'] ?? await file.length(),
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
        'time': createdAt,
      });
      unawaited(InteractionFeedbackSettings.playSentSound());
      final taskId = uploaded['_uploadTaskId'] ?? '';
      if (taskId.toString().isNotEmpty) {
        await SpaceSyncService.acknowledgeUpload(taskId.toString());
      }
      if (mounted) {
        setState(() {
          if (_replyToMessage?['id'] == replyTo?['id']) _replyToMessage = null;
          _recordedVoicePath = null;
          _recordingPath = null;
          _recordingStartedAt = null;
          _recordingElapsed = Duration.zero;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ভয়েস মেসেজ পাঠানো হয়েছে।')),
        );
      }
      _scrollToBottom();
    } catch (error) {
      debugPrint('Voice upload failed: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ভয়েস পাঠানো যায়নি: $error')),
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

  void _scrollToBottom({bool animate = true, bool settle = false}) {
    final requestToken = ++_scrollRequestToken;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (settle) {
        await Future<void>.delayed(const Duration(milliseconds: 90));
      }
      if (!mounted ||
          !scrollController.hasClients ||
          requestToken != _scrollRequestToken ||
          _userIsScrolling ||
          _userHasScrolledAwayFromBottom ||
          scrollController.position.isScrollingNotifier.value) {
        return;
      }

      final position = scrollController.position;
      final target = position.maxScrollExtent;
      if (animate) {
        await scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      } else {
        scrollController.jumpTo(target);
      }

      // Do not issue a second corrective jump after the first frame.
      // Repeated jumps during lazy media layout cause visible chat-list shaking.
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

  void _updateChatScrollPosition() {
    if (!scrollController.hasClients) return;
    final position = scrollController.position;
    _isNearChatBottom = position.maxScrollExtent - position.pixels <= 120;
  }

  Future<void> _jumpToMessage(String targetId) async {
    final targetIndex =
        messages.indexWhere((item) => '${item['id'] ?? ''}' == targetId);
    if (targetIndex < 0 ||
        messages.isEmpty ||
        messages[targetIndex]['unsent'] == true ||
        !scrollController.hasClients) {
      return;
    }

    _messageHighlightTimer?.cancel();
    if (mounted) setState(() => _highlightedMessageId = targetId);

    final key = _messageKeys.putIfAbsent(targetId, () => GlobalKey());

    // Index-এর অনুপাত দিয়ে offset আন্দাজ করা যাবে না—মেসেজের উচ্চতা একেক রকম।
    // বর্তমানে তৈরি হওয়া row-গুলোর index দেখে এক viewport করে সঠিক দিকে যাই।
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!mounted || !scrollController.hasClients) return;

      final targetContext = key.currentContext;
      if (targetContext != null) {
        await Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeInOutCubic,
          alignment: 0.45,
        );
        _messageHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
          if (mounted && _highlightedMessageId == targetId) {
            setState(() => _highlightedMessageId = null);
          }
        });
        return;
      }

      var minVisibleIndex = messages.length;
      var maxVisibleIndex = -1;
      for (var i = 0; i < messages.length; i++) {
        final id = '${messages[i]['id'] ?? i}';
        final context = _messageKeys[id]?.currentContext;
        final renderObject = context?.findRenderObject();
        if (renderObject is RenderBox && renderObject.attached) {
          minVisibleIndex = i < minVisibleIndex ? i : minVisibleIndex;
          maxVisibleIndex = i > maxVisibleIndex ? i : maxVisibleIndex;
        }
      }

      final position = scrollController.position;
      final maxExtent = position.maxScrollExtent;
      if (maxExtent <= 0 || position.viewportDimension <= 0) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        continue;
      }

      final double nextOffset;
      if (maxVisibleIndex < 0) {
        nextOffset = targetIndex < messages.length / 2 ? 0 : maxExtent;
      } else if (targetIndex < minVisibleIndex) {
        nextOffset = position.pixels - position.viewportDimension * 0.72;
      } else if (targetIndex > maxVisibleIndex) {
        nextOffset = position.pixels + position.viewportDimension * 0.72;
      } else {
        nextOffset = targetIndex < (minVisibleIndex + maxVisibleIndex) / 2
            ? position.pixels - position.viewportDimension * 0.45
            : position.pixels + position.viewportDimension * 0.45;
      }

      final clampedOffset = nextOffset.clamp(0.0, maxExtent).toDouble();
      if ((clampedOffset - position.pixels).abs() < 1) break;
      // Build off-screen rows without repeated intermediate animations.
      scrollController.jumpTo(clampedOffset);
      await WidgetsBinding.instance.endOfFrame;
    }

    if (!mounted || !scrollController.hasClients) return;
    final finalContext = key.currentContext;
    if (finalContext != null) {
      await Scrollable.ensureVisible(
        finalContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
        alignment: 0.45,
      );
    }
    _messageHighlightTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted && _highlightedMessageId == targetId) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<String?> _resolveChatVideoThumbnail(Map<String, dynamic> message, String videoPath) {
    final key = '${message['fileId'] ?? message['driveFileId'] ?? videoPath}';
    final existing = _chatVideoThumbnailFutures[key];
    if (existing != null) return existing;
    final future = Future<String?>.microtask(() async {
      try {
        if (!await File(videoPath).exists()) return null;
        final support = await getApplicationSupportDirectory();
        final directory = Directory('${support.path}/chat_video_thumbnails');
        await directory.create(recursive: true);
        final safeId = key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
        final thumbnail = File('${directory.path}/chat_thumb_$safeId.jpg');
        if (await thumbnail.exists() && await thumbnail.length() > 0) return thumbnail.path;
        final generated = await VideoThumbnail.thumbnailFile(video: videoPath, thumbnailPath: thumbnail.path, imageFormat: ImageFormat.JPEG, maxHeight: 320, quality: 75);
        if (generated != null && generated.isNotEmpty) {
          final generatedFile = File(generated);
          if (await generatedFile.exists() && await generatedFile.length() > 0) return generatedFile.path;
        }
      } catch (error) {
        debugPrint('Chat video thumbnail error: $error');
      }
      return null;
    });
    _chatVideoThumbnailFutures[key] = future;
    future.then((path) {
      if (path == null && identical(_chatVideoThumbnailFutures[key], future)) _chatVideoThumbnailFutures.remove(key);
    });
    return future;
  }

  Widget _buildReplyQuote(Map<String, dynamic> message) {
    final replyId = '${message['replyToId'] ?? ''}';
    if (replyId.isEmpty) return const SizedBox.shrink();
    final senderName = '${message['replyToSenderName'] ?? 'সঙ্গী'}';
    final preview = '${message['replyToText'] ?? ''}';
    return InkWell(
      onTap: () => _jumpToMessage(replyId),
      borderRadius: BorderRadius.circular(7),
      child: Container(
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
      ),
    );
  }

  Future<void> _showMessageOptions(Map<String, dynamic> sourceMessage) async {
    final message = Map<String, dynamic>.from(sourceMessage);
    final messageId = '${message['id'] ?? ''}';
    final senderUid = '${message['senderUid'] ?? ''}';
    // Firestore senderUid is authoritative for permission-sensitive actions.
    final mine = senderUid.isNotEmpty && _currentUid.isNotEmpty &&
        senderUid == _currentUid;
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
              if (!unsent)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      ..._quickReactionEmojis.map((emoji) => InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          unawaited(_setMessageReaction(messageId, emoji));
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Text(emoji, style: const TextStyle(fontSize: 27)),
                        ),
                      )),
                      IconButton(
                        tooltip: 'সব ইমোজি',
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showReactionPicker(message);
                        },
                        icon: const Icon(Icons.add_circle_outline_rounded, color: pinkColor),
                      ),
                    ],
                  ),
                ),
              ListTile(
                enabled: !unsent && '${message['type'] ?? 'text'}' == 'text' && '${message['text'] ?? ''}'.trim().isNotEmpty,
                leading: Icon(Icons.copy_rounded, color: unsent ? Colors.white24 : pinkColor),
                title: const Text('Copy message'),
                onTap: unsent || '${message['type'] ?? 'text'}' != 'text' || '${message['text'] ?? ''}'.trim().isEmpty ? null : () async {
                  await Clipboard.setData(ClipboardData(text: '${message['text'] ?? ''}'));
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('মেসেজ কপি হয়েছে')));
                },
              ),
              if (!unsent)
                ListTile(
                  leading: Icon(Icons.push_pin_rounded, color: message['pinned'] == true ? pinkColor : Colors.white70),
                  title: Text(message['pinned'] == true ? 'Unpin' : 'Pin'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    try {
                      await ChatSyncService.setMessagePinned(messageId: messageId, pinned: message['pinned'] != true);
                    } catch (error) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Pin করা যায়নি: $error')));
                    }
                  },
                ),
              ListTile(
                enabled: !unsent,
                leading: Icon(
                  Icons.reply_rounded,
                  color: unsent ? Colors.white24 : pinkColor,
                ),
                title: Text(
                  unsent ? 'পাঠানো হয়নি—Reply করা যাবে না' : 'Reply / উত্তর দাও',
                  style: TextStyle(
                    color: unsent ? Colors.white38 : Colors.white,
                  ),
                ),
                onTap: unsent
                    ? null
                    : () {
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
              if (!unsent)
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded, color: Colors.white70),
                  title: const Text('Delete for me'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    _locallyDeletedMessageIds.add(messageId);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setStringList('orbitDeletedForMeMessageIds', _locallyDeletedMessageIds.toList());
                    if (mounted) setState(() {
                      messages.removeWhere((item) => '${item['id'] ?? ''}' == messageId);
                    });
                  },
                ),
              if (mine && !unsent)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text('Unsend'),
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

                      if ((mediaType == 'image' || mediaType == 'video' || mediaType == 'voice') &&
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
        Object? lastDownloadError;
        // অ্যাপ Recents-এ গেলে বা দুর্বল নেটওয়ার্কে সাময়িক ব্যর্থ হলে retry।
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            final result = await SpaceSyncService.downloadMedia(
              fileId,
              saveAs: '${fileId}_$name',
            );
            if (await File(result).exists()) {
              return result;
            }
            lastDownloadError = Exception('ডাউনলোডের ফাইল পাওয়া যায়নি।');
          } catch (error) {
            lastDownloadError = error;
            final message = error.toString();
            final permanentError = RegExp(
              r'সার্ভার ত্রুটি: (400|401|403|404)',
            ).hasMatch(message);
            if (permanentError || attempt == 2) rethrow;
          }
          await Future<void>.delayed(
            Duration(milliseconds: 700 * (attempt + 1)),
          );
        }
        throw Exception('ডাউনলোড ব্যর্থ: $lastDownloadError');
      } catch (error) {
        debugPrint('Chat media download error: $error');
        return null;
      }
    });
    _mediaPathFutures[key] = future;
    future.then((path) {
      if (path == null) {
        if (identical(_mediaPathFutures[key], future)) {
          _mediaPathFutures.remove(key);
        }
        _failedMediaMessages[key] = Map<String, dynamic>.from(media);
      } else {
        _failedMediaMessages.remove(key);
      }
    });
    return future;
  }

  void _retryFailedMediaDownloads() {
    if (!mounted || _failedMediaMessages.isEmpty) return;
    final pending = _failedMediaMessages.entries.toList(growable: false);
    for (final entry in pending) {
      if (_mediaPathFutures.containsKey(entry.key)) continue;
      unawaited(_resolveMediaPath(entry.value).then((path) {
        if (!mounted) return;
        setState(() {});
      }).catchError((Object error) {
        debugPrint('Automatic media retry failed: $error');
      }));
    }
    if (mounted) setState(() {});
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

    if (type == 'image' || type == 'video' || type == 'voice') {
      final fileId =
          '${message['fileId'] ?? message['driveFileId'] ?? ''}'.trim();

      final mediaKey = fileId.isNotEmpty ? fileId : path;
      Uint8List? embeddedVideoThumbnail = _embeddedVideoThumbnails[mediaKey];
      if (type == 'video' && embeddedVideoThumbnail == null) {
        final encodedThumbnail =
            '${message['thumbnailBase64'] ?? ''}'.trim();
        if (encodedThumbnail.isNotEmpty) {
          try {
            embeddedVideoThumbnail = base64Decode(encodedThumbnail);
            _embeddedVideoThumbnails[mediaKey] = embeddedVideoThumbnail;
          } catch (error) {
            debugPrint('Embedded chat video preview decode skipped: $error');
          }
        }
      }

      return ValueListenableBuilder<bool>(
        valueListenable: DataSaverSettings.enabled,
        builder: (context, dataSaverEnabled, _) {
          final localMediaPath =
              '${message['text'] ?? message['path'] ?? ''}'.trim();

          // File existence is checked asynchronously inside _resolveMediaPath.
          // Synchronous disk checks here were blocking the UI while scrolling media.
          final senderHasLocalFile = _isMine(message) && localMediaPath.isNotEmpty;

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
                  child: type == 'video'
                      ? SizedBox(
                          width: 210,
                          height: 130,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (embeddedVideoThumbnail != null)
                                  Image.memory(
                                    embeddedVideoThumbnail,
                                    cacheWidth: 420,
                                    cacheHeight: 260,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(color: Colors.black26),
                                  )
                                else
                                  const ColoredBox(color: Colors.black26),
                                const DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Color(0xAA000000),
                                      ],
                                    ),
                                  ),
                                ),
                                const Center(
                                  child: Icon(
                                    Icons.play_circle_fill_rounded,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                ),
                                Positioned(
                                  left: 8,
                                  bottom: 7,
                                  child: Text(
                                    'ডাউনলোড করতে ট্যাপ করো • ${_formatMediaSize(message['size'])}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Container(
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
                              const Icon(
                                Icons.image_outlined,
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
                if (type == 'video' && embeddedVideoThumbnail != null) {
                  return SizedBox(
                    width: 210,
                    height: 130,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            embeddedVideoThumbnail,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const ColoredBox(color: Colors.black26),
                          ),
                          const DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Color(0xCC000000),
                                ],
                              ),
                            ),
                          ),
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              size: 46,
                              color: Colors.white,
                            ),
                          ),
                          Positioned(
                            left: 8,
                            right: 8,
                            bottom: 7,
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
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      current == null
                                          ? 'ভিডিও ডাউনলোড হচ্ছে...'
                                          : '${(current.progress * 100).toStringAsFixed(0)}% ডাউনলোড',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    LinearProgressIndicator(
                                      value: current?.progress,
                                      backgroundColor: Colors.white24,
                                      color: pinkColor,
                                      minHeight: 3,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // ছবি লোড হওয়ার সময়ও চূড়ান্ত 210x210 জায়গা ধরে রাখি;
                // নইলে 120px placeholder থেকে 210px ছবিতে বদলে scroll offset লাফায়।
                if (type == 'image') {
                  return SizedBox(
                    width: 210,
                    height: 210,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              color: pinkColor,
                              strokeWidth: 2,
                            ),
                            const SizedBox(height: 10),
                            ValueListenableBuilder<List<DownloadProgress>>(
                              valueListenable: SpaceSyncService.downloadProgress,
                              builder: (context, downloads, _) {
                                DownloadProgress? current;
                                for (final item in downloads) {
                                  if (item.fileId == fileId) {
                                    current = item;
                                    break;
                                  }
                                }
                                return Text(
                                  current == null
                                      ? 'ছবি লোড হচ্ছে...'
                                      : '${(current.progress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // Keep the voice bubble close to its final height while downloading,
                // so resolving a voice file does not move neighbouring chat rows.
                return SizedBox(
                  width: 270,
                  height: 52,
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

              if (snapshot.hasError || resolvedPath == null) {
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

              if (type == 'voice') {
                return ChatVoicePlayer(
                  path: resolvedPath,
                  durationMs: int.tryParse('${message['durationMs'] ?? ''}'),
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
                      cacheWidth: (210 * MediaQuery.devicePixelRatioOf(context)).round(),
                      cacheHeight: (210 * MediaQuery.devicePixelRatioOf(context)).round(),
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
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VideoViewerPage(path: resolvedPath)));
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 210,
                    height: 130,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        FutureBuilder<String?>(
                          future: _resolveChatVideoThumbnail(message, resolvedPath),
                          builder: (context, snapshot) {
                            final thumbnailPath = snapshot.data;
                            if (thumbnailPath != null) {
                              return Image.file(File(thumbnailPath), cacheWidth: (210 * MediaQuery.devicePixelRatioOf(context)).round(), cacheHeight: (130 * MediaQuery.devicePixelRatioOf(context)).round(), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black26));
                            }
                            return const ColoredBox(color: Colors.black26);
                          },
                        ),
                        const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)]))),
                        const Center(child: Icon(Icons.play_circle_fill_rounded, size: 48, color: Colors.white)),
                        const Positioned(left: 8, bottom: 7, child: Text('ভিডিও', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    final linkRegex = RegExp(r'(https?://\S+|www\.\S+)', caseSensitive: false);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in linkRegex.allMatches(path)) {
      if (match.start > last) spans.add(TextSpan(text: path.substring(last, match.start)));
      final rawUrl = match.group(0)!;
      final url = Uri.tryParse(rawUrl.startsWith('www.') ? 'https://$rawUrl' : rawUrl);
      if (url != null && (url.scheme == 'http' || url.scheme == 'https') && url.host.isNotEmpty) {
        spans.add(TextSpan(text: rawUrl, style: const TextStyle(color: Color(0xFF80CFFF), decoration: TextDecoration.underline), recognizer: TapGestureRecognizer()..onTap = () async {
          try { await launchUrl(url, mode: LaunchMode.externalApplication); }
          catch (error) { debugPrint('Could not open chat link: $error'); }
        }));
      } else { spans.add(TextSpan(text: rawUrl)); }
      last = match.end;
    }
    if (last < path.length) spans.add(TextSpan(text: path.substring(last)));
    return RichText(text: TextSpan(style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.45), children: spans), softWrap: true, textWidthBasis: TextWidthBasis.parent);
  }

  Widget _buildPendingMediaMessage() {
    final fileName = _pendingMediaName ?? 'মিডিয়া ফাইল';
    final progress =
        _pendingMediaProgress.clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
                      Text(
                        _pendingMediaProgress <= 0
                            ? 'আপলোড প্রস্তুত হচ্ছে...'
                            : 'আপলোড হচ্ছে...',
                        style: const TextStyle(
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

  DateTime? _messageDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toLocal();
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse('${value ?? ''}')?.toLocal();
  }

  bool _shouldShowTimeDivider(int index) {
    if (index <= 0 || index >= messages.length) return false;
    final previous = messages[index - 1];
    final current = messages[index];
    if ('${previous['senderUid'] ?? ''}' == '${current['senderUid'] ?? ''}') return false;
    final previousDate = _messageDate(previous['time']);
    final currentDate = _messageDate(current['time']);
    if (previousDate == null || currentDate == null) return false;
    return currentDate.difference(previousDate) > const Duration(minutes: 10);
  }

  int _emojiDisplayCount(String value) {
    var count = 0;
    for (final rune in value.trim().runes) {
      if (rune == 0x20 ||
          rune == 0x00A0 ||
          rune == 0x200D ||
          rune == 0xFE0E ||
          rune == 0xFE0F ||
          rune == 0x20E3 ||
          (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
          (rune >= 0xE0020 && rune <= 0xE007F)) {
        continue;
      }
      count++;
    }
    return count;
  }

  bool _isEmojiOnlyText(String value) {
    final runes = value.trim().runes.toList();
    if (runes.isEmpty) return false;

    final hasKeycap = runes.contains(0x20E3);
    const emojiSymbols = <int>{
      0x00A9, 0x00AE, 0x203C, 0x2049, 0x2122, 0x2139,
      0x3030, 0x303D, 0x3297, 0x3299, 0x24C2,
    };
    var foundEmoji = false;

    for (final rune in runes) {
      if (rune == 0x20 ||
          rune == 0x00A0 ||
          rune == 0x200D ||
          rune == 0xFE0E ||
          rune == 0xFE0F ||
          rune == 0x20E3 ||
          (rune >= 0xE0020 && rune <= 0xE007F)) {
        continue;
      }

      final isEmojiCodePoint =
          (rune >= 0x1F000 && rune <= 0x1FAFF) ||
          (rune >= 0x2600 && rune <= 0x27BF) ||
          (rune >= 0x2300 && rune <= 0x23FF) ||
          emojiSymbols.contains(rune) ||
          (hasKeycap &&
              ((rune >= 0x30 && rune <= 0x39) ||
                  rune == 0x23 ||
                  rune == 0x2A));

      if (!isEmojiCodePoint) return false;
      foundEmoji = true;
    }

    return foundEmoji;
  }

  static const Map<String, List<String>> _reactionEmojiCategories = {
    'সাম্প্রতিক': ['❤️', '😂', '🥹', '😍', '😮', '😢', '🔥', '👍', '🙏', '🎉', '💯', '🫶'],
    'হৃদয়': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘', '💝', '💟'],
    'মুখ': ['😀', '😃', '😄', '😁', '😆', '🥹', '😂', '🤣', '😊', '😇', '🙂', '🙃', '😉', '😍', '🥰', '😘', '😗', '😙', '😚', '😋', '😛', '😜', '🤪', '🤗', '🤭', '🫢', '🤫', '🤔', '🫡', '😎', '🥳', '😭', '😢', '😤', '😡', '😱', '😮', '😴', '🤒', '🥺'],
    'হাত': ['👍', '👎', '👏', '🙌', '🫶', '🤝', '🙏', '🤲', '💪', '✌️', '🤞', '🤟', '🤘', '👌', '🫰', '👋', '🤚', '✋', '🖐️', '☝️', '👇', '👆'],
    'ফুল': ['🌹', '🌷', '🌸', '🌺', '🌻', '🌼', '💐', '🪷', '🪻', '🌱', '🌿', '🍀', '☘️', '🌵', '🌴', '🌳', '🌲', '🍁', '🍂', '🍃'],
    'খাবার': ['🍎', '🍓', '🍒', '🍉', '🍇', '🍑', '🥭', '🍍', '🥥', '🥝', '🍌', '🍋', '🍊', '🥑', '🍕', '🍔', '🍟', '🌭', '🍿', '🍩', '🍪', '🎂', '🍰', '🧁', '🍫', '🍭', '☕', '🧋'],
    'প্রকৃতি': ['🔥', '✨', '⭐', '🌟', '💫', '⚡', '☀️', '🌈', '☁️', '🌧️', '❄️', '🌙', '🌍', '🌊', '💧', '🎉', '🎊', '💯', '🏆', '🎁'],
  };

  static const List<String> _quickReactionEmojis = [
    '❤️', '😂', '🥹', '😍', '😮', '😢', '🔥', '👍', '🙏', '🎉', '💯', '🫶',
  ];

  Future<void> _setMessageReaction(
    String messageId,
    String emoji,
  ) async {
    try {
      await ChatSyncService.setMessageReaction(
        messageId: messageId,
        emoji: emoji,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('রিঅ্যাকশন দেওয়া যায়নি: ${error}')),
      );
    }
  }

  Future<void> _showReactionPicker(
    Map<String, dynamic> message,
  ) async {
    if (message['unsent'] == true) return;
    final messageId = '${message['id'] ?? ''}'.trim();
    if (messageId.isEmpty) return;

    final categories = _reactionEmojiCategories.keys.toList();
    var selectedCategory = categories.first;
    final selectedEmoji = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final emojis = _reactionEmojiCategories[selectedCategory]!;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Center(
                      child: Text(
                        'ইমোজি দিয়ে রিঅ্যাক্ট করো',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories.map((category) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(category),
                              selected: selectedCategory == category,
                              onSelected: (_) => setSheetState(() => selectedCategory = category),
                              selectedColor: pinkColor.withValues(alpha: 0.28),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        itemCount: emojis.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                        itemBuilder: (context, index) {
                          final emoji = emojis[index];
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => Navigator.pop(sheetContext, emoji),
                            child: Center(
                              child: Text(emoji, style: const TextStyle(fontSize: 27)),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (selectedEmoji != null) {
      await _setMessageReaction(messageId, selectedEmoji);
    }
  }

  Widget _buildReactionSummary(
    Map<String, dynamic> message,
    bool mine,
  ) {
    if (message['unsent'] == true) return const SizedBox.shrink();
    final raw = message['reactions'];
    if (raw is! Map || raw.isEmpty) return const SizedBox.shrink();

    final reactions = <String, String>{};
    for (final entry in raw.entries) {
      final emoji = '${entry.value}'.trim();
      if (emoji.isNotEmpty) reactions['${entry.key}'] = emoji;
    }
    if (reactions.isEmpty) return const SizedBox.shrink();

    final grouped = <String, int>{};
    for (final emoji in reactions.values) {
      grouped[emoji] = (grouped[emoji] ?? 0) + 1;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(
          spacing: 5,
          runSpacing: 4,
          children: grouped.entries.map((entry) {
            final selectedByMe = reactions[_currentUid] == entry.key;
            return InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _setMessageReaction(
                '${message['id'] ?? ''}',
                selectedByMe ? '' : entry.key,
              ),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: selectedByMe
                      ? pinkColor.withValues(alpha: 0.22)
                      : Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: selectedByMe
                        ? pinkColor.withValues(alpha: 0.7)
                        : Colors.white12,
                  ),
                ),
                child: Text(
                  '${entry.key} ${entry.value}',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMessage(Map<String, dynamic> message, int index) {
    final mine = _isMine(message);
    final senderUid = '${message['senderUid'] ?? ''}';
    final messageId = '${message['id'] ?? index}';
    final dragOffset = (_replyDragOffsets[messageId] ?? 0).clamp(0.0, 104.0).toDouble();
    final expanded = _expandedMessageTimes.contains(messageId);
    final messageText = '${message['text'] ?? ''}';
    final isEmojiOnly = message['unsent'] != true &&
        '${message['type'] ?? 'text'}' == 'text' &&
        _isEmojiOnlyText(messageText) &&
        _emojiDisplayCount(messageText) <= 3;

    final row = Row(
      mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
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
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  if (isEmojiOnly)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      child: Text(
                        '${message['text'] ?? ''}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 40, height: 1.08),
                      ),
                    )
                  else
                    Container(
                      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
                      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                      decoration: BoxDecoration(
                        color: mine ? const Color(0xFF453078) : surfaceColor,
                        border: Border.all(
                          color: mine ? pinkColor.withValues(alpha: 0.25) : Colors.white10,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(index > 0 &&
                                  '${messages[index - 1]['senderUid'] ?? ''}' == senderUid
                              ? 18 : 24),
                          topRight: Radius.circular(index > 0 &&
                                  '${messages[index - 1]['senderUid'] ?? ''}' == senderUid
                              ? 18 : 24),
                          bottomLeft: Radius.circular(index + 1 < messages.length &&
                                  '${messages[index + 1]['senderUid'] ?? ''}' == senderUid
                              ? 18 : (mine ? 24 : 18)),
                          bottomRight: Radius.circular(index + 1 < messages.length &&
                                  '${messages[index + 1]['senderUid'] ?? ''}' == senderUid
                              ? 18 : (mine ? 18 : 24)),
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
                  if (message['pinned'] == true)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: surfaceColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.push_pin_rounded, size: 13, color: pinkColor),
                      ),
                    ),
                  if (expanded && message['unsent'] != true)
                    Positioned(
                      bottom: -8,
                      left: mine ? 0 : null,
                      right: mine ? null : 0,
                      child: Material(
                        color: surfaceColor,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _showReactionPicker(message),
                          child: const Padding(
                            padding: EdgeInsets.all(5),
                            child: Icon(Icons.add_reaction_outlined, size: 17, color: pinkColor),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              _buildReactionSummary(message, mine),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _formatTime(message['time']),
                          style: const TextStyle(fontSize: 10, color: Colors.white54),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              if (mine && index == _lastOwnMessageIndex)
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 2),
                  child: Builder(
                    builder: (context) {
                      final rawSeenBy = message['seenBy'];
                      final wasSeen = rawSeenBy is Map &&
                          rawSeenBy.entries.any((entry) =>
                              '${entry.key}' != _currentUid && entry.value == true);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            wasSeen ? Icons.done_all_rounded : Icons.done_rounded,
                            size: 13,
                            color: wasSeen ? const Color(0xFF53D9FF) : Colors.white54,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            wasSeen ? 'Seen' : 'Sent',
                            style: TextStyle(
                              fontSize: 10,
                              color: wasSeen ? const Color(0xFF53D9FF) : Colors.white54,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
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
                  FirebaseAuth.instance.currentUser?.email?.split('@').first ??
                  'You',
            ),
            photoBase64: _photoBase64ForUid(_currentUid),
            radius: 16,
            color: pinkColor,
          ),
        ],
      ],
    );

    return RepaintBoundary(
      key: ValueKey<String>('chat-row-$messageId'),
      child: KeyedSubtree(
        key: _messageKeys.putIfAbsent(messageId, () => GlobalKey()),
        child: Column(
          children: [
        if (_shouldShowTimeDivider(index))
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 5),
            child: Center(
              child: Text(
                _formatTime(message['time']),
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: () {
            setState(() {
              if (expanded) {
                _expandedMessageTimes.remove(messageId);
              } else {
                _expandedMessageTimes.add(messageId);
              }
            });
          },
          onLongPress: () {
            unawaited(InteractionFeedbackSettings.vibrate());
            if (mine || message['unsent'] != true) _showMessageOptions(message);
          },
          onDoubleTap: () => unawaited(
            _setMessageReaction(messageId, '❤️'),
          ),
          onHorizontalDragUpdate: (details) {
            final currentOffset = _replyDragOffsets[messageId] ?? 0;
            // Messenger-এর মতো reply করতে স্পষ্টভাবে ডানদিকে টানতে হবে;
            // অল্প/তির্যক swipe-এ মেসেজ সরবে না।
            if (details.delta.dx <= 0 && currentOffset <= 0) return;
            if (details.delta.dx.abs() < details.delta.dy.abs() * 1.15 &&
                currentOffset < 18) {
              return;
            }
            setState(() {
              _replyDragOffsets[messageId] =
                  (currentOffset + details.delta.dx).clamp(0.0, 104.0).toDouble();
            });
          },
          onHorizontalDragEnd: (_) {
            final offset = _replyDragOffsets[messageId] ?? 0;
            if (offset >= 78 && message['unsent'] != true) {
              unawaited(InteractionFeedbackSettings.vibrate());
              _setReplyTo(message);
            }
            setState(() => _replyDragOffsets[messageId] = 0);
          },
          child: Container(
            transform: Matrix4.identity()..scale(_highlightedMessageId == messageId ? 1.025 : 1.0),
            transformAlignment: Alignment.center,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: _highlightedMessageId == messageId ? pinkColor.withValues(alpha: 0.13) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Padding(
              padding: EdgeInsets.only(top: index > 0 && '${messages[index - 1]['senderUid'] ?? ''}' == senderUid ? 0 : 3, bottom: index + 1 < messages.length && '${messages[index + 1]['senderUid'] ?? ''}' == senderUid ? 0 : 3),
              child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 2,
                  child: AnimatedOpacity(
                    opacity: dragOffset >= 22 ? 1 : 0,
                    duration: const Duration(milliseconds: 100),
                    child: const Icon(Icons.reply_rounded, color: pinkColor, size: 22),
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  transform: Matrix4.translationValues(dragOffset, 0, 0),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      row,
                    ],
                  ),
                ),
              ],
              ),
            ),
          ),
        ),
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
          IconButton(
            tooltip: 'Pinned messages',
            onPressed: _showPinnedMessages,
            icon: const Icon(Icons.push_pin_rounded, color: pinkColor, size: 21),
          ),
        ],
      ),
    );
  }

  Future<void> _showPinnedMessages() async {
    final pinned = messages.where((message) => message['pinned'] == true && message['unsent'] != true).toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (sheetContext) => SafeArea(
        child: pinned.isEmpty
            ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('এখনো কোনো মেসেজ Pin করা হয়নি।')))
            : ListView.builder(
                shrinkWrap: true,
                itemCount: pinned.length,
                itemBuilder: (context, index) {
                  final item = pinned[index];
                  final id = '${item['id'] ?? ''}';
                  final body = '${item['text'] ?? (item['type'] == 'voice' ? 'Voice message' : 'Media message')}';
                  return ListTile(
                    leading: const Icon(Icons.push_pin_rounded, color: pinkColor),
                    title: Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_jumpToMessage(id));
                    },
                  );
                },
              ),
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
              : NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollStartNotification &&
                        notification.dragDetails != null) {
                      _userIsScrolling = true;
                      _scrollRequestToken++;
                      if (scrollController.hasClients) {
                        final distanceFromBottom =
                            scrollController.position.maxScrollExtent -
                                scrollController.position.pixels;
                        if (distanceFromBottom > 24) {
                          _userHasScrolledAwayFromBottom = true;
                        }
                      }
                    } else if (notification is ScrollEndNotification) {
                      _userIsScrolling = false;
                    }
                    if (notification is ScrollUpdateNotification ||
                        notification is ScrollEndNotification) {
                      _updateChatScrollPosition();
                      if (scrollController.hasClients) {
                        final distanceFromBottom =
                            scrollController.position.maxScrollExtent -
                                scrollController.position.pixels;
                        // Clear auto-follow lock only when genuinely back at
                        // the bottom, not merely within the 120px UI threshold.
                        if (distanceFromBottom <= 24) {
                          _userHasScrolledAwayFromBottom = false;
                        } else if (notification is ScrollUpdateNotification &&
                            notification.dragDetails != null) {
                          // Any manual drag away from the bottom pauses
                          // automatic following while the user reads history.
                          _userHasScrolledAwayFromBottom = true;
                        }
                      }
                      final shouldShow = !_isNearChatBottom;
                      if (shouldShow != _showJumpToBottom && mounted) {
                        setState(() => _showJumpToBottom = shouldShow);
                      }
                    }
                    return false;
                  },
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ListView.builder(
                    key: const PageStorageKey<String>('couple-zone-chat-list'),
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    // কম off-screen row তৈরি রাখি, যাতে ছবি/ভিডিও/ভয়েসের
                    // decode ও download একসঙ্গে শুরু হয়ে scroll frame drop না করে।
                    cacheExtent: 80,
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    itemCount:
                        messages.length + (_pendingMediaName != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= messages.length) {
                        return _buildPendingMediaMessage();
                      }

                      final message = messages[index];
                      final messageId = '${message['id'] ?? index}';
                      return KeyedSubtree(
                        key: ValueKey<String>('chat-message-$messageId'),
                        child: _buildMessage(message, index),
                      );
                    },
                        ),
                      ),
                      if (_showJumpToBottom)
                        Positioned(
                          right: 16,
                          bottom: 14,
                          child: Material(
                            color: pinkColor,
                            elevation: 7,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                  _userHasScrolledAwayFromBottom = false;
                                  _scrollToBottom();
                                },
                              child: const SizedBox(
                                width: 48,
                                height: 48,
                                child: Icon(
                                  Icons.keyboard_double_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 27,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
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
                _buildVoiceRecordingPanel(),
                Row(
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'ছবি, ভিডিও বা ক্যামেরা',
                      onOpened: () {
                        if (mounted) setState(() => _attachmentMenuOpen = true);
                      },
                      onCanceled: () {
                        if (mounted) setState(() => _attachmentMenuOpen = false);
                      },
                      onSelected: (choice) {
                        setState(() => _attachmentMenuOpen = false);
                        if (choice == 'image') {
                          _sendMedia(false);
                        } else if (choice == 'video') {
                          _sendMedia(true);
                        } else if (choice == 'camera') {
                          _sendMedia(false, source: ImageSource.camera);
                        } else if (choice == 'voice') {
                          _startVoiceRecording();
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'image',
                          child: ListTile(
                            leading: Icon(Icons.image_outlined),
                            title: Text('ছবি'),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'video',
                          child: ListTile(
                            leading: Icon(Icons.video_library_outlined),
                            title: Text('ভিডিও'),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'camera',
                          child: ListTile(
                            leading: Icon(Icons.camera_alt_outlined),
                            title: Text('ক্যামেরা'),
                            dense: true,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'voice',
                          child: ListTile(
                            leading: Icon(Icons.mic_none_rounded),
                            title: Text('ভয়েস রেকর্ড'),
                            dense: true,
                          ),
                        ),
                      ],
                      icon: AnimatedRotation(
                        turns: _attachmentMenuOpen ? 0.125 : 0,
                        duration: const Duration(milliseconds: 160),
                        child: const Icon(Icons.add_rounded, color: pinkColor),
                      ),
                    ),
                    IconButton(
                      tooltip: _isRecordingVoice ? 'রেকর্ড বন্ধ' : 'ভয়েস রেকর্ড',
                      onPressed: _toggleVoiceRecording,
                      icon: Icon(
                        _isRecordingVoice ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
                        color: _isRecordingVoice ? Colors.redAccent : pinkColor,
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
  bool _autoDownloadRunning = false;

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
        {'id': 'videos', 'name': 'Videos'},
      ];
      unawaited(SpaceStore.saveList('galleryFolders', folders));
    } else if (!folders.any((folder) => '${folder['id']}' == 'videos')) {
      folders.add({'id': 'videos', 'name': 'Videos'});
      unawaited(SpaceStore.saveList('galleryFolders', folders));
    }
    unawaited(_autoDownloadMissingMedia());
  }

  Future<void> _autoDownloadMissingMedia() async {
    if (_autoDownloadRunning || !mounted) return;
    _autoDownloadRunning = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedRaw = prefs.getString('galleryLocalPaths');
      final savedPaths = <String, dynamic>{};
      if (savedRaw != null && savedRaw.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedRaw);
          if (decoded is Map) savedPaths.addAll(Map<String, dynamic>.from(decoded));
        } catch (_) {}
      }

      var changed = false;
      final candidates = media.map((item) => Map<String, dynamic>.from(item)).toList();
      for (final item in candidates) {
        if (!mounted) break;
        final fileId = '${item['fileId'] ?? item['driveFileId'] ?? ''}'.trim();
        if (fileId.isEmpty) continue;
        final isPersonal = item['storage'] == 'personal';
        final localPath = '${item['path'] ?? ''}'.trim();
        if (localPath.isNotEmpty) {
          try {
            final localFile = File(localPath);
            if (await localFile.exists() && await localFile.length() > 0) continue;
          } catch (_) {}
        }

        try {
          String resolvedPath =
              (await SpaceSyncService.getCachedMediaPath(
                fileId,
                shared: !isPersonal,
              )) ??
              '';
          if (resolvedPath.isEmpty || !await File(resolvedPath).exists()) {
            final originalName = '${item['driveFileName'] ?? item['name'] ?? 'memory'}';
            final safeName = '${item['id'] ?? fileId}_$originalName';
            resolvedPath = isPersonal
                ? await SpaceSyncService.downloadPersonalMedia(fileId, saveAs: safeName)
                : await SpaceSyncService.downloadMedia(fileId, saveAs: safeName);
          }
          final downloaded = File(resolvedPath);
          if (!await downloaded.exists() || await downloaded.length() <= 0) continue;
          savedPaths[fileId] = resolvedPath;
          final index = media.indexWhere((entry) =>
              '${entry['fileId'] ?? entry['driveFileId'] ?? ''}' == fileId);
          if (index >= 0 && media[index]['path'] != resolvedPath) {
            media[index]['path'] = resolvedPath;
            changed = true;
          }
        } catch (error) {
          debugPrint('Gallery background download skipped ($fileId): $error');
        }
      }

      if (savedPaths.isNotEmpty) {
        await prefs.setString('galleryLocalPaths', jsonEncode(savedPaths));
      }
      if (changed) {
        await _save();
        if (mounted) setState(() {});
      }
    } catch (error) {
      debugPrint('Gallery background download error: $error');
    } finally {
      _autoDownloadRunning = false;
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
    unawaited(_autoDownloadMissingMedia());
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
    final isDefault = id == 'all' || id == 'favorites' || id == 'videos';

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

    if (id == 'all' || id == 'favorites' || id == 'videos') return;

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

    if (id == 'all' || id == 'favorites' || id == 'videos') return;

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
        : await picker.pickImage(source: ImageSource.gallery, imageQuality: 88, maxWidth: 2560, maxHeight: 2560);

    if (picked == null) return null;
    if (!mounted) return null;

    File uploadFile = File(picked.path);
    if (video) {
      try {
        uploadFile = await _makeCompatibleVideo(uploadFile);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ভিডিও অপটিমাইজ করা যায়নি; অন্য ভিডিও দিয়ে চেষ্টা করুন।')),
          );
        }
        return null;
      }
    }

    final itemId = DateTime.now().microsecondsSinceEpoch.toString();
    final uploadCreatedAt = DateTime.now().toIso8601String();
    final creatorUid =
        FirebaseAuth.instance.currentUser?.uid ?? '';
    final creatorName = _currentCreatorName();

    Map<String, String> uploaded;

    try {
      uploaded = await SpaceSyncService.uploadSharedMedia(
        uploadFile,
        metadata: {
          'purpose': 'gallery',
          'itemId': itemId,
          'type': video ? 'video' : 'image',
          'folderId': folderId,
          'createdByUid': creatorUid,
          'createdByName': creatorName,
          'createdAt': uploadCreatedAt,
          'fileName': uploadFile.uri.pathSegments.last,
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
    var galleryLocalPath = uploadFile.path;
    try {
      final fileId = (
        uploaded['fileId'] ??
        uploaded['driveFileId'] ??
        ''
      ).toString().trim();

      final sourceFile = uploadFile;

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
        final uploadName = uploadFile.uri.pathSegments.last;
        final dot = uploadName.lastIndexOf('.');
        final extension = dot > 0 && uploadName.length - dot <= 10
            ? uploadName.substring(dot).toLowerCase()
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

  Future<void> _showMediaMenu(
    Map<String, dynamic> item, {
    bool fromFavorites = false,
  }) async {
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
                  await _deleteMediaItem(item, fromFavorites: fromFavorites);
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
          onLongPress: (item) => _showMediaMenu(
            item,
            fromFavorites: id == 'favorites',
          ),
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

    if (id == 'videos') {
      // Videos from every folder appear here; images are excluded.
      return media
          .where((item) => '${item['type']}'.toLowerCase() == 'video')
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
            onPressed: () async {
              await widget.onFavorite(widget.items[currentIndex]);
              if (mounted) setState(() {});
            },
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
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: surfaceColor,
                    title: const Text('Delete memory?'),
                    content: const Text('This item will be removed from the gallery.'),
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
                if (confirmed == true) {
                  await widget.onDelete(item);
                  if (mounted) Navigator.pop(context);
                }
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
                isActive: index == currentIndex,
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
  final bool isActive;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _GalleryVideoPlayer({
    super.key,
    required this.path,
    this.isActive = true,
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
  String? _optimizedPath;
  bool _isOptimizing = false;
  bool _hasAttemptedOptimization = false;
  bool _showControls = false;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant _GalleryVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    final controller = _controller;
    if (!widget.isActive) {
      if (controller != null && controller.value.isInitialized) {
        unawaited(controller.setVolume(0).then((_) => controller.pause()));
      }
    } else if (controller == null) {
      unawaited(_initialize());
    } else if (controller.value.isInitialized) {
      unawaited(controller.setVolume(1).then((_) => controller.play()));
    }
  }

  Future<void> _initialize([String? sourcePath]) async {
    if (!widget.isActive) return;
    final video = VideoPlayerController.file(File(sourcePath ?? _optimizedPath ?? widget.path));
    _controller = video;

    try {
      await video.initialize();

      if (!mounted) {
        await video.dispose();
        return;
      }

      setState(() {});
      await video.setVolume(widget.isActive ? 1.0 : 0.0);
      if (widget.isActive) await video.play();
    } catch (error) {
      await video.dispose();
      if (identical(_controller, video)) _controller = null;

      if (!mounted) return;
      if (!_hasAttemptedOptimization) {
        // পুরোনো/HEVC ভিডিও প্রথমবার না চললে নিজে থেকেই MP4/H.264-এ রূপান্তর করো।
        unawaited(_tryOptimizeAndPlay());
        return;
      }
      setState(() {
        _error = 'ভিডিও খোলা যায়নি। ফাইলটি অসম্পূর্ণ বা এই ডিভাইসে অসমর্থিত হতে পারে।';
      });
    }
  }

  Future<void> _tryOptimizeAndPlay({bool force = false}) async {
    if (_isOptimizing || (_hasAttemptedOptimization && !force)) return;
    _hasAttemptedOptimization = true;
    setState(() {
      _isOptimizing = true;
      _error = null;
    });
    try {
      final support = await getApplicationSupportDirectory();
      final optimizedDirectory = Directory('${support.path}/orbit_optimized_videos');
      await optimizedDirectory.create(recursive: true);
      final sourceName = File(widget.path).uri.pathSegments.last
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final sourceHash = widget.path.codeUnits.fold<int>(
        17,
        (hash, unit) => (hash * 31 + unit) & 0x7fffffff,
      );
      final optimizedFile = File(
        '${optimizedDirectory.path}/${sourceName}_${sourceHash}_720p.mp4',
      );

      if (force && await optimizedFile.exists()) {
        await optimizedFile.delete();
      }
      if (!await optimizedFile.exists() || await optimizedFile.length() <= 0) {
        final result = await VideoCompress.compressVideo(
          widget.path,
          quality: VideoQuality.Res1280x720Quality,
          deleteOrigin: false,
          includeAudio: true,
        );
        final compressed = result?.file;
        if (compressed == null ||
            !await compressed.exists() ||
            await compressed.length() <= 0) {
          throw Exception('অপটিমাইজ করা ফাইল পাওয়া যায়নি।');
        }
        if (await optimizedFile.exists()) await optimizedFile.delete();
        await compressed.copy(optimizedFile.path);
      }

      if (await optimizedFile.length() <= 0) {
        throw Exception('অপটিমাইজ করা ভিডিও খালি।');
      }
      _optimizedPath = optimizedFile.path;
      await _controller?.dispose();
      _controller = null;
      await _initialize(optimizedFile.path);
    } catch (error) {
      debugPrint('Automatic video optimization failed: $error');
      if (mounted) {
        setState(() {
          _error = 'ভিডিও স্বয়ংক্রিয়ভাবে অপটিমাইজ করা যায়নি। আবার চেষ্টা করুন।';
        });
      }
    } finally {
      if (mounted) setState(() => _isOptimizing = false);
    }
  }

  Future<void> _togglePlayback() async {
    final video = _controller;
    if (!widget.isActive || video == null || !video.value.isInitialized) return;

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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.video_file_outlined, size: 42, color: pinkColor),
              const SizedBox(height: 10),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _isOptimizing ? null : () => _tryOptimizeAndPlay(force: true),
                icon: _isOptimizing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_fix_high_rounded),
                label: Text(_isOptimizing ? 'ভিডিও অপটিমাইজ হচ্ছে…' : 'অপটিমাইজ করে আবার চালাও'),
              ),
            ],
          ),
        ),
      );
    }

    if (video == null || !video.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: video.value.aspectRatio,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(video),
              if (_showControls) Center(child: IconButton(onPressed: _togglePlayback, iconSize: 44, color: Colors.white, icon: Icon(video.value.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded))),
              if (_showControls) Positioned(
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
      ),
    );
  }
}


class ChatVoicePlayer extends StatefulWidget {
  const ChatVoicePlayer({
    super.key,
    required this.path,
    this.durationMs,
  });

  final String path;
  final int? durationMs;

  @override
  State<ChatVoicePlayer> createState() => _ChatVoicePlayerState();
}

class _ChatVoicePlayerState extends State<ChatVoicePlayer> {
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _stateSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  bool _isPlaying = false;
  bool _isPreparing = false;
  bool _sourceLoaded = false;
  Future<void>? _sourceLoadFuture;
  Duration? _duration;
  Duration _position = Duration.zero;
  double _playbackRate = 1.0;

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final milliseconds = widget.durationMs ?? 0;
    if (milliseconds > 0) {
      _duration = Duration(milliseconds: milliseconds);
    } else {
      // Older voice messages do not contain duration metadata; read it in the
      // background so the total duration appears before the user presses Play.
      unawaited(_preloadDuration());
    }
  }

  Future<void> _preloadDuration() async {
    try {
      final player = await _getPlayer();
      await _loadSource(player);
    } catch (error) {
      debugPrint('Voice duration preload failed: $error');
    }
  }

  Future<AudioPlayer> _getPlayer() async {
    var player = _player;
    if (player != null) return player;

    player = AudioPlayer();
    _player = player;
    _stateSubscription = player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      if (state == PlayerState.playing && !_isPlaying) {
        unawaited(InteractionFeedbackSettings.vibrate());
      }
      setState(() {
        _isPlaying = state == PlayerState.playing;
        if (state == PlayerState.completed && _duration != null) {
          _position = _duration!;
        }
      });
    });
    _durationSubscription = player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    _positionSubscription = player.onPositionChanged.listen((position) {
      if (!mounted) return;
      setState(() => _position = position);
    });
    // Keep the local audio source available after completion so replaying
    // a voice message starts reliably from the beginning.
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setPlaybackRate(_playbackRate);
    return player;
  }

  Future<void> _loadSource(AudioPlayer player) {
    if (_sourceLoaded) return Future<void>.value();
    final existingLoad = _sourceLoadFuture;
    if (existingLoad != null) return existingLoad;
    final load = _loadSourceInternal(player);
    _sourceLoadFuture = load;
    return load;
  }

  Future<void> _loadSourceInternal(AudioPlayer player) async {
    try {
      await player.setSource(DeviceFileSource(widget.path));
      _sourceLoaded = true;
      final actualDuration = await player.getDuration();
      if (actualDuration != null && mounted) {
        setState(() => _duration = actualDuration);
      }
    } catch (_) {
      _sourceLoadFuture = null;
      rethrow;
    }
  }

  Future<void> _togglePlayback() async {
    if (_isPreparing) return;
    setState(() => _isPreparing = true);
    try {
      final player = await _getPlayer();

      if (player.state == PlayerState.playing) {
        await player.pause();
      } else if (player.state == PlayerState.paused) {
        await player.resume();
      } else {
        // Load metadata first so the full duration appears before playback starts.
        await _loadSource(player);
        if (player.state == PlayerState.completed) {
          await player.seek(Duration.zero);
          if (mounted) setState(() => _position = Duration.zero);
        }
        await player.setPlaybackRate(_playbackRate);
        await player.resume();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ভয়েস চালানো যায়নি: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  Future<void> _cyclePlaybackRate() async {
    final nextRate = _playbackRate == 1.0
        ? 2.0
        : _playbackRate == 2.0
            ? 4.0
            : 1.0;

    setState(() => _playbackRate = nextRate);

    final player = _player;
    if (player != null) {
      try {
        await player.setPlaybackRate(nextRate);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('প্লেব্যাক স্পিড বদলানো যায়নি: $error')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _duration == null ? '--:--' : _formatDuration(_duration!);
    final elapsed = _formatDuration(_position);
    return Container(
      width: 270,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: _isPlaying ? 'Pause voice message' : 'Play voice message',
            onPressed: _isPreparing ? null : _togglePlayback,
            icon: _isPreparing
                ? const SizedBox(
                    width: 25,
                    height: 25,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: pinkColor,
                    ),
                  )
                : Icon(
                    _isPlaying
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                    color: pinkColor,
                    size: 34,
                  ),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 32,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final durationMs = (_duration?.inMilliseconds ?? 0).clamp(0, 1 << 31);
                      final positionMs = _position.inMilliseconds.clamp(0, durationMs);
                      final progress = durationMs <= 0 ? 0.0 : positionMs / durationMs;
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: Size(constraints.maxWidth, 30),
                            painter: _VoiceWaveformPainter(progress: progress),
                          ),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 1,
                              activeTrackColor: Colors.transparent,
                              inactiveTrackColor: Colors.transparent,
                              thumbColor: pinkColor,
                              overlayColor: pinkColor.withValues(alpha: 0.16),
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
                            ),
                            child: Slider(
                              min: 0,
                              max: durationMs > 0 ? durationMs.toDouble() : 1,
                              value: durationMs > 0 ? positionMs.toDouble() : 0,
                              onChanged: durationMs <= 0 ? null : (value) {
                                final target = Duration(milliseconds: value.round());
                                setState(() => _position = target);
                                unawaited(_player?.seek(target) ?? Future<void>.value());
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Text(
                  '$elapsed / $total',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: _cyclePlaybackRate,
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 36),
              padding: const EdgeInsets.symmetric(horizontal: 7),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              foregroundColor: Colors.white,
            ),
            child: Text(
              '${_playbackRate.toInt()}×',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  _VoiceWaveformPainter({required this.progress});
  final double progress;
  static const List<double> _heights = [
    0.28, 0.52, 0.38, 0.72, 0.46, 0.88, 0.58, 0.34, 0.66, 0.95,
    0.43, 0.61, 0.31, 0.78, 0.50, 0.90, 0.40, 0.64, 0.35, 0.82,
    0.55, 0.29, 0.70, 0.48, 0.93, 0.37, 0.59, 0.76, 0.42, 0.67,
    0.33, 0.86, 0.51, 0.73, 0.39, 0.62, 0.97, 0.44, 0.56, 0.30,
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final active = Paint()..color = pinkColor..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    final inactive = Paint()..color = Colors.white38..strokeWidth = 2.2..strokeCap = StrokeCap.round;
    final step = size.width / _heights.length;
    final playedWidth = size.width * progress.clamp(0.0, 1.0);
    for (var i = 0; i < _heights.length; i++) {
      final x = step * i + step / 2;
      final h = 5 + _heights[i] * (size.height - 7);
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), x <= playedWidth ? active : inactive);
    }
  }
  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) => oldDelegate.progress != progress;
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
        Card(
          color: surfaceColor,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: blueColor,
              child: Icon(Icons.privacy_tip_outlined, color: Colors.white),
            ),
            title: const Text('Privacy & account'),
            subtitle: const Text('ইমেইল, পাসওয়ার্ড, নাম ও প্রোফাইল সেটিংস'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PrivacyPage(
                    partnerOne: widget.partnerOne,
                    partnerTwo: widget.partnerTwo,
                    onSave: widget.onSave,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
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

        const SizedBox(height: 20),
        const SectionHeading(title: 'Notifications'),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: NotificationPrivacySettings.notificationsEnabled,
          builder: (context, notificationsEnabled, _) {
            final hideNotifications = !notificationsEnabled;
            return Card(
              color: surfaceColor,
              child: SwitchListTile(
                secondary: Icon(
                  hideNotifications
                      ? Icons.notifications_off_outlined
                      : Icons.notifications_active_outlined,
                  color: pinkColor,
                ),
                title: const Text('Message notifications'),
                subtitle: Text(
                  hideNotifications
                      ? 'বন্ধ: নতুন মেসেজের নোটিফিকেশন আসবে না।'
                      : 'চালু: নতুন মেসেজের নোটিফিকেশন আসবে।',
                ),
                value: hideNotifications,
                activeColor: pinkColor,
                onChanged: (hide) async {
                  try {
                    await NotificationPrivacySettings.setNotificationsEnabled(!hide);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Notification setting could not be saved.'),
                      ),
                    );
                  }
                },
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<bool>(
          valueListenable: NotificationPrivacySettings.hideDetails,
          builder: (context, hideDetails, _) => Card(
            color: surfaceColor,
            child: SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined, color: pinkColor),
              title: const Text('Hide message details'),
              subtitle: Text(
                hideDetails
                    ? 'নোটিফিকেশনে শুধু ব্যক্তিগত সতর্কবার্তা দেখাবে।'
                    : 'নোটিফিকেশনে মেসেজের বিবরণ দেখা যাবে।',
              ),
              value: hideDetails,
              activeColor: pinkColor,
              onChanged: (value) async {
                try {
                  await NotificationPrivacySettings.setHideDetails(value);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Privacy setting could not be saved.')),
                  );
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () async {
              final shouldLogout = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  backgroundColor: surfaceColor,
                  title: const Text('Log out?'),
                  content: const Text('You can sign in again with the same account.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                      child: const Text('Log out'),
                    ),
                  ],
                ),
              );
              if (shouldLogout != true || !context.mounted) return;
              try {
                await SpaceStore.stopRealtimeSync();
                await PushNotificationService.unregisterCurrentToken();
                await PrivateSpaceService.clearCachedSpaceData();
                await AuthService.signOut();
                if (!context.mounted) return;
                rootNavigatorKey.currentState?.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const SplashScreen()),
                  (route) => false,
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Log out failed: $error')),
                );
              }
            },
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            label: const Text('Log out', style: TextStyle(color: Colors.redAccent)),
          ),
        ),
        const SizedBox(height: 20),
        const Center(child: Text('Orbit Two Made by Tawsif', style: TextStyle(color: Colors.white60, fontSize: 11))),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 48),
          child: Divider(height: 1, thickness: 0.7, color: Colors.white24),
        ),
        const SizedBox(height: 8),
        const Center(child: Text('Made with love', style: TextStyle(color: Colors.white38, fontSize: 11))),
      ],
    );
  }
}


class PrivacyPage extends StatefulWidget {
  final String partnerOne;
  final String partnerTwo;
  final void Function(String first, String second) onSave;

  const PrivacyPage({
    super.key,
    required this.partnerOne,
    required this.partnerTwo,
    required this.onSave,
  });

  @override
  State<PrivacyPage> createState() => _PrivacyPageState();
}

class _PrivacyPageState extends State<PrivacyPage> {
  late final TextEditingController firstController;

  @override
  void initState() {
    super.initState();
    firstController = TextEditingController(text: widget.partnerOne);
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


  Future<void> _changeEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('আগে অ্যাকাউন্টে সাইন ইন করো।');
      return;
    }

    final controller = TextEditingController();
    final newEmail = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('ইমেইল পরিবর্তন'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'নতুন ইমেইল',
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('বাতিল'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('ভেরিফিকেশন পাঠাও'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (newEmail == null || newEmail.trim().isEmpty || !mounted) return;
    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      _showMessage('সঠিক ইমেইল ঠিকানা দাও।');
      return;
    }
    if (newEmail.trim().toLowerCase() == (user.email ?? '').toLowerCase()) {
      _showMessage('এটি তোমার বর্তমান ইমেইল।');
      return;
    }

    try {
      await user.verifyBeforeUpdateEmail(newEmail.trim());
      if (!mounted) return;
      _showMessage('নতুন ইমেইলে ভেরিফিকেশন লিংক পাঠানো হয়েছে। ইমেইল যাচাই করে আবার লগইন করো।');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message = error.code == 'requires-recent-login'
          ? 'নিরাপত্তার জন্য আবার লগইন করে ইমেইল পরিবর্তন করো।'
          : error.code == 'email-already-in-use'
              ? 'এই ইমেইলটি অন্য অ্যাকাউন্টে ব্যবহৃত হচ্ছে।'
              : error.code == 'invalid-email'
                  ? 'সঠিক ইমেইল ঠিকানা দাও।'
                  : 'ইমেইল পরিবর্তনের অনুরোধ পাঠানো যায়নি: ${error.message ?? error.code}';
      _showMessage(message);
    } catch (error) {
      if (!mounted) return;
      _showMessage('ইমেইল পরিবর্তনের অনুরোধ পাঠানো যায়নি। আবার চেষ্টা করো।');
    }
  }

  Future<void> _sendPasswordReset() async {
    final email = FirebaseAuth.instance.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) {
      _showMessage('অ্যাকাউন্টের ইমেইল পাওয়া যায়নি।');
      return;
    }

    try {
      await AuthService.resetPassword(email);
      if (!mounted) return;
      _showMessage('পাসওয়ার্ড রিসেট করার লিংক ইমেইলে পাঠানো হয়েছে। Inbox/Spam দেখো।');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      _showMessage(AuthService.friendlyError(error));
    } catch (error) {
      if (!mounted) return;
      _showMessage('রিসেট ইমেইল পাঠানো যায়নি। Firebase Authentication ও ইন্টারনেট পরীক্ষা করো।');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & account'),
        backgroundColor: backgroundColor,
      ),
      body: GlowBackground(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Account security',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'তোমার অ্যাকাউন্ট ও ব্যক্তিগত প্রোফাইল এখানে পরিচালনা করো।',
              style: TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 22),
            const SectionHeading(title: 'Email'),
            const SizedBox(height: 10),
            Card(
              color: surfaceColor,
              child: ListTile(
                leading: const Icon(Icons.email_outlined, color: pinkColor),
                title: Text(user?.email ?? 'ইমেইল পাওয়া যায়নি'),
                subtitle: const Text('বর্তমান অ্যাকাউন্ট ইমেইল'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _changeEmail,
              icon: const Icon(Icons.mark_email_read_outlined),
              label: const Text('ইমেইল পরিবর্তন করো'),
            ),
            const SizedBox(height: 20),
            const SectionHeading(title: 'Password'),
            const SizedBox(height: 10),
            Card(
              color: surfaceColor,
              child: ListTile(
                leading: const Icon(Icons.lock_reset_rounded, color: purpleColor),
                title: const Text('পাসওয়ার্ড রিসেট'),
                subtitle: const Text('ইমেইলে নিরাপদ রিসেট লিংক পাঠাবে'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _sendPasswordReset,
              ),
            ),
            const SizedBox(height: 22),
            const SectionHeading(title: 'Profile'),
            const SizedBox(height: 10),
            TextField(
              controller: firstController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'তোমার নাম',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save_outlined),
              label: const Text('নাম সংরক্ষণ করো'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickProfilePhoto,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('প্রোফাইল ছবি সেট করো'),
            ),
            const SizedBox(height: 20),
            const Card(
              color: surfaceColor,
              child: ListTile(
                leading: Icon(Icons.verified_user_outlined, color: blueColor),
                title: Text('তোমার অ্যাকাউন্ট সুরক্ষা'),
                subtitle: Text('ইমেইল পরিবর্তন নিশ্চিত করতে ইমেইল ভেরিফিকেশন লাগবে।'),
              ),
            ),
          ],
        ),
      ),
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
  final String authorUid;
  final List<String> readBy;

  const SpaceComplaint({
    required this.id,
    required this.author,
    required this.title,
    required this.details,
    required this.createdAt,
    this.authorUid = '',
    this.readBy = const [],
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'author': author,
        'title': title,
        'details': details,
        'createdAt': createdAt,
        'authorUid': authorUid,
        'readBy': readBy,
      };

  factory SpaceComplaint.fromMap(Map<String, dynamic> map) {
    return SpaceComplaint(
      id: map['id']?.toString() ?? '',
      author: map['author']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      details: map['details']?.toString() ?? '',
      createdAt: map['createdAt']?.toString() ?? '',
      authorUid: map['authorUid']?.toString() ?? '',
      readBy: (map['readBy'] is List)
          ? List<String>.from(map['readBy'])
          : const [],
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

  Future<void> _markComplaintRead(SpaceComplaint complaint) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty || complaint.readBy.contains(uid)) return;
    final index = complaints.indexWhere((item) => item.id == complaint.id);
    if (index < 0) return;
    final updated = SpaceComplaint(
      id: complaint.id,
      author: complaint.author,
      title: complaint.title,
      details: complaint.details,
      createdAt: complaint.createdAt,
      authorUid: complaint.authorUid,
      readBy: [...complaint.readBy, uid],
    );
    setState(() => complaints[index] = updated);
    await _saveComplaints();
  }

  Future<void> _deleteComplaint(SpaceComplaint complaint) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surfaceColor,
        title: const Text('Delete complaint?'),
        content: const Text('This complaint will be removed for both partners.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => complaints.removeWhere((item) => item.id == complaint.id));
    await _saveComplaints();
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
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'This complaint will be marked as yours automatically.',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
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
                        authorUid: existing?.authorUid ??
                            FirebaseAuth.instance.currentUser?.uid ?? '',
                        readBy: existing?.readBy ??
                            <String>[
                              if ((FirebaseAuth.instance.currentUser?.uid ?? '').isNotEmpty)
                                FirebaseAuth.instance.currentUser!.uid,
                            ],
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

                final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
                final isOwnComplaint = complaint.authorUid.isNotEmpty
                    ? complaint.authorUid == currentUid
                    : complaint.author == 'You';
                final isUnread = currentUid.isNotEmpty &&
                    !isOwnComplaint &&
                    !complaint.readBy.contains(currentUid);
                final displayAuthor = isOwnComplaint ? 'You' : 'Partner';

                return Card(
                  color: surfaceColor,
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ListTile(
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0x33FF5FA2),
                          child: Icon(
                            isOwnComplaint
                                ? Icons.person
                                : Icons.favorite_outline,
                            color: pinkColor,
                          ),
                        ),
                        if (isUnread)
                          const Positioned(
                            right: -2,
                            top: -2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              child: SizedBox(width: 10, height: 10),
                            ),
                          ),
                      ],
                    ),
                    title: Text(
                      complaint.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '$displayAuthor • ${complaint.details}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        if (value == 'edit') {
                          _editComplaint(existing: complaint);
                        } else if (value == 'delete') {
                          _deleteComplaint(complaint);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await _markComplaintRead(complaint);
                      showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: surfaceColor,
                          title: Text(complaint.title),
                          content: SingleChildScrollView(
                            child: Text(
                              'By: $displayAuthor\n\n'
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
      if (!mounted) return;
      if (widget.isTyping) {
        // Messenger-like short typing ticks while the partner is actively typing.
        unawaited(InteractionFeedbackSettings.playTypingSound());
      } else if (!widget.isOnline) {
        setState(() {});
      }
    });
  }

  @override
  void didUpdateWidget(covariant PresenceStatusLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isTyping && widget.isTyping) {
      unawaited(InteractionFeedbackSettings.playTypingSound());
    }
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