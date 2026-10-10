
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

  static Future<void> requestDisconnection(
    String spaceId,
  ) async {
    await _saveApproval(
      spaceId: spaceId,
      approvalField: 'disconnectionApprovals',
      requestedAtField: 'disconnectionRequestedAt',
      requiredStatus: 'connected',
      completedStatus: 'disconnected',
      completedAtField: 'disconnectedAt',
    );
  }

  static Future<void> approveDisconnection(
    String spaceId,
  ) async {
    await _saveApproval(
      spaceId: spaceId,
      approvalField: 'disconnectionApprovals',
      requestedAtField: 'disconnectionRequestedAt',
      requiredStatus: 'connected',
      completedStatus: 'disconnected',
      completedAtField: 'disconnectedAt',
      requireOtherApproval: true,
    );
  }

  static Future<void> requestReconnection(
    String spaceId,
  ) async {
    await _saveApproval(
      spaceId: spaceId,
      approvalField: 'reconnectionApprovals',
      requestedAtField: 'reconnectionRequestedAt',
      requiredStatus: 'disconnected',
      completedStatus: 'connected',
      completedAtField: 'reconnectedAt',
    );
  }

  static Future<void> approveReconnection(
    String spaceId,
  ) async {
    await _saveApproval(
      spaceId: spaceId,
      approvalField: 'reconnectionApprovals',
      requestedAtField: 'reconnectionRequestedAt',
      requiredStatus: 'disconnected',
      completedStatus: 'connected',
      completedAtField: 'reconnectedAt',
      requireOtherApproval: true,
    );
  }

  static Future<void> _saveApproval({
    required String spaceId,
    required String approvalField,
    required String requestedAtField,
    required String requiredStatus,
    required String completedStatus,
    required String completedAtField,
    bool requireOtherApproval = false,
  }) async {
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
        throw Exception('দুজনের সদস্যপদ নিশ্চিত করা যায়নি।');
      }

      final status = data['connectionStatus'] ?? 'connected';

      if (status != requiredStatus) {
        throw Exception(
          requiredStatus == 'connected'
              ? 'Space ইতিমধ্যে বিচ্ছিন্ন বা পরিবর্তিত হয়েছে।'
              : 'Space এখন বিচ্ছিন্ন অবস্থায় নেই।',
        );
      }

      final otherUid = members.firstWhere(
        (member) => member != uid,
      );

      final raw = data[approvalField];
      final approvals = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      if (requireOtherApproval && approvals[otherUid] != true) {
        throw Exception(
          'আগে অন্য সদস্যের সম্মতি প্রয়োজন।',
        );
      }

      approvals[uid] = true;

      final bothApproved =
          approvals[uid] == true &&
          approvals[otherUid] == true;

      final updates = <String, dynamic>{
        approvalField: approvals,
        requestedAtField: FieldValue.serverTimestamp(),
      };

      if (bothApproved) {
        updates['connectionStatus'] = completedStatus;
        updates[completedAtField] = FieldValue.serverTimestamp();

        // পরবর্তী চক্রের সম্মতি যেন পুরোনো সম্মতি থেকে না আসে।
        if (completedStatus == 'disconnected') {
          updates['reconnectionApprovals'] = <String, bool>{};
        } else {
          updates['disconnectionApprovals'] = <String, bool>{};
        }
      }

      transaction.update(ref, updates);
    });
  }
}
