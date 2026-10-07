import 'package:flutter/material.dart';

void main() {
  runApp(const OurPrivateSpaceApp());
}

class OurPrivateSpaceApp extends StatefulWidget {
  const OurPrivateSpaceApp({super.key});

  @override
  State<OurPrivateSpaceApp> createState() => _OurPrivateSpaceAppState();
}

class _OurPrivateSpaceAppState extends State<OurPrivateSpaceApp> {
  bool isDarkMode = true;
  bool isBengali = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Our Private Space',
      theme: isDarkMode ? ThemeData.dark() : ThemeData.light(),
      home: MainHomeScreen(
        isBengali: isBengali,
        onLanguageToggle: () => setState(() => isBengali = !isBengali),
        onThemeToggle: () => setState(() => isDarkMode = !isDarkMode),
      ),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  final bool isBengali;
  final VoidCallback onLanguageToggle;
  final VoidCallback onThemeToggle;

  const MainHomeScreen({
    super.key,
    required this.isBengali,
    required this.onLanguageToggle,
    required this.onThemeToggle,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  bool _isPanicMode = false;

  final TextEditingController _messageController = TextEditingController();
  final List<String> _dummyMessages = [
    "হাই! কেমন আছো?",
    "ভালো, তুমি কেমন আছো?",
    "এই তো ভালো। অ্যাপটি কেমন লাগছে?"
  ];

  @override
  Widget build(BuildContext context) {
    // প্যানিক মোড / ফেক নোটপ্যাড স্ক্রিন
    if (_isPanicMode) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notes'),
          actions: [
            IconButton(
              icon: const Icon(Icons.lock_open),
              onPressed: () => setState(() => _isPanicMode = false),
            )
          ],
        ),
        body: const Padding(
          padding: EdgeInsets.all(16.0),
          child: TextField(
            maxLines: null,
            decoration: InputDecoration(
              hintText: 'Write your private note here...',
              border: InputBorder.none,
            ),
          ),
        ),
      );
    }

    final pages = [
      _buildChatPage(),
      _buildGalleryPage(),
      _buildLoveCounterPage(),
      _buildSettingsPage(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isBengali ? 'আওয়ার প্রাইভেট স্পেস' : 'Our Private Space'),
        actions: [
          IconButton(
            icon: const Icon(Icons.privacy_tip, color: Colors.redAccent),
            tooltip: 'Panic Mode',
            onPressed: () => setState(() => _isPanicMode = true),
          ),
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
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble),
            label: widget.isBengali ? 'গোপন চ্যাট' : 'Chat',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.photo_library),
            label: widget.isBengali ? 'গ্যালারি' : 'Gallery',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.favorite),
            label: widget.isBengali ? 'কাউন্টার' : 'Counter',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.security),
            label: widget.isBengali ? 'সিকিউরিটি' : 'Security',
          ),
        ],
      ),
    );
  }

  // ১. চ্যাট পেজ
  Widget _buildChatPage() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _dummyMessages.length,
            itemBuilder: (context, index) {
              bool isMe = index % 2 == 0;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.pinkAccent : Colors.grey[800],
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    _dummyMessages[index],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Colors.black26,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image, color: Colors.pinkAccent),
                onPressed: () {},
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: widget.isBengali ? 'গোপন বার্তা লিখুন...' : 'Type a private message...',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.pinkAccent),
                onPressed: () {
                  if (_messageController.text.isNotEmpty) {
                    setState(() {
                      _dummyMessages.add(_messageController.text);
                      _messageController.clear();
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ২. ফটো গ্যালারি পেজ
  Widget _buildGalleryPage() {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pinkAccent,
        onPressed: () {},
        child: const Icon(Icons.add_a_photo),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.photo_album, size: 70, color: Colors.grey),
            const SizedBox(height: 10),
            Text(
              widget.isBengali
                  ? 'আপনাদের গোপন ফটো গ্যালারি খালি'
                  : 'Your private gallery is empty',
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  // ৩. লাভ কাউন্টার (আলাদা অপশনে)
  Widget _buildLoveCounterPage() {
    DateTime startDate = DateTime(2023, 1, 1); // উদাহরণস্বরূপ শুরুর তারিখ
    int daysTogether = DateTime.now().difference(startDate).inDays;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, size: 80, color: Colors.redAccent),
          const SizedBox(height: 20),
          Text(
            widget.isBengali ? 'আমরা একসাথে আছি' : 'We have been together for',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            '$daysTogether ${widget.isBengali ? 'দিন' : 'Days'}',
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
          ),
        ],
      ),
    );
  }

  // ৪. সিকিউরিটি সেটিং
  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: Text(widget.isBengali ? 'পাসকোড সিকিউরিটি' : 'Passcode Lock'),
          subtitle: Text(
              widget.isBengali ? 'পিন/ফিঙ্গারপ্রিন্ট লক অন করুন' : 'Enable Pin/Biometrics'),
          value: true,
          onChanged: (val) {},
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.visibility_off, color: Colors.redAccent),
          title: Text(widget.isBengali ? 'প্যানিক মোড' : 'Panic Mode'),
          subtitle: Text(widget.isBengali
              ? 'উপরের রেড বাটন চাপলে নোটপ্যাড ভেসে উঠবে'
              : 'Tap red button on AppBar to show Fake Notepad'),
        ),
      ],
    );
  }
}
