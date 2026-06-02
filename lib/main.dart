import 'package:flutter/material.dart';

void main() => runApp(const WalkableApp());

class WalkableApp extends StatelessWidget {
  const WalkableApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Walkable',
      home: Scaffold(
        appBar: AppBar(title: const Text('Walkable')),
        body: const Center(child: Text('Walkable')),
      ),
    );
  }
}
