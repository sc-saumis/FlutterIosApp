import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

// Import the platform-specific WKWebView package
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

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
    // Use the WebKit-specific creation params for iOS
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        // This is the key property to disable PiP
        allowsPictureInPictureMediaPlayback: false,
        // You may also want to allow inline playback and disable other media interactions
        allowsInlineMediaPlayback: true,
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    _controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setMediaPlaybackRequiresUserGesture(false);

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
