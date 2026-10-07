import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const EternalSpaceApp());
}

class EternalSpaceApp extends StatelessWidget {
  const EternalSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Eternal Space',
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0F172A)),
      home: const PasscodeLockScreen(),
    );
  }
}

class HyperOSAnimatedBackground extends StatefulWidget {
  final Widget child;
  const HyperOSAnimatedBackground({super.key, required this.child});

  @override
  State<HyperOSAnimatedBackground> createState() => _HyperOSAnimatedBackgroundState();
}

class _HyperOSAnimatedBackgroundState extends State<HyperOSAnimatedBackground> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat(reverse: true);
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
        double val = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-1.0 + (val * 2.0), -0.8 + (val * 1.6)),
              radius: 1.5,
              colors: const [Color(0xFF831843), Color(0xFF4C1D95), Color(0xFF0F172A)],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

class PasscodeLockScreen extends StatefulWidget {
  const PasscodeLockScreen({super.key});

  @override
  State<PasscodeLockScreen> createState() => _PasscodeLockScreenState();
}

class _PasscodeLockScreenState extends State<PasscodeLockScreen> {
  final TextEditingController _pinController = TextEditingController();

  void _verifyPin() {
    if (_pinController.text == "1234") {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainHomeScreen()));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ভুল পিন!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: HyperOSAnimatedBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline, size: 80, color: Colors.pinkAccent),
                const SizedBox(height: 20),
                const Text('Enter Passcode', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 20),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8, color: Colors.white),
                    decoration: InputDecoration(hintText: 'PIN', filled: true, fillColor: Colors.white12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(15))),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent), onPressed: _verifyPin, child: const Text('Unlock')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  bool _isPanicMode = false;
  final TextEditingController _msgCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _myName = "My Name";
  String _myImgUrl = "";
  List<Map<String, dynamic>> _messages = [];
  List<String> _folders = ["General", "Memories"];
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  @override
  void initState() {
    super.initState();
    _dbRef.child("chats").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        List<Map<String, dynamic>> list = [];
        data.forEach((k, v) => list.add({"key": k, ...Map<String, dynamic>.from(v)}));
        list.sort((a, b) => (a["time"] ?? 0).compareTo(b["time"] ?? 0));
        setState(() => _messages = list);
      }
    });
  }

  void _editProfile() {
    TextEditingController nameCtrl = TextEditingController(text: _myName);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B4B),
        title: const Text('Edit Profile'),
        content: TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(labelText: 'Name', labelStyle: TextStyle(color: Colors.white70))),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() => _myName = nameCtrl.text.trim());
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }

  void _sendChat(String? imgUrl, String text) {
    _dbRef.child("chats").push().set({
      "text": text,
      "sender": _myName,
      "profileImg": _myImgUrl,
      "imageUrl": imgUrl ?? "",
      "time": ServerValue.timestamp,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isPanicMode) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calculator'), actions: [IconButton(icon: const Icon(Icons.lock_open), onPressed: () => setState(() => _isPanicMode = false))]),
        body: const Center(child: Text('0', style: TextStyle(fontSize: 60, color: Colors.white))),
      );
    }

    final pages = [
      const RealtimeLoveCounterPage(),
      _buildChatView(),
      _buildGalleryView(),
      _buildSettingsView(),
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Eternal Space', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_currentIndex == 1) IconButton(icon: const Icon(Icons.edit, color: Colors.pinkAccent), onPressed: _editProfile),
          IconButton(icon: const Icon(Icons.security, color: Colors.redAccent), onPressed: () => setState(() => _isPanicMode = true)),
        ],
      ),
      body: HyperOSAnimatedBackground(child: SafeArea(child: pages[_currentIndex])),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        currentIndex: _currentIndex,
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.grey,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Journey'),
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_special), label: 'Gallery'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildChatView() {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              var m = _messages[i];
              bool isMe = m["sender"] == _myName;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: isMe ? Colors.pinkAccent : Colors.white12, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m["sender"], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70)),
                      if (m["imageUrl"] != "") Image.network(m["imageUrl"], height: 120, width: 160, fit: BoxFit.cover),
                      if (m["text"] != "") Text(m["text"], style: const TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.image, color: Colors.pinkAccent),
                onPressed: () async {
                  XFile? img = await _picker.pickImage(source: ImageSource.gallery);
                  if (img != null) {
                    Reference ref = FirebaseStorage.instance.ref().child("chats/${DateTime.now().millisecondsSinceEpoch}.jpg");
                    await ref.putFile(File(img.path));
                    String url = await ref.getDownloadURL();
                    _sendChat(url, "");
                  }
                },
              ),
              Expanded(child: TextField(controller: _msgCtrl, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'Type message...', border: InputBorder.none))),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.pinkAccent),
                onPressed: () {
                  if (_msgCtrl.text.trim().isNotEmpty) {
                    _sendChat("", _msgCtrl.text.trim());
                    _msgCtrl.clear();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGalleryView() {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
      itemCount: _folders.length,
      itemBuilder: (context, i) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => FolderPage(folderName: _folders[i]))),
        child: Container(
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.pinkAccent.withOpacity(0.4))),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Icon(Icons.folder, size: 50, color: Colors.pinkAccent), Text(_folders[i], style: const TextStyle(fontWeight: FontWeight.bold))]),
        ),
      ),
    );
  }

  Widget _buildSettingsView() {
    return const Center(child: Text('Firebase Cloud Sync Active', style: TextStyle(color: Colors.white70)));
  }
}

class FolderPage extends StatefulWidget {
  final String folderName;
  const FolderPage({super.key, required this.folderName});

  @override
  State<FolderPage> createState() => _FolderPageState();
}

class _FolderPageState extends State<FolderPage> {
  List<String> _urls = [];
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    FirebaseDatabase.instance.ref().child("galleries/${widget.folderName}").onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        List<String> list = [];
        data.forEach((k, v) => list.add(v["url"]));
        setState(() => _urls = list);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folderName)),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.pinkAccent,
        onPressed: () async {
          XFile? img = await _picker.pickImage(source: ImageSource.gallery);
          if (img != null) {
            Reference ref = FirebaseStorage.instance.ref().child("galleries/${widget.folderName}/${DateTime.now().millisecondsSinceEpoch}.jpg");
            await ref.putFile(File(img.path));
            String url = await ref.getDownloadURL();
            FirebaseDatabase.instance.ref().child("galleries/${widget.folderName}").push().set({"url": url});
          }
        },
        child: const Icon(Icons.add),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
        itemCount: _urls.length,
        itemBuilder: (context, i) => Image.network(_urls[i], fit: BoxFit.cover),
      ),
    );
  }
}

class RealtimeLoveCounterPage extends StatefulWidget {
  const RealtimeLoveCounterPage({super.key});

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
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (mounted) setState(() => _duration = DateTime.now().difference(_startDate));
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
    int mins = _duration.inMinutes % 60;
    int secs = _duration.inSeconds % 60;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.favorite, size: 90, color: Colors.pinkAccent),
          const SizedBox(height: 20),
          const Text('Our Endless Journey', style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _box(days.toString(), 'Days'),
              _box(hours.toString().padLeft(2, '0'), 'Hours'),
              _box(mins.toString().padLeft(2, '0'), 'Mins'),
              _box(secs.toString().padLeft(2, '0'), 'Secs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(String val, String lbl) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.pinkAccent.withOpacity(0.5))),
      child: Column(children: [Text(val, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.pinkAccent)), Text(lbl, style: const TextStyle(fontSize: 11))]),
    );
  }
}
