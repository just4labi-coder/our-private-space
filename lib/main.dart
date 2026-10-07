import 'package:flutter/material.dart';

void main() {
  runApp(const OurPrivateApp());
}

class OurPrivateApp extends StatefulWidget {
  const OurPrivateApp({super.key});

  @override
  State<OurPrivateApp> createState() => _OurPrivateAppState();
}

class _OurPrivateAppState extends State<OurPrivateApp> {
  bool isDarkMode = true;
  bool isBengali = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Our Private Space',
      theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: MainNavigationScreen(
        isBengali: isBengali,
        onLanguageToggle: () => setState(() => isBengali = !isBengali),
        onThemeToggle: () => setState(() => isDarkMode = !isDarkMode),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  final bool isBengali;
  final VoidCallback onLanguageToggle;
  final VoidCallback onThemeToggle;

  const MainNavigationScreen({
    super.key,
    required this.isBengali,
    required this.onLanguageToggle,
    required this.onThemeToggle,
  });

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      LoveCounterPage(isBengali: widget.isBengali),
      SecretChatPage(isBengali: widget.isBengali),
      GalleryPage(isBengali: widget.isBengali),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isBengali ? 'আমাদের নিজস্ব জায়গা' : 'Our Private Space'),
        actions: [
          IconButton(
            icon: Icon(widget.isBengali ? Icons.language : Icons.g_translate),
            onPressed: widget.onLanguageToggle,
          ),
          IconButton(
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onThemeToggle,
          ),
        ],
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.favorite),
            label: widget.isBengali ? 'কাউন্টার' : 'Counter',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble),
            label: widget.isBengali ? 'চ্যাট' : 'Chat',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.photo_library),
            label: widget.isBengali ? 'গ্যালারি' : 'Gallery',
          ),
        ],
      ),
    );
  }
}

class LoveCounterPage extends StatelessWidget {
  final bool isBengali;
  const LoveCounterPage({super.key, required this.isBengali});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, size: 80, color: Colors.redAccent),
          const SizedBox(height: 20),
          Text(
            isBengali ? 'আমরা একসাথে আছি' : 'We have been together for',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 10),
          const Text(
            '365 Days',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
          ),
        ],
      ),
    );
  }
}

class SecretChatPage extends StatelessWidget {
  final bool isBengali;
  const SecretChatPage({super.key, required this.isBengali});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        isBengali ? 'গোপন চ্যাট রুম শীঘ্রই আসছে...' : 'Secret Chat Room Coming Soon...',
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}

class GalleryPage extends StatelessWidget {
  final bool isBengali;
  const GalleryPage({super.key, required this.isBengali});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        isBengali ? 'আমাদের গ্যালারি ফাঁকা' : 'Our Photo Gallery is Empty',
        style: const TextStyle(fontSize: 16),
      ),
    );
  }
}
