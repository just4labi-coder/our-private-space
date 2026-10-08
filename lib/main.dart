import 'package:flutter/material.dart';

void main() {
  runApp(const EternalSpaceApp());
}

class EternalSpaceApp extends StatelessWidget {
  const EternalSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eternal Space',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F051D),
        primaryColor: const Color(0xFFFF2E93),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF2E93),
          secondary: Color(0xFF8A2BE2),
          surface: Color(0xFF1A0B2E),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _isCalculatorMode = false;
  String _calcDisplay = '0';

  // Love Counter Start Date: August 7, 2025
  final DateTime _startDate = DateTime(2025, 8, 7);

  Duration get _timeTogether {
    return DateTime.now().difference(_startDate);
  }

  void _onCalcButtonPressed(String value) {
    setState(() {
      if (value == 'C') {
        _calcDisplay = '0';
      } else if (value == 'EXIT') {
        _isCalculatorMode = false;
      } else {
        if (_calcDisplay == '0') {
          _calcDisplay = value;
        } else {
          _calcDisplay += value;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCalculatorMode) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Calculator'),
          backgroundColor: Colors.black,
          actions: [
            IconButton(
              icon: const Icon(Icons.lock_open, color: Colors.pinkAccent),
              onPressed: () => _onCalcButtonPressed('EXIT'),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                alignment: Alignment.bottomRight,
                padding: const EdgeInsets.all(24),
                child: Text(
                  _calcDisplay,
                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const Divider(height: 1),
            _buildCalculatorPad(),
          ],
        ),
      );
    }

    final days = _timeTogether.inDays;
    final hours = _timeTogether.inHours % 24;
    final minutes = _timeTogether.inMinutes % 60;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Eternal Space ❤️',
          style: TextStyle(color: Color(0xFFFF2E93), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined, color: Colors.purpleAccent),
            onPressed: () {
              setState(() {
                _isCalculatorMode = true;
              });
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A0B2E), Color(0xFF0F051D)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF26103F),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF2E93).withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      'Our Journey Together',
                      style: TextStyle(fontSize: 18, color: Colors.white70),
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildCounterBox('$days', 'Days'),
                        _buildCounterBox('$hours', 'Hours'),
                        _buildCounterBox('$minutes', 'Mins'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              const Text(
                'Welcome to our private world.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white60,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF2E93),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chat & Gallery coming next!')),
                  );
                },
                child: const Text('Open Secret Chat & Gallery', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounterBox(String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF2E93),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 14, color: Colors.purpleAccent),
        ),
      ],
    );
  }

  Widget _buildCalculatorPad() {
    return Column(
      children: [
        Row(children: [_buildCalcButton('7'), _buildCalcButton('8'), _buildCalcButton('9'), _buildCalcButton('/')]),
        Row(children: [_buildCalcButton('4'), _buildCalcButton('5'), _buildCalcButton('6'), _buildCalcButton('*')]),
        Row(children: [_buildCalcButton('1'), _buildCalcButton('2'), _buildCalcButton('3'), _buildCalcButton('-')]),
        Row(children: [_buildCalcButton('C'), _buildCalcButton('0'), _buildCalcButton('='), _buildCalcButton('+')]),
      ],
    );
  }

  Widget _buildCalcButton(String text) {
    return Expanded(
      child: TextButton(
        onPressed: () => _onCalcButtonPressed(text),
        child: Text(text, style: const TextStyle(fontSize: 24, color: Colors.white)),
      ),
    );
  }
}
