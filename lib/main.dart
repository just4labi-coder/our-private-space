import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EternalSpaceApp());
}

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
        scaffoldBackgroundColor: const Color(0xFF080914),
        fontFamily: 'sans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFF2F92),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const MainScreen(),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: AnimatedBackground(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLogo(size: 88),
              SizedBox(height: 24),
              Text(
                'Eternal Space',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Our little private universe',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 30),
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF4FA3),
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

  final List<GalleryFolder> folders = [
    GalleryFolder(
      name: 'Our Memories',
      createdAt: DateTime(2025, 8, 7, 12, 0),
    ),
    GalleryFolder(
      name: 'Special Days',
      createdAt: DateTime(2025, 8, 7, 12, 5),
    ),
  ];

  final List<ChatMessage> messages = [
    ChatMessage(
      text: 'Welcome to our private chat ❤️',
      isMe: false,
      sentAt: DateTime(2025, 8, 7, 20, 30),
    ),
    ChatMessage(
      text: 'এই জায়গাটা শুধু আমাদের জন্য।',
      isMe: true,
      sentAt: DateTime(2025, 8, 7, 20, 32),
    ),
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
      myName = prefs.getString('myName') ?? 'Me';
      partnerName = prefs.getString('partnerName') ?? 'My Love';
    });
  }

  Future<void> _saveProfile(String me, String partner) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('myName', me);
    await prefs.setString('partnerName', partner);

    if (!mounted) return;

    setState(() {
      myName = me;
      partnerName = partner;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        myName: myName,
        partnerName: partnerName,
        onChat: () {
          setState(() => _selectedIndex = 1);
        },
        onGallery: () {
          setState(() => _selectedIndex = 2);
        },
      ),
      ChatPage(
        myName: myName,
        partnerName: partnerName,
        messages: messages,
      ),
      GalleryPage(
        folders: folders,
        onFolderCreated: (folder) {
          setState(() {
            folders.add(folder);
          });
        },
        onFolderDeleted: (folder) {
          setState(() {
            folders.remove(folder);
          });
        },
      ),
      SettingsPage(
        myName: myName,
        partnerName: partnerName,
        onSaveProfile: _saveProfile,
      ),
    ];

    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: IndexedStack(
            index: _selectedIndex,
            children: pages,
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: const Color(0xFF0B0C19),
        indicatorColor: const Color(0x33FF2F92),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.photo_library_outlined),
            selectedIcon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
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
  final String myName;
  final String partnerName;
  final VoidCallback onChat;
  final VoidCallback onGallery;

  const HomePage({
    super.key,
    required this.myName,
    required this.partnerName,
    required this.onChat,
    required this.onGallery,
  });

  String _loveDuration() {
    final start = DateTime(2025, 8, 7);
    final now = DateTime.now();

    final difference = now.difference(start);

    final days = difference.inDays;
    final hours = difference.inHours % 24;
    final minutes = difference.inMinutes % 60;

    return '$days days • $hours hours • $minutes minutes';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 28),
      children: [
        Row(
          children: [
            const AppLogo(size: 48),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Eternal Space',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Just for the two of us',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 7,
              ),
              decoration: BoxDecoration(
                color: const Color(0x221CFF72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0x443CFF8A),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 8,
                    color: Color(0xFF42FF85),
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Private',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8BFFB1),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 28),

        GlassCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Together for',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _loveDuration(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFF6BAF),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Since 07 August 2025 ❤️',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        GlassCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 30,
                backgroundColor: Color(0x33FF2F92),
                child: Icon(
                  Icons.favorite,
                  color: Color(0xFFFF4F9A),
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$myName & $partnerName',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Our private little universe',
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
        ),

        const SizedBox(height: 20),

        const SectionTitle(
          title: 'Our Space',
          icon: Icons.favorite_border,
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: FeatureCard(
                icon: Icons.chat_bubble,
                title: 'Private Chat',
                subtitle: 'Just us',
                onTap: onChat,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FeatureCard(
                icon: Icons.photo_library,
                title: 'Memories',
                subtitle: 'Our gallery',
                onTap: onGallery,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: FeatureCard(
                icon: Icons.mail_outline,
                title: 'Love Notes',
                subtitle: 'Little words',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoveNotesPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FeatureCard(
                icon: Icons.music_note,
                title: 'Our Music',
                subtitle: 'Our songs',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OurMusicPage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: FeatureCard(
                icon: Icons.event,
                title: 'Special Dates',
                subtitle: 'Important days',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SpecialDatesPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FeatureCard(
                icon: Icons.auto_awesome,
                title: 'Surprise',
                subtitle: 'Something special',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SurprisePage(),
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        FeatureCard(
          icon: Icons.timeline,
          title: 'Relationship Timeline',
          subtitle: 'Our story from the beginning',
          fullWidth: true,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TimelinePage(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ============================================================
// CHAT
// ============================================================

class ChatPage extends StatefulWidget {
  final String myName;
  final String partnerName;
  final List<ChatMessage> messages;

  const ChatPage({
    super.key,
    required this.myName,
    required this.partnerName,
    required this.messages,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void _sendMessage() {
    final text = _controller.text.trim();

    if (text.isEmpty) return;

    setState(() {
      widget.messages.add(
        ChatMessage(
          text: text,
          isMe: true,
          sentAt: DateTime.now(),
        ),
      );
    });

    _controller.clear();

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showMessageActions(ChatMessage message) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 18),
                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                    color: Color(0xFFB88CFF),
                  ),
                  title: const Text('Details'),
                  onTap: () {
                    Navigator.pop(context);
                    _showMessageDetails(message);
                  },
                ),
                if (!message.deleted)
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                    title: const Text('Delete'),
                    onTap: () {
                      Navigator.pop(context);
                      _deleteMessage(message);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteMessage(ChatMessage message) {
    setState(() {
      message.deleted = true;
    });
  }

  void _showMessageDetails(ChatMessage message) {
    final sender = message.isMe ? widget.myName : widget.partnerName;

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('Message Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DetailRow(
                icon: Icons.person_outline,
                title: 'Sender',
                value: sender,
              ),
              DetailRow(
                icon: Icons.calendar_today_outlined,
                title: 'Date',
                value: formatDate(message.sentAt),
              ),
              DetailRow(
                icon: Icons.access_time,
                title: 'Time',
                value: formatTime(message.sentAt),
              ),
              DetailRow(
                icon: Icons.done_all,
                title: 'Status',
                value: message.deleted ? 'Unsent' : 'Sent',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 25,
                backgroundColor: Color(0x33FF2F92),
                child: Icon(
                  Icons.favorite,
                  color: Color(0xFFFF4F9A),
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: Color(0xFF43FF80),
                        ),
                        SizedBox(width: 5),
                        Text(
                          'Active now',
                          style: TextStyle(
                            color: Color(0xFF72FF9E),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  _showInfo(
                    context,
                    'Active Status',
                    'এই Trial Mode-এ Active Now দেখানো হচ্ছে। Firebase Presence যুক্ত হলে এখানে আসল online/offline status দেখানো হবে।',
                  );
                },
                icon: const Icon(Icons.info_outline),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.messages.isEmpty
              ? const Center(
                  child: Text(
                    'No messages yet ❤️',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  itemCount: widget.messages.length,
                  itemBuilder: (context, index) {
                    final message = widget.messages[index];

                    return MessageBubble(
                      message: message,
                      onLongPress: () => _showMessageActions(message),
                    );
                  },
                ),
        ),
        _ChatInput(
          controller: _controller,
          onSend: _sendMessage,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final deleted = message.deleted;

    return Align(
      alignment:
          message.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 310),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 8),
          decoration: BoxDecoration(
            color: deleted
                ? const Color(0x221F2133)
                : message.isMe
                    ? const Color(0xFFB52F78)
                    : const Color(0xFF1B1D30),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(message.isMe ? 18 : 4),
              bottomRight: Radius.circular(message.isMe ? 4 : 18),
            ),
            border: deleted
                ? Border.all(color: Colors.white12)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (deleted)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Icon(
                          Icons.remove_circle_outline,
                          size: 15,
                          color: Colors.white38,
                        ),
                      ),
                    Flexible(
                      child: Text(
                        deleted ? 'Unsent' : message.text,
                        style: TextStyle(
                          fontSize: 15,
                          color: deleted
                              ? Colors.white38
                              : Colors.white,
                          fontStyle:
                              deleted ? FontStyle.italic : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatTime(message.sentAt),
                style: TextStyle(
                  color: deleted
                      ? Colors.white24
                      : Colors.white54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _ChatInput({
    required this.controller,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xCC0A0B16),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Write something...',
                filled: true,
                fillColor: const Color(0xFF171827),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    Color(0xFFFF2F92),
                    Color(0xFF8D4DFF),
                  ],
                ),
              ),
              child: const Icon(Icons.send_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// GALLERY
// ============================================================

class GalleryPage extends StatefulWidget {
  final List<GalleryFolder> folders;
  final ValueChanged<GalleryFolder> onFolderCreated;
  final ValueChanged<GalleryFolder> onFolderDeleted;

  const GalleryPage({
    super.key,
    required this.folders,
    required this.onFolderCreated,
    required this.onFolderDeleted,
  });

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  void _createFolder() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('New Folder'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Folder name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = controller.text.trim();

                if (name.isEmpty) return;

                widget.onFolderCreated(
                  GalleryFolder(
                    name: name,
                    createdAt: DateTime.now(),
                  ),
                );

                Navigator.pop(context);
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _openFolder(GalleryFolder folder) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FolderPage(folder: folder),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _folderActions(GalleryFolder folder) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: Color(0xFFB88CFF),
                ),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(context);
                  _folderDetails(folder);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteFolder(folder);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _folderDetails(GalleryFolder folder) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: Text(folder.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DetailRow(
                icon: Icons.folder_outlined,
                title: 'Folder',
                value: folder.name,
              ),
              DetailRow(
                icon: Icons.calendar_today_outlined,
                title: 'Created',
                value: formatDate(folder.createdAt),
              ),
              DetailRow(
                icon: Icons.access_time,
                title: 'Time',
                value: formatTime(folder.createdAt),
              ),
              DetailRow(
                icon: Icons.photo_library_outlined,
                title: 'Media',
                value: '${folder.media.length} item(s)',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _deleteFolder(GalleryFolder folder) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('Delete folder?'),
          content: Text(
            '“${folder.name}” folder এবং এর ভিতরের media এই Trial Mode থেকে মুছে যাবে।',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                widget.onFolderDeleted(folder);
                Navigator.pop(context);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
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
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'A private place for our moments',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _createFolder,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0x33FF2F92),
              ),
              icon: const Icon(Icons.create_new_folder_outlined),
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (widget.folders.isEmpty)
          GlassCard(
            child: Column(
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 48,
                  color: Colors.white38,
                ),
                const SizedBox(height: 12),
                const Text(
                  'No folders yet',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Create your first memories folder.',
                  style: TextStyle(
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _createFolder,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Folder'),
                ),
              ],
            ),
          )
        else
          ...widget.folders.map(
            (folder) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onLongPress: () => _folderActions(folder),
                child: GlassCard(
                  onTap: () => _openFolder(folder),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0x33FF2F92),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: const Icon(
                          Icons.folder_rounded,
                          color: Color(0xFFFF5AA5),
                          size: 30,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(
                              folder.name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${folder.media.length} media • ${formatDate(folder.createdAt)}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: Colors.white38,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 10),

        const GlassCard(
          child: Row(
            children: [
              Icon(
                Icons.touch_app_outlined,
                color: Color(0xFFB88CFF),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Folder-এ long press করলে Delete এবং Details পাওয়া যাবে।',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// FOLDER PAGE
// ============================================================

class FolderPage extends StatefulWidget {
  final GalleryFolder folder;

  const FolderPage({
    super.key,
    required this.folder,
  });

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _chooseMedia() async {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const Text(
                'Add to Memories',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(
                  Icons.image_outlined,
                  color: Color(0xFFFF5AA5),
                ),
                title: const Text('Choose Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.video_library_outlined,
                  color: Color(0xFFB88CFF),
                ),
                title: const Text('Choose Video'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 95,
      );

      if (file == null) return;

      setState(() {
        widget.folder.media.add(
          GalleryMedia(
            path: file.path,
            name: file.name,
            type: MediaKind.image,
            createdAt: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;

      _showInfo(
        context,
        'Could not add image',
        'Image select করার সময় সমস্যা হয়েছে।\n\n$e',
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? file = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (file == null) return;

      setState(() {
        widget.folder.media.add(
          GalleryMedia(
            path: file.path,
            name: file.name,
            type: MediaKind.video,
            createdAt: DateTime.now(),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;

      _showInfo(
        context,
        'Could not add video',
        'Video select করার সময় সমস্যা হয়েছে।\n\n$e',
      );
    }
  }

  void _mediaActions(GalleryMedia media) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141526),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.open_in_full,
                  color: Color(0xFFB88CFF),
                ),
                title: const Text('Open'),
                onTap: () {
                  Navigator.pop(context);
                  _openMedia(media);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.info_outline,
                  color: Color(0xFFB88CFF),
                ),
                title: const Text('Details'),
                onTap: () {
                  Navigator.pop(context);
                  _mediaDetails(media);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                ),
                title: const Text('Delete'),
                onTap: () {
                  Navigator.pop(context);
                  _deleteMedia(media);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openMedia(GalleryMedia media) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MediaViewerPage(media: media),
      ),
    );
  }

  void _mediaDetails(GalleryMedia media) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('Media Details'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DetailRow(
                icon: media.type == MediaKind.image
                    ? Icons.image_outlined
                    : Icons.video_library_outlined,
                title: 'Type',
                value: media.type == MediaKind.image
                    ? 'Photo'
                    : 'Video',
              ),
              DetailRow(
                icon: Icons.description_outlined,
                title: 'Name',
                value: media.name,
              ),
              DetailRow(
                icon: Icons.folder_outlined,
                title: 'Folder',
                value: widget.folder.name,
              ),
              DetailRow(
                icon: Icons.calendar_today_outlined,
                title: 'Date',
                value: formatDate(media.createdAt),
              ),
              DetailRow(
                icon: Icons.access_time,
                title: 'Time',
                value: formatTime(media.createdAt),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _deleteMedia(GalleryMedia media) {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('Delete media?'),
          content: Text(
            '“${media.name}” এই folder থেকে মুছে যাবে।',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () {
                setState(() {
                  widget.folder.media.remove(media);
                });
                Navigator.pop(context);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080914),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(widget.folder.name),
        actions: [
          IconButton(
            onPressed: _chooseMedia,
            icon: const Icon(Icons.add_photo_alternate_outlined),
          ),
        ],
      ),
      body: AnimatedBackground(
        child: widget.folder.media.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: GlassCard(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.photo_library_outlined,
                          size: 55,
                          color: Colors.white30,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'No memories yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'এই folder-এ photo অথবা video যোগ করো।',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _chooseMedia,
                          icon: const Icon(
                            Icons.add_photo_alternate_outlined,
                          ),
                          label: const Text('Add Media'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: widget.folder.media.length,
                itemBuilder: (context, index) {
                  final media = widget.folder.media[index];

                  return GestureDetector(
                    onTap: () => _openMedia(media),
                    onLongPress: () => _mediaActions(media),
                    child: MediaGridTile(media: media),
                  );
                },
              ),
      ),
      floatingActionButton: widget.folder.media.isEmpty
          ? null
          : FloatingActionButton(
              backgroundColor: const Color(0xFFFF2F92),
              onPressed: _chooseMedia,
              child: const Icon(Icons.add),
            ),
    );
  }
}

// ============================================================
// MEDIA VIEWER
// ============================================================

class MediaViewerPage extends StatefulWidget {
  final GalleryMedia media;

  const MediaViewerPage({
    super.key,
    required this.media,
  });

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  VideoPlayerController? _videoController;

  @override
  void initState() {
    super.initState();

    if (widget.media.type == MediaKind.video) {
      _initializeVideo();
    }
  }

  Future<void> _initializeVideo() async {
    final controller = VideoPlayerController.file(
      File(widget.media.path),
    );

    _videoController = controller;

    try {
      await controller.initialize();

      if (!mounted) return;

      setState(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          widget.media.name,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: widget.media.type == MediaKind.image
            ? _buildImage()
            : _buildVideo(),
      ),
    );
  }

  Widget _buildImage() {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 5,
      panEnabled: true,
      child: Image.file(
        File(widget.media.path),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) {
          return const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.broken_image_outlined,
                size: 60,
                color: Colors.white38,
              ),
              SizedBox(height: 12),
              Text(
                'Image could not be opened',
                style: TextStyle(color: Colors.white54),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideo() {
    final controller = _videoController;

    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator(
        color: Color(0xFFFF4FA3),
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              iconSize: 50,
              onPressed: () {
                setState(() {
                  if (controller.value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                });
              },
              icon: Icon(
                controller.value.isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class MediaGridTile extends StatelessWidget {
  final GalleryMedia media;

  const MediaGridTile({
    super.key,
    required this.media,
  });

  @override
  Widget build(BuildContext context) {
    if (media.type == MediaKind.image) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(media.path),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            return _videoStyle();
          },
        ),
      );
    }

    return _videoStyle();
  }

  Widget _videoStyle() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF25203B),
            Color(0xFF111322),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(
            Icons.play_circle_fill,
            size: 42,
            color: Colors.white,
          ),
          Positioned(
            left: 7,
            right: 7,
            bottom: 6,
            child: Text(
              media.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9,
                color: Colors.white60,
              ),
            ),
          ),
        ],
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
  final List<LoveNote> notes = [
    LoveNote(
      title: 'For you ❤️',
      text: 'তুমি আমার দিনের সবচেয়ে সুন্দর অংশ।',
      createdAt: DateTime(2025, 8, 7, 21, 0),
    ),
  ];

  void _addNote() {
    final title = TextEditingController();
    final text = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('New Love Note'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(
                  hintText: 'Title',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: text,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Write something...',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (text.text.trim().isEmpty) return;

                setState(() {
                  notes.insert(
                    0,
                    LoveNote(
                      title: title.text.trim().isEmpty
                          ? 'Love Note'
                          : title.text.trim(),
                      text: text.text.trim(),
                      createdAt: DateTime.now(),
                    ),
                  );
                });

                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleFeaturePage(
      title: 'Love Notes',
      subtitle: 'Little words from the heart',
      action: IconButton(
        onPressed: _addNote,
        icon: const Icon(Icons.add),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: notes.length,
        itemBuilder: (_, index) {
          final note = notes[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    note.text,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${formatDate(note.createdAt)} • ${formatTime(note.createdAt)}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
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
}

// ============================================================
// OUR MUSIC
// ============================================================

class OurMusicPage extends StatefulWidget {
  const OurMusicPage({super.key});

  @override
  State<OurMusicPage> createState() => _OurMusicPageState();
}

class _OurMusicPageState extends State<OurMusicPage> {
  final List<String> songs = [
    'Our first song',
    'The song that reminds me of you',
  ];

  void _addSong() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('Add Song'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Song name',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) return;

                setState(() {
                  songs.add(controller.text.trim());
                });

                Navigator.pop(context);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SimpleFeaturePage(
      title: 'Our Music',
      subtitle: 'Songs that belong to us',
      action: IconButton(
        onPressed: _addSong,
        icon: const Icon(Icons.add),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: songs.length,
        itemBuilder: (_, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0x33FF2F92),
                    child: Icon(
                      Icons.music_note,
                      color: Color(0xFFFF5AA5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      songs[index],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white54,
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
// SPECIAL DATES
// ============================================================

class SpecialDatesPage extends StatelessWidget {
  const SpecialDatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dates = [
      ('Our Beginning', DateTime(2025, 8, 7)),
      ('Labi Birthday', DateTime(2026, 1, 19)),
    ];

    return SimpleFeaturePage(
      title: 'Special Dates',
      subtitle: 'Days worth remembering',
      child: ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: dates.length,
        itemBuilder: (_, index) {
          final item = dates[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: GlassCard(
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0x33FF2F92),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.favorite,
                      color: Color(0xFFFF5AA5),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          formatDate(item.$2),
                          style: const TextStyle(
                            color: Colors.white54,
                          ),
                        ),
                      ],
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
}

// ============================================================
// SURPRISE
// ============================================================

class SurprisePage extends StatelessWidget {
  const SurprisePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleFeaturePage(
      title: 'Surprise',
      subtitle: 'A little secret corner',
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.card_giftcard_rounded,
                  size: 70,
                  color: Color(0xFFFF5AA5),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Something special is waiting...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'এই জায়গাটা পরে আরও special করা যাবে।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () {
                    _showInfo(
                      context,
                      'Surprise',
                      'এখানে পরে তোমাদের custom surprise animation, message বা special unlock যোগ করা যাবে।',
                    );
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('Open'),
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
// TIMELINE
// ============================================================

class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final events = [
      TimelineEvent(
        date: DateTime(2025, 8, 7),
        title: 'Our Beginning',
        description: 'The day our private story starts.',
      ),
      TimelineEvent(
        date: DateTime(2025, 8, 7),
        title: 'Eternal Space',
        description: 'Our little private universe begins.',
      ),
    ];

    return SimpleFeaturePage(
      title: 'Our Story',
      subtitle: 'Everything that brought us here',
      child: ListView.builder(
        padding: const EdgeInsets.all(18),
        itemCount: events.length,
        itemBuilder: (_, index) {
          final event = events[index];

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 15,
                      height: 15,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFF4F9A),
                      ),
                    ),
                    if (index != events.length - 1)
                      Container(
                        width: 2,
                        height: 90,
                        color: const Color(0x44FF4F9A),
                      ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: GlassCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          formatDate(event.date),
                          style: const TextStyle(
                            color: Color(0xFFFF6BAF),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          event.description,
                          style: const TextStyle(
                            color: Colors.white60,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
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

class SettingsPage extends StatelessWidget {
  final String myName;
  final String partnerName;
  final Future<void> Function(String, String) onSaveProfile;

  const SettingsPage({
    super.key,
    required this.myName,
    required this.partnerName,
    required this.onSaveProfile,
  });

  void _editProfile(BuildContext context) {
    final me = TextEditingController(text: myName);
    final partner = TextEditingController(text: partnerName);

    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(0xFF141526),
          title: const Text('Profile'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: me,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: partner,
                decoration: const InputDecoration(
                  labelText: 'Partner name',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await onSaveProfile(
                  me.text.trim().isEmpty
                      ? 'Me'
                      : me.text.trim(),
                  partner.text.trim().isEmpty
                      ? 'My Love'
                      : partner.text.trim(),
                );

                if (context.mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
      children: [
        const Text(
          'Settings',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Manage your private space',
          style: TextStyle(
            color: Colors.white54,
          ),
        ),

        const SizedBox(height: 22),

        GlassCard(
          child: Row(
            children: [
              const CircleAvatar(
                radius: 32,
                backgroundColor: Color(0x33FF2F92),
                child: Icon(
                  Icons.person,
                  color: Color(0xFFFF5AA5),
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      myName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'With $partnerName',
                      style: const TextStyle(
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _editProfile(context),
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        SettingsTile(
          icon: Icons.link,
          title: 'Couple Code',
          subtitle: 'Connect your partner later',
          onTap: () {
            _showInfo(
              context,
              'Couple Code',
              'Firebase account system যুক্ত করার সময় এখানে unique Couple Code তৈরি হবে।',
            );
          },
        ),

        SettingsTile(
          icon: Icons.lock_outline,
          title: 'PIN Lock',
          subtitle: 'Coming in security phase',
          onTap: () {
            _showInfo(
              context,
              'PIN Lock',
              'Login system শেষ করার পর এখানে App PIN Lock যুক্ত হবে।',
            );
          },
        ),

        SettingsTile(
          icon: Icons.cloud_outlined,
          title: 'Firebase Sync',
          subtitle: 'Cloud sync will be connected later',
          onTap: () {
            _showInfo(
              context,
              'Firebase',
              'বর্তমান build Trial Mode। Firebase sync পরের phase-এ connect হবে।',
            );
          },
        ),

        SettingsTile(
          icon: Icons.password_outlined,
          title: 'Forgot Password',
          subtitle: 'Available after account system',
          onTap: () {
            _showInfo(
              context,
              'Forgot Password',
              'Permanent account/login system চালু হলে এখানে password recovery থাকবে।',
            );
          },
        ),

        const SizedBox(height: 20),

        const GlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Eternal Space',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Trial Mode • v1.0.0',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'This private space is being built for two people and their memories.',
                style: TextStyle(
                  color: Colors.white54,
                  height: 1.4,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SIMPLE FEATURE PAGE
// ============================================================

class SimpleFeaturePage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? action;
  final Widget child;

  const SimpleFeaturePage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080914),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.45),
              ),
            ),
          ],
        ),
        actions: [
          if (action != null) action!,
        ],
      ),
      body: AnimatedBackground(
        child: child,
      ),
    );
  }
}

// ============================================================
// MODELS
// ============================================================

class ChatMessage {
  final String text;
  final bool isMe;
  final DateTime sentAt;
  bool deleted;

  ChatMessage({
    required this.text,
    required this.isMe,
    required this.sentAt,
    this.deleted = false,
  });
}

enum MediaKind {
  image,
  video,
}

class GalleryMedia {
  final String path;
  final String name;
  final MediaKind type;
  final DateTime createdAt;

  GalleryMedia({
    required this.path,
    required this.name,
    required this.type,
    required this.createdAt,
  });
}

class GalleryFolder {
  String name;
  final DateTime createdAt;
  final List<GalleryMedia> media;

  GalleryFolder({
    required this.name,
    required this.createdAt,
    List<GalleryMedia>? media,
  }) : media = media ?? [];
}

class LoveNote {
  final String title;
  final String text;
  final DateTime createdAt;

  LoveNote({
    required this.title,
    required this.text,
    required this.createdAt,
  });
}

class TimelineEvent {
  final DateTime date;
  final String title;
  final String description;

  TimelineEvent({
    required this.date,
    required this.title,
    required this.description,
  });
}

// ============================================================
// UI COMPONENTS
// ============================================================

class GlassCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0x66191A2C),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0x22FFFFFF),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );

    if (onTap == null) return card;

    return GestureDetector(
      onTap: onTap,
      child: card,
    );
  }
}

class FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool fullWidth;

  const FeatureCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0x33FF2F92),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: const Color(0xFFFF5AA5),
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 10,
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

class SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const SectionTitle({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xFFFF5AA5),
          size: 19,
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        onTap: onTap,
        child: Row(
          children: [
            Icon(
              icon,
              color: const Color(0xFFB88CFF),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}

class DetailRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const DetailRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: const Color(0xFFB88CFF),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 60,
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
          colors: [
            Color(0xFFFF2F92),
            Color(0xFF7A4DFF),
          ],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66FF2F92),
            blurRadius: 25,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Icon(
        Icons.favorite_rounded,
        size: size * .48,
        color: Colors.white,
      ),
    );
  }
}

// ============================================================
// ANIMATED BACKGROUND
// ============================================================

class AnimatedBackground extends StatefulWidget {
  final Widget child;

  const AnimatedBackground({
    super.key,
    required this.child,
  });

  @override
  State<AnimatedBackground> createState() =>
      _AnimatedBackgroundState();
}

class _AnimatedBackgroundState
    extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 9),
    )..repeat(reverse: true);
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
      builder: (_, child) {
        final value = _controller.value;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(
                -1 + value * 1.4,
                -1,
              ),
              end: Alignment(
                1,
                1 - value * 1.2,
              ),
              colors: const [
                Color(0xFF090A17),
                Color(0xFF15102A),
                Color(0xFF0B1428),
                Color(0xFF100A1E),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                top: -100 + (value * 50),
                right: -90,
                child: _GlowOrb(
                  size: 260,
                  color: const Color(0x443E64FF),
                ),
              ),
              Positioned(
                bottom: -120 + (value * 40),
                left: -100,
                child: _GlowOrb(
                  size: 300,
                  color: const Color(0x442F1FFF),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({
    required this.size,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 100,
              spreadRadius: 30,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HELPERS
// ============================================================

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final year = date.year.toString();

  return '$day/$month/$year';
}

String formatTime(DateTime date) {
  final hour = date.hour;
  final minute = date.minute.toString().padLeft(2, '0');

  final isPm = hour >= 12;
  final displayHour =
      hour % 12 == 0 ? 12 : hour % 12;

  return '$displayHour:$minute ${isPm ? 'PM' : 'AM'}';
}

void _showInfo(
  BuildContext context,
  String title,
  String message,
) {
  showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        backgroundColor: const Color(0xFF141526),
        title: Text(title),
        content: Text(
          message,
          style: const TextStyle(
            color: Colors.white70,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      );
    },
  );
}
