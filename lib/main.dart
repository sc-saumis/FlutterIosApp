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

  void _updateStatus(String msg) {
    final timestamp = TimeOfDay.now().format(context);
    setState(() {
      logText += "[$timestamp] $msg\n";
    });
    debugPrint(msg);
  }

  Future<void> _getSessionToken() async {
    final res = await http.post(
      Uri.parse("${serverUrlCtrl.text}/avatar/generate-session-token"),
      headers: {
        "Content-Type": "application/json",
        "access-token": tokenCtrl.text.trim(),
      },
    );
    final data = jsonDecode(res.body);
    _sessionToken = data["data"]["token"];
    _updateStatus("Session token obtained ✅");
  }

  Future<void> _createNewSession() async {
    if (_sessionToken == null) await _getSessionToken();
    _updateStatus("Creating new streaming session...");

    final res = await http.post(
      Uri.parse("${serverUrlCtrl.text}/avatar/create-avatar-session"),
      headers: {
        "Content-Type": "application/json",
        "access-token": tokenCtrl.text.trim(),
      },
      body: jsonEncode({"sessionToken": _sessionToken}),
    );
    final data = jsonDecode(res.body)["data"];
    _sessionId = data["session_id"];
    _livekitUrl = data["url"];
    _livekitToken = data["access_token"];
    _updateStatus("Session info received ✅");

    final room = Room(adaptiveStream: true, dynacast: true);
    room.on<TrackSubscribedEvent>((e) {
      _updateStatus("TrackSubscribed: ${e.track.kind}");
      setState(() {
        _connected = true;
      });
    });
    room.on<RoomDisconnectedEvent>((e) {
      _updateStatus("Room disconnected: ${e.reason}");
    });
    _room = room;

    // Prepare connection (like JS prepareConnection)
    await room.prepareConnection(_livekitUrl!, _livekitToken!);
    _updateStatus("Room connection prepared ✅");
  }

  Future<void> _startStreaming() async {
    if (_sessionId == null) return;
    _updateStatus("Starting streaming session...");

    await http.post(
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

    await _room?.connect(_livekitUrl!, _livekitToken!);
    _updateStatus("Connected to LiveKit room ✅");
  }

  Future<void> _sendText(String text, {String task = "repeat"}) async {
    if (_sessionId == null) return;
    await http.post(
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
    _updateStatus("Sent text ($task): $text");
  }

  Future<void> _closeSession() async {
    if (_sessionId == null) return;
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
    setState(() {
      _room = null;
      _sessionId = null;
      _sessionToken = null;
      _connected = false;
    });
    _updateStatus("Session closed ✅");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Auriga | Interactive Avatar"),
        backgroundColor: Colors.indigo,
        actions: [
          ElevatedButton(
            onPressed: () async {
              await _createNewSession();
              await _startStreaming();
            },
            child: const Text("Start Session"),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _closeSession,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
                // Config
                TextField(
                  controller: serverUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: "Server URL",
                  ),
                ),
                TextField(
                  controller: tokenCtrl,
                  decoration: const InputDecoration(
                    labelText: "Access Token",
                  ),
                ),
                const SizedBox(height: 12),
                // Text Input
                TextField(
                  controller: taskCtrl,
                  decoration: const InputDecoration(
                    labelText: "Enter text for avatar",
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => _sendText(taskCtrl.text, task: "repeat"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                  ),
                  child: const Text("Repeat Text"),
                ),
                const SizedBox(height: 12),
                // Status Log
                const Text(
                  "Session Status:",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
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
          // Right side video + audio
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black),
                color: Colors.black,
              ),
              child: _connected && _room != null && _room!.remoteParticipants.isNotEmpty
                  ? ParticipantWidget.participant(
                      _room!.remoteParticipants.values.first,
                      showStatsLayer: false,
                    )
                  : const Center(
                      child: Text("No Video/Audio Stream",
                          style: TextStyle(color: Colors.white))),
            ),
          )
        ],
      ),
    );
  }
}
