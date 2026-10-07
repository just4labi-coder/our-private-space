import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';

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
      home: PasscodeLockScreen(
        isBengali: isBengali,
        isDarkMode: isDarkMode,
        onLanguageToggle: () => setState(() => isBengali = !isBengali),
        onThemeToggle: () => setState(() => isDarkMode = !isDarkMode),
      ),
    );
  }
}

// ১. স্মুথ অ্যানিমেটেড ব্যাকগ্রাউন্ড (HyperOS Gradient Effect)
class AnimatedGradientBackground extends StatefulWidget {
  final Widget child;
  const AnimatedGradientBackground({super.key, required this.child});

  @override
  State<AnimatedGradientBackground> createState() => _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState extends State<AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Alignment> _topAlignment;
  late Animation<Alignment> _bottomAlignment;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
    _topAlignment = Tween<Alignment>(begin: Alignment.topLeft, end: Alignment.bottomRight).animate(_controller);
    _bottomAlignment = Tween<Alignment>(begin: Alignment.bottomRight, end: Alignment.topLeft).animate(_controller);
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
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: _topAlignment.value,
              end: _bottomAlignment.value,
              colors: const [
                Color(0xFF1B0B38),
                Color(0xFF3B0764),
                Color(0xFF0F172A),
                Color(0xFF2E1065),
              ],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ২. পিন সিকিউরিটি লক স্ক্রিন
class PasscodeLockScreen extends StatefulWidget {
  final bool isBengali;
  final bool isDarkMode;
  final VoidCallback onLanguageToggle;
  final VoidCallback onThemeToggle;

  const PasscodeLockScreen({
    super.key,
    required this.isBengali,
    required this.isDarkMode,
    required this.onLanguageToggle,
    required this.onThemeToggle,
  });

  @override
  State<PasscodeLockScreen> createState() => _PasscodeLockScreenState();
}

class _PasscodeLockScreenState extends State<PasscodeLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final String _savedPin = "1234";

  void _verifyPin() {
    if (_pinController.text == _savedPin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MainHomeScreen(
            isBengali: widget.isBengali,
            isDarkMode: widget.isDarkMode,
            onLanguageToggle: widget.onLanguageToggle,
            onThemeToggle: widget.onThemeToggle,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.isBengali ? 'ভুল পিন!' : 'Wrong PIN!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedGradientBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 80, color: Colors.pinkAccent),
                const SizedBox(height: 20),
                Text(
                  widget.isBengali ? 'প্রাইভেট স্পেসে ঢুকতে পিন দিন' : 'Enter PIN to Access',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 24, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: 'PIN',
                      hintStyle: const TextStyle(color: Colors.white54, letterSpacing: 0),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _verifyPin,
                  child: Text(widget.isBengali ? 'প্রবেশ করুন' : 'Unlock', style: const TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ৩. মেইন অ্যাপ হোম স্ক্রিন
class MainHomeScreen extends StatefulWidget {
  final bool isBengali;
  final bool isDarkMode;
  final VoidCallback onLanguageToggle;
  final VoidCallback onThemeToggle;

  const MainHomeScreen({
    super.key,
    required this.isBengali,
    required this.isDarkMode,
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
  final List<Map<String, dynamic>> _messages = [
    {"text": "হাই! কেমন আছো?", "isMe": false, "sender": "Partner", "image": null},
    {"text": "ভালো, তুমি কেমন আছো?", "isMe": true, "sender": "Me", "image": null},
  ];

  final List<File> _galleryImages = [];
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source, {bool isChat = false}) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        if (isChat) {
          _messages.add({
            "text": "",
            "isMe": true,
            "sender": "Me",
            "image": File(image.path),
          });
        } else {
          _galleryImages.add(File(image.path));
        }
      });
    }
  }

  void _openImageViewer(File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.file(imageFile),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              hintText: 'Write notes here...',
              border: InputBorder.none,
            ),
          ),
        ),
      );
    }

    final pages = [
      _buildChatPage(),
      _buildGalleryPage(),
      RealtimeLoveCounterPage(isBengali: widget.isBengali),
      _buildSettingsPage(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.isBengali ? 'আমাদের প্রাইভেট জায়গা' : 'Our Private Space'),
        actions: [
          IconButton(
            icon: const Icon(Icons.security, color: Colors.redAccent),
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
      body: AnimatedGradientBackground(
        child: SafeArea(child: pages[_currentIndex]),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        currentIndex: _currentIndex,
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.chat_bubble),
            label: widget.isBengali ? 'চ্যাট' : 'Chat',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.photo_library),
            label: widget.isBengali ? 'গ্যালারি' : 'Gallery',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.favorite),
            label: widget.isBengali ? 'আমাদের সময়' : 'Journey',
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings),
            label: widget.isBengali ? 'সেটিংস' : 'Settings',
          ),
        ],
      ),
    );
  }

  // চ্যাট পেজ
  Widget _buildChatPage() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              bool isMe = _messages[index]["isMe"];
              File? msgImage = _messages[index]["image"];

              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isMe)
                      const CircleAvatar(
                        backgroundColor: Colors.purple,
                        radius: 14,
                        child: Icon(Icons.person, size: 16, color: Colors.white),
                      ),
                    const SizedBox(width: 6),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(10),
                      constraints: const BoxConstraints(maxWidth: 250),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.pinkAccent : Colors.white12,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _messages[index]["sender"],
                            style: const TextStyle(fontSize: 10, color: Colors.white60, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          if (msgImage != null)
                            GestureDetector(
                              onTap: () => _openImageViewer(msgImage),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(msgImage, height: 150, width: 200, fit: BoxFit.cover),
                              ),
                            ),
                          if (_messages[index]["text"].toString().isNotEmpty)
                            Text(
                              _messages[index]["text"],
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (isMe)
                      const CircleAvatar(
                        backgroundColor: Colors.pink,
                        radius: 14,
                        child: Icon(Icons.favorite, size: 14, color: Colors.white),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.black26,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.camera_alt, color: Colors.pinkAccent),
                onPressed: () => _pickImage(ImageSource.camera, isChat: true),
              ),
              IconButton(
                icon: const Icon(Icons.image, color: Colors.pinkAccent),
                onPressed: () => _pickImage(ImageSource.gallery, isChat: true),
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: InputDecoration(
                    hintText: widget.isBengali ? 'গোপন বার্তা লিখুন...' : 'Type message...',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.pinkAccent),
                onPressed: () {
                  if (_messageController.text.isNotEmpty) {
                    setState(() {
                      _messages.add({
                        "text": _messageController.text,
                        "isMe": true,
                        "sender": "Me",
                        "image": null,
                      });
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

  // গ্যালারি পেজ (ফুল স্ক্রিন ও জুম সহ)
  Widget _buildGalleryPage() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pinkAccent,
        onPressed: () => _pickImage(ImageSource.gallery),
        child: const Icon(Icons.add_a_photo),
      ),
      body: _galleryImages.isEmpty
          ? Center(
              child: Text(
                widget.isBengali ? 'কোনো ছবি যুক্ত করা হয়নি' : 'Gallery is Empty',
                style: const TextStyle(color: Colors.white70),
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _galleryImages.length,
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => _openImageViewer(_galleryImages[index]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(_galleryImages[index], fit: BoxFit.cover),
                  ),
                );
              },
            ),
    );
  }

  // সেটিংস পেজ
  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          title: Text(widget.isBengali ? 'পাসকোড সিকিউরিটি' : 'Passcode Lock'),
          subtitle: Text(widget.isBengali ? 'পিন সিকিউরিটি অন আছে' : 'PIN Protection Active'),
          value: true,
          onChanged: (val) {},
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.visibility_off, color: Colors.redAccent),
          title: Text(widget.isBengali ? 'প্যানিক মোড' : 'Panic Mode'),
          subtitle: Text(widget.isBengali ? 'উপরে লাল বাটন চাপুন' : 'Tap top red button'),
        ),
      ],
    );
  }
}

// ৪. রিয়েল-টাইম লাভ কাউন্টার (০৭/০৮/২০২৫ থেকে প্রতি সেকেন্ড লাইভ পরিবর্তন)
class RealtimeLoveCounterPage extends StatefulWidget {
  final bool isBengali;
  const RealtimeLoveCounterPage({super.key, required this.isBengali});

  @override
  State<RealtimeLoveCounterPage> createState() => _RealtimeLoveCounterPageState();
}

class _RealtimeLoveCounterPageState extends State<RealtimeLoveCounterPage> {
  final DateTime _startDate = DateTime(2025, 8, 7);
  late Timer _timer;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateDuration();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateDuration();
    });
  }

  void _updateDuration() {
    setState(() {
      _duration = DateTime.now().difference(_startDate);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int days = _duration.inDays;
    int hours = _duration.inHours % 24;
    int minutes = _duration.inMinutes % 60;
    int seconds = _duration.inSeconds % 60;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, size: 90, color: Colors.redAccent),
          const SizedBox(height: 20),
          Text(
            widget.isBengali ? 'আমাদের একসাথে পথচলা' : 'Our Journey Together',
            style: const TextStyle(fontSize: 20, color: Colors.white70),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTimeBox(days.toString(), widget.isBengali ? 'দিন' : 'Days'),
              _buildTimeBox(hours.toString().padLeft(2, '0'), widget.isBengali ? 'ঘণ্টা' : 'Hours'),
              _buildTimeBox(minutes.toString().padLeft(2, '0'), widget.isBengali ? 'মিঃ' : 'Mins'),
              _buildTimeBox(seconds.toString().padLeft(2, '0'), widget.isBengali ? 'সেঃ' : 'Secs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeBox(String value, String label) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.pinkAccent.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.pinkAccent),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
