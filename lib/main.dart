import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EternalSpaceApp());
}

// ============================================================
// COLORS
// ============================================================

const Color pink = Color(0xFFFF2E93);
const Color violet = Color(0xFF8B5CF6);
const Color deepBlue = Color(0xFF172554);
const Color darkBg = Color(0xFF070513);

// ============================================================
// APP
// ============================================================

class EternalSpaceApp extends StatelessWidget {
  const EternalSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eternal Space',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: darkBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: pink,
          brightness: Brightness.dark,
        ).copyWith(
          primary: pink,
          secondary: violet,
          surface: const Color(0xFF100A20),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============================================================
// SPLASH
// ============================================================

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );

    _controller.forward();

    Future.delayed(const Duration(milliseconds: 2400), () {
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MainScreen(),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const AnimatedBackground(),
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppLogo(size: 105),
                    const SizedBox(height: 28),
                    const Text(
                      'Eternal Space',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Our private little universe',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.60),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: pink.withOpacity(0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// MAIN SCREEN
// ============================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  String myName = 'Me';
  String partnerName = 'My Love';

  final List<String> folders = [
    'Our Memories',
    'Special Days',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      myName = prefs.getString('my_name') ?? 'Me';
      partnerName = prefs.getString('partner_name') ?? 'My Love';
    });
  }

  Future<void> _saveProfile(
    String newMyName,
    String newPartnerName,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('my_name', newMyName);
    await prefs.setString('partner_name', newPartnerName);

    if (!mounted) return;

    setState(() {
      myName = newMyName;
      partnerName = newPartnerName;
    });
  }

  void _openTab(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        onOpenChat: () => _openTab(1),
        onOpenGallery: () => _openTab(2),
        partnerName: partnerName,
      ),
      ChatPage(
        myName: myName,
        partnerName: partnerName,
        onProfileChanged: _saveProfile,
      ),
      GalleryPage(
        folders: folders,
        onFolderCreated: (name) {
          setState(() {
            folders.add(name);
          });
        },
      ),
      SettingsPage(
        myName: myName,
        partnerName: partnerName,
        onProfileChanged: _saveProfile,
      ),
    ];

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const AnimatedBackground(),
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _selectedIndex,
              children: pages,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: const Color(0xE6120A23),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: pink.withOpacity(0.10),
                blurRadius: 25,
              ),
            ],
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: _selectedIndex,
            onDestinationSelected: _openTab,
            indicatorColor: pink.withOpacity(0.18),
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
                label: 'Memories',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HOME
// ============================================================

class HomePage extends StatefulWidget {
  final VoidCallback onOpenChat;
  final VoidCallback onOpenGallery;
  final String partnerName;

  const HomePage({
    super.key,
    required this.onOpenChat,
    required this.onOpenGallery,
    required this.partnerName,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;

  final DateTime _startDate = DateTime(2025, 8, 7);
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();

    _updateCounter();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateCounter(),
    );
  }

  void _updateCounter() {
    if (!mounted) return;

    var difference = DateTime.now().difference(_startDate);

    if (difference.isNegative) {
      difference = Duration.zero;
    }

    setState(() {
      _duration = difference;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = _duration.inDays;
    final hours = _duration.inHours % 24;
    final minutes = _duration.inMinutes % 60;
    final seconds = _duration.inSeconds % 60;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 24),
          _loveCounter(
            days,
            hours,
            minutes,
            seconds,
          ),
          const SizedBox(height: 22),
          _privateCard(),
          const SizedBox(height: 22),
          const Text(
            'Our Space',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _featureCard(
                  icon: Icons.chat_bubble_rounded,
                  title: 'Private Chat',
                  subtitle: 'Just between us',
                  color: pink,
                  onTap: widget.onOpenChat,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _featureCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Memories',
                  subtitle: 'Our shared gallery',
                  color: violet,
                  onTap: widget.onOpenGallery,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _featureCard(
            icon: Icons.favorite_rounded,
            title: 'Our Journey',
            subtitle: 'Together since 7 August 2025',
            color: const Color(0xFFFF4F81),
            onTap: () {
              _showInfo(
                context,
                'Our Journey',
                'Together since 7 August 2025 ❤️',
              );
            },
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        const AppLogo(size: 52),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Eternal Space',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF6BAE),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'A private world for ${widget.partnerName} & you',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: () {
              _showInfo(
                context,
                'Eternal Space',
                'Your private little universe.',
              );
            },
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _loveCounter(
    int days,
    int hours,
    int minutes,
    int seconds,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF281044).withOpacity(0.95),
            const Color(0xFF111A3D).withOpacity(0.95),
          ],
        ),
        border: Border.all(
          color: pink.withOpacity(0.22),
        ),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.favorite_rounded,
                color: pink,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'OUR JOURNEY',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.favorite_rounded,
                color: pink,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Together since 7 August 2025',
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _counter(
                  days.toString(),
                  'DAYS',
                ),
              ),
              _divider(),
              Expanded(
                child: _counter(
                  hours.toString().padLeft(2, '0'),
                  'HOURS',
                ),
              ),
              _divider(),
              Expanded(
                child: _counter(
                  minutes.toString().padLeft(2, '0'),
                  'MIN',
                ),
              ),
              _divider(),
              Expanded(
                child: _counter(
                  seconds.toString().padLeft(2, '0'),
                  'SEC',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _counter(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 27,
            fontWeight: FontWeight.w800,
            color: pink,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            letterSpacing: 1.2,
            color: Colors.white.withOpacity(0.48),
          ),
        ),
      ],
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 35,
      color: Colors.white.withOpacity(0.10),
    );
  }

  Widget _privateCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        color: Colors.white.withOpacity(0.045),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [pink, violet],
              ),
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Private Space',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'A little world made only for the two of you.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    bool fullWidth = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          color: Colors.white.withOpacity(0.045),
          border: Border.all(
            color: Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: color.withOpacity(0.13),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                icon,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 13,
              color: Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// CHAT
// ============================================================

class ChatPage extends StatefulWidget {
  final String myName;
  final String partnerName;

  final Future<void> Function(
    String myName,
    String partnerName,
  ) onProfileChanged;

  const ChatPage({
    super.key,
    required this.myName,
    required this.partnerName,
    required this.onProfileChanged,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController =
      TextEditingController();

  final List<ChatMessage> _messages = [
    ChatMessage(
      text: 'Welcome to our private chat ❤️',
      isMe: false,
    ),
    ChatMessage(
      text: 'এই জায়গাটা শুধু আমাদের জন্য।',
      isMe: true,
    ),
  ];

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();

    if (text.isEmpty) return;

    setState(() {
      _messages.add(
        ChatMessage(
          text: text,
          isMe: true,
        ),
      );
    });

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              15,
            ),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _bubble(_messages[index]);
            },
          ),
        ),
        _input(),
      ],
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: Color(0x332E1A4F),
            child: Icon(
              Icons.favorite_rounded,
              color: pink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.partnerName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                const Text(
                  'Private Chat • Only us',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openProfile,
            icon: const Icon(
              Icons.edit_rounded,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(ChatMessage message) {
    final sender =
        message.isMe ? widget.myName : widget.partnerName;

    return Align(
      alignment:
          message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 310,
        ),
        margin: const EdgeInsets.only(bottom: 11),
        child: Column(
          crossAxisAlignment: message.isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 5,
              ),
              child: Text(
                sender,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 15,
                vertical: 11,
              ),
              decoration: BoxDecoration(
                gradient: message.isMe
                    ? const LinearGradient(
                        colors: [
                          pink,
                          Color(0xFFB026FF),
                        ],
                      )
                    : null,
                color: message.isMe
                    ? null
                    : Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(
                    message.isMe ? 18 : 4,
                  ),
                  bottomRight: Radius.circular(
                    message.isMe ? 4 : 18,
                  ),
                ),
              ),
              child: Text(
                message.text,
                style: const TextStyle(
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        16,
        8,
        16,
        100,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              _showInfo(
                context,
                'Media',
                'Photo/video sharing will be connected with Firebase later.',
              );
            },
            icon: const Icon(
              Icons.add_circle_outline_rounded,
              color: violet,
            ),
          ),
          Expanded(
            child: TextField(
              controller: _messageController,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Write a message...',
                hintStyle: const TextStyle(
                  color: Colors.white30,
                  fontSize: 13,
                ),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  pink,
                  violet,
                ],
              ),
            ),
            child: IconButton(
              onPressed: _sendMessage,
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openProfile() async {
    final myController = TextEditingController(
      text: widget.myName,
    );

    final partnerController = TextEditingController(
      text: widget.partnerName,
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF120A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Our Profile',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set the names shown in your private space.',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: myController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: const Icon(
                      Icons.person_rounded,
                      color: pink,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: partnerController,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Partner name',
                    prefixIcon: const Icon(
                      Icons.favorite_rounded,
                      color: violet,
                    ),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () async {
                      final myName =
                          myController.text.trim();
                      final partnerName =
                          partnerController.text.trim();

                      if (myName.isEmpty ||
                          partnerName.isEmpty) {
                        ScaffoldMessenger.of(sheetContext)
                            .showSnackBar(
                          const SnackBar(
                            content: Text(
                              'দুটো নামই দিতে হবে।',
                            ),
                          ),
                        );
                        return;
                      }

                      await widget.onProfileChanged(
                        myName,
                        partnerName,
                      );

                      if (sheetContext.mounted) {
                        Navigator.pop(
                          sheetContext,
                          true,
                        );
                      }
                    },
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    myController.dispose();
    partnerController.dispose();

    if (result == true && mounted) {
      setState(() {});
    }
  }
}

// ============================================================
// GALLERY
// ============================================================

class GalleryPage extends StatefulWidget {
  final List<String> folders;
  final ValueChanged<String> onFolderCreated;

  const GalleryPage({
    super.key,
    required this.folders,
    required this.onFolderCreated,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  void _createFolder() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF17102A),
          title: const Text('Create Folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Folder name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();

                if (name.isNotEmpty) {
                  widget.onFolderCreated(name);
                }

                Navigator.pop(dialogContext);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    ).then((_) {
      controller.dispose();
    });
  }

  void _openFolder(String name) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderPage(
          folderName: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Our Memories',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Photos, videos & little moments',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: pink.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _createFolder,
                  icon: const Icon(
                    Icons.create_new_folder_rounded,
                    color: pink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () {
              _showInfo(
                context,
                'Add Photos & Videos',
                'Gallery picker and Firebase Storage will be connected in the next step.',
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                vertical: 27,
                horizontal: 20,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(25),
                gradient: LinearGradient(
                  colors: [
                    pink.withOpacity(0.13),
                    violet.withOpacity(0.13),
                  ],
                ),
                border: Border.all(
                  color: pink.withOpacity(0.20),
                ),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.cloud_upload_rounded,
                    color: pink,
                    size: 42,
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Add Photos & Videos',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Shared memories for both of you',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 25),
          const Text(
            'Folders',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 13),
          ...widget.folders.map(
            (folder) => _folderTile(folder),
          ),
        ],
      ),
    );
  }

  Widget _folderTile(String name) {
    return GestureDetector(
      onTap: () => _openFolder(name),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white.withOpacity(0.045),
          border: Border.all(
            color: Colors.white.withOpacity(0.07),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 47,
              height: 47,
              decoration: BoxDecoration(
                color: violet.withOpacity(0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: violet,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white38,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// FOLDER PAGE
// ============================================================

class FolderPage extends StatelessWidget {
  final String folderName;

  const FolderPage({
    super.key,
    required this.folderName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(folderName),
      ),
      body: Stack(
        children: [
          const AnimatedBackground(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.photo_library_outlined,
                    size: 65,
                    color: violet,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    folderName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'No memories added yet.',
                    style: TextStyle(
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 25),
                  ElevatedButton.icon(
                    onPressed: () {
                      _showInfo(
                        context,
                        'Coming Next',
                        'Photo and video upload will be connected with Firebase Storage.',
                      );
                    },
                    icon: const Icon(
                      Icons.add_photo_alternate_rounded,
                    ),
                    label: const Text(
                      'Add Memory',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS
// ============================================================

class SettingsPage extends StatelessWidget {
  final String myName;
  final String partnerName;

  final Future<void> Function(
    String myName,
    String partnerName,
  ) onProfileChanged;

  const SettingsPage({
    super.key,
    required this.myName,
    required this.partnerName,
    required this.onProfileChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        120,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Make your private space yours.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 25),
          _profilePreview(context),
          const SizedBox(height: 18),
          _section(
            title: 'Our Space',
            children: [
              _tile(
                icon: Icons.favorite_border_rounded,
                title: 'Couple Space',
                subtitle: 'Connect your private space later',
                color: pink,
                onTap: () {
                  _showInfo(
                    context,
                    'Couple Space',
                    'Couple Code and Firebase connection will be added later.',
                  );
                },
              ),
              _tile(
                icon: Icons.person_outline_rounded,
                title: 'Profile',
                subtitle: 'Name and profile information',
                color: violet,
                onTap: () {
                  _openProfileEditor(context);
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            title: 'Security',
            children: [
              _tile(
                icon: Icons.pin_outlined,
                title: 'PIN Lock',
                subtitle: 'Will be added with Login system',
                color: const Color(0xFF60A5FA),
                onTap: () {
                  _showInfo(
                    context,
                    'PIN Lock',
                    'PIN Lock will be added after the account system.',
                  );
                },
              ),
              _tile(
                icon: Icons.lock_outline_rounded,
                title: 'Account & Login',
                subtitle: 'Coming at the final development stage',
                color: const Color(0xFFA78BFA),
                onTap: () {
                  _showInfo(
                    context,
                    'Account & Login',
                    'Firebase Authentication will be connected at the final stage.',
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 18),
          _section(
            title: 'About',
            children: [
              _tile(
                icon: Icons.info_outline_rounded,
                title: 'Eternal Space',
                subtitle: 'Version 1.0.0 • Trial Mode',
                color: pink,
                onTap: () {
                  _showInfo(
                    context,
                    'Eternal Space',
                    'Your private little universe ❤️',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profilePreview(BuildContext context) {
    return GestureDetector(
      onTap: () => _openProfileEditor(context),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(23),
          gradient: LinearGradient(
            colors: [
              pink.withOpacity(0.12),
              violet.withOpacity(0.12),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 28,
              backgroundColor: Color(0x332E1A4F),
              child: Icon(
                Icons.person_rounded,
                color: pink,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    myName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'With $partnerName ❤️',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.edit_rounded,
              color: Colors.white54,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openProfileEditor(BuildContext context) async {
    final myController = TextEditingController(
      text: myName,
    );

    final partnerController = TextEditingController(
      text: partnerName,
    );

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF120A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 22,
            right: 22,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom +
                24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: myController,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  prefixIcon: Icon(
                    Icons.person_rounded,
                    color: pink,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: partnerController,
                decoration: const InputDecoration(
                  labelText: 'Partner name',
                  prefixIcon: Icon(
                    Icons.favorite_rounded,
                    color: violet,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: () async {
                    final newMyName =
                        myController.text.trim();
                    final newPartnerName =
                        partnerController.text.trim();

                    if (newMyName.isEmpty ||
                        newPartnerName.isEmpty) {
                      return;
                    }

                    await onProfileChanged(
                      newMyName,
                      newPartnerName,
                    );

                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                  child: const Text(
                    'Save Changes',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    myController.dispose();
    partnerController.dispose();
  }

  Widget _section({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(23),
            color: Colors.white.withOpacity(0.04),
            border: Border.all(
              color: Colors.white.withOpacity(0.07),
            ),
          ),
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 5,
      ),
      leading: Container(
        width: 43,
        height: 43,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(
          icon,
          color: color,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.white38,
          fontSize: 10,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: Colors.white30,
      ),
    );
  }
}

// ============================================================
// ANIMATED BACKGROUND
// ============================================================

class AnimatedBackground extends StatefulWidget {
  const AnimatedBackground({super.key});

  @override
  State<AnimatedBackground> createState() =>
      _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;

        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(
              color: darkBg,
            ),
            Positioned(
              left: -150 + value * 120,
              top: -120,
              child: _glow(
                360,
                deepBlue,
              ),
            ),
            Positioned(
              right: -150 + value * 140,
              top: 130,
              child: _glow(
                350,
                violet,
              ),
            ),
            Positioned(
              left: -120,
              bottom: -150 + value * 100,
              child: _glow(
                330,
                pink,
              ),
            ),
            Positioned(
              right: -100,
              bottom: -120,
              child: _glow(
                280,
                const Color(0xFF2563EB),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _glow(
    double size,
    Color color,
  ) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.38),
            color.withOpacity(0.18),
            color.withOpacity(0),
          ],
          stops: const [
            0,
            0.45,
            1,
          ],
        ),
      ),
    );
  }
}

// ============================================================
// APP LOGO
// ============================================================

class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({
    super.key,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            pink,
            Color(0xFFB026FF),
            Color(0xFF5B21B6),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: pink.withOpacity(0.35),
            blurRadius: size * 0.28,
          ),
          BoxShadow(
            color: violet.withOpacity(0.25),
            blurRadius: size * 0.40,
          ),
        ],
      ),
      child: Icon(
        Icons.favorite_rounded,
        color: Colors.white,
        size: size * 0.47,
      ),
    );
  }
}

// ============================================================
// MODEL
// ============================================================

class ChatMessage {
  final String text;
  final bool isMe;

  ChatMessage({
    required this.text,
    required this.isMe,
  });
}

// ============================================================
// HELPER
// ============================================================

void _showInfo(
  BuildContext context,
  String title,
  String message,
) {
  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        backgroundColor: const Color(0xFF17102A),
        title: Text(title),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
