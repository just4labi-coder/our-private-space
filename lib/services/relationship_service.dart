import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RelationshipService {
  RelationshipService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<String?> _savedSpaceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('eternal_space_id');
  }

  static Future<DocumentReference<Map<String, dynamic>>?>
      _connectedSpace() async {
    final user = _auth.currentUser;
    final spaceId = await _savedSpaceId();

    if (user == null || spaceId == null || spaceId.isEmpty) {
      return null;
    }

    final ref = _db.collection('privateSpaces').doc(spaceId);
    final snapshot = await ref.get();

    if (!snapshot.exists) return null;

    final data = snapshot.data()!;
    final members = List<String>.from(data['memberUids'] ?? []);

    if (members.length != 2 ||
        !members.contains(user.uid) ||
        (data['connectionStatus'] ?? 'connected') != 'connected') {
      return null;
    }

    return ref;
  }

  static Future<Map<String, dynamic>> loadHomeData() async {
    final prefs = await SharedPreferences.getInstance();
    final user = _auth.currentUser;
    final fallbackName = prefs.getString('myDisplayName') ?? 'Your name';

    final ref = await _connectedSpace();

    if (ref == null || user == null) {
      return {
        'connected': false,
        'ownName': fallbackName,
        'partnerName': 'No one',
        'startAt': null,
      };
    }

    final snapshot = await ref.get();
    final data = snapshot.data()!;
    final members = List<String>.from(data['memberUids'] ?? []);
    final otherUid = members.firstWhere((uid) => uid != user.uid);

    final namesRaw = data['memberNames'];
    final names = namesRaw is Map
        ? Map<String, dynamic>.from(namesRaw)
        : <String, dynamic>{};

    final ownName = '${names[user.uid] ?? fallbackName}'.trim();
    final partnerName = '${names[otherUid] ?? 'Partner'}'.trim();

    final rawStart = data['relationshipStartAt'];
    DateTime? startAt;

    if (rawStart is Timestamp) {
      startAt = rawStart.toDate();
    } else if (rawStart is DateTime) {
      startAt = rawStart;
    }

    return {
      'connected': true,
      'ownName': ownName.isEmpty ? fallbackName : ownName,
      'partnerName': partnerName.isEmpty ? 'Partner' : partnerName,
      'startAt': startAt,
    };
  }

  static Future<void> saveOwnName(String name) async {
    final cleaned = name.trim();

    if (cleaned.isEmpty) {
      throw Exception('নাম খালি রাখা যাবে না।');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('myDisplayName', cleaned);

    final user = _auth.currentUser;

    // লগইন না থাকলেও নিজের ফোনে নাম সংরক্ষণ হবে।
    if (user == null) return;

    final ref = await _connectedSpace();

    // Partner-এর সঙ্গে যুক্ত না থাকলেও নিজের নাম রাখা যাবে।
    if (ref == null) return;

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);

      if (!snapshot.exists) {
        throw Exception('Private Space পাওয়া যায়নি।');
      }

      final data = snapshot.data()!;
      final members = List<String>.from(data['memberUids'] ?? []);

      if (members.length != 2 ||
          !members.contains(user.uid) ||
          (data['connectionStatus'] ?? 'connected') != 'connected') {
        throw Exception('Partner Connection সক্রিয় নেই।');
      }

      final rawNames = data['memberNames'];
      final names = rawNames is Map
          ? Map<String, dynamic>.from(rawNames)
          : <String, dynamic>{};

      names[user.uid] = cleaned;

      transaction.update(ref, {
        'memberNames': names,
      });
    });
  }

  static Future<void> saveRelationshipStart(DateTime dateTime) async {
    final ref = await _connectedSpace();

    if (ref == null) {
      throw Exception('আগে Partner-এর সঙ্গে যুক্ত হও।');
    }

    await ref.update({
      'relationshipStartAt': Timestamp.fromDate(dateTime),
    });
  }

  static Future<void> clearRelationshipStart() async {
    final ref = await _connectedSpace();

    if (ref == null) {
      throw Exception('Partner Connection সক্রিয় নেই।');
    }

    await ref.update({
      'relationshipStartAt': FieldValue.delete(),
    });
  }
}
