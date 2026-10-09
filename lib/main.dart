import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:video_player/video_player.dart';

const Color backgroundColor = Color(0xFF080B20);
const Color surfaceColor = Color(0xFF141936);
const Color blueColor = Color(0xFF5577FF);
const Color pinkColor = Color(0xFFFF5FA2);
const Color purpleColor = Color(0xFF9A70FF);

final FlutterLocalNotificationsPlugin notifications =
FlutterLocalNotificationsPlugin();

Future<void> main() async {
WidgetsFlutterBinding.ensureInitialized();

tz_data.initializeTimeZones();

const androidSettings =
AndroidInitializationSettings('@android:drawable/sym_def_app_icon');

const initializationSettings =
InitializationSettings(android: androidSettings);

await notifications.initialize(initializationSettings);

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
scaffoldBackgroundColor: backgroundColor,
colorScheme: ColorScheme.fromSeed(
seedColor: blueColor,
brightness: Brightness.dark,
),
useMaterial3: true,
inputDecorationTheme: InputDecorationTheme(
filled: true,
fillColor: Colors.white.withOpacity(0.055),
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

class SpaceStore {
static SharedPreferences? _prefs;

static Future<void> init() async {
_prefs = await SharedPreferences.getInstance();
}

static List<Map<String, dynamic>> readList(String key) {
final raw = _prefs?.getString(key);
if (raw == null) return [];

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
await _prefs?.setString(key, jsonEncode(value));
}

static String readString(String key, [String fallback = '']) {
return _prefs?.getString(key) ?? fallback;
}

static Future<void> saveString(String key, String value) async {
await _prefs?.setString(key, value);
}
}

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

Navigator.pushReplacement(  
  context,  
  MaterialPageRoute(builder: (_) => const MainScreen()),  
);

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
Color(0xFF090D27),
Color(0xFF17133D),
Color(0xFF250F35),
Color(0xFF090D27),
],
),
),
child: Stack(
children: [
Positioned(
top: -130,
left: -100,
child: _glow(300, blueColor.withOpacity(0.14)),
),
Positioned(
bottom: -150,
right: -100,
child: _glow(320, pinkColor.withOpacity(0.12)),
),
Positioned(
top: 250,
right: -160,
child: _glow(280, purpleColor.withOpacity(0.10)),
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
colors: [color, color.withOpacity(0)],
),
),
),
);
}
}

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
    backgroundColor: const Color(0xFF10142D),  
    indicatorColor: blueColor.withOpacity(0.25),  
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
const Icon(Icons.favorite_rounded, color: pinkColor, size: 28),
],
),
const SizedBox(height: 26),
_CoupleCard(first: partnerOne, second: partnerTwo),
const SizedBox(height: 18),
const LoveCounterCard(),
const SizedBox(height: 26),
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
icon: Icons.chat_bubble_rounded,
title: 'Private Chat',
subtitle: 'Just between us',
color: blueColor,
onTap: () => onNavigate(1),
),
FeatureCard(
icon: Icons.photo_library_rounded,
title: 'Memories',
subtitle: 'Photos and videos',
color: pinkColor,
onTap: () => onNavigate(2),
),
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
FeatureCard(
icon: Icons.music_note_rounded,
title: 'Our Music',
subtitle: 'Songs that mean us',
color: blueColor,
onTap: () => _open(context, const OurMusicPage()),
),
FeatureCard(
icon: Icons.card_giftcard_rounded,
title: 'Surprise',
subtitle: 'A little something',
color: purpleColor,
onTap: () => _open(context, const SurprisePage()),
),
FeatureCard(
icon: Icons.timeline_rounded,
title: 'Relationship Timeline',
subtitle: 'Our story so far',
color: pinkColor,
onTap: () => _open(context, const TimelinePage()),
),
],
),
],
);
}

void open(BuildContext context, Widget page) {
Navigator.push(context, MaterialPageRoute(builder: () => page));
}
}

class _CoupleCard extends StatelessWidget {
final String first;
final String second;

const _CoupleCard({required this.first, required this.second});

@override
Widget build(BuildContext context) {
return Container(
padding: const EdgeInsets.all(20),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(25),
gradient: LinearGradient(
colors: [
blueColor.withOpacity(0.22),
pinkColor.withOpacity(0.16),
],
),
border: Border.all(color: Colors.white.withOpacity(0.09)),
),
child: Row(
children: [
_AvatarLetter(name: first, color: blueColor),
const Padding(
padding: EdgeInsets.symmetric(horizontal: 13),
child: Icon(Icons.favorite_rounded, color: pinkColor, size: 27),
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

const _AvatarLetter({required this.name, required this.color});

@override
Widget build(BuildContext context) {
return CircleAvatar(
radius: 25,
backgroundColor: color.withOpacity(0.23),
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
    color: surfaceColor.withOpacity(0.86),  
    border: Border.all(color: pinkColor.withOpacity(0.25)),  
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

const _TimePart({required this.value, required this.label});

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

class SectionHeading extends StatelessWidget {
final String title;

const SectionHeading({super.key, required this.title});

@override
Widget build(BuildContext context) {
return Text(
title,
style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
color: surfaceColor.withOpacity(0.82),
borderRadius: BorderRadius.circular(21),
child: InkWell(
onTap: onTap,
borderRadius: BorderRadius.circular(21),
child: Container(
padding: const EdgeInsets.all(15),
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(21),
border: Border.all(color: Colors.white.withOpacity(0.055)),
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
style: const TextStyle(fontSize: 10, color: Colors.white54),
),
],
),
),
),
);
}
}

class ChatPage extends StatefulWidget {
const ChatPage({super.key});

@override
State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
final TextEditingController controller = TextEditingController();
final ScrollController scrollController = ScrollController();
List<Map<String, dynamic>> messages = [];

@override
void initState() {
super.initState();
messages = SpaceStore.readList('chatMessages');
}

@override
void dispose() {
controller.dispose();
scrollController.dispose();
super.dispose();
}

Future<void> _save() => SpaceStore.saveList('chatMessages', messages);

Future<void> _sendText() async {
final text = controller.text.trim();
if (text.isEmpty) return;

setState(() {  
  messages.add({  
    'id': DateTime.now().microsecondsSinceEpoch.toString(),  
    'text': text,  
    'type': 'text',  
    'mine': true,  
    'unsent': false,  
    'time': DateTime.now().toIso8601String(),  
  });  
  controller.clear();  
});  

await _save();  
_scrollToBottom();

}

Future<void> _sendMedia(bool video) async {
final picker = ImagePicker();
final file = video
? await picker.pickVideo(source: ImageSource.gallery)
: await picker.pickImage(source: ImageSource.gallery);

if (file == null || !mounted) return;  

setState(() {  
  messages.add({  
    'id': DateTime.now().microsecondsSinceEpoch.toString(),  
    'text': file.path,  
    'type': video ? 'video' : 'image',  
    'mine': true,  
    'unsent': false,  
    'time': DateTime.now().toIso8601String(),  
  });  
});  

await _save();  
_scrollToBottom();

}

void scrollToBottom() {
WidgetsBinding.instance.addPostFrameCallback(() {
if (scrollController.hasClients) {
scrollController.animateTo(
scrollController.position.maxScrollExtent,
duration: const Duration(milliseconds: 250),
curve: Curves.easeOut,
);
}
});
}

Future<void> _showMessageOptions(int index) async {
final message = messages[index];
final mine = message['mine'] == true;
final unsent = message['unsent'] == true;

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
            _showDetails(message);  
          },  
        ),  
        if (mine && !unsent)  
          ListTile(  
            leading: const Icon(Icons.remove_circle_outline),  
            title: const Text('Unsend'),  
            onTap: () async {  
              Navigator.pop(sheetContext);  
              setState(() {  
                messages[index]['unsent'] = true;  
                messages[index]['text'] = '';  
              });  
              await _save();  
            },  
          ),  
      ],  
    ),  
  ),  
);

}

void showDetails(Map<String, dynamic> message) {
final date = DateTime.tryParse('${message['time'] ?? ''}');
showDialog<void>(
context: context,
builder: () => AlertDialog(
backgroundColor: surfaceColor,
title: const Text('Message details'),
content: Text(
'Type: ${message['type'] ?? 'text'}\n'
'Sender: ${message['mine'] == true ? 'You' : 'Partner'}\n'
'Time: ${date?.toLocal().toString() ?? 'Unknown'}',
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Close'),
),
],
),
);
}

@override
Widget build(BuildContext context) {
return Column(
children: [
const Padding(
padding: EdgeInsets.fromLTRB(20, 16, 20, 14),
child: Row(
children: [
Icon(Icons.favorite_rounded, color: pinkColor, size: 25),
SizedBox(width: 12),
Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'Private Chat',
style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
),
Text(
'A little space just for us',
style: TextStyle(fontSize: 11, color: Colors.white54),
),
],
),
],
),
),
Expanded(
child: messages.isEmpty
? const Center(
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
Icon(Icons.forum_outlined, size: 44, color: Colors.white30),
SizedBox(height: 12),
Text('Your story starts with a message',
style: TextStyle(color: Colors.white54)),
],
),
)
: ListView.builder(
controller: scrollController,
padding: const EdgeInsets.symmetric(horizontal: 16),
itemCount: messages.length,
itemBuilder: (context, index) {
final message = messages[index];
final mine = message['mine'] == true;
return GestureDetector(
onLongPress: () => _showMessageOptions(index),
child: Align(
alignment:
mine ? Alignment.centerRight : Alignment.centerLeft,
child: Container(
constraints: BoxConstraints(
maxWidth: MediaQuery.sizeOf(context).width * 0.76,
),
margin: const EdgeInsets.symmetric(vertical: 5),
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: mine
? blueColor.withOpacity(0.25)
: surfaceColor,
borderRadius: BorderRadius.circular(18),
),
child: _messageContent(message),
),
),
);
},
),
),
SafeArea(
top: false,
child: Padding(
padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
child: Row(
children: [
IconButton(
onPressed: () => _sendMedia(false),
icon: const Icon(Icons.image_outlined, color: pinkColor),
),
IconButton(
onPressed: () => sendMedia(true),
icon: const Icon(Icons.videocam_outlined, color: purpleColor),
),
Expanded(
child: TextField(
controller: controller,
textCapitalization: TextCapitalization.sentences,
onSubmitted: () => _sendText(),
decoration: const InputDecoration(
hintText: 'Write a message...',
contentPadding:
EdgeInsets.symmetric(horizontal: 16, vertical: 12),
),
),
),
const SizedBox(width: 6),
IconButton.filled(
onPressed: _sendText,
icon: const Icon(Icons.send_rounded),
),
],
),
),
),
],
);
}

Widget _messageContent(Map<String, dynamic> message) {
if (message['unsent'] == true) {
return const Text(
'Unsent',
style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
);
}

final type = message['type'];  
final path = '${message['text'] ?? ''}';  

if (type == 'image') {  
  return GestureDetector(  
    onTap: () => Navigator.push(  
      context,  
      MaterialPageRoute(builder: (_) => ImageViewerPage(path: path)),  
    ),  
    child: Image.file(  
      File(path),  
      width: 210,  
      height: 210,  
      fit: BoxFit.cover,  
      errorBuilder: (_, __, ___) =>  
          const Text('Image is no longer available'),  
    ),  
  );  
}  

if (type == 'video') {  
  return GestureDetector(  
    onTap: () => Navigator.push(  
      context,  
      MaterialPageRoute(builder: (_) => VideoViewerPage(path: path)),  
    ),  
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
          Icon(Icons.play_circle_fill_rounded, size: 45),  
          SizedBox(height: 6),  
          Text('Play video'),  
        ],  
      ),  
    ),  
  );  
}  

return Text('$path', style: const TextStyle(fontSize: 15));

}
}

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
builder: (context) => AlertDialog(
backgroundColor: surfaceColor,
title: const Text('New folder'),
content: TextField(
controller: controller,
autofocus: true,
decoration: const InputDecoration(hintText: 'Folder name'),
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Cancel'),
),
FilledButton(
onPressed: () => Navigator.pop(context, controller.text.trim()),
child: const Text('Create'),
),
],
),
);

if (name == null || name.isEmpty) return;  

setState(() {  
  folders.add({  
    'id': DateTime.now().microsecondsSinceEpoch.toString(),  
    'name': name,  
  });  
});  
await _save();

}

Future<void> _addMedia(String folderId, bool video) async {
final picker = ImagePicker();
final picked = video
? await picker.pickVideo(source: ImageSource.gallery)
: await picker.pickImage(source: ImageSource.gallery);

if (picked == null) return;  

setState(() {  
  media.add({  
    'id': DateTime.now().microsecondsSinceEpoch.toString(),  
    'path': picked.path,  
    'type': video ? 'video' : 'image',  
    'folderId': folderId,  
    'createdAt': DateTime.now().toIso8601String(),  
  });  
});  
await _save();

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
leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
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

void showMediaDetails(Map<String, dynamic> item) {
showDialog<void>(
context: context,
builder: () => AlertDialog(
backgroundColor: surfaceColor,
title: const Text('Memory details'),
content: Text(
'Type: ${item['type']}\n'
'Added: ${item['createdAt'] ?? 'Unknown'}\n'
'Folder: ${_folderName('${item['folderId']}')}',
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
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
      initialItems: media.where((m) => m['folderId'] == id).toList(),  
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
style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
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
final count =
media.where((m) => m['folderId'] == folder['id']).length;

return Material(  
          color: surfaceColor,  
          borderRadius: BorderRadius.circular(20),  
          child: InkWell(  
            borderRadius: BorderRadius.circular(20),  
            onTap: () => _openFolder(folder),  
            child: Padding(  
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
                    style: const TextStyle(fontWeight: FontWeight.bold),  
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
final Future<void> Function(bool video) onAdd;
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
items = List.from(widget.initialItems);
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
onPressed: () => _chooseAddType(),
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
                        errorBuilder: (_, __, ___) => const ColoredBox(  
                          color: surfaceColor,  
                          child: Icon(Icons.broken_image_outlined),  
                        ),  
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
builder: (context) => SafeArea(
child: Wrap(
children: [
ListTile(
leading: const Icon(Icons.image_outlined),
title: const Text('Add image'),
onTap: () => Navigator.pop(context, false),
),
ListTile(
leading: const Icon(Icons.video_library_outlined),
title: const Text('Add video'),
onTap: () => Navigator.pop(context, true),
),
],
),
),
);

if (video != null) {  
  await widget.onAdd(video);  
  if (mounted) setState(() {});  
}

}
}

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
errorBuilder: (_, __, ___) =>
const Text('Image is no longer available'),
),
),
),
);
}
}

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

Future<void> initialize() async {
try {
final video = VideoPlayerController.file(File(widget.path));
await video.initialize();
if (!mounted) {
await video.dispose();
return;
}
setState(() => controller = video);
await video.play();
} catch () {
if (mounted) setState(() => error = 'Unable to open this video.');
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
setState(() {
controller!.value.isPlaying
? controller!.pause()
: controller!.play();
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

Future<void> _save() => SpaceStore.saveList('specialDates', dates);

Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
final titleController =
TextEditingController(text: '${existing?['title'] ?? ''}');
final noteController =
TextEditingController(text: '${existing?['note'] ?? ''}');

DateTime selectedDate = DateTime.tryParse(  
      '${existing?['date'] ?? ''}',  
    ) ??  
    DateTime.now();  

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
              onChanged: (value) =>  
                  setDialogState(() => yearly = value ?? true),  
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

if (result == null) return;  

final id = '${existing?['id'] ?? DateTime.now().microsecondsSinceEpoch}';  
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
final yearly = !item.containsKey('yearly') || item['yearly'] == true;  

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
setState(() => dates.removeWhere((d) => d['id'] == item['id']));
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

            return Container(  
              margin: const EdgeInsets.only(bottom: 12),  
              decoration: BoxDecoration(  
                color: surfaceColor,  
                borderRadius: BorderRadius.circular(18),  
              ),  
              child: ListTile(  
                leading: const CircleAvatar(  
                  backgroundColor: Color(0x33FF5FA2),  
                  child: Icon(Icons.favorite_rounded, color: pinkColor),  
                ),  
                title: Text('${item['title']}'),  
                subtitle: Text(  
                  '${date?.day}/${date?.month}/${date?.year}'  
                  '${item['yearly'] == true ? ' • Every year' : ''}'  
                  '${'${item['note'] ?? ''}'.isNotEmpty ? '\n${item['note']}' : ''}',  
                ),  
                isThreeLine: '${item['note'] ?? ''}'.isNotEmpty,  
                trailing: PopupMenuButton<String>(  
                  onSelected: (value) {  
                    if (value == 'edit') {  
                      _addOrEdit(existing: item);  
                    } else if (value == 'delete') {  
                      _delete(item);  
                    }  
                  },  
                  itemBuilder: (_) => const [  
                    PopupMenuItem(value: 'edit', child: Text('Edit')),  
                    PopupMenuItem(value: 'delete', child: Text('Delete')),  
                  ],  
                ),  
              ),  
            );  
          },  
        ),  
);

}
}

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
  builder: (context) => AlertDialog(  
    backgroundColor: surfaceColor,  
    title: const Text('Write a love note'),  
    content: TextField(  
      controller: controller,  
      autofocus: true,  
      maxLines: 5,  
      decoration: const InputDecoration(hintText: 'Write from your heart...'),  
    ),  
    actions: [  
      TextButton(  
        onPressed: () => Navigator.pop(context),  
        child: const Text('Cancel'),  
      ),  
      FilledButton(  
        onPressed: () => Navigator.pop(context, controller.text.trim()),  
        child: const Text('Save'),  
      ),  
    ],  
  ),  
);  

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
border: Border.all(color: pinkColor.withOpacity(0.14)),
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

class OurMusicPage extends StatefulWidget {
const OurMusicPage({super.key});

@override
State<OurMusicPage> createState() => _OurMusicPageState();
}

class _OurMusicPageState extends State<OurMusicPage> {
List<Map<String, dynamic>> songs = [];

@override
void initState() {
super.initState();
songs = SpaceStore.readList('ourMusic');
}

Future<void> _addSong() async {
final titleController = TextEditingController();
final artistController = TextEditingController();

final result = await showDialog<Map<String, String>>(  
  context: context,  
  builder: (context) => AlertDialog(  
    backgroundColor: surfaceColor,  
    title: const Text('Add a song'),  
    content: Column(  
      mainAxisSize: MainAxisSize.min,  
      children: [  
        TextField(  
          controller: titleController,  
          decoration: const InputDecoration(labelText: 'Song title'),  
        ),  
        const SizedBox(height: 10),  
        TextField(  
          controller: artistController,  
          decoration: const InputDecoration(labelText: 'Artist'),  
        ),  
      ],  
    ),  
    actions: [  
      TextButton(  
        onPressed: () => Navigator.pop(context),  
        child: const Text('Cancel'),  
      ),  
      FilledButton(  
        onPressed: () => Navigator.pop(context, {  
          'title': titleController.text.trim(),  
          'artist': artistController.text.trim(),  
        }),  
        child: const Text('Save'),  
      ),  
    ],  
  ),  
);  

if (result == null || result['title']!.isEmpty) return;  

setState(() {  
  songs.add({  
    'id': DateTime.now().microsecondsSinceEpoch.toString(),  
    ...result,  
  });  
});  
await SpaceStore.saveList('ourMusic', songs);

}

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: backgroundColor,
appBar: AppBar(
backgroundColor: backgroundColor,
title: const Text('Our Music'),
),
floatingActionButton: FloatingActionButton(
onPressed: _addSong,
child: const Icon(Icons.add),
),
body: songs.isEmpty
? const Center(
child: Text(
'Add songs that remind you of each other.',
style: TextStyle(color: Colors.white54),
textAlign: TextAlign.center,
),
)
: ListView.builder(
padding: const EdgeInsets.all(16),
itemCount: songs.length,
itemBuilder: (context, index) => Card(
color: surfaceColor,
child: ListTile(
leading: const CircleAvatar(
backgroundColor: Color(0x335577FF),
child: Icon(Icons.music_note_rounded, color: blueColor),
),
title: Text('${songs[index]['title']}'),
subtitle: Text('${songs[index]['artist'] ?? ''}'),
trailing: IconButton(
onPressed: () async {
setState(() => songs.removeAt(index));
await SpaceStore.saveList('ourMusic', songs);
},
icon: const Icon(Icons.delete_outline),
),
),
),
),
);
}
}

class SurprisePage extends StatelessWidget {
const SurprisePage({super.key});

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: backgroundColor,
appBar: AppBar(
backgroundColor: backgroundColor,
title: const Text('A Little Surprise'),
),
body: Center(
child: Padding(
padding: const EdgeInsets.all(28),
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
const Icon(Icons.card_giftcard_rounded,
size: 82, color: pinkColor),
const SizedBox(height: 25),
const Text(
'You are my favorite part of every day.',
textAlign: TextAlign.center,
style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold),
),
const SizedBox(height: 14),
const Text(
'No matter how ordinary a day feels, you make it special.',
textAlign: TextAlign.center,
style: TextStyle(color: Colors.white60, height: 1.6),
),
const SizedBox(height: 30),
FilledButton.icon(
onPressed: () {
showDialog<void>(
context: context,
builder: (_) => AlertDialog(
backgroundColor: surfaceColor,
title: const Text('One little promise 💗'),
content: const Text(
'Let us keep choosing kindness, honesty, and each other.',
),
actions: [
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text('Always'),
),
],
),
);
},
icon: const Icon(Icons.favorite),
label: const Text('Open your surprise'),
),
],
),
),
),
);
}
}

class TimelinePage extends StatefulWidget {
const TimelinePage({super.key});

@override
State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> {
List<Map<String, dynamic>> events = [];

@override
void initState() {
super.initState();
events = SpaceStore.readList('relationshipTimeline');
}

Future<void> _addEvent() async {
final titleController = TextEditingController();
final detailController = TextEditingController();

final result = await showDialog<Map<String, String>>(  
  context: context,  
  builder: (context) => AlertDialog(  
    backgroundColor: surfaceColor,  
    title: const Text('Add to our story'),  
    content: Column(  
      mainAxisSize: MainAxisSize.min,  
      children: [  
        TextField(  
          controller: titleController,  
          decoration: const InputDecoration(labelText: 'Event'),  
        ),  
        const SizedBox(height: 10),  
        TextField(  
          controller: detailController,  
          maxLines: 3,  
          decoration: const InputDecoration(labelText: 'Memory'),  
        ),  
      ],  
    ),  
    actions: [  
      TextButton(  
        onPressed: () => Navigator.pop(context),  
        child: const Text('Cancel'),  
      ),  
      FilledButton(  
        onPressed: () => Navigator.pop(context, {  
          'title': titleController.text.trim(),  
          'detail': detailController.text.trim(),  
        }),  
        child: const Text('Save'),  
      ),  
    ],  
  ),  
);  

if (result == null || result['title']!.isEmpty) return;  

setState(() {  
  events.insert(0, {  
    'id': DateTime.now().microsecondsSinceEpoch.toString(),  
    ...result,  
    'date': DateTime.now().toIso8601String(),  
  });  
});  
await SpaceStore.saveList('relationshipTimeline', events);

}

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: backgroundColor,
appBar: AppBar(
backgroundColor: backgroundColor,
title: const Text('Our Story'),
),
floatingActionButton: FloatingActionButton(
onPressed: _addEvent,
child: const Icon(Icons.add),
),
body: events.isEmpty
? const Center(
child: Text(
'Add the moments that shaped your story.',
style: TextStyle(color: Colors.white54),
),
)
: ListView.builder(
padding: const EdgeInsets.all(20),
itemCount: events.length,
itemBuilder: (context, index) {
final event = events[index];
return Padding(
padding: const EdgeInsets.only(bottom: 20),
child: Row(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Icon(Icons.favorite, color: pinkColor),
const SizedBox(width: 14),
Expanded(
child: Container(
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: surfaceColor,
borderRadius: BorderRadius.circular(18),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
'${event['title']}',
style: const TextStyle(
fontWeight: FontWeight.bold,
fontSize: 16,
),
),
if ('${event['detail'] ?? ''}'.isNotEmpty) ...[
const SizedBox(height: 8),
Text(
'${event['detail']}',
style: const TextStyle(
color: Colors.white70,
height: 1.5,
),
),
],
const SizedBox(height: 8),
Text(
'${event['date'] ?? ''}'.split('T').first,
style: const TextStyle(
color: Colors.white38,
fontSize: 11,
),
),
Align(
alignment: Alignment.centerRight,
child: IconButton(
onPressed: () async {
setState(() => events.removeAt(index));
await SpaceStore.saveList(
'relationshipTimeline',
events,
);
},
icon: const Icon(
Icons.delete_outline,
size: 19,
),
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
firstController.text = widget.partnerOne;
secondController.text = widget.partnerTwo;
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

if (first.isEmpty || second.isEmpty) return;  

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
'Not connected yet. Real two-device sync needs Firebase setup.',
),
),
),
const Card(
color: surfaceColor,
child: ListTile(
leading: Icon(Icons.notifications_active_outlined, color: pinkColor),
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
