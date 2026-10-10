import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PrivateSpaceService {
  PrivateSpaceService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static User? get currentUser => _auth.currentUser;

  static CollectionReference<Map<String, dynamic>> get _spaces =>
      _db.collection('privateSpaces');

  /// পরীক্ষার জন্য অস্থায়ী Firebase পরিচয় তৈরি।
  /// পরে চাইলে স্থায়ী লগইনের সঙ্গে যুক্ত করা যাবে।
  static Future<User> ensureSignedIn() async {
    User? user = _auth.currentUser;

    if (user == null) {
      final result = await _auth.signInAnonymously();
      user = result.user;
    }

    if (user == null) {
      throw Exception('Firebase sign-in failed.');
    }

    return user;
  }

  /// নতুন private space তৈরি করে 6 অক্ষরের invite code দেয়।
  static Future<String> createSpace() async {
    final user = await ensureSignedIn();

    for (int attempt = 0; attempt < 5; attempt++) {
      final code =
          DateTime.now().microsecondsSinceEpoch
              .toRadixString(36)
              .toUpperCase()
              .substring(0, 6);

      final existing = await _db
          .collection('spaceInvites')
          .doc(code)
          .get();

      if (existing.exists) continue;

      final spaceRef = _spaces.doc();

      final batch = _db.batch();

      batch.set(spaceRef, {
        'memberUids': [user.uid],
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(_db.collection('spaceInvites').doc(code), {
        'spaceId': spaceRef.id,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      return code;
    }

    throw Exception('Invite code তৈরি করা যায়নি। আবার চেষ্টা করো।');
  }

  /// অন্য ফোনে invite code দিয়ে একই space-এ যোগ দেয়।
  static Future<void> joinSpace(String inviteCode) async {
    final user = await ensureSignedIn();
    final code = inviteCode.trim().toUpperCase();

    if (code.isEmpty) {
      throw Exception('Invite code লিখতে হবে।');
    }

    final inviteRef = _db.collection('spaceInvites').doc(code);
    final spaceId = await _db.runTransaction<String>((transaction) async {
      final invite = await transaction.get(inviteRef);

      if (!invite.exists) {
        throw Exception('Invite code সঠিক নয়।');
      }

      final data = invite.data()!;
      final id = data['spaceId'] as String;
      final spaceRef = _spaces.doc(id);
      final space = await transaction.get(spaceRef);

      if (!space.exists) {
        throw Exception('Private space পাওয়া যায়নি।');
      }

      final members = List<String>.from(
        space.data()?['memberUids'] ?? [],
      );

      if (members.contains(user.uid)) return id;

      if (members.length >= 2) {
        throw Exception('এই space-এ ইতিমধ্যে দুইজন সদস্য আছে।');
      }

      transaction.update(spaceRef, {
        'memberUids': FieldValue.arrayUnion([user.uid]),
      });

      return id;
    });

    // এই ID পরে অ্যাপের shared profile-এ সংরক্ষণ করতে হবে।
    await user.getIdToken();
    // Returning successfully means the join transaction completed.
    assert(spaceId.isNotEmpty);
  }

  /// Space-এর সদস্যদের পরিবর্তন শোনে।
  static Stream<Map<String, dynamic>?> watchSpace(String spaceId) {
    return _spaces.doc(spaceId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return snapshot.data();
    });
  }
}
