import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

void main() {
  runApp(const OurPrivateSpaceApp());
}

class OurPrivateSpaceApp extends StatelessWidget {
  const OurPrivateSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Our Private Space',
      theme: ThemeData.dark(),
      home: const PasscodeLockScreen(),
    );
  }
}

// ১. পাসকোড / পিন সিকিউরিটি স্ক্রিন
class PasscodeLockScreen extends StatefulWidget {
  const PasscodeLockScreen({super.key});

  @override
  State<PasscodeLockScreen> createState() => _PasscodeLockScreenState();
}

class _PasscodeLockScreenState extends State<PasscodeLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final String _savedPin = "1234"; // ডিফল্ট পিন

  void _verifyPin() {
    if (_pinController.text == _savedPin) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const MainHomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ভুল পিন! আবার চেষ্টা করুন।')),
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
                const Icon(Icons.lock_outline, size: 80, color: Colors.white),
                const SizedBox(height: 20),
                const Text(
                  'প্রাইভেট স্পেসে ঢুকতে পিন দিন',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
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
                    backgroundColor: Colors.purpleAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _verifyPin,
                  child: const Text('প্রবেশ করুন', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ২. সুন্দর কালারফুল চলাচল করা ব্যাকগ্রাউন্ড (HyperOS Gradient Effect)
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
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
    _topAlignment = Tween<Alignment>(begin: Alignment.topLeft, end: Alignment.topRight).animate(_controller);
    _bottomAlignment = Tween<Alignment>(begin: Alignment.bottomRight, end: Alignment.bottomLeft).animate(_controller);
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
                Color(0xFF2E1065),
                Color(0xFF0F172A),
                Color(0xFF3B0764),
              ],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// ৩. মেইন অ্যাপ হোম স্ক্রিন
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  bool _isPanicMode = false;

  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {"text": "হাই! কেমন আছো?", "isMe": false},
    {"text": "ভালো, তুমি কেমন আছো?", "isMe": true},
    {"text": "এই তো ভালো!", "isMe": false},
  ];

  final List<File> _galleryImages = [];
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage(ImageSource source) async {
    final XFile? image = await _picker.pickImage(source: source);
    if (image != null) {
      setState(() {
        _galleryImages.add(File(image.path));
      });
    }
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
      _buildLoveCounterPage(),
    ];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Our Private Space'),
        actions: [
          IconButton(
            icon: const Icon(Icons.security, color: Colors.redAccent),
            onPressed: () => setState(() => _isPanicMode = true),
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'চ্যাট'),
          BottomNavigationBarItem(icon: Icon(Icons.photo_library), label: 'গ্যালারি'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'কাউন্টার'),
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
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isMe ? Colors.pinkAccent : Colors.white12,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    _messages[index]["text"],
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.black38,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.camera_alt, color: Colors.purpleAccent),
                onPressed: () => _pickImage(ImageSource.camera),
              ),
              IconButton(
                icon: const Icon(Icons.image, color: Colors.purpleAccent),
                onPressed: () => _pickImage(ImageSource.gallery),
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(
                    hintText: 'গোপন বার্তা লিখুন...',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.pinkAccent),
                onPressed: () {
                  if (_messageController.text.isNotEmpty) {
                    setState(() {
                      _messages.add({"text": _messageController.text, "isMe": true});
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

  // গ্যালারি পেজ (ক্যামেরা ও ছবি যুক্ত সহ)
  Widget _buildGalleryPage() {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pinkAccent,
        onPressed: () => _pickImage(ImageSource.gallery),
        child: const Icon(Icons.add_a_photo),
      ),
      body: _galleryImages.isEmpty
          ? const Center(child: Text('কোনো ছবি যুক্ত করা হয়নি'))
          : GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: _galleryImages.length,
              itemBuilder: (context, index) {
                return Image.file(_galleryImages[index], fit: BoxFit.cover);
              },
            ),
    );
  }

  // লাভ কাউন্টার
  Widget _buildLoveCounterPage() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.favorite, size: 80, color: Colors.redAccent),
          SizedBox(height: 20),
          Text('আমাদের নিজস্ব স্থান', style: TextStyle(fontSize: 22, color: Colors.white)),
        ],
      ),
    );
  }
}
