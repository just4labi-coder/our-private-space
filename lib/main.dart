import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
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
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}

// ফায়ারবেস লগইন স্টেট চেক
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return const PasscodeLockScreen();
        }
        return const LoginScreen();
      },
    );
  }
}

// ফায়ারবেস অ্যাকাউন্ট তৈরি ও লগইন স্ক্রিন
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool isSignUp = false;

  Future<void> _submit() async {
    try {
      if (isSignUp) {
        await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
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
                const Icon(Icons.favorite, size: 80, color: Colors.pinkAccent),
                const SizedBox(height: 10),
                Text(
                  isSignUp ? 'Create Cloud Account' : 'Welcome to Eternal Space',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email', filled: true, fillColor: Colors.white12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password', filled: true, fillColor: Colors.white12),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                  onPressed: _submit,
                  child: Text(isSignUp ? 'Sign Up' : 'Login'),
                ),
                TextButton(
                  onPressed: () => setState(() => isSignUp = !isSignUp),
                  child: Text(isSignUp ? 'Already have an account? Login' : "Don't have an account? Sign Up"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// HyperOS Dynamic Moving Background
class HyperOSAnimatedBackground extends StatefulWidget {
  final Widget child;
  const HyperOSAnimatedBackground({super.key, required this.child});

  @override
  State<HyperOSAnimatedBackground> createState() => _HyperOSAnimatedBackgroundState();
}

class _HyperOSAnimatedBackgroundState extends State<HyperOSAnimatedBackground>
    with SingleTickerProviderStateMixin {
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
              center: Alignment(-1.0 + (val * 2), -0.8 + (val * 1.6)),
              radius: 1.4,
              colors: const [
                Color(0xFF5B21B6),
                Color(0xFF1E1B4B),
                Color(0xFF0F172A),
              ],
              stops: const [0.0, 0.55, 1.0],
            ),
          ),
          child: widget.child,
        );
      },
    );
  }
}

// পিন স্ক্রিন
class PasscodeLockScreen extends StatefulWidget {
  const PasscodeLockScreen({super.key});

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
        MaterialPageRoute(builder: (context) => const MainHomeScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ভুল পিন!')),
      );
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
                const Text('Enter Passcode', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _pinController,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 24, letterSpacing: 8),
                    decoration: InputDecoration(
                      hintText: 'PIN',
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.pinkAccent),
                  onPressed: _verifyPin,
                  child: const Text('Unlock'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// মেইন হোম স্ক্রিন (রিয়েলটাইম ফায়ারবেস চ্যাট ও স্টোরেজ সহ)
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  bool _isPanicMode = false;
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final User? currentUser = FirebaseAuth.instance.currentUser;

  Future<void> _sendMessage({String? imageUrl}) async {
    if (_messageController.text.trim().isEmpty && imageUrl == null) return;

    await FirebaseFirestore.instance.collection('chats').add({
      'text': _messageController.text.trim(),
      'imageUrl': imageUrl,
      'senderId': currentUser?.uid,
      'senderEmail': currentUser?.email,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
  }

  Future<void> _pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      File file = File(image.path);
      String fileName = DateTime.now().millisecondsSinceEpoch.toString();
      Reference ref = FirebaseStorage.instance.ref().child('chat_images/$fileName.jpg');
      await ref.putFile(file);
      String downloadUrl = await ref.getDownloadURL();
      _sendMessage(imageUrl: downloadUrl);
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
            decoration: InputDecoration(hintText: 'Write private notes here...', border: InputBorder.none),
          ),
        ),
      );
    }

    final pages = [
      _buildChatPage(),
      const Center(child: Text('Gallery - Cloud Syncing')),
      const RealtimeLoveCounterPage(),
      _buildSettingsPage(),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Eternal Space', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.security, color: Colors.redAccent),
            onPressed: () => setState(() => _isPanicMode = true),
          ),
        ],
      ),
      body: HyperOSAnimatedBackground(
        child: SafeArea(child: pages[_currentIndex]),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: const Color(0xFF0F172A),
        currentIndex: _currentIndex,
        selectedItemColor: Colors.pinkAccent,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.folder_special), label: 'Gallery'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: 'Journey'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildChatPage() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('chats').orderBy('timestamp', descending: true).snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              var docs = snapshot.data!.docs;

              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var data = docs[index].data() as Map<String, dynamic>;
                  bool isMe = data['senderId'] == currentUser?.uid;

                  return Align(
                    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
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
                          if (data['imageUrl'] != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.network(data['imageUrl'], height: 150, width: 200, fit: BoxFit.cover),
                            ),
                          if (data['text'] != null && data['text'].toString().isNotEmpty)
                            Text(data['text'], style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    ),
                  );
                },
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
                icon: const Icon(Icons.image, color: Colors.pinkAccent),
                onPressed: _pickAndUploadImage,
              ),
              Expanded(
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(hintText: 'Type secret message...', border: InputBorder.none),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send, color: Colors.pinkAccent),
                onPressed: () => _sendMessage(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.person, color: Colors.pinkAccent),
          title: Text(currentUser?.email ?? 'User'),
          subtitle: const Text('Logged in'),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Colors.redAccent),
          title: const Text('Logout'),
          onTap: () => FirebaseAuth.instance.signOut(),
        ),
      ],
    );
  }
}

// রিয়েল-টাইম লাভ কাউন্টার
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
          const Text('Our Endless Journey', style: TextStyle(fontSize: 22, color: Colors.white70, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTimeBox(days.toString(), 'Days'),
              _buildTimeBox(hours.toString().padLeft(2, '0'), 'Hours'),
              _buildTimeBox(minutes.toString().padLeft(2, '0'), 'Mins'),
              _buildTimeBox(seconds.toString().padLeft(2, '0'), 'Secs'),
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
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.pinkAccent)),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ],
      ),
    );
  }
}
