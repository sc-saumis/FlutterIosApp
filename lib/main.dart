import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

void main() {
  runApp(const AurigaApp());
}

class AurigaApp extends StatelessWidget {
  const AurigaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Auriga | Interactive Avatar',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const AvatarScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  final TextEditingController serverUrlCtrl =
      TextEditingController(text: "http://localhost:9000");
  final TextEditingController tokenCtrl = TextEditingController();
  final TextEditingController taskCtrl = TextEditingController();

  String logText = "";
  Room? _room;
  String? _sessionId;
  String? _sessionToken;
  String? _livekitUrl;
  String? _livekitToken;
  bool _connected = false;
  bool _isLoading = false;

  RemoteVideoTrack? _videoTrack;
  EventsListener<RoomEvent>? _roomListener;

  void _updateStatus(String msg) {
    final timestamp = TimeOfDay.now().format(context);
    setState(() {
      logText += "[$timestamp] $msg\n";
      _isLoading = false;
    });
    debugPrint(msg);
  }

  Future<void> _getSessionToken() async {
    try {
      _updateStatus("Requesting avatar session token from Auriga...");
      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/generate-session-token"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        _sessionToken = data["data"]["token"];
        _updateStatus("Session token received for Auriga avatar!");
      } else {
        _updateStatus("Error getting session token: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error getting session token: $e");
    }
  }

  Future<void> _createNewSession() async {
    if (_sessionToken == null) await _getSessionToken();
    _updateStatus("Creating a new Auriga avatar session...");
    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/create-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
        body: jsonEncode({"sessionToken": _sessionToken}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body)["data"];
        _sessionId = data["session_id"];
        _livekitUrl = data["url"];
        _livekitToken = data["access_token"];
        _updateStatus("Session information received for Auriga avatar.");

        final room = Room();
        _roomListener = room.createListener();

        _roomListener!.on<TrackSubscribedEvent>((event) {
          _updateStatus(
              "Auriga Avatar TrackSubscribed: ${event.track.kind} from ${event.participant.identity}");
          if (event.track is RemoteVideoTrack) {
            setState(() {
              _videoTrack = event.track as RemoteVideoTrack;
            });
          }
          setState(() {
            _connected = true;
          });
        });

        _roomListener!.on<TrackUnsubscribedEvent>((event) {
          _updateStatus(
              "Auriga Avatar TrackUnsubscribed: ${event.track.kind}");
          if (event.track is RemoteVideoTrack) {
            setState(() {
              _videoTrack = null;
            });
          }
        });

        _roomListener!.on<RoomDisconnectedEvent>((event) {
          _updateStatus("Room disconnected: ${event.reason}");
          setState(() {
            _connected = false;
            _videoTrack = null;
          });
        });

        _room = room;
        await room.prepareConnection(_livekitUrl!, _livekitToken!);
        _updateStatus(
            "Auriga Avatar connection prepared. The Avatar will connect shortly ...");
      } else {
        _updateStatus("Error creating session: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error creating session: $e");
    }
  }

  Future<void> _startStreaming() async {
    if (_sessionId == null || _room == null) {
      _updateStatus("Session not initialized");
      return;
    }

    _updateStatus("Starting Auriga Avatar Live Session...");
    setState(() => _isLoading = true);

    try {
      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/start-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "sessionId": _sessionId,
        }),
      );

      if (res.statusCode == 200) {
        await _room!.connect(_livekitUrl!, _livekitToken!);
        _updateStatus("Connected to Auriga LiveKit room ✅");
        _updateStatus("Playing Auriga avatar media");
      } else {
        _updateStatus("Error starting streaming: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error starting streaming: $e");
    }
  }

  Future<void> _sendText(String text, {String task = "repeat"}) async {
    if (_sessionId == null || _room == null) {
      _updateStatus("Session not initialized");
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/execute-avatar-task"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "sessionId": _sessionId,
          "text": text,
          "task": task
        }),
      );

      if (res.statusCode == 200) {
        _updateStatus(
            "Sent text to Auriga Avatar ($task): $text");
      } else {
        _updateStatus("Error sending text: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error sending text: $e");
    }
  }

  Future<void> _closeSession() async {
    if (_sessionId == null) return;

    _updateStatus("Closing session...");
    setState(() => _isLoading = true);

    try {
      await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/stop-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "sessionId": _sessionId,
        }),
      );

      await _roomListener?.dispose();
      await _room?.disconnect();

      setState(() {
        _room = null;
        _sessionId = null;
        _sessionToken = null;
        _connected = false;
        _videoTrack = null;
        _roomListener = null;
      });
      _updateStatus("Session closed for Auriga Avatar");
    } catch (e) {
      _updateStatus("Error closing session: $e");
    }
  }

  @override
  void dispose() {
    serverUrlCtrl.dispose();
    tokenCtrl.dispose();
    taskCtrl.dispose();
    _roomListener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Auriga | Interactive Avatar"),
        backgroundColor: Colors.indigo,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator(color: Colors.white),
            )
          else
            ElevatedButton(
              onPressed: _connected
                  ? null
                  : () async {
                      await _createNewSession();
                      await _startStreaming();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: const Text("Start", style: TextStyle(fontSize: 14)),
            ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _connected ? _closeSession : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: const Text("End", style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: isPortrait ? _buildPortraitLayout() : _buildLandscapeLayout(),
    );
  }

  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildControlsSection(),
          const SizedBox(height: 16),
          _buildVideoSection(height: 250, iconSize: 48),
        ],
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    return Column(
      children: [
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildControlsSection(),
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildVideoSection(iconSize: 64),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoSection(
      {double height = double.infinity, double iconSize = 48}) {
    return Container(
      width: double.infinity,
      height: height == double.infinity ? null : height,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: _videoTrack != null && _connected
          ? VideoTrackRenderer(_videoTrack!)
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off, color: Colors.white54, size: iconSize),
                  const SizedBox(height: 12),
                  const Text("No Video Stream",
                      style: TextStyle(color: Colors.white54)),
                ],
              ),
            ),
    );
  }

  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Configuration",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: serverUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: "Server URL",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: "Access Token",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Send Text to Auriga Avatar",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: taskCtrl,
                  decoration: const InputDecoration(
                    labelText: "Enter text for avatar to speak",
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _connected
                        ? () => _sendText(taskCtrl.text, task: "repeat")
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Repeat Text",
                        style: TextStyle(fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Auriga Avatar Session Status",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      logText.isEmpty
                          ? "[11:16:39 AM] Requesting avatar session token from Auriga...\n"
                          : logText,
                      style: const TextStyle(
                          fontSize: 12, fontFamily: 'Monospace'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
