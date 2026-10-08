import 'dart:async';

import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EternalSpaceApp());
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

// =========================
// COLORS
// =========================

const Color pink = Color(0xFFFF2E93);
const Color violet = Color(0xFF8B5CF6);
const Color deepBlue = Color(0xFF172554);
const Color darkBg = Color(0xFF070513);

// =========================
// SPLASH SCREEN
// =========================

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
                        letterSpacing: 0.5,
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

// =========================
// MAIN SCREEN
// =========================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    ChatPage(),
    GalleryPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          const AnimatedBackground(),
          SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
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
                spreadRadius: 1,
              ),
            ],
          ),
          child: NavigationBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
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

// =========================
// HOME PAGE
// =========================

class HomePage extends StatefulWidget {
  const HomePage({super.key});

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

    final now = DateTime.now();
    var difference = now.difference(_startDate);

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
          _buildHeader(),

          const SizedBox(height: 24),

          _buildLoveCounter(
            days: days,
            hours: hours,
            minutes: minutes,
            seconds: seconds,
          ),

          const SizedBox(height: 22),

          _buildSpaceCard(),

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
                child: _buildFeatureCard(
                  icon: Icons.chat_bubble_rounded,
                  title: 'Private Chat',
                  subtitle: 'Just between us',
                  color: pink,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Chat is ready for the next development step.',
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFeatureCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Memories',
                  subtitle: 'Our shared gallery',
                  color: violet,
                  onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Gallery is ready for the next development step.',
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          _buildFeatureCard(
            icon: Icons.favorite_rounded,
            title: 'Our Journey',
            subtitle: 'Together since 7 August 2025',
            color: const Color(0xFFFF4F81),
            fullWidth: true,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
                'Welcome to our private world',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.52),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),

        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          child: IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoveCounter({
    required int days,
    required int hours,
    required int minutes,
    required int seconds,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF281044).withOpacity(0.95),
            const Color(0xFF111A3D).withOpacity(0.95),
          ],
        ),
        border: Border.all(
          color: pink.withOpacity(0.22),
        ),
        boxShadow: [
          BoxShadow(
            color: pink.withOpacity(0.10),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.favorite_rounded,
                color: pink,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text(
                'OUR JOURNEY',
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
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
                child: _counterItem(
                  value: days.toString(),
                  label: 'DAYS',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _counterItem(
                  value: hours.toString().padLeft(2, '0'),
                  label: 'HOURS',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _counterItem(
                  value: minutes.toString().padLeft(2, '0'),
                  label: 'MIN',
                ),
              ),
              _verticalDivider(),
              Expanded(
                child: _counterItem(
                  value: seconds.toString().padLeft(2, '0'),
                  label: 'SEC',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _counterItem({
    required String value,
    required String label,
  }) {
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

  Widget _verticalDivider() {
    return Container(
      width: 1,
      height: 35,
      color: Colors.white.withOpacity(0.10),
    );
  }

  Widget _buildSpaceCard() {
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  pink,
                  violet,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: pink.withOpacity(0.25),
                  blurRadius: 15,
                ),
              ],
            ),
            child: const Icon(
              Icons.lock_rounded,
              color: Colors.white,
              size: 23,
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

  Widget _buildFeatureCard({
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
                size: 22,
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

// =========================
// CHAT PAGE
// =========================

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

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
        _buildChatHeader(),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 15),
            physics: const BouncingScrollPhysics(),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              return _messageBubble(_messages[index]);
            },
          ),
        ),

        _buildMessageInput(),
      ],
    );
  }

  Widget _buildChatHeader() {
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

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Private Chat',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Only us • Private space',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          IconButton(
            onPressed: () {
              _showProfileDialog(context);
            },
            icon: const Icon(
              Icons.edit_rounded,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBubble(ChatMessage message) {
    return Align(
      alignment:
          message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 300,
        ),
        margin: const EdgeInsets.only(bottom: 10),
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
    );
  }

  Widget _buildMessageInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Media sharing will be connected with Firebase later.',
                  ),
                ),
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 13,
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
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF120A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(28),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Profile',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 22),

                const CircleAvatar(
                  radius: 42,
                  backgroundColor: Color(0x332E1A4F),
                  child: Icon(
                    Icons.person_rounded,
                    size: 40,
                    color: violet,
                  ),
                ),

                const SizedBox(height: 15),

                const Text(
                  'Profile picture & name',
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);

                      ScaffoldMessenger.of(this.context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Gallery picker will be connected in the next step.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.photo_library_rounded,
                    ),
                    label: const Text(
                      'Choose Profile Picture',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// =========================
// GALLERY PAGE
// =========================

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final List<String> _folders = [
    'Our Memories',
    'Special Days',
  ];

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
                  setState(() {
                    _folders.add(name);
                  });
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
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

          _buildUploadCard(),

          const SizedBox(height: 25),

          const Text(
            'Folders',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 13),

          ..._folders.map(
            (folder) => _folderTile(folder),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadCard() {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Photo/video picker will be connected with Firebase Storage next.',
            ),
          ),
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
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
              child: const Icon(
                Icons.cloud_upload_rounded,
                color: pink,
                size: 31,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              'Add Photos & Videos',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Shared with your partner when Firebase sync is enabled',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0x73FFFFFF),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _folderTile(String name) {
    return Container(
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
    );
  }
}

// =========================
// SETTINGS PAGE
// =========================

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
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

          _settingsSection(
            title: 'Our Space',
            children: [
              _settingTile(
                icon: Icons.favorite_border_rounded,
                title: 'Couple Space',
                subtitle: 'Connect your private space later',
                color: pink,
                onTap: () {
                  _comingSoon(context);
                },
              ),
              _settingTile(
                icon: Icons.person_outline_rounded,
                title: 'Profile',
                subtitle: 'Name and profile picture',
                color: violet,
                onTap: () {
                  _comingSoon(context);
                },
              ),
            ],
          ),

          const SizedBox(height: 18),

          _settingsSection(
            title: 'Security',
            children: [
              _settingTile(
                icon: Icons.pin_outlined,
                title: 'PIN Lock',
                subtitle: 'Will be added with Login system',
                color: const Color(0xFF60A5FA),
                onTap: () {
                  _comingSoon(context);
                },
              ),
              _settingTile(
                icon: Icons.lock_outline_rounded,
                title: 'Account & Login',
                subtitle: 'Coming at the final development stage',
                color: const Color(0xFFA78BFA),
                onTap: () {
                  _comingSoon(context);
                },
              ),
            ],
          ),

          const SizedBox(height: 18),

          _settingsSection(
            title: 'About',
            children: [
              _settingTile(
                icon: Icons.info_outline_rounded,
                title: 'Eternal Space',
                subtitle: 'Version 1.0.0 • Trial Mode',
                color: pink,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsSection({
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

  Widget _settingTile({
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
          size: 21,
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

  void _comingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This feature will be connected in the next development stage.',
        ),
      ),
    );
  }
}

// =========================
// ANIMATED BACKGROUND
// =========================
//
// এখানে BackdropFilter/blur ব্যবহার করা হয়নি।
// তার বদলে RadialGradient glow ব্যবহার করা হয়েছে,
// যাতে rendering আরও simple ও safe থাকে.
//

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
              left: -150 + (value * 120),
              top: -120,
              child: _glowOrb(
                size: 360,
                color: deepBlue,
              ),
            ),

            Positioned(
              right: -150 + (value * 140),
              top: 130,
              child: _glowOrb(
                size: 350,
                color: violet,
              ),
            ),

            Positioned(
              left: -120,
              bottom: -150 + (value * 100),
              child: _glowOrb(
                size: 330,
                color: pink,
              ),
            ),

            Positioned(
              right: -100,
              bottom: -120,
              child: _glowOrb(
                size: 280,
                color: const Color(0xFF2563EB),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _glowOrb({
    required double size,
    required Color color,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withOpacity(0.38),
            color.withOpacity(0.18),
            color.withOpacity(0.0),
          ],
          stops: const [
            0.0,
            0.45,
            1.0,
          ],
        ),
      ),
    );
  }
}

// =========================
// APP LOGO
// =========================

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
            spreadRadius: 2,
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

// =========================
// CHAT MODEL
// =========================

class ChatMessage {
  final String text;
  final bool isMe;

  ChatMessage({
    required this.text,
    required this.isMe,
  });
}
