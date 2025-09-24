import 'package:flutter/material.dart';

void main() {
  runApp(const AurigaDemoApp());
}

class AurigaDemoApp extends StatelessWidget {
  const AurigaDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dummy Host Site',
      home: Scaffold(
        appBar: AppBar(
          title: const Text("Dummy Host Website"),
          backgroundColor: Colors.blue,
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const Text(
                "Integrating Auriga Chatbot Widget in style",
                style: TextStyle(fontSize: 18),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    "Chatbot Controls (Flutter)",
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(12),
          color: Colors.grey[200],
          child: const Text(
            "© 2025 Dummy Host Inc.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }
}
