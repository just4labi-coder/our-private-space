import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'private_space_service.dart';

/// Eternal Space-এর দুই ফোনে একই Private Space-এর
/// তথ্য সংরক্ষণ ও রিয়েল-টাইমে পড়ার সার্ভিস।
class SharedSpaceDataService {
  SharedSpaceDataService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  /// বর্তমান ফোনে সংরক্ষিত Space ID ফেরত দেয়।
  static Future<String?> get spaceId async {
    final id = await PrivateSpaceService.getSavedSpaceId();

    if (id == null || id.trim().isEmpty) {
      return null;
    }

    return id.trim();
  }

  /// বর্তমান ব্যবহারকারীর প্রোফাইলের রেফারেন্স।
  static DocumentReference<Map<String, dynamic>> get myProfileRef {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('আগে Firebase-এ সাইন ইন করতে হবে।');
    }

    return _db.collection('users').doc(user.uid);
  }

  /// প্রথমবার নাম সংরক্ষণ বা নিজের নাম পরিবর্তন।
  static Future<void> saveMyProfile({
    required String name,
  }) async {
    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('নাম খালি রাখা যাবে না।');
    }

    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('Firebase ব্যবহারকারী পাওয়া যায়নি।');
    }

    await myProfileRef.set({
      'uid': user.uid,
      'name': cleanName,
      'email': user.email,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('myProfileName', cleanName);
  }

  /// নিজের প্রোফাইলের পরিবর্তন রিয়েল-টাইমে শোনে।
  static Stream<Map<String, dynamic>?> watchMyProfile() {
    return myProfileRef.snapshots().map((snapshot) {
      return snapshot.data();
    });
  }

  /// Space-এর ভেতরের নির্দিষ্ট কালেকশন।
  /// উদাহরণ: loveNotes, specialDates, complaints, messages।
  static Future<CollectionReference<Map<String, dynamic>>>
      collection(String collectionName) async {
    final id = await spaceId;

    if (id == null) {
      throw StateError(
        'আগে Partner Connection থেকে Private Space তৈরি '
        'অথবা Join করতে হবে।',
      );
    }

    const allowedCollections = <String>{
      'loveNotes',
      'specialDates',
      'complaints',
      'messages',
      'galleryItems',
      'galleryFolders',
      'trash',
    };

    if (!allowedCollections.contains(collectionName)) {
      throw ArgumentError('এই collection অনুমোদিত নয়।');
    }

    return _db
        .collection('privateSpaces')
        .doc(id)
        .collection(collectionName);
  }

  /// একটি নতুন রেকর্ড যোগ বা একই ID-র রেকর্ড আপডেট।
  static Future<void> saveRecord({
    required String collectionName,
    required String id,
    required Map<String, dynamic> data,
  }) async {
    final user = _auth.currentUser;

    if (user == null) {
      throw StateError('আগে Firebase-এ সাইন ইন করতে হবে।');
    }

    final ref = await collection(collectionName);

    await ref.doc(id).set({
      ...data,
      'id': id,
      'createdByUid': user.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// রেকর্ডের পরিবর্তন রিয়েল-টাইমে শোনে।
  static Future<Stream<List<Map<String, dynamic>>>> watchRecords({
    required String collectionName,
  }) async {
    final ref = await collection(collectionName);

    return ref.snapshots().map((snapshot) {
      final records = snapshot.docs.map((doc) {
        return <String, dynamic>{
          ...doc.data(),
          'id': doc.id,
        };
      }).toList();

      records.sort((a, b) {
        final aTime = a['createdAt'];
        final bTime = b['createdAt'];

        final aDate = aTime is Timestamp
            ? aTime.toDate()
            : DateTime.tryParse('$aTime') ?? DateTime(2000);

        final bDate = bTime is Timestamp
            ? bTime.toDate()
            : DateTime.tryParse('$bTime') ?? DateTime(2000);

        return bDate.compareTo(aDate);
      });

      return records;
    });
  }

  /// একটি রেকর্ড মুছে দেয়।
  static Future<void> deleteRecord({
    required String collectionName,
    required String id,
  }) async {
    final ref = await collection(collectionName);
    await ref.doc(id).delete();
  }
}
