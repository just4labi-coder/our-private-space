
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'private_space_service.dart';

class ChatSyncService {
  ChatSyncService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  // --------------------------------------------------
  // PRIVATE SPACE VALIDATION
  // --------------------------------------------------

  static Future<String> _getConnectedSpaceId() async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('আগে অ্যাকাউন্টে সাইন ইন করো।');
    }

    final spaceId = await PrivateSpaceService.getSavedSpaceId();

    if (spaceId == null || spaceId.isEmpty) {
      throw Exception(
        'আগে Partner Connection তৈরি করো।',
      );
    }

    final snapshot =
        await _db.collection('privateSpaces').doc(spaceId).get();

    if (!snapshot.exists) {
      throw Exception('Private Space পাওয়া যায়নি।');
    }

    final data = snapshot.data();

    if (data == null) {
      throw Exception('Private Space-এর তথ্য পাওয়া যায়নি।');
    }

    final members = List<String>.from(
      data['memberUids'] ?? [],
    );

    if (members.length != 2 || !members.contains(user.uid)) {
      throw Exception(
        'তোমাদের দুজনের Partner Connection সম্পূর্ণ হয়নি।',
      );
    }

    if ((data['connectionStatus'] ?? 'connected') != 'connected') {
      throw Exception('Partner Connection বর্তমানে বিচ্ছিন্ন।');
    }

    return spaceId;
  }

  static Future<CollectionReference<Map<String, dynamic>>>
      _messagesRef() async {
    final spaceId = await _getConnectedSpaceId();

    return _db
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('chatMessages');
  }

  static Future<CollectionReference<Map<String, dynamic>>>
      _membersRef() async {
    final spaceId = await _getConnectedSpaceId();

    return _db
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('members');
  }

  static Future<CollectionReference<Map<String, dynamic>>>
      _presenceRef() async {
    final spaceId = await _getConnectedSpaceId();

    return _db
        .collection('privateSpaces')
        .doc(spaceId)
        .collection('presence');
  }

  // --------------------------------------------------
  // CHAT MESSAGES
  // --------------------------------------------------

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

  /// একটি মেসেজ Firebase-এ সংরক্ষণ করে।
  static Future<void> sendMessage(
    Map<String, dynamic> message,
  ) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('আগে সাইন ইন করো।');
    }

    final id = '${message['id'] ?? ''}'.trim();

    if (id.isEmpty) {
      throw Exception('মেসেজ ID পাওয়া যায়নি।');
    }

    final ref = await _messagesRef();

    await ref.doc(id).set({
      ...message,
      'id': id,
      'senderUid': user.uid,
      'time': message['time'] ??
          DateTime.now().toUtc().toIso8601String(),
      'unsent': false,
    });
  }

  /// নিজের পাঠানো মেসেজ সবার জন্য Unsend করে।
  static Future<void> unsendMessage(String messageId) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('আগে সাইন ইন করো।');
    }

    if (messageId.trim().isEmpty) {
      throw Exception('মেসেজ ID পাওয়া যায়নি।');
    }

    final ref = await _messagesRef();
    final docRef = ref.doc(messageId);
    final snapshot = await docRef.get();

    if (!snapshot.exists) {
      throw Exception('মেসেজটি পাওয়া যায়নি।');
    }

    final data = snapshot.data();

    if (data == null || data['senderUid'] != user.uid) {
      throw Exception('শুধু নিজের পাঠানো মেসেজ Unsend করা যাবে।');
    }

    if (data['unsent'] == true) return;

    await docRef.update({
      'unsent': true,
      'text': '',
      'unsentAt': FieldValue.serverTimestamp(),
    });
  }

  // --------------------------------------------------
  // MEMBER PROFILE
  // --------------------------------------------------

  /// Space-এর সদস্যদের প্রোফাইল পরিবর্তন রিয়েল-টাইমে শোনে।
  static Stream<List<Map<String, dynamic>>> watchMemberProfiles() async* {
    final ref = await _membersRef();

    yield* ref.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return <String, dynamic>{
          ...doc.data(),
          'uid': doc.id,
        };
      }).toList();
    });
  }

  /// নিজের নাম ও প্রোফাইল ছবির URL সংরক্ষণ করে।
  ///
  /// photoUrl না দিলে আগের সংরক্ষিত ছবি মুছে যাবে না।
  static Future<void> saveMyProfile({
    required String name,
    String? photoUrl,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('আগে সাইন ইন করো।');
    }

    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw Exception('নিজের নাম লিখতে হবে।');
    }

    final ref = await _membersRef();
    final profileRef = ref.doc(user.uid);

    final profile = <String, dynamic>{
      'uid': user.uid,
      'name': cleanName,
      'email': user.email ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final cleanPhotoUrl = photoUrl?.trim();

    if (cleanPhotoUrl != null && cleanPhotoUrl.isNotEmpty) {
      profile['photoUrl'] = cleanPhotoUrl;
    } else if (user.photoURL != null &&
        user.photoURL!.trim().isNotEmpty) {
      profile['photoUrl'] = user.photoURL!.trim();
    }

    await profileRef.set(
      profile,
      SetOptions(merge: true),
    );
  }

  // --------------------------------------------------
  // ONLINE / OFFLINE PRESENCE
  // --------------------------------------------------

  /// নিজের Online / Offline অবস্থা ও সর্বশেষ সক্রিয় সময় সংরক্ষণ করে।
  static Future<void> setPresence({
    required bool isOnline,
  }) async {
    final user = _auth.currentUser;

    if (user == null) return;

    final ref = await _presenceRef();

    await ref.doc(user.uid).set({
      'uid': user.uid,
      'isOnline': isOnline,
      'lastSeen': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// নির্দিষ্ট সদস্যের Online / Offline অবস্থা শোনে।
  static Stream<Map<String, dynamic>?> watchPresence(
    String uid,
  ) async* {
    if (uid.trim().isEmpty) {
      yield null;
      return;
    }

    final ref = await _presenceRef();

    yield* ref.doc(uid).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;

      return snapshot.data();
    });
  }
}
