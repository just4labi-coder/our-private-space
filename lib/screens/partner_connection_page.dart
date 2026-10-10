
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../services/private_space_service.dart';
import '../services/disconnection_service.dart';

class PartnerConnectionPage extends StatefulWidget {
  const PartnerConnectionPage({super.key});

  @override
  State<PartnerConnectionPage> createState() =>
      _PartnerConnectionPageState();
}

class _PartnerConnectionPageState
    extends State<PartnerConnectionPage> {
  static const Color _background = Color(0xFF070513);
  static const Color _surface = Color(0xFF111026);
  static const Color _pink = Color(0xFFFF2E93);
  static const Color _purple = Color(0xFF8B5CF6);

  final TextEditingController _codeController =
      TextEditingController();

  String? _savedCode;
  String? _spaceId;
  String? _message;
  bool _messageIsError = false;
  bool _loading = true;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _loadConnection();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _loadConnection() async {
    try {
      final id = await PrivateSpaceService.getSavedSpaceId();
      final code = await PrivateSpaceService.getSavedInviteCode();

      if (!mounted) return;

      setState(() {
        _spaceId = id;
        _savedCode = code;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() => _loading = false);
      _showMessage(
        'সংযোগের তথ্য লোড করা যায়নি। ইন্টারনেট পরীক্ষা করো।',
        isError: true,
      );
    }
  }

  void _showMessage(
    String message, {
    required bool isError,
  }) {
    if (!mounted) return;

    setState(() {
      _message = message;
      _messageIsError = isError;
    });
  }

  Future<void> _createSpace() async {
    if (_working) return;

    setState(() {
      _working = true;
      _message = null;
    });

    try {
      final code = await PrivateSpaceService.createSpace();
      final id = await PrivateSpaceService.getSavedSpaceId();

      if (!mounted) return;

      setState(() {
        _savedCode = code;
        _spaceId = id;
      });

      _showMessage(
        'Private Space তৈরি হয়েছে! ❤️\nInvite Code-টি সঙ্গীকে দাও।',
        isError: false,
      );
    } catch (e) {
      _showMessage(
        _friendlyError(e, creating: true),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _joinSpace() async {
    if (_working) return;

    final code = _codeController.text.trim().toUpperCase();

    if (code.length != 6) {
      _showMessage(
        'সঠিক ৬ অক্ষরের Invite Code লিখো।',
        isError: true,
      );
      return;
    }

    setState(() {
      _working = true;
      _message = null;
    });

    try {
      await PrivateSpaceService.joinSpace(code);

      final id = await PrivateSpaceService.getSavedSpaceId();
      final savedCode =
          await PrivateSpaceService.getSavedInviteCode();

      if (!mounted) return;

      setState(() {
        _spaceId = id;
        _savedCode = savedCode;
      });

      _showMessage(
        'সফলভাবে Partner Space-এ যুক্ত হয়েছ! 💕',
        isError: false,
      );
    } catch (e) {
      _showMessage(
        _friendlyError(e, creating: false),
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String _friendlyError(
    Object error, {
    required bool creating,
  }) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('network') ||
        raw.contains('unavailable') ||
        raw.contains('timeout')) {
      return 'ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করো।';
    }

    if (raw.contains('permission-denied') ||
        raw.contains('permission denied')) {
      return 'Firebase অনুমতি দেয়নি। Firestore Rules পরীক্ষা করো।';
    }

    if (raw.contains('invite code') ||
        raw.contains('সঠিক নয়') ||
        raw.contains('মেলেনি')) {
      return 'Invite Code সঠিক নয়। আবার পরীক্ষা করো।';
    }

    return creating
        ? 'Private Space তৈরি হয়নি।\n$error'
        : 'Space-এ যুক্ত হওয়া যায়নি।\n$error';
  }

  Future<void> _runDisconnectionAction({
    required String spaceId,
    required bool approve,
  }) async {
    if (_working) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
          approve
              ? 'বিচ্ছিন্নতায় সম্মতি দেবে?'
              : 'বিচ্ছিন্নতার অনুরোধ পাঠাবে?',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'দুজন সম্মতি দিলে Space-এর শেয়ার করা তথ্য অ্যাপ থেকে '
          'অ্যাক্সেস করা যাবে না। ডেটা মুছে ফেলা হবে না। '
          'পুনঃসংযোগের সুবিধা এখনো তৈরি হয়নি।',
          style: TextStyle(
            color: Colors.white70,
            height: 1.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, false),
            child: const Text('এখন নয়'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: _pink,
            ),
            child: const Text('আমি নিশ্চিত'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _working = true;
      _message = null;
    });

    try {
      if (approve) {
        await DisconnectionService.approveDisconnection(
          spaceId,
        );

        _showMessage(
          'দুজনের সম্মতিতে Space বিচ্ছিন্ন হয়েছে। '
          'ডেটা মুছে ফেলা হয়নি।',
          isError: false,
        );
      } else {
        await DisconnectionService.requestDisconnection(
          spaceId,
        );

        _showMessage(
          'তোমার সম্মতি সংরক্ষিত হয়েছে। '
          'এখন সঙ্গীর সম্মতির অপেক্ষা করো।',
          isError: false,
        );
      }
    } catch (e) {
      _showMessage(
        'অনুরোধ সম্পন্ন হয়নি। Firebase Rules পরীক্ষা করো।\n$e',
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Widget _disconnectionPanel(
    String spaceId,
    Map<String, dynamic> data,
    List members,
  ) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null || !members.contains(uid)) {
      return const SizedBox.shrink();
    }

    final rawApprovals = data['disconnectionApprovals'];
    final approvals = rawApprovals is Map
        ? Map<String, dynamic>.from(rawApprovals)
        : <String, dynamic>{};

    final status = data['connectionStatus'] ?? 'connected';

    if (status == 'disconnected') {
      return _panelContainer(
        color: const Color(0xFF35131F),
        borderColor: const Color(0xFFFF7185),
        child: const Column(
          children: [
            Icon(
              Icons.link_off_rounded,
              color: Color(0xFFFF7185),
              size: 30,
            ),
            SizedBox(height: 8),
            Text(
              'Private Space বিচ্ছিন্ন',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'শেয়ার করা ডেটা মুছে ফেলা হয়নি। '
              'অ্যাক্সেস বন্ধ রয়েছে। পুনঃসংযোগের সুবিধা '
              'এখনো তৈরি হয়নি।',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    if (members.length != 2) {
      return const SizedBox.shrink();
    }

    final otherUid = members.firstWhere(
      (member) => member != uid,
    );

    final ownApproval = approvals[uid] == true;
    final otherApproval = approvals[otherUid] == true;

    final bool canApprove = otherApproval && !ownApproval;
    final bool alreadyWaiting = ownApproval && !otherApproval;

    final String description;

    if (alreadyWaiting) {
      description =
          'তোমার সম্মতি দেওয়া হয়েছে। এখন সঙ্গীর সম্মতির অপেক্ষা।';
    } else if (canApprove) {
      description =
          'সঙ্গী বিচ্ছিন্ন হওয়ার অনুরোধ করেছে। '
          'সম্মতি দিলে Space বিচ্ছিন্ন হবে।';
    } else {
      description =
          'অনুরোধ পাঠাও। Space বিচ্ছিন্ন করতে দুজনের সম্মতি লাগবে।';
    }

    return _panelContainer(
      color: const Color(0xFF21172E),
      borderColor: _purple,
      child: Column(
        children: [
          const Icon(
            Icons.link_off_rounded,
            color: _pink,
            size: 30,
          ),
          const SizedBox(height: 8),
          const Text(
            'Private Space বিচ্ছিন্নকরণ',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          if (!alreadyWaiting) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _working
                    ? null
                    : () => _runDisconnectionAction(
                          spaceId: spaceId,
                          approve: canApprove,
                        ),
                style: FilledButton.styleFrom(
                  backgroundColor: _pink,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  canApprove
                      ? 'বিচ্ছিন্ন হতে সম্মতি দাও'
                      : 'বিচ্ছিন্নতার অনুরোধ',
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'এতে Firestore ডেটা ডিলিট করা হয় না।',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelContainer({
    required Color color,
    required Color borderColor,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }

  Widget _statusCard() {
    final isError = _messageIsError;

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError
            ? const Color(0xFF35131F)
            : const Color(0xFF103126),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isError
              ? const Color(0xFFFF5C75)
              : const Color(0xFF4ADE80),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            color: isError
                ? const Color(0xFFFF7185)
                : const Color(0xFF4ADE80),
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _message ?? '',
              style: TextStyle(
                color: isError
                    ? const Color(0xFFFFC5CE)
                    : const Color(0xFFB8FFD6),
                height: 1.6,
              ),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _message = null),
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionCard() {
    final id = _spaceId;

    if (id == null || id.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<Map<String, dynamic>?>(
      stream: PrivateSpaceService.watchSpace(id),
      builder: (context, snapshot) {
        final data = snapshot.data;
        final members = data?['memberUids'];

        final memberList = members is List ? members : <dynamic>[];
        final memberCount = memberList.length;
        final connected = memberCount == 2 &&
            data?['connectionStatus'] != 'disconnected';

        return Container(
          margin: const EdgeInsets.only(bottom: 22),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: connected
                  ? const Color(0xFF4ADE80).withValues(alpha: 0.65)
                  : _purple.withValues(alpha: 0.6),
            ),
          ),
          child: Column(
            children: [
              Icon(
                snapshot.hasError
                    ? Icons.cloud_off_rounded
                    : connected
                        ? Icons.favorite_rounded
                        : Icons.hourglass_top_rounded,
                color: snapshot.hasError
                    ? const Color(0xFFFF7185)
                    : connected
                        ? const Color(0xFF4ADE80)
                        : _purple,
                size: 42,
              ),
              const SizedBox(height: 10),
              Text(
                snapshot.hasError
                    ? 'সংযোগ যাচাই করা যাচ্ছে না'
                    : connected
                        ? 'তোমরা দুজন যুক্ত হয়েছ! ❤️'
                        : 'Space-এর তথ্য',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'সদস্য: $memberCount / 2',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                connected
                    ? 'দুই ফোন একই Private Space-এ যুক্ত।'
                    : 'সঙ্গী Join করলে তথ্য আপডেট হবে।',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
              if (_savedCode != null) ...[
                const SizedBox(height: 14),
                const Text(
                  'তোমার Invite Code',
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  _savedCode!,
                  style: const TextStyle(
                    color: _pink,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 5,
                  ),
                ),
              ],
              if (snapshot.hasError) ...[
                const SizedBox(height: 10),
                const Text(
                  'Firestore Rules ও ইন্টারনেট পরীক্ষা করো।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFA7B4),
                    fontSize: 12,
                  ),
                ),
              ],
              if (data != null &&
                  members is List &&
                  !snapshot.hasError)
                _disconnectionPanel(id, data, memberList),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Partner Connection'),
        backgroundColor: _surface,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: _pink),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: _pink,
                  size: 58,
                ),
                const SizedBox(height: 12),
                const Text(
                  'দুজনের একটি Private Space',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'এক ফোনে Space তৈরি করো, অন্য ফোনে Invite Code দিয়ে যুক্ত হও।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                _connectionCard(),
                FilledButton.icon(
                  onPressed: _working || _spaceId != null
                      ? null
                      : _createSpace,
                  icon: const Icon(Icons.add_link_rounded),
                  label: const Text('Create Private Space'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _pink,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
                const SizedBox(height: 24),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
                  'সঙ্গীর Space-এ যুক্ত হও',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  enabled: !_working,
                  textCapitalization: TextCapitalization.characters,
                  autocorrect: false,
                  maxLength: 6,
                  decoration: InputDecoration(
                    labelText: '৬ অক্ষরের Invite Code',
                    hintText: 'যেমন: A1B2C3',
                    counterText: '',
                    filled: true,
                    fillColor: _surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _working ? null : _joinSpace,
                  icon: const Icon(Icons.people_alt_rounded),
                  label: const Text('Join Partner Space'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
                if (_working) ...[
                  const SizedBox(height: 18),
                  const Center(
                    child: CircularProgressIndicator(color: _pink),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Firebase-এর সঙ্গে সংযোগ করা হচ্ছে...',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60),
                  ),
                ],
                if (_message != null) _statusCard(),
                const SizedBox(height: 20),
                const Text(
                  'Space-এ যুক্ত হওয়া আর Chat, Gallery বা Notes সিঙ্ক হওয়া আলাদা কাজ।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    height: 1.6,
                  ),
                ),
              ],
            ),
    );
  }
}
