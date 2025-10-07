import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

void main() {
  runApp(const AurigaApp());
}

// Main application widget
class AurigaApp extends StatelessWidget {
  const AurigaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ScryAI - Auriga | Interactive Avatar',
      theme: ThemeData(primarySwatch: Colors.indigo),
      home: const AvatarScreen(), // The main screen of the app
      debugShowCheckedModeBanner: false,
    );
  }
}

// Main screen that manages the avatar interaction
class AvatarScreen extends StatefulWidget {
  const AvatarScreen({super.key});

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen> {
  // Controllers for text input fields
  final TextEditingController serverUrlCtrl =
      TextEditingController(text: "http://localhost:9000");
  final TextEditingController tokenCtrl = TextEditingController();
  final TextEditingController taskCtrl = TextEditingController();

  // State variables
  String logText = ""; // For storing status messages
  Room? _room; // LiveKit room object for video connection
  String? _sessionId; // Unique session ID from Auriga service
  String? _sessionToken; // Authentication token for Auriga service
  String? _livekitUrl; // URL for LiveKit video server
  String? _livekitToken; // Token for LiveKit connection
  bool _connected = false; // Whether we're connected to the avatar
  bool _isLoading = false; // For showing loading indicator
  
  // Audio file handling
  html.File? _selectedPcmFile;
  bool _hasSelectedFile = false;
  
  bool _isPcmSelected = false;
  String? _selectedPcmFileName;
  Uint8List? _selectedPcmData;

  // Video track for displaying the avatar stream
  RemoteVideoTrack? _videoTrack;
  // Listener for room events (connection, disconnection, etc.)
  EventsListener<RoomEvent>? _roomListener;

  // Helper method to update status messages with timestamp
  void _updateStatus(String msg, {bool error = false}) {
    final timestamp = TimeOfDay.now().format(context);
    setState(() {
      if (error) {
        logText += "[$timestamp] ERROR: $msg\n";
      } else {
        logText += "[$timestamp] $msg\n";
      }
      _isLoading = false;
    });
    if (error) {
      debugPrint("ERROR: $msg");
    } else {
      debugPrint("INFO: $msg");
    }
  }

  // Update file input availability
  void _updateFileInputAvailability() {
    setState(() {
      _hasSelectedFile = _selectedPcmFile != null;
    });
  }

  // Step 1: Get session token from Auriga server
  Future<void> _getSessionToken() async {
    try {
      _updateStatus("Requesting avatar session token from Auriga...");
      // Make HTTP POST request to get session token
      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/generate-session-token"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(), // Authentication
        },
      );

      if (res.statusCode == 200) {
        // Parse successful response
        final data = jsonDecode(res.body);
        _sessionToken = data["data"]["token"];
        _updateStatus("Session token received for Auriga avatar!");
      } else {
        _updateStatus("Error getting session token: ${res.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error getting session token: $e", error: true);
    }
  }

  // Step 2: Create a new avatar session
  Future<void> _createNewSession() async {
    // Ensure we have a session token first
    if (_sessionToken == null) await _getSessionToken();
    _updateStatus("Creating a new Auriga avatar session...");
    setState(() => _isLoading = true); // Show loading indicator

    try {
      // Make HTTP POST request to create session
      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/create-avatar-session"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
        body: jsonEncode({"sessionToken": _sessionToken}),
      );

      if (res.statusCode == 200) {
        // Parse successful response
        final data = jsonDecode(res.body)["data"];
        _sessionId = data["session_id"];
        _livekitUrl = data["url"]; // LiveKit server URL
        _livekitToken = data["access_token"]; // LiveKit access token
        _updateStatus("Session information received for Auriga avatar.");

        // Initialize LiveKit room
        final room = Room();
        _roomListener = room.createListener(); // Create event listener

        // Listen for when a video track becomes available (avatar starts streaming)
        _roomListener!.on<TrackSubscribedEvent>((event) {
          _updateStatus(
              "Auriga Avatar TrackSubscribed: ${event.track.kind} from ${event.participant.identity}");
          if (event.track is RemoteVideoTrack) {
            setState(() {
              _videoTrack = event.track as RemoteVideoTrack; // Store video track for display
            });
          }
          setState(() {
            _connected = true; // Mark as connected
          });
        });

        // Listen for when video track ends
        _roomListener!.on<TrackUnsubscribedEvent>((event) {
          _updateStatus("Auriga Avatar TrackUnsubscribed: ${event.track.kind}");
          if (event.track is RemoteVideoTrack) {
            setState(() {
              _videoTrack = null;
            });
          }
        });

        // Listen for room disconnection
        _roomListener!.on<RoomDisconnectedEvent>((event) {
          _updateStatus("Room disconnected: ${event.reason}", error: true);
          setState(() {
            _connected = false;
            _videoTrack = null; // Clear video track
          });
        });

        _room = room;
        await room.prepareConnection(_livekitUrl!, _livekitToken!);
        _updateStatus(
            "Auriga Avatar connection prepared. The Avatar will connect shortly ...");
        // Enable file input now that session is active
        _updateFileInputAvailability();
      } else {
        _updateStatus("Error creating session: ${res.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error creating session: $e", error: true);
    }
  }

  // Step 3: Start the avatar streaming session
  Future<void> _startStreaming() async {
    if (_sessionId == null || _room == null) {
      _updateStatus("Session not initialized", error: true);
      return;
    }

    _updateStatus("Starting Auriga Avatar Live Session...");
    setState(() => _isLoading = true);

    try {
      // Tell Auriga server to start the avatar session
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
        // Connect to LiveKit room to receive video stream
        await _room!.connect(_livekitUrl!, _livekitToken!);
        _updateStatus("Connected to Auriga LiveKit room ✅");
        _updateStatus("Playing Auriga avatar media");
      } else {
        _updateStatus("Error starting streaming: ${res.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error starting streaming: $e", error: true);
    }
  }

  // Send text to the avatar to make it speak
  Future<void> _sendText(String text, {String task = "repeat"}) async {
    if (_sessionId == null || _room == null) {
      _updateStatus("Session not initialized", error: true);
      return;
    }

    try {
      // Send text to Auriga server for the avatar to speak
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
          "task": task // Type of task (e.g., "repeat" for speaking)
        }),
      );

      if (res.statusCode == 200) {
        _updateStatus("Sent text to Auriga Avatar ($task): $text");
      } else {
        _updateStatus("Error sending text: ${res.statusCode}", error: true);
      }
    } catch (e) {
      _updateStatus("Error sending text: $e", error: true);
    }
  }

  // Select PCM file
  Future<void> _selectPcmFile() async {
    final input = html.FileUploadInputElement();
    input.accept = '.pcm';
    input.click();

    input.onChange.listen((e) {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        setState(() {
          _selectedPcmFile = files[0];
          _hasSelectedFile = true;
        });
        _updateStatus("Selected PCM16 audio file: ${_selectedPcmFile!.name}");
      }
    });
  }

  // Transcribe PCM file
  Future<void> _transcribePcmFile() async {
    if (_selectedPcmFile == null) {
      _updateStatus("No PCM16 audio file selected!", error: true);
      return;
    }
    if (_sessionId == null || _sessionToken == null) {
      _updateStatus("Session information is missing. Please start the session first!", error: true);
      return;
    }

    final formData = html.FormData();
    formData.appendBlob('audio', _selectedPcmFile!, _selectedPcmFile!.name);
    formData.append('sessionToken', _sessionToken!);
    formData.append('sessionId', _sessionId!);

    _updateStatus("Sending raw audio file via FormData to transcription API...");

    try {
      final response = await html.HttpRequest.request(
        '${serverUrlCtrl.text}/avatar/execute-avatar-audio',
        method: 'POST',
        requestHeaders: {
          'access-token': tokenCtrl.text.trim(),
        },
        sendData: formData,
      );

      final data = json.decode(response.responseText);
      if (data['transcription'] != null) {
        _updateStatus("Transcription result: ${data['transcription']}");
      } else {
        _updateStatus("Transcription failed!", error: true);
      }
    } catch (err) {
      _updateStatus("Error calling transcription API!", error: true);
    }
  }

  // Step 4: Close the session when done
  Future<void> _closeSession() async {
    if (_sessionId == null) return;

    _updateStatus("Closing session...");
    setState(() {
      _isLoading = true;
    });

    try {
      // Tell Auriga server to stop the session
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

      // Clean up LiveKit resources
      await _roomListener?.dispose();
      await _room?.disconnect();

      // Reset all state variables
      setState(() {
        _room = null;
        _sessionId = null;
        _sessionToken = null;
        _connected = false;
        _videoTrack = null;
        _roomListener = null;
        _selectedPcmFile = null;
        _hasSelectedFile = false;
        _isPcmSelected = false;
        _selectedPcmFileName = null;
        _selectedPcmData = null;
      });
      _updateStatus("Session closed for Auriga Avatar");
    } catch (e) {
      _updateStatus("Error closing session: $e", error: true);
    }
  }

  // Method to select PCM file
  Future<void> _selectPcmFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pcm'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final bytes = await file.readAsBytes();

        if (bytes.lengthInBytes > 10 * 1024 * 1024) { // 10MB limit
          _updateStatus("File too large. Please select a smaller PCM file.");
          return;
        }
        
        setState(() {
          _selectedPcmData = bytes;
          _selectedPcmFileName = result.files.single.name;
          _isPcmSelected = true;
        });
        _updateStatus("Selected PCM16 audio file: $_selectedPcmFileName");
      }
    } catch (e) {
      _updateStatus("Error selecting PCM file: $e");
    }
  }

  // Method to transcribe PCM audio
  Future<void> _transcribePcmAudio() async {
    if (_selectedPcmData == null) {
      _updateStatus("No PCM16 audio file selected!");
      return;
    }

    if (_sessionId == null) {
      _updateStatus("No active Auriga Avatar session");
      return;
    }

    _updateStatus("Sending audio to transcription API...");
    setState(() => _isLoading = true);

    try {
      // Convert bytes to base64
      final base64Audio = base64Encode(_selectedPcmData!);

      final res = await http.post(
        Uri.parse("${serverUrlCtrl.text}/avatar/transcribe"),
        headers: {
          "Content-Type": "application/json",
          "access-token": tokenCtrl.text.trim(),
        },
        body: jsonEncode({"audio": base64Audio}),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['transcription'] != null) {
          final transcription = data['transcription'];
          _updateStatus("Transcription result: $transcription");
          
          // Automatically send the transcription to the avatar
          await _sendText(transcription, task: "repeat");
        } else {
          _updateStatus("Transcription failed!");
        }
      } else {
        _updateStatus("Error in transcription: ${res.statusCode}");
      }
    } catch (e) {
      _updateStatus("Error calling transcription API: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    // Clean up controllers and resources when widget is disposed
    serverUrlCtrl.dispose();
    tokenCtrl.dispose();
    taskCtrl.dispose();
    _roomListener?.dispose();
    _room?.dispose();
    _selectedPcmData = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check device orientation for responsive layout
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;

    return Scaffold(
      appBar: AppBar(
        title: const Text("ScryAI - Auriga | Interactive Avatar"),
        backgroundColor: Colors.indigo[700],
        actions: [
          // Start button - only enabled when not connected
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
                      // Start sequence: create session then start streaming
                      await _createNewSession();
                      await _startStreaming();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[500],
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
              child: const Text("Start Session", style: TextStyle(fontSize: 14)),
            ),
          const SizedBox(width: 8),
          // End button - only enabled when connected
          ElevatedButton(
            onPressed: _connected ? _closeSession : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red[500],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: const Text("End Session", style: TextStyle(fontSize: 14)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Different layouts for portrait and landscape orientations
      body: isPortrait ? _buildPortraitLayout() : _buildLandscapeLayout(),
    );
  }

  Widget _buildPortraitLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildControlsSection(), // Input controls at top
          const SizedBox(height: 16),
          _buildAudioSection(),
          const SizedBox(height: 16),
          _buildVideoSection(height: 250, iconSize: 48), // Video at bottom
        ],
      ),
    );
  }

  // Layout for landscape orientation (side by side)
  Widget _buildLandscapeLayout() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildControlsSection(),
                  const SizedBox(height: 16),
                  _buildAudioSection(),
                ],
              ),
            ),
          ),
          const SizedBox(width: 16),
        Expanded(
          flex: 2,
            child: _buildVideoSection(iconSize: 64),
          ),
        ],
      ),
    );
  }

  // Video display section
  Widget _buildVideoSection(
      {double height = double.infinity, double iconSize = 48}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Auriga Avatar Stream",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black),
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      // Display video track if available, otherwise show placeholder
      child: _videoTrack != null && _connected
          ? VideoTrackRenderer(_videoTrack!) // Render the video stream
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Send Audio to Auriga Avatar",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Select PCM16 Audio"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (_connected && _hasSelectedFile) ? _transcribePcmFile : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text("Send Audio"),
                  ),
                ),
              ],
            ),
            if (_hasSelectedFile) ...[
              const SizedBox(height: 8),
              Text(
                "Selected: ${_selectedPcmFile!.name}",
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
                ],
              ),
            ),
    );
  }

  // Controls and input section
  Widget _buildControlsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Server configuration card
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
        
        // Text input card for sending text to avatar
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
                        ? () {
                            if (taskCtrl.text.trim().isNotEmpty) {
                              _sendText(taskCtrl.text.trim(), task: "repeat");
                              taskCtrl.clear();
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[600],
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

        // NEW: PCM Audio Transcription Card
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Transcribe PCM16 Audio",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                // File selection info
                if (_selectedPcmFileName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      "Selected: $_selectedPcmFileName",
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                
                // Buttons row
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _sessionId != null ? _selectPcmFile : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text("Select PCM16 Audio"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_isPcmSelected && _sessionId != null && !_isLoading)
                            ? _transcribePcmAudio
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text("Send Audio"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
          
        // Status log card
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
                          ? "Session status will appear here...\n"
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