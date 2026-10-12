import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:video_player/video_player.dart';
import 'screens/partner_connection_page.dart';
import 'services/space_sync_service.dart';
import 'services/chat_sync_service.dart';
import 'screens/auth_screen.dart';
import 'services/auth_service.dart';

const Color backgroundColor = Color(0xFF070513);
const Color surfaceColor = Color(0xFF111026);
const Color blueColor = Color(0xFF172554);
const Color pinkColor = Color(0xFFFF2E93);
const Color purpleColor = Color(0xFF8B5CF6);

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  tz_data.initializeTimeZones();

  const androidSettings =
      AndroidInitializationSettings('@android:drawable/sym_def_app_icon');

  const initializationSettings = InitializationSettings(
    android: androidSettings,
  );

  await notifications.initialize(initializationSettings);
  await SpaceStore.init();

  // লগইন যাচাই করার আগে Firebase Sync চালু হবে না।
  runApp(const EternalSpaceApp());
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
      title: 'Eternal Space',
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
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('eternal_space_id');
  }

  // Space যুক্ত এবং connected না থাকলে কোনো Firebase sync নয়।
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

      // দুজন সদস্য যুক্ত না হলে সংযোগ সম্পূর্ণ নয়।
      if (members is! List ||
          members.length != 2 ||
          !members.contains(user.uid)) {
        return null;
      }

      // বিচ্ছিন্ন অবস্থায় কোনো শেয়ার করা ডেটা সিঙ্ক হবে না।
      final status = data['connectionStatus'] ?? 'connected';
      if (status != 'connected') return null;

      return spaceId;
    } catch (e) {
      debugPrint('Connection check error: $e');
      return null;
    }
  }

  static Future<void> _syncKey(String key, dynamic value) async {
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
    if (spaceId == null) {
      debugPrint('Sync বন্ধ: Space connected নয়।');
      return;
    }

    await init();

    final data = <String, dynamic>{
      'partnerOne': readString('partnerOne', 'Tawsif'),
      'partnerTwo': readString('partnerTwo', 'Nabila'),
      'chatMessages': readList('chatMessages'),
      'loveNotes': readList('loveNotes'),
      'specialDates': readList('specialDates'),
      'spaceComplaints': readList('spaceComplaints'),
    };

    for (final entry in data.entries) {
      // আপলোডের সময়ও connected অবস্থা পুনরায় যাচাই হবে।
      if (await _getConnectedSpaceId() != spaceId) return;
      await _syncKey(entry.key, entry.value);
    }
  }

  static Future<void> syncFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final spaceId = await _getConnectedSpaceId();
      if (spaceId == null) {
        debugPrint('Download বন্ধ: Space connected নয়।');
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('privateSpaces')
          .doc(spaceId)
          .collection('syncData')
          .doc('appState')
          .get();

      // ডাউনলোড চলাকালে সংযোগ বিচ্ছিন্ন হলে স্থানীয় ডেটা বদলাবে না।
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

        // স্থানীয় গ্যালারির ফাইল-পাথ অন্য ফোন থেকে ব্যবহারযোগ্য নয়।
        if (entry.key == 'galleryMedia' ||
            entry.key == 'galleryFolders') {
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

        // নিজের পরিবর্তন আবার ডাউনলোড করার দরকার নেই।
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

    final isTrial = await AuthService.isTrialMode();
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (isTrial || user != null) {
      if (!isTrial) {
        await SpaceStore.syncFromFirebase();
        await SpaceStore.startRealtimeSync();
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AuthScreen(
            onSuccess: () async {
              await SpaceStore.syncFromFirebase();
              await SpaceStore.startRealtimeSync();

              if (!mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MainScreen()),
              );
            },
            onTrial: () async {
              await AuthService.startTrial();

              if (!mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MainScreen()),
              );
            },
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
                'Eternal Space',
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

class GlowBackground extends StatelessWidget {
  final Widget child;

  const GlowBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF070513),
            Color(0xFF111026),
            Color(0xFF172554),
            Color(0xFF070513),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -130,
            left: -100,
            child: _glow(300, blueColor.withValues(alpha: 0.14)),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: _glow(320, pinkColor.withValues(alpha: 0.12)),
          ),
          Positioned(
            top: 250,
            right: -160,
            child: _glow(280, purpleColor.withValues(alpha: 0.10)),
          ),
          SafeArea(child: child),
        ],
      ),
    );
  }

  Widget _glow(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
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

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;
  String partnerOne = 'Tawsif';
  String partnerTwo = 'Nabila';

  @override
  void initState() {
    super.initState();
    partnerOne = SpaceStore.readString('partnerOne', 'Tawsif');
    partnerTwo = SpaceStore.readString('partnerTwo', 'Nabila');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        partnerOne: partnerOne,
        partnerTwo: partnerTwo,
        onNavigate: (index) => setState(() => selectedIndex = index),
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
      body: GlowBackground(child: pages[selectedIndex]),
      bottomNavigationBar: NavigationBar(
        backgroundColor: surfaceColor,
        indicatorColor: blueColor.withValues(alpha: 0.25),
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          setState(() => selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library_rounded),
            label: 'Gallery',
          ),
          NavigationDestination(
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
// HOME
// ============================================================

class HomePage extends StatelessWidget {
  final String partnerOne;
  final String partnerTwo;
  final ValueChanged<int> onNavigate;

  const HomePage({
    super.key,
    required this.partnerOne,
    required this.partnerTwo,
    required this.onNavigate,
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
                    'Eternal Space',
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
        _CoupleCard(first: partnerOne, second: partnerTwo),
        const SizedBox(height: 18),
        const LoveCounterCard(),
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
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PartnerConnectionPage(),
                ),
              );

              // সংযোগের অবস্থা যাচাই করে আগে পুরোনো শেয়ার করা ডেটা নামাও।
              await SpaceStore.syncFromFirebase();

              // তারপর দুই ফোনের রিয়েল-টাইম সিঙ্ক চালু করো।
              await SpaceStore.startRealtimeSync();

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Partner Connection-এর সিঙ্ক যাচাই করা হয়েছে।'),
                  ),
                );
              }
            },
          ),
        ),
        const SizedBox(height: 18),
        // Complaints Box Card
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

class _CoupleCard extends StatelessWidget {
  final String first;
  final String second;

  const _CoupleCard({
    required this.first,
    required this.second,
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
          _AvatarLetter(name: first, color: blueColor),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 13),
            child: Icon(
              Icons.favorite_rounded,
              color: pinkColor,
              size: 27,
            ),
          ),
          _AvatarLetter(name: second, color: pinkColor),
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
                  style: TextStyle(fontSize: 11, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarLetter extends StatelessWidget {
  final String name;
  final Color color;

  const _AvatarLetter({
    required this.name,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 25,
      backgroundColor: color.withValues(alpha: 0.23),
      child: Text(
        name.isEmpty ? '?' : name[0].toUpperCase(),
        style: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}

// ============================================================
// LOVE COUNTER
// ============================================================

class LoveCounterCard extends StatefulWidget {
  const LoveCounterCard({super.key});

  @override
  State<LoveCounterCard> createState() => _LoveCounterCardState();
}

class _LoveCounterCardState extends State<LoveCounterCard> {
  Timer? timer;
  DateTime now = DateTime.now();

  final DateTime startDate = DateTime(2025, 8, 7);

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

  @override
  Widget build(BuildContext context) {
    final difference = now.difference(startDate);
    final totalSeconds = max(0, difference.inSeconds);
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
          Row(
            children: [
              _TimePart(value: '$days', label: 'DAYS'),
              _TimePart(value: _two(hours), label: 'HOURS'),
              _TimePart(value: _two(minutes), label: 'MINUTES'),
              _TimePart(value: _two(seconds), label: 'SECONDS'),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Since August 7, 2025',
            style: TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _two(int value) => value.toString().padLeft(2, '0');
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

  String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _startChatSync();
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

    // পুরোনো মেসেজের জন্য সাময়িক সামঞ্জস্য।
    return message['mine'] == true;
  }


  Future<void> _sendText() async {
    final text = controller.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('আগে Partner Space-এ যুক্ত হয়ে নাও।'),
        ),
      );
      return;
    }

    final message = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'senderUid': user.uid,
      'text': text,
      'type': 'text',
      'mine': true,
      'unsent': false,
      'time': DateTime.now().toIso8601String(),
    };

    controller.clear();

    try {
      await ChatSyncService.sendMessage(message);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('মেসেজ পাঠানো যায়নি: $error')),
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

    final picker = ImagePicker();

    final file = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);

    if (file == null || !mounted) return;

    final message = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'senderUid': user.uid,
      'text': file.path,
      'type': video ? 'video' : 'image',
      'mine': true,
      'unsent': false,
      'time': DateTime.now().toIso8601String(),
    };

    try {
      await ChatSyncService.sendMessage(message);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('মিডিয়া পাঠানো যায়নি: $error')),
      );
    }
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
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';

    return '$hour:$minute $period';
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
                      await ChatSyncService.unsendMessage(messageId);
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

  Widget _messageContent(Map<String, dynamic> message) {
    if (message['unsent'] == true) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block_rounded,
            size: 15,
            color: Colors.white54,
          ),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              'এই মেসেজটি সরানো হয়েছে',
              style: TextStyle(
                color: Colors.white60,
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ),
        ],
      );
    }

    final type = '${message['type'] ?? 'text'}';
    final path = '${message['text'] ?? ''}';

    if (type == 'image') {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ImageViewerPage(path: path),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.file(
            File(path),
            width: 210,
            height: 210,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) {
              return const SizedBox(
                width: 210,
                height: 100,
                child: Center(
                  child: Text(
                    'ছবিটি এই ফোনে পাওয়া যায়নি',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    if (type == 'video') {
      return GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VideoViewerPage(path: path),
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

  Widget _buildMessage(Map<String, dynamic> message, int index) {
    final mine = _isMine(message);

    return GestureDetector(
      onLongPress: () => _showMessageOptions(index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment:
              mine ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!mine) ...[
              const CircleAvatar(
                radius: 16,
                backgroundColor: purpleColor,
                child: Icon(
                  Icons.person_rounded,
                  size: 19,
                  color: Colors.white,
                ),
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
                    child: _messageContent(message),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message['time']),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
            if (mine) const SizedBox(width: 3),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [pinkColor, purpleColor],
                  ),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Colors.white,
                  size: 25,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Private Chat',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'তোমাদের দুজনের ব্যক্তিগত জায়গা',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white54,
                      ),
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
        ),
        const Divider(height: 1, color: Colors.white10),
        Expanded(
          child: messages.isEmpty
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
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _buildMessage(messages[index], index);
                  },
                ),
        ),
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
            child: Row(
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

  Future<void> _save() async {
    await SpaceStore.saveList('galleryFolders', folders);
    await SpaceStore.saveList('galleryMedia', media);
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

    final item = <String, dynamic>{
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'path': picked.path,
      'type': video ? 'video' : 'image',
      'folderId': folderId,
      'createdAt': DateTime.now().toIso8601String(),
    };

    setState(() {
      media.add(item);
    });

    await _save();
    return item;
  }

  Future<void> _showMediaMenu(Map<String, dynamic> item) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: surfaceColor,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
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
                  setState(() {
                    media.removeWhere((m) => m['id'] == item['id']);
                  });

                  await _save();
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
          initialItems: _itemsForFolder(id),
          onAdd: (video) => _addMedia(id, video),
          onDelete: (item) async {
            setState(() {
              media.removeWhere((m) => m['id'] == item['id']);
            });

            await _save();
          },
          onDetails: _showMediaDetails,
          onLongPress: _showMediaMenu,
        ),
      ),
    );

    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> _itemsForFolder(String id) {
    if (id == 'all') return List<Map<String, dynamic>>.from(media);

    if (id == 'favorites') {
      return media.where((item) => item['favorite'] == true).toList();
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
  final List<Map<String, dynamic>> initialItems;
  final Future<Map<String, dynamic>?> Function(bool video) onAdd;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final void Function(Map<String, dynamic>) onDetails;
  final Future<void> Function(Map<String, dynamic>) onLongPress;

  const GalleryFolderPage({
    super.key,
    required this.title,
    required this.initialItems,
    required this.onAdd,
    required this.onDelete,
    required this.onDetails,
    required this.onLongPress,
  });

  @override
  State<GalleryFolderPage> createState() => _GalleryFolderPageState();
}

class _GalleryFolderPageState extends State<GalleryFolderPage> {
  late List<Map<String, dynamic>> items;

  @override
  void initState() {
    super.initState();
    items = List<Map<String, dynamic>>.from(widget.initialItems);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        title: Text(widget.title),
        actions: [
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
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
              ),
              itemBuilder: (context, index) {
                final item = items[index];
                final path = '${item['path']}';
                final video = item['type'] == 'video';

                return GestureDetector(
                  onLongPress: () => widget.onLongPress(item),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => video
                            ? VideoViewerPage(path: path)
                            : ImageViewerPage(path: path),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (video)
                          Container(
                            color: surfaceColor,
                            child: const Icon(
                              Icons.play_circle_fill_rounded,
                              size: 50,
                            ),
                          )
                        else
                          Image.file(
                            File(path),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) {
                              return const ColoredBox(
                                color: surfaceColor,
                                child: Icon(Icons.broken_image_outlined),
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
                      ],
                    ),
                  ),
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
      setState(() => items.add(item));
    }
  }
}

// ============================================================
// IMAGE VIEWER
// ============================================================

class ImageViewerPage extends StatelessWidget {
  final String path;

  const ImageViewerPage({super.key, required this.path});

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
              return const Text('Image is no longer available');
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================
// VIDEO VIEWER
// ============================================================

class VideoViewerPage extends StatefulWidget {
  final String path;

  const VideoViewerPage({super.key, required this.path});

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  VideoPlayerController? controller;
  String? error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    VideoPlayerController? video;

    try {
      video = VideoPlayerController.file(File(widget.path));
      await video.initialize();

      if (!mounted) {
        await video.dispose();
        return;
      }

      setState(() => controller = video);
      await video.play();
    } catch (_) {
      await video?.dispose();

      if (mounted) {
        setState(() => error = 'Unable to open this video.');
      }
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: Center(
        child: error != null
            ? Text(error!)
            : controller == null
                ? const CircularProgressIndicator()
                : AspectRatio(
                    aspectRatio: controller!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(controller!),
                        VideoProgressIndicator(
                          controller!,
                          allowScrubbing: true,
                          padding: const EdgeInsets.all(12),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: IconButton.filled(
                            onPressed: () {
                              final video = controller!;

                              setState(() {
                                if (video.value.isPlaying) {
                                  video.pause();
                                } else {
                                  video.play();
                                }
                              });
                            },
                            icon: Icon(
                              controller!.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
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
  late TextEditingController secondController;

  @override
  void initState() {
    super.initState();

    firstController = TextEditingController(text: widget.partnerOne);
    secondController = TextEditingController(text: widget.partnerTwo);
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.partnerOne != widget.partnerOne) {
      firstController.text = widget.partnerOne;
    }

    if (oldWidget.partnerTwo != widget.partnerTwo) {
      secondController.text = widget.partnerTwo;
    }
  }

  @override
  void dispose() {
    firstController.dispose();
    secondController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final first = firstController.text.trim();
    final second = secondController.text.trim();

    if (first.isEmpty || second.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both names.')),
      );
      return;
    }

    await SpaceStore.saveString('partnerOne', first);
    await SpaceStore.saveString('partnerTwo', second);

    widget.onSave(first, second);

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile names saved')),
    );
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
        const SizedBox(height: 12),
        TextField(
          controller: secondController,
          decoration: const InputDecoration(
            labelText: 'Partner name',
            prefixIcon: Icon(Icons.favorite_outline),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _saveProfile,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Save profile'),
        ),
        const SizedBox(height: 28),
        const SectionHeading(title: 'Cloud Sync'),
        const SizedBox(height: 10),
        Card(
          color: surfaceColor,
          child: ListTile(
            leading: const Icon(
              Icons.cloud_upload_rounded,
              color: pinkColor,
            ),
            title: const Text('Upload local data'),
            subtitle: const Text('Send this phone’s data to Firebase'),
            onTap: () async {
              try {
                await SpaceStore.syncAllToFirebase();

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Local data uploaded to Firebase'),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Upload failed: $e')),
                );
              }
            },
          ),
        ),
        Card(
          color: surfaceColor,
          child: ListTile(
            leading: const Icon(
              Icons.cloud_sync_rounded,
              color: purpleColor,
            ),
            title: const Text('Sync from Firebase'),
            subtitle: const Text('Download shared app data'),
            onTap: () async {
              try {
                await SpaceStore.syncFromFirebase();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Firebase sync completed'),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Sync failed: $e')),
                );
              }
            },
          ),
        ),
        Card(
          color: surfaceColor,
          child: ListTile(
            leading: const Icon(
              Icons.backup_rounded,
              color: pinkColor,
            ),
            title: const Text('Backup to Google Drive'),
            subtitle: const Text('Save app data to your Drive'),
            onTap: () async {
              try {
                await SpaceSyncService.backupToGoogleDrive({
                  'partnerOne': SpaceStore.readString('partnerOne'),
                  'partnerTwo': SpaceStore.readString('partnerTwo'),
                  'chatMessages': SpaceStore.readList('chatMessages'),
                  'loveNotes': SpaceStore.readList('loveNotes'),
                  'specialDates': SpaceStore.readList('specialDates'),
                  'spaceComplaints': SpaceStore.readList('spaceComplaints'),
                });

                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Google Drive backup completed'),
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Drive backup failed: $e')),
                );
              }
            },
          ),
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
            'Eternal Space • Made with love',
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
  }

  void _loadComplaints() {
    final data = SpaceStore.readList('spaceComplaints');
    complaints = data.map(SpaceComplaint.fromMap).toList();
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
