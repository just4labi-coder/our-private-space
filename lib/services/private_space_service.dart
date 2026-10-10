
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PrivateSpaceService {
  PrivateSpaceService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _spaceIdKey = 'eternal_space_id';
  static const String _inviteCodeKey = 'eternal_space_invite_code';

  static User? get currentUser => _auth.currentUser;

  static CollectionReference<Map<String, dynamic>> get _spaces =>
      _db.collection('privateSpaces');

  static Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  /// আগে থেকে সংরক্ষিত Space ID
  static Future<String?> getSavedSpaceId() async {
    final prefs = await _prefs;
    return prefs.getString(_spaceIdKey);
  }

  /// আগে থেকে সংরক্ষিত Invite Code
  static Future<String?> getSavedInviteCode() async {
    final prefs = await _prefs;
    return prefs.getString(_inviteCodeKey);
  }

  /// Space ID ও Invite Code ফোনে সংরক্ষণ
  static Future<void> _saveConnection(
    String spaceId,
    String inviteCode,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(_spaceIdKey, spaceId);
    await prefs.setString(_inviteCodeKey, inviteCode);
  }

  /// Firebase-এ অস্থায়ী পরিচয় তৈরি বা বর্তমান পরিচয় ব্যবহার
  static Future<User> ensureSignedIn() async {
    User? user = _auth.currentUser;

    if (user == null) {
      final result = await _auth.signInAnonymously();
      user = result.user;
    }

    if (user == null) {
      throw Exception('Firebase sign-in ব্যর্থ হয়েছে।');
    }

    return user;
  }

  /// নতুন Private Space তৈরি করে Invite Code ফেরত দেয়
  static Future<String> createSpace() async {
    final user = await ensureSignedIn();

    // আগে থেকেই Space যুক্ত থাকলে নতুন Space তৈরি করবে না।
    final savedSpaceId = await getSavedSpaceId();

    if (savedSpaceId != null && savedSpaceId.isNotEmpty) {
      final savedCode = await getSavedInviteCode();

      if (savedCode != null && savedCode.isNotEmpty) {
        final existingSpace = await _spaces.doc(savedSpaceId).get();

        if (existingSpace.exists &&
            (existingSpace.data()?['memberUids'] as List?)
                    ?.contains(user.uid) ==
                true) {
          return savedCode;
        }
      }
    }

    for (int attempt = 0; attempt < 10; attempt++) {
      final rawCode = DateTime.now()
          .microsecondsSinceEpoch
          .toRadixString(36)
          .toUpperCase();

      final code = rawCode.length >= 6
          ? rawCode.substring(rawCode.length - 6)
          : rawCode.padLeft(6, '0');

      final inviteRef = _db.collection('spaceInvites').doc(code);
      final existingInvite = await inviteRef.get();

      if (existingInvite.exists) continue;

      final spaceRef = _spaces.doc();
      final batch = _db.batch();

      batch.set(spaceRef, {
        'memberUids': [user.uid],
        'createdBy': user.uid,
        'inviteCode': code,
        'createdAt': FieldValue.serverTimestamp(),
      });

      batch.set(inviteRef, {
        'spaceId': spaceRef.id,
        'createdBy': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      await _saveConnection(spaceRef.id, code);

      return code;
    }

    throw Exception('Invite Code তৈরি করা যায়নি। আবার চেষ্টা করো।');
  }

  /// Invite Code দিয়ে অন্য ফোনকে একই Space-এ যুক্ত করে
  static Future<void> joinSpace(String inviteCode) async {
    final user = await ensureSignedIn();
    final code = inviteCode.trim().toUpperCase();

    if (code.isEmpty) {
      throw Exception('Invite Code লিখতে হবে।');
    }

    final inviteRef = _db.collection('spaceInvites').doc(code);

    final spaceId = await _db.runTransaction<String>(
      (transaction) async {
        final invite = await transaction.get(inviteRef);

        if (!invite.exists) {
          throw Exception('Invite Code সঠিক নয়।');
        }

        final inviteData = invite.data()!;
        final id = inviteData['spaceId'] as String?;
        if (id == null || id.isEmpty) {
          throw Exception('Space ID পাওয়া যায়নি।');
        }

        final spaceRef = _spaces.doc(id);
        final space = await transaction.get(spaceRef);

        if (!space.exists) {
          throw Exception('Private Space পাওয়া যায়নি।');
        }

        final spaceData = space.data()!;

        if (spaceData['inviteCode'] != code) {
          throw Exception('Invite Code মেলেনি।');
        }

        final members = List<String>.from(
          spaceData['memberUids'] ?? [],
        );

        if (members.contains(user.uid)) {
          return id;
        }

        if (members.length >= 2) {
          throw Exception(
            'এই Space-এ ইতিমধ্যে দুজন সদস্য আছে।',
          );
        }

        transaction.update(spaceRef, {
          'memberUids': FieldValue.arrayUnion([user.uid]),
        });

        return id;
      },
    );

    await _saveConnection(spaceId, code);
  }

  /// Space-এর তথ্যের পরিবর্তন শোনে
  static Stream<Map<String, dynamic>?> watchSpace(String spaceId) {
    return _spaces.doc(spaceId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return snapshot.data();
    });
  }

  /// বর্তমান ফোনের সংরক্ষিত Space সংযোগ মুছে দেয়।
  /// Firebase-এর Space বা অন্য সদস্যকে মুছে দেয় না।
  static Future<void> clearSavedConnection() async {
    final prefs = await _prefs;
    await prefs.remove(_spaceIdKey);
    await prefs.remove(_inviteCodeKey);
  }
}
