import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // Import for checking platform
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

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

    // Create a new WebViewController instance.
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setMediaPlaybackRequiresUserGesture(false);

    // Conditionally apply iOS-specific configuration
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Access the platform-specific implementation
      final platform = _controller.platform;
      if (platform is WebKitWebViewController) {
        platform.setAllowsPictureInPictureMediaPlayback(false);
      }
    }
    
    _loadHtmlFromAssets();
  }

  Future<void> _loadHtmlFromAssets() async {
    final html = await rootBundle.loadString('assets/auriga/index.html');
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
