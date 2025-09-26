import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;
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
    
    _initializeWebView();
  }

  void _initializeWebView() {
    late final PlatformWebViewControllerCreationParams params;
    
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true, // Most important for iOS
        allowsPictureInPictureMediaPlayback: false, // Disable PiP
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final WebViewController controller =
        WebViewController.fromPlatformCreationParams(params);

    // Configure the controller
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (String url) {
          _injectPIPDisableScript();
        },
        onPageFinished: (String url) {
          _injectPIPDisableScript();
        },
      ));

    _controller = controller;
    _loadHtmlFromAssets();
  }

  Future<void> _loadHtmlFromAssets() async {
    try {
      final html = await rootBundle.loadString('assets/auriga/index.html');
      _controller.loadHtmlString(
        html,
        baseUrl: 'https://auriga-chat-dev.scryai.com',
      );
    } catch (e) {
      print('Error loading HTML: $e');
    }
  }

  Future<void> _injectPIPDisableScript() async {
    try {
      await _controller.runJavaScript('''
        (function() {
          function disablePictureInPicture() {
            var videos = document.querySelectorAll('video');
            for (var i = 0; i < videos.length; i++) {
              var video = videos[i];
              
              // Disable PiP if supported
              if ('disablePictureInPicture' in video) {
                video.disablePictureInPicture = true;
              }
              
              // Set attributes for inline playback
              video.setAttribute('playsinline', 'true');
              video.setAttribute('webkit-playsinline', 'true');
              video.setAttribute('x-webkit-airplay', 'deny');
              
              // Prevent PiP activation
              video.addEventListener('enterpictureinpicture', function(e) {
                if (document.exitPictureInPicture) {
                  document.exitPictureInPicture().catch(function() {});
                }
              });
              
              // Block context menu
              video.addEventListener('contextmenu', function(e) {
                e.preventDefault();
                return false;
              });
            }
          }
          
          // Run initially
          disablePictureInPicture();
          
          // Watch for new videos
          var observer = new MutationObserver(function(mutations) {
            var hasChanges = false;
            mutations.forEach(function(mutation) {
              if (mutation.addedNodes.length > 0) {
                hasChanges = true;
              }
            });
            if (hasChanges) {
              setTimeout(disablePictureInPicture, 150);
            }
          });
          
          observer.observe(document.body, {
            childList: true,
            subtree: true
          });
        })();
      ''');
    } catch (e) {
      print('Error injecting PIP script: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auriga Widget"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}