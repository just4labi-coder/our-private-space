import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Firebase authentication for Eternal Space.
class SpaceAuth {
  SpaceAuth._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  static Stream<User?> get authChanges => _auth.authStateChanges();

  static Future<UserCredential> createAccount({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('সঠিক ইমেইল ঠিকানা দাও।');
    }

    if (password.length < 6) {
      throw Exception('পাসওয়ার্ড কমপক্ষে ৬ অক্ষরের হতে হবে।');
    }

    return _auth.createUserWithEmailAndPassword(
      email: cleanEmail,
      password: password,
    );
  }

  static Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty || password.isEmpty) {
      throw Exception('ইমেইল ও পাসওয়ার্ড দুটোই দিতে হবে।');
    }

    return _auth.signInWithEmailAndPassword(
      email: cleanEmail,
      password: password,
    );
  }

  static Future<void> sendPasswordReset(String email) async {
    final cleanEmail = email.trim();

    if (cleanEmail.isEmpty || !cleanEmail.contains('@')) {
      throw Exception('সঠিক ইমেইল ঠিকানা দাও।');
    }

    await _auth.sendPasswordResetEmail(email: cleanEmail);
  }

  static Future<void> signOut() async {
    await _auth.signOut();
  }
}

/// Couple creation and joining.
class CoupleSpace {
  CoupleSpace._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _makeCode() {
    final random = Random.secure();

    return List.generate(
      8,
      (_) => _alphabet[random.nextInt(_alphabet.length)],
    ).join();
  }

  static String _cleanCode(String code) {
    return code.trim().toUpperCase().replaceAll(' ', '');
  }

  /// Creates a shared couple space and returns its invitation code.
  static Future<String> createSpace({
    required String displayName,
  }) async {
    final user = SpaceAuth.currentUser;

    if (user == null) {
      throw Exception('প্রথমে নিজের অ্যাকাউন্টে লগইন করো।');
    }

    final name = displayName.trim();

    if (name.isEmpty) {
      throw Exception('তোমার নাম লিখো।');
    }

    final coupleRef = _db.collection('couples').doc();
    final memberRef =
        coupleRef.collection('members').doc(user.uid);

    String code = '';
    DocumentReference<Map<String, dynamic>>? inviteRef;

    // Avoid accidentally reusing an existing invitation code.
    for (var attempt = 0; attempt < 10; attempt++) {
      final candidate = _makeCode();
      final ref = _db.collection('coupleInvites').doc(candidate);
      final existing = await ref.get();

      if (!existing.exists) {
        code = candidate;
        inviteRef = ref;
        break;
      }
    }

    if (inviteRef == null) {
      throw Exception('কোড তৈরি করা যায়নি। আবার চেষ্টা করো।');
    }

    // Create the couple first, then its owner membership.
    await coupleRef.set({
      'ownerUid': user.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'active',
    });

    try {
      await memberRef.set({
        'uid': user.uid,
        'displayName': name,
        'role': 'owner',
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await inviteRef.set({
        'coupleId': coupleRef.id,
        'ownerUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'used': false,
      });
    } catch (_) {
      // The already-created couple may need manual cleanup if a later
      // operation fails. Do not delete it automatically.
      rethrow;
    }

    return code;
  }

  /// Joins a couple using its invitation code.
  ///
  /// Note: the currently described Firestore rules do not consume the code,
  /// limit the space to two members, or prevent code sharing. See below.
  static Future<String> joinSpace({
    required String invitationCode,
    required String displayName,
  }) async {
    final user = SpaceAuth.currentUser;

    if (user == null) {
      throw Exception('প্রথমে নিজের অ্যাকাউন্টে লগইন করো।');
    }

    final code = _cleanCode(invitationCode);
    final name = displayName.trim();

    if (code.length != 8) {
      throw Exception('৮ অক্ষরের সঠিক Couple Code দাও।');
    }

    if (name.isEmpty) {
      throw Exception('তোমার নাম লিখো।');
    }

    final inviteRef = _db.collection('coupleInvites').doc(code);
    final inviteSnapshot = await inviteRef.get();

    if (!inviteSnapshot.exists) {
      throw Exception('এই Couple Code পাওয়া যায়নি।');
    }

    final invite = inviteSnapshot.data();

    if (invite == null) {
      throw Exception('কোডের তথ্য পড়া যায়নি।');
    }

    final coupleId = invite['coupleId'];

    if (coupleId is! String || coupleId.isEmpty) {
      throw Exception('এই Couple Code-এর তথ্য সঠিক নয়।');
    }

    if (invite['ownerUid'] == user.uid) {
      throw Exception('নিজের তৈরি কোড দিয়ে নিজের জায়গায় আবার যুক্ত হওয়া যাবে না।');
    }

    final memberRef = _db
        .collection('couples')
        .doc(coupleId)
        .collection('members')
        .doc(user.uid);

    // The published rules allow a signed-in user to create their own
    // membership document. Production rules should validate the invite.
    await memberRef.set({
      'uid': user.uid,
      'displayName': name,
      'role': 'partner',
      'inviteCode': code,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    return coupleId;
  }

  /// Reads the current user's couple membership.
  static Future<Map<String, dynamic>?> findMySpace() async {
    final user = SpaceAuth.currentUser;

    if (user == null) return null;

    final memberships = await _db
        .collectionGroup('members')
        .where('uid', isEqualTo: user.uid)
        .limit(1)
        .get();

    if (memberships.docs.isEmpty) return null;

    final member = memberships.docs.first;
    final parent = member.reference.parent.parent;

    if (parent == null) return null;

    return {
      'coupleId': parent.id,
      'member': member.data(),
    };
  }

  /// Saves one document in a shared collection.
  ///
  /// Examples of collectionName: chat, memories, loveNotes, specialDates.
  static Future<void> saveSharedDocument({
    required String coupleId,
    required String collectionName,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    const allowedCollections = {
      'chat',
      'memories',
      'loveNotes',
      'specialDates',
      'timeline',
      'music',
      'folders',
    };

    if (!allowedCollections.contains(collectionName)) {
      throw Exception('এই ডেটা-সংগ্রহের নাম অনুমোদিত নয়।');
    }

    await _db
        .collection('couples')
        .doc(coupleId)
        .collection(collectionName)
        .doc(documentId)
        .set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Live updates from a shared collection.
  static Stream<QuerySnapshot<Map<String, dynamic>>> watchSharedCollection({
    required String coupleId,
    required String collectionName,
  }) {
    return _db
        .collection('couples')
        .doc(coupleId)
        .collection(collectionName)
        .snapshots();
  }
}
