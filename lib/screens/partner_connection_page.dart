
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
  final TextEditingController _codeController =
      TextEditingController();

  String? _savedCode;
  String? _spaceId;
  String? _message;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'সংযোগের তথ্য লোড করা যায়নি: $e';
      });
    }
  }

  Future<void> _createSpace() async {
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
        _message = 'Private Space তৈরি হয়েছে। কোডটি সঙ্গীকে দাও।';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'Space তৈরি হয়নি: $e';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _joinSpace() async {
    final code = _codeController.text.trim();

    if (code.isEmpty) {
      setState(() => _message = 'সঙ্গীর Invite Code লিখো।');
      return;
    }

    setState(() {
      _working = true;
      _message = null;
    });

    try {
      await PrivateSpaceService.joinSpace(code);
      final id = await PrivateSpaceService.getSavedSpaceId();
      final savedCode = await PrivateSpaceService.getSavedInviteCode();

      if (!mounted) return;

      setState(() {
        _spaceId = id;
        _savedCode = savedCode;
        _message = 'Space-এ যুক্ত হওয়া সফল হয়েছে!';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'যুক্ত হওয়া যায়নি: $e';
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070513),
      appBar: AppBar(
        title: const Text('Partner Connection'),
        backgroundColor: const Color(0xFF111026),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFFFF2E93),
                  size: 58,
                ),
                const SizedBox(height: 12),
                const Text(
                  'দুজনের একটি Private Space',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'একটি ফোনে Space তৈরি করো। অন্য ফোনে সেই কোড দিয়ে যুক্ত হও।',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white60),
                ),
                const SizedBox(height: 24),

                if (_spaceId != null) ...[
                  Card(
                    color: const Color(0xFF111026),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 38,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Space সংরক্ষিত আছে',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (_savedCode != null) ...[
                            const SizedBox(height: 12),
                            const Text(
                              'তোমার Invite Code',
                              style: TextStyle(color: Colors.white60),
                            ),
                            SelectableText(
                              _savedCode!,
                              style: const TextStyle(
                                fontSize: 28,
                                letterSpacing: 4,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF2E93),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          const Text(
                            'এটি Space সংরক্ষিত থাকার তথ্য; অন্য সদস্য যুক্ত হয়েছেন কি না, তা আলাদাভাবে যাচাই করতে হবে।',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                FilledButton.icon(
                  onPressed:
                      _working || _spaceId != null ? null : _createSpace,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Create Private Space'),
                ),
                const SizedBox(height: 24),
                const Divider(color: Colors.white24),
                const SizedBox(height: 12),
                const Text(
                  'সঙ্গীর Space-এ যুক্ত হও',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: '৬ অক্ষরের Invite Code',
                    hintText: 'যেমন: A1B2C3',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _working ? null : _joinSpace,
                  icon: const Icon(Icons.people_alt_rounded),
                  label: const Text('Join Partner Space'),
                ),
                if (_working) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  SelectableText(
                    _message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
    );
  }
}
