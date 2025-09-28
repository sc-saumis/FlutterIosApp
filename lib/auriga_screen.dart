import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

class AurigaScreen extends StatefulWidget {
  const AurigaScreen({super.key});

  @override
  State<AurigaScreen> createState() => _AurigaScreenState();
}

class _AurigaScreenState extends State<AurigaScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted);

    _loadHtmlFromAssets();
  }

  Future<void> _loadHtmlFromAssets() async {
    // load your index.html from assets folder
    final html = await rootBundle.loadString('assets/auriga/index.html');

    // set baseUrl so that relative links (CSS, JS) resolve correctly
    _controller.loadHtmlString(
      html,
      baseUrl: 'https://auriga-chat-dev.scryai.com',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Auriga Widget")),
      body: WebViewWidget(controller: _controller),
    );
  }
}
