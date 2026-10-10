
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DisconnectionService {
  DisconnectionService._();

  static final FirebaseFirestore _db =
      FirebaseFirestore.instance;

  static final FirebaseAuth _auth =
      FirebaseAuth.instance;

  static String get _uid {
    final user = _auth.currentUser;

    if (user == null) {
      throw Exception('আগে Firebase-এ সাইন ইন করতে হবে।');
    }

    return user.uid;
  }

  static DocumentReference<Map<String, dynamic>> _space(
    String spaceId,
  ) {
    return _db.collection('privateSpaces').doc(spaceId);
  }

  /// একজন সদস্য বিচ্ছিন্ন হওয়ার অনুরোধ পাঠায়।
  /// এতে শুধু বর্তমান সদস্যের সম্মতি সংরক্ষিত হয়।
  static Future<void> requestDisconnection(
    String spaceId,
  ) async {
    final uid = _uid;
    final ref = _space(spaceId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception('Private Space পাওয়া যায়নি।');
      }

      final data = snapshot.data()!;
      final members = List<String>.from(
        data['memberUids'] ?? [],
      );

      if (members.length != 2 || !members.contains(uid)) {
        throw Exception('দুজনের সক্রিয় সংযোগ পাওয়া যায়নি।');
      }

      if (data['connectionStatus'] == 'disconnected') {
        throw Exception('Space ইতিমধ্যে বিচ্ছিন্ন।');
      }

      final approvals = Map<String, dynamic>.from(
        data['disconnectionApprovals'] ?? {},
      );

      approvals[uid] = true;

      transaction.update(ref, {
        'disconnectionApprovals': approvals,
        'disconnectionRequestedAt':
            FieldValue.serverTimestamp(),
      });
    });
  }

  /// অন্য সদস্যের সম্মতি দেওয়ার পর বিচ্ছিন্নতা সম্পন্ন করে।
  static Future<void> approveDisconnection(
    String spaceId,
  ) async {
    final uid = _uid;
    final ref = _space(spaceId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception('Private Space পাওয়া যায়নি।');
      }

      final data = snapshot.data()!;
      final members = List<String>.from(
        data['memberUids'] ?? [],
      );

      if (members.length != 2 || !members.contains(uid)) {
        throw Exception('দুজনের সক্রিয় সংযোগ পাওয়া যায়নি।');
      }

      if (data['connectionStatus'] == 'disconnected') {
        throw Exception('Space ইতিমধ্যে বিচ্ছিন্ন।');
      }

      final otherUid = members.firstWhere(
        (member) => member != uid,
      );

      final approvals = Map<String, dynamic>.from(
        data['disconnectionApprovals'] ?? {},
      );

      if (approvals[otherUid] != true) {
        throw Exception(
          'অন্য সদস্যের অনুরোধের অপেক্ষায় থাকতে হবে।',
        );
      }

      approvals[uid] = true;

      transaction.update(ref, {
        'disconnectionApprovals': approvals,
        'connectionStatus': 'disconnected',
        'disconnectedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// একতরফাভাবে Space পুনরায় চালু করা নিষিদ্ধ।
  /// পারস্পরিক পুনঃসংযোগের ব্যবস্থা তৈরি না হওয়া পর্যন্ত
  /// এই পদ্ধতি ইচ্ছাকৃতভাবে কোনো পরিবর্তন করে না।
  static Future<void> reactivateSpace(
    String spaceId,
  ) async {
    throw Exception(
      'নিরাপদ পারস্পরিক পুনঃসংযোগের ব্যবস্থা এখনো তৈরি হয়নি।',
    );
  }
}
