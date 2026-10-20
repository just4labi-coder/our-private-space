import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

  /// এই ফোনে সংরক্ষিত নিজের নাম ফেরত দেয়।
  static Future<String> _getOwnName() async {
    final prefs = await _prefs;

    final savedName = prefs.getString('myDisplayName')?.trim();
    if (savedName != null && savedName.isNotEmpty) {
      return savedName;
    }

    final previousName = prefs.getString('partnerOne')?.trim();
    if (previousName != null && previousName.isNotEmpty) {
      return previousName;
    }

    return 'Your name';
  }

  /// আগে থেকে সংরক্ষিত Space ID
  static Future<String?> getSavedSpaceId() async {
    final prefs = await _prefs;
    final user = _auth.currentUser;

    // A cached Space ID must never be trusted without checking the signed-in
    // Firebase UID. This prevents one account inheriting another account's
    // local chat, gallery, notes, and complaints after logout/account switch.
    if (user == null) return null;

    final savedId = prefs.getString(_spaceIdKey);
    if (savedId != null && savedId.isNotEmpty) {
      try {
        final savedSpace = await _spaces.doc(savedId).get();
        final data = savedSpace.data();

        // A fresh invite used by the same two accounts can redirect to their
        // original Space, preserving the original cloud history.
        final redirectId = data?['redirectSpaceId'];
        if (savedSpace.exists &&
            redirectId is String &&
            redirectId.isNotEmpty) {
          final original = await _spaces.doc(redirectId).get();
          final originalData = original.data();
          final originalMembers = List<String>.from(
            originalData?['memberUids'] ?? const [],
          );
          if (original.exists &&
              originalMembers.length == 2 &&
              originalMembers.contains(user.uid) &&
              (originalData?['connectionStatus'] ?? 'connected') ==
                  'connected') {
            await _saveConnection(
              redirectId,
              '${originalData?['inviteCode'] ?? ''}',
            );
            return redirectId;
          }
        }

        final members = List<String>.from(data?['memberUids'] ?? const []);

        if (savedSpace.exists && members.contains(user.uid)) {
          // Keep disconnected Spaces for the same members so their original
          // cloud data can be restored if those same accounts reconnect.
          return savedId;
        }

        // The cached Space belongs to a different account or no longer exists.
        await _clearSpaceScopedLocalData(prefs);
        await prefs.remove(_spaceIdKey);
        await prefs.remove(_inviteCodeKey);
      } catch (error) {
        // If the network is temporarily unavailable, fail closed instead of
        // using an unverified Space ID. Keep local cache for a later retry.
        debugPrint('Cached Space membership check failed: $error');
        return null;
      }
    }

    // If the local ID is missing, recover only a Space that explicitly lists
    // the currently signed-in UID as a member.
    try {
      final result = await _spaces
          .where('memberUids', arrayContains: user.uid)
          .get();

      QueryDocumentSnapshot<Map<String, dynamic>>? disconnectedSpace;

      for (final document in result.docs) {
        final data = document.data();
        final members = List<String>.from(data['memberUids'] ?? []);

        if (!members.contains(user.uid) || members.length != 2) {
          continue;
        }

        final status = data['connectionStatus'] ?? 'connected';
        if (status == 'connected') {
          final inviteCode = '${data['inviteCode'] ?? ''}';
          await _saveConnection(document.id, inviteCode);
          return document.id;
        }

        if (status == 'disconnected' && disconnectedSpace == null) {
          disconnectedSpace = document;
        }
      }

      // Same two accounts can reconnect to their old Space and recover its
      // cloud data. A different account cannot pass the membership check above.
      if (disconnectedSpace != null) {
        final data = disconnectedSpace.data();
        await _saveConnection(
          disconnectedSpace.id,
          '${data['inviteCode'] ?? ''}',
        );
        return disconnectedSpace.id;
      }
    } catch (error) {
      debugPrint('Saved Space recovery error: $error');
    }

    return null;
  }

  /// আগে থেকে সংরক্ষিত Invite Code
  static Future<String?> getSavedInviteCode() async {
    final prefs = await _prefs;
    return prefs.getString(_inviteCodeKey);
  }

  /// Space ID ও Invite Code ফোনে সংরক্ষণ
  static const List<String> _spaceScopedLocalKeys = [
    'loveNotes',
    'specialDates',
    'galleryMedia',
    'galleryFolders',
    'spaceComplaints',
    'relationshipStartAt',
    'partnerTwo',
    'chatDraft',
    'chatMessages',
  ];

  static Future<void> _clearSpaceScopedLocalData(
    SharedPreferences prefs,
  ) async {
    for (final key in _spaceScopedLocalKeys) {
      await prefs.remove(key);
    }
    // Upload queue from an old space must never be replayed into a new one.
    await prefs.remove('pendingDriveUploads');
  }

  static Future<bool> clearCachedSpaceData() async {
    final prefs = await _prefs;
    final keys = <String>[
      ..._spaceScopedLocalKeys,
      'pendingDriveUploads',
    ];
    final hadData = keys.any(prefs.containsKey);
    await _clearSpaceScopedLocalData(prefs);
    return hadData;
  }

  static Future<void> _saveConnection(
    String spaceId,
    String inviteCode,
  ) async {
    final prefs = await _prefs;
    final previousSpaceId = prefs.getString(_spaceIdKey);
    if (previousSpaceId != spaceId) {
      // Never carry local data into a different Space. Its own cloud copy
      // will be restored after the connection has been verified.
      await _clearSpaceScopedLocalData(prefs);
    }
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
    final ownName = await _getOwnName();

    // আগে থেকেই Space যুক্ত থাকলে নতুন Space তৈরি করবে না।
    final savedSpaceId = await getSavedSpaceId();

    if (savedSpaceId != null && savedSpaceId.isNotEmpty) {
      final savedCode = await getSavedInviteCode();

      if (savedCode != null && savedCode.isNotEmpty) {
        final existingSpace = await _spaces.doc(savedSpaceId).get();

        if (existingSpace.exists &&
            (existingSpace.data()?['memberUids'] as List?)
                    ?.contains(user.uid) ==
                true &&
            (existingSpace.data()?['connectionStatus'] ?? 'connected') ==
                'connected') {
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
        'memberNames': {
          user.uid: ownName,
        },
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
    final ownName = await _getOwnName();
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

        final rawNames = spaceData['memberNames'];
        final names = rawNames is Map
            ? Map<String, dynamic>.from(rawNames)
            : <String, dynamic>{};

        // একই Space-এ আগে থেকেই যুক্ত থাকলে
        // নিজের নাম অনুপস্থিত থাকলে সেটিও সংরক্ষণ করবে।
        if (members.contains(user.uid)) {
          if (names[user.uid] == null ||
              '${names[user.uid]}'.trim().isEmpty) {
            names[user.uid] = ownName;
            transaction.update(spaceRef, {
              'memberNames': names,
            });
          }

          return id;
        }

        if (members.length >= 2) {
          throw Exception(
            'এই Space-এ ইতিমধ্যে দুজন সদস্য আছে।',
          );
        }

        names[user.uid] = ownName;

        transaction.update(spaceRef, {
          'memberUids': FieldValue.arrayUnion([user.uid]),
          'memberNames': names,
        });

        return id;
      },
    );

    // Reusing a temporary invite that already redirects to an original
    // Space must keep using the original Space and its original invite code.
    final joinedSnapshot = await _spaces.doc(spaceId).get();
    final joinedData = joinedSnapshot.data();
    final redirectId = joinedData?['redirectSpaceId'];
    if (redirectId is String && redirectId.isNotEmpty) {
      final original = await _spaces.doc(redirectId).get();
      final originalData = original.data();
      final originalMembers = List<String>.from(
        originalData?['memberUids'] ?? const [],
      );
      if (original.exists &&
          originalMembers.length == 2 &&
          originalMembers.contains(user.uid) &&
          (originalData?['connectionStatus'] ?? 'connected') == 'connected') {
        await _saveConnection(
          redirectId,
          '${originalData?['inviteCode'] ?? ''}',
        );
        return;
      }
    }

    // If a fresh invite connects the same two Firebase accounts that
    // previously shared a disconnected Space, restore that original Space.
    final joinedMembers = List<String>.from(
      joinedData?['memberUids'] ?? const [],
    );
    String? originalSpaceId;
    String? originalInviteCode;

    if (joinedMembers.length == 2 && joinedMembers.contains(user.uid)) {
      final candidates = await _spaces
          .where('memberUids', arrayContains: user.uid)
          .get();

      for (final candidate in candidates.docs) {
        if (candidate.id == spaceId) continue;
        final oldData = candidate.data();
        final oldMembers = List<String>.from(oldData['memberUids'] ?? []);
        final oldStatus = oldData['connectionStatus'] ?? 'connected';
        final samePair = oldMembers.length == 2 &&
            oldMembers.toSet().containsAll(joinedMembers) &&
            joinedMembers.toSet().containsAll(oldMembers);

        if (samePair && oldStatus == 'disconnected') {
          originalSpaceId = candidate.id;
          originalInviteCode = '${oldData['inviteCode'] ?? ''}';
          await candidate.reference.update({
            'connectionStatus': 'connected',
            'disconnectionApprovals': <String, bool>{},
            'reconnectionApprovals': <String, bool>{},
            'reconnectedAt': FieldValue.serverTimestamp(),
            'reconnectedByFreshInvite': true,
          });
          await _spaces.doc(spaceId).update({
            'connectionStatus': 'disconnected',
            'redirectSpaceId': candidate.id,
            'redirectInviteCode': originalInviteCode,
            'redirectedAt': FieldValue.serverTimestamp(),
          });
          break;
        }
      }
    }

    if (originalSpaceId != null) {
      await _saveConnection(originalSpaceId, originalInviteCode ?? '');
    } else {
      await _saveConnection(spaceId, code);
    }
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
