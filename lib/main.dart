// import 'package:flutter/material.dart';
// import 'auriga_screen.dart';

// void main() {
//   runApp(const AurigaDemoApp());
// }

// class AurigaDemoApp extends StatelessWidget {
//   const AurigaDemoApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'Auriga Host App',
//       home: const AurigaScreen(),
//     );
//   }
// }
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
      _updateStatus("Getting session token...");
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
        _updateStatus("Session token obtained ✅");
      } else {
        _updateStatus("Error getting session token: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error getting session token: $e");
    }
  }

  Future<void> _createNewSession() async {
    if (_sessionToken == null) await _getSessionToken();
    _updateStatus("Creating new streaming session...");
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
        _updateStatus("Session info received ✅");

        final room = Room();

        // Set up event listeners using the correct syntax for livekit_client 2.5.1
        room
          ..onTrackSubscribed = _onTrackSubscribed
          ..onTrackUnsubscribed = _onTrackUnsubscribed
          ..onDisconnected = _onDisconnected
          ..onParticipantDisconnected = _onParticipantDisconnected;

        _room = room;

        await room.prepareConnection(_livekitUrl!, _livekitToken!);
        _updateStatus("Room connection prepared ✅");
      } else {
        _updateStatus("Error creating session: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error creating session: $e");
    }
  }

  void _onTrackSubscribed(Track track, RemoteTrackPublication publication, RemoteParticipant participant) {
    _updateStatus("TrackSubscribed: ${track.kind}");
    if (track is RemoteVideoTrack) {
      setState(() {
        _videoTrack = track;
      });
    }
    setState(() {
      _connected = true;
    });
  }

  void _onTrackUnsubscribed(Track track, RemoteTrackPublication publication, RemoteParticipant participant) {
    _updateStatus("TrackUnsubscribed: ${track.kind}");
    if (track is RemoteVideoTrack) {
      setState(() {
        _videoTrack = null;
      });
    }
  }

  void _onDisconnected() {
    _updateStatus("Room disconnected");
    setState(() {
      _connected = false;
      _videoTrack = null;
    });
  }

  void _onParticipantDisconnected(RemoteParticipant participant) {
    _updateStatus("Participant disconnected: ${participant.identity}");
  }

  Future<void> _startStreaming() async {
    if (_sessionId == null || _room == null) {
      _updateStatus("Session not initialized");
      return;
    }
    
    _updateStatus("Starting streaming session...");
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
        _updateStatus("Connected to LiveKit room ✅");
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
        _updateStatus("Sent text ($task): $text");
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
      
      await _room?.disconnect();
      await _room?.dispose();
      
      setState(() {
        _room = null;
        _sessionId = null;
        _sessionToken = null;
        _connected = false;
        _videoTrack = null;
      });
      _updateStatus("Session closed ✅");
    } catch (e) {
      _updateStatus("Error closing session: $e");
    }
  }

  @override
  void dispose() {
    serverUrlCtrl.dispose();
    tokenCtrl.dispose();
    taskCtrl.dispose();
    _room?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: _connected ? null : () async {
                await _createNewSession();
                await _startStreaming();
              },
              child: const Text("Start Session"),
            ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _connected ? _closeSession : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("End Session"),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Row(
        children: [
          // Left side controls
          Expanded(
            flex: 1,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                TextField(
                  controller: serverUrlCtrl,
                  decoration: const InputDecoration(labelText: "Server URL"),
                ),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(labelText: "Access Token"),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: taskCtrl,
                  decoration: const InputDecoration(labelText: "Enter text for avatar"),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _connected ? () => _sendText(taskCtrl.text, task: "repeat") : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text("Repeat Text"),
                ),
                const SizedBox(height: 12),
                const Text("Session Status:", style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    color: Colors.grey.shade200,
                  ),
                  child: SingleChildScrollView(
                    child: Text(logText, style: const TextStyle(fontSize: 12)),
                  ),
                )
              ],
            ),
          ),
          // Right side video
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
                color: Colors.black,
              ),
              child: _videoTrack != null && _room?.isConnected == true
                  ? VideoTrackRenderer(_videoTrack!)
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.videocam_off, color: Colors.white54, size: 64),
                          SizedBox(height: 16),
                          Text("No Video Stream", style: TextStyle(color: Colors.white54)),
                        ],
                      )),
            ),
          )
        ],
      ),
    );
  }
}