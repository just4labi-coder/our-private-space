
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

      if (!members.contains(uid) || members.length != 2) {
        throw Exception('দুজনের সংযোগ সক্রিয় নেই।');
      }

      final approvals =
          Map<String, dynamic>.from(
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

  /// অন্য সদস্যের অনুরোধে সম্মতি দেয়।
  /// উভয়ের সম্মতি হলে Space-এর শেয়ার করা ডেটার
  /// অ্যাক্সেস বন্ধ করার জন্য বিচ্ছিন্ন অবস্থা সেট করে।
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

      if (!members.contains(uid) || members.length != 2) {
        throw Exception('দুজনের সংযোগ সক্রিয় নেই।');
      }

      final approvals =
          Map<String, dynamic>.from(
        data['disconnectionApprovals'] ?? {},
      );

      final otherMembers =
          members.where((member) => member != uid).toList();

      if (otherMembers.isEmpty ||
          approvals[otherMembers.first] != true) {
        throw Exception(
          'আগে অন্য সদস্যকে বিচ্ছিন্ন হওয়ার অনুরোধ পাঠাতে হবে।',
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

  /// পুনরায় যুক্ত হওয়ার অনুরোধের জন্য আগের অনুমোদন
  /// মুছে দিয়ে Space-কে পুনরায় সক্রিয় করে।
  /// এটি কেবল দুজন সদস্য একই Space-এ ফিরে আসার
  /// প্রক্রিয়ার অংশ হিসেবে ব্যবহার করতে হবে।
  static Future<void> reactivateSpace(
    String spaceId,
  ) async {
    final uid = _uid;
    final ref = _space(spaceId);

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception('পুরোনো Private Space পাওয়া যায়নি।');
      }

      final data = snapshot.data()!;
      final members = List<String>.from(
        data['memberUids'] ?? [],
      );

      if (!members.contains(uid) || members.length != 2) {
        throw Exception(
          'পুরোনো Space-এর দুজন সদস্যকে পুনরায় যুক্ত হতে হবে।',
        );
      }

      transaction.update(ref, {
        'connectionStatus': 'connected',
        'disconnectionApprovals': <String, bool>{},
        'disconnectionRequestedAt': FieldValue.delete(),
        'disconnectedAt': FieldValue.delete(),
      });
    });
  }
}
