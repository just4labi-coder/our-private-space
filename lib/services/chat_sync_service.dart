import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'private_space_service.dart';

class ChatSyncService {
  ChatSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static Future<CollectionReference<Map<String, dynamic>>> _messagesRef()
      async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('আগে Partner Space-এ যুক্ত হও।');
    }

    final spaceId = await PrivateSpaceService.getSavedSpaceId();

    if (spaceId == null || spaceId.isEmpty) {
      throw Exception('Private Space পাওয়া যায়নি।');
    }

    return _db
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('chatMessages');
  }

  /// দুই ফোনের মেসেজ রিয়েল-টাইমে শোনে।
  static Stream<List<Map<String, dynamic>>> watchMessages() async* {
    final ref = await _messagesRef();

    yield* ref.orderBy('time').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return <String, dynamic>{
          ...doc.data(),
          'id': doc.id,
        };
      }).toList();
    });
  }

  /// প্রতিটি মেসেজ আলাদা Firebase document-এ সেভ করে।
  static Future<void> sendMessage(
    Map<String, dynamic> message,
  ) async {
    final ref = await _messagesRef();
    final id = '${message['id'] ?? ''}';

    if (id.isEmpty) {
      throw Exception('মেসেজ ID পাওয়া যায়নি।');
    }

    await ref.doc(id).set({
      ...message,
      'id': id,
      'senderUid': FirebaseAuth.instance.currentUser!.uid,
      'time': message['time'] ??
          DateTime.now().toIso8601String(),
    });
  }

  /// নিজের পাঠানো মেসেজ সবার জন্য Unsend করে।
  static Future<void> unsendMessage(String messageId) async {
    final ref = await _messagesRef();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('আগে Partner Space-এ যুক্ত হও।');
    }

    final docRef = ref.doc(messageId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('মেসেজটি পাওয়া যায়নি।');
    }

    final data = snapshot.data()!;

    if (data['senderUid'] != user.uid) {
      throw Exception('শুধু নিজের মেসেজ Unsend করা যাবে।');
    }

    await docRef.update({
      'unsent': true,
      'text': '',
    });
  }
}
