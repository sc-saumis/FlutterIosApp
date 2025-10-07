import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const AurigaApp());
}

class AurigaApp extends StatelessWidget {
  const AurigaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScryAI - Auriga | Interactive Avatar',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        fontFamily: 'sans-serif',
      ),
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
  final TextEditingController _serverUrlController = TextEditingController(text: "http://localhost:9000");
  final TextEditingController _accessTokenController = TextEditingController();
  final TextEditingController _taskInputController = TextEditingController();
  
  final List<String> _statusMessages = [];
  final ScrollController _statusScrollController = ScrollController();
  
  Room? _room;
  String? _sessionId;
  String? _sessionToken;
  String? _livekitUrl;
  String? _livekitToken;
  bool _isLoading = false;
  bool _connected = false;
  
  // Audio file handling
  PlatformFile? _selectedPcmFile;
  bool _hasSelectedFile = false;
  
  // Video track
  VideoTrack? _videoTrack;
  EventsListener<RoomEvent>? _listener;

  @override
  void initState() {
    super.initState();
    _updateFileInputAvailability();
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _accessTokenController.dispose();
    _taskInputController.dispose();
    _statusScrollController.dispose();
    _listener?.dispose();
    _room?.dispose();
    super.dispose();
  }

  void _updateStatus(String msg, {bool error = false}) {
    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final formattedMsg = error ? '[$timestamp] ERROR: $msg' : '[$timestamp] $msg';
    
    setState(() {
      _statusMessages.add(formattedMsg);
    });
    
    // Auto-scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _statusScrollController.animateTo(
        _statusScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });

    if (error) {
      debugPrint('ERROR: $msg');
    } else {
      debugPrint('INFO: $msg');
    }
  }

  void _updateFileInputAvailability() {
    setState(() {
      _hasSelectedFile = _selectedPcmFile != null;
    });
  }

  void _updateConfig() {
    if (_serverUrlController.text.trim().isNotEmpty) {
      // Config is updated when used
    }
    if (_accessTokenController.text.trim().isNotEmpty) {
      // Config is updated when used
    }
  }

  String get _serverUrl => _serverUrlController.text.trim();
  String get _accessToken => _accessTokenController.text.trim();

  Future<void> _getSessionToken() async {
    try {
      _updateStatus("Requesting avatar session token from Auriga...");
      _updateConfig();
      
      final response = await http.post(
        Uri.parse("$_serverUrl/avatar/generate-session-token"),
        headers: {
          "Content-Type": "application/json",
          "access-token": _accessToken,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _sessionToken = data["data"]["token"];
        _updateStatus("Session token received for Auriga Avatar!");
      } else {
        _updateStatus("Error getting session token: ${response.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error getting session token: $e", error: true);
    }
  }

  Future<void> _createNewSession() async {
    try {
      if (_sessionToken == null) await _getSessionToken();
      _updateStatus("Creating a new Auriga Avatar session...");
      setState(() => _isLoading = true);

      final response = await http.post(
        Uri.parse("$_serverUrl/avatar/create-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": _accessToken,
        },
        body: jsonEncode({"sessionToken": _sessionToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sessionData = data["data"];
        _sessionId = sessionData["session_id"];
        _livekitUrl = sessionData["url"];
        _livekitToken = sessionData["access_token"];
        _updateStatus("Session information received for Auriga Avatar.");

        // Initialize room
        _room = Room();
        _listener = _room!.createListener();

        // Set up event listeners
        _listener!.on<TrackSubscribedEvent>((event) {
          _updateStatus("Auriga Avatar TrackSubscribed: ${event.track.kind}");
          
          if (event.track is VideoTrack) {
            setState(() {
              _videoTrack = event.track as VideoTrack;
            });
          }
        });

        _listener!.on<TrackUnsubscribedEvent>((event) {
          _updateStatus("Auriga Avatar TrackUnsubscribed: ${event.track.kind}");
          if (event.track is VideoTrack) {
            setState(() {
              _videoTrack = null;
            });
          }
        });

        _listener!.on<RoomDisconnectedEvent>((event) {
          _updateStatus("Room disconnected: ${event.reason}", error: true);
          setState(() {
            _connected = false;
            _videoTrack = null;
          });
        });

        await _room!.prepareConnection(_livekitUrl!, _livekitToken!);
        _updateStatus("Auriga Avatar connection prepared. The Avatar will connect shortly ...");
        _updateFileInputAvailability();
      } else {
        _updateStatus("Error creating session: ${response.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error creating session: $e", error: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startStreamingSession() async {
    try {
      if (_sessionId == null) {
        _updateStatus("Auriga Avatar session information missing!", error: true);
        return;
      }
      
      _updateStatus("Starting Auriga Avatar Live Session...");
      setState(() => _isLoading = true);

      final response = await http.post(
        Uri.parse("$_serverUrl/avatar/start-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": _accessToken,
        },
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "sessionId": _sessionId,
        }),
      );

      if (response.statusCode == 200) {
        await _room!.connect(_livekitUrl!, _livekitToken!);
        _updateStatus("Connected to Auriga LiveKit room ✅");
        setState(() {
          _connected = true;
        });
      } else {
        _updateStatus("Error starting streaming: ${response.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error starting streaming: $e", error: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendText(String text, {String taskType = "repeat"}) async {
    try {
      if (_sessionId == null) {
        _updateStatus("No active Auriga Avatar session", error: true);
        return;
      }

      final response = await http.post(
        Uri.parse("$_serverUrl/avatar/execute-avatar-task"),
        headers: {
          "Content-Type": "application/json",
          "access-token": _accessToken,
        },
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "sessionId": _sessionId,
          "text": text,
          "task": taskType,
        }),
      );

      if (response.statusCode == 200) {
        _updateStatus("Sent text to Auriga Avatar ($taskType): $text");
      } else {
        _updateStatus("Error sending text: ${response.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error sending text: $e", error: true);
    }
  }

  Future<void> _selectPcmFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pcm'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _selectedPcmFile = result.files.first;
          _hasSelectedFile = true;
        });
        _updateStatus("Selected PCM16 audio file: ${_selectedPcmFile!.name}");
      }
    } catch (e) {
      _updateStatus("Error selecting file: $e", error: true);
    }
  }

  Future<void> _transcribePcmFile() async {
    _updateConfig();
    
    if (_selectedPcmFile == null) {
      _updateStatus("No PCM16 audio file selected!", error: true);
      return;
    }
    
    if (_sessionId == null || _sessionToken == null) {
      _updateStatus("Session information is missing. Please start the session first!", error: true);
      return;
    }

    _updateStatus("Sending raw audio file via FormData to transcription API...");

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$_serverUrl/avatar/execute-avatar-audio'),
      );

      request.headers['access-token'] = _accessToken;

      request.fields['sessionToken'] = _sessionToken!;
      request.fields['sessionId'] = _sessionId!;

      if (_selectedPcmFile!.path != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'audio',
          _selectedPcmFile!.path!,
          filename: _selectedPcmFile!.name,
        ));
      } else if (_selectedPcmFile!.bytes != null) {
        request.files.add(http.MultipartFile.fromBytes(
          'audio',
          _selectedPcmFile!.bytes!,
          filename: _selectedPcmFile!.name,
        ));
      } else {
        _updateStatus("No file data available", error: true);
        return;
      }

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var data = json.decode(responseData);

      if (response.statusCode == 200) {
        if (data['transcription'] != null) {
          _updateStatus("Transcription result: ${data['transcription']}");
        } else {
          _updateStatus("Transcription failed!", error: true);
        }
      } else {
        _updateStatus("Transcription API error: ${response.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error calling transcription API: $e", error: true);
    }
  }

  Future<void> _closeSession() async {
    try {
      if (_sessionId == null) {
        _updateStatus("No active Auriga Avatar session");
        return;
      }

      _updateStatus("Closing session...");
      setState(() => _isLoading = true);

      await http.post(
        Uri.parse("$_serverUrl/avatar/stop-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": _accessToken,
        },
        body: jsonEncode({
          "sessionToken": _sessionToken,
          "sessionId": _sessionId,
        }),
      );

      await _listener?.dispose();
      await _room?.disconnect();

      setState(() {
        _room = null;
        _sessionId = null;
        _sessionToken = null;
        _connected = false;
        _videoTrack = null;
        _listener = null;
        _selectedPcmFile = null;
        _hasSelectedFile = false;
      });

      _updateStatus("Session closed for Auriga Avatar");
    } catch (e) {
      _updateStatus("Error closing session: $e", error: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startSession() async {
    await _createNewSession();
    await _startStreamingSession();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            color: Colors.indigo[700],
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'ScryAI - Auriga | Interactive Avatar',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: _connected ? null : _startSession,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[500],
                        disabledBackgroundColor: Colors.green[500]!.withOpacity(0.5),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Start Session'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _connected ? _closeSession : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red[500],
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('End Session'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth > 1024) {
                    return _buildDesktopLayout();
                  } else {
                    return _buildMobileLayout();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildConfigSection(),
                const SizedBox(height: 16),
                _buildTextInputSection(),
                const SizedBox(height: 16),
                _buildAudioInputSection(),
                const SizedBox(height: 16),
                _buildStatusSection(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 24),
        // Right Column
        Expanded(
          flex: 2,
          child: _buildVideoSection(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildConfigSection(),
          const SizedBox(height: 16),
          _buildTextInputSection(),
          const SizedBox(height: 16),
          _buildAudioInputSection(),
          const SizedBox(height: 16),
          _buildVideoSection(),
          const SizedBox(height: 16),
          _buildStatusSection(),
        ],
      ),
    );
  }

  Widget _buildConfigSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Configuration',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.indigo[700],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: 'Server URL',
                hintText: 'Enter Server URL (e.g. http://localhost:9000)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _accessTokenController,
              decoration: const InputDecoration(
                labelText: 'Access Token',
                hintText: 'Enter Access Token',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextInputSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send Text to Auriga Avatar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.indigo[700],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _taskInputController,
                    decoration: const InputDecoration(
                      hintText: 'Enter text for avatar to speak',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _connected
                      ? () {
                          final text = _taskInputController.text.trim();
                          if (text.isNotEmpty) {
                            _sendText(text, taskType: "repeat");
                            _taskInputController.clear();
                          }
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Repeat Text'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioInputSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send Audio to Auriga Avatar',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.indigo[700],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _connected ? _selectPcmFile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Select PCM16 Audio'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_connected && _hasSelectedFile) ? _transcribePcmFile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Send Audio'),
                  ),
                ),
              ],
            ),
            if (_hasSelectedFile) ...[
              const SizedBox(height: 8),
              Text(
                'Selected: ${_selectedPcmFile!.name}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auriga Avatar Session Status',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.indigo[700],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 200,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border.all(color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                controller: _statusScrollController,
                child: Text(
                  _statusMessages.isEmpty ? 'Session status will appear here...' : _statusMessages.join('\n'),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auriga Avatar Stream',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.indigo[700],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              height: 400,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.black),
              ),
              child: _videoTrack != null && _connected
                  ? VideoTrackRenderer(_videoTrack!)
                  : Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_off,
                            color: Colors.white54,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'No Video Stream',
                            style: TextStyle(color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}