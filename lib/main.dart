import 'package:flutter/material.dart';
import 'auriga_screen.dart';

void main() {
  runApp(const AurigaDemoApp());
}

class AurigaDemoApp extends StatelessWidget {
  const AurigaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Auriga Host App',
      home: const AurigaScreen(),
    );
  }
}
