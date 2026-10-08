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
      theme: ThemeData(
        primarySwatch: Colors.pink,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Eternal Space'),
      ),
      body: const Center(
        child: Text(
          'Welcome to Our Private Space',
          style: TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}
