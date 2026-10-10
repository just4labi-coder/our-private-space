import 'package:flutter/material.dart';

import '../services/private_space_service.dart';

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

      setState(() {
        _loading = false;
      });

      _showMessage(
        'সংযোগের তথ্য লোড করা যায়নি। ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করো।',
        isError: true,
      );
    }
  }

  void _showMessage(String message, {required bool isError}) {
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
        _messageIsError = false;
        _message =
            'তোমার Private Space তৈরি হয়েছে! ❤️\n'
            'এখন এই Invite Code-টি সঙ্গীকে দাও।';
      });
    } catch (e) {
      _showMessage(
        _friendlyError(e, creating: true),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _joinSpace() async {
    if (_working) return;

    final code = _codeController.text.trim().toUpperCase();

    if (code.isEmpty) {
      _showMessage(
        'আগে সঙ্গীর ৬ অক্ষরের Invite Code লিখো।',
        isError: true,
      );
      return;
    }

    if (code.length != 6) {
      _showMessage(
        'Invite Code-টি ৬ অক্ষরের হতে হবে। কোডটি আবার পরীক্ষা করো।',
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
        _messageIsError = false;
        _message =
            'সফলভাবে Partner Space-এ যুক্ত হয়েছ! 💕\n'
            'এখন এই Space-এর সদস্যসংখ্যা ও সংযোগের অবস্থা নিচে দেখতে পাবে।';
      });
    } catch (e) {
      _showMessage(
        _friendlyError(e, creating: false),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _working = false);
      }
    }
  }

  String _friendlyError(Object error, {required bool creating}) {
    final raw = error.toString().toLowerCase();

    if (raw.contains('network') ||
        raw.contains('unavailable') ||
        raw.contains('timeout')) {
      return 'ইন্টারনেট সংযোগ পাওয়া যাচ্ছে না।\n'
          'ইন্টারনেট পরীক্ষা করে আবার চেষ্টা করো।';
    }

    if (raw.contains('permission-denied') ||
        raw.contains('permission denied')) {
      return 'Firebase অনুমতি দেয়নি।\n'
          'Firestore Rules ও Firebase Authentication সেটিংস পরীক্ষা করতে হবে।';
    }

    if (raw.contains('already has') ||
        raw.contains('ইতিমধ্যে দুজন')) {
      return 'এই Private Space-এ ইতিমধ্যে দুজন সদস্য আছে।';
    }

    if (raw.contains('invite code') ||
        raw.contains('সঠিক নয়') ||
        raw.contains('মেলেনি')) {
      return 'Invite Code সঠিক নয়। সঙ্গীর কাছ থেকে কোডটি আবার নিয়ে চেষ্টা করো।';
    }

    return creating
        ? 'Private Space তৈরি করা যায়নি।\n'
            'ইন্টারনেট ও Firebase সেটিংস পরীক্ষা করে আবার চেষ্টা করো।\n'
            'বিস্তারিত: $error'
        : 'Partner Space-এ যুক্ত হওয়া যায়নি।\n'
            'কোড ও Firebase সেটিংস পরীক্ষা করে আবার চেষ্টা করো।\n'
            'বিস্তারিত: $error';
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
          width: 1.3,
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
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _message ?? '',
              style: TextStyle(
                color: isError
                    ? const Color(0xFFFFC5CE)
                    : const Color(0xFFB8FFD6),
                fontSize: 14,
                height: 1.6,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: 'বন্ধ করো',
            onPressed: () {
              setState(() => _message = null);
            },
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.white60,
              size: 19,
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

        final memberCount = members is List
            ? members.length
            : 0;

        final connected = memberCount >= 2;

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
                        : snapshot.connectionState ==
                                ConnectionState.waiting &&
                            !snapshot.hasData
                            ? 'Space-এর তথ্য লোড হচ্ছে...'
                            : 'Space তৈরি হয়েছে',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                snapshot.hasError
                    ? 'Firestore Rules ও ইন্টারনেট পরীক্ষা করো।'
                    : 'সদস্য: $memberCount / 2',
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
                    : 'সঙ্গী Join করলে এই তথ্য স্বয়ংক্রিয়ভাবে আপডেট হবে।',
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
                  'সদস্যসংখ্যা নিশ্চিত করা যায়নি। শুধু আগের সংরক্ষিত Space ID-কে সফল সংযোগ হিসেবে ধরে নেওয়া হচ্ছে না।',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFA7B4),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
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
                  onPressed:
                      _working || _spaceId != null
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
                  'মনে রেখো: Space-এ যুক্ত হওয়া আর Chat, Gallery বা Notes সিঙ্ক হওয়া আলাদা কাজ। অন্য ফিচারগুলোও Firebase-এর সঙ্গে যুক্ত করতে হবে।',
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
