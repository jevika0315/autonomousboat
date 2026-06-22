// ============================================================
// EV SQUARE - WebRTC Service
// Handles WebRTC connection and signaling from the Flutter side
// ============================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

// ─────────────────────────────────────────────────────────────
// Connection status enum — used to update the UI
// ─────────────────────────────────────────────────────────────
enum ConnectionStatus {
  disconnected,   // Not connected at all
  connecting,     // Trying to connect
  waitingForPi,   // Connected to signaling server, Pi not yet online
  negotiating,    // Exchanging WebRTC offer/answer
  connected,      // Video is streaming
  error,          // Something went wrong
}

// ─────────────────────────────────────────────────────────────
// WebRTC Service
// ─────────────────────────────────────────────────────────────
class WebRTCService extends ChangeNotifier {
  // ── Public state (watched by the UI) ───────────────────────
  ConnectionStatus status = ConnectionStatus.disconnected;
  String statusMessage = 'Not connected';
  RTCVideoRenderer? remoteRenderer;   // The widget that shows the video
  String? errorMessage;

  // ── Private state ───────────────────────────────────────────
  WebSocketChannel? _channel;
  RTCPeerConnection? _pc;
  StreamSubscription? _wsSubscription;
  bool _disposed = false;

  // ── ICE servers (STUN — helps WebRTC punch through routers) ─
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // ─────────────────────────────────────────────────────────────
  // CONNECT
  // Called when user taps the "Connect" button.
  // signalingUrl example: "ws://192.168.1.10:8765"
  // ─────────────────────────────────────────────────────────────
  Future<void> connect(String signalingUrl) async {
    if (status == ConnectionStatus.connecting ||
        status == ConnectionStatus.connected) return;

    _setStatus(ConnectionStatus.connecting, 'Connecting to signaling server...');
    errorMessage = null;

    try {
      // ── Step 1: Initialize the video renderer ───────────────
      remoteRenderer = RTCVideoRenderer();
      await remoteRenderer!.initialize();
      notifyListeners();

      // ── Step 2: Connect to signaling server via WebSocket ───
      _channel = WebSocketChannel.connect(Uri.parse(signalingUrl));

      // ── Step 3: Listen for messages from signaling server ───
      _wsSubscription = _channel!.stream.listen(
        _onSignalingMessage,
        onError: _onSignalingError,
        onDone:  _onSignalingClosed,
      );

      // ── Step 4: Register as a viewer ────────────────────────
      _send({'type': 'register', 'role': 'viewer'});

    } catch (e) {
      _setError('Failed to connect: $e\n\nCheck that the signaling server is running on your laptop.');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // DISCONNECT
  // Called when user taps "Disconnect" or app closes.
  // ─────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    await _cleanup();
    _setStatus(ConnectionStatus.disconnected, 'Disconnected');
  }

  // ─────────────────────────────────────────────────────────────
  // Handle incoming messages from signaling server
  // ─────────────────────────────────────────────────────────────
  Future<void> _onSignalingMessage(dynamic rawData) async {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(rawData as String);
    } catch (_) {
      return;
    }

    final type = message['type'] as String?;
    debugPrint('[Signaling] Received: $type');

    switch (type) {
      case 'registered':
        // Successfully registered with signaling server
        final piOnline = message['publisherOnline'] == true;
        if (piOnline) {
          _setStatus(ConnectionStatus.negotiating, 'Raspberry Pi found — starting video...');
          await _startWebRTC();
        } else {
          _setStatus(ConnectionStatus.waitingForPi, 'Waiting for Raspberry Pi to connect...');
        }
        break;

      case 'publisher_online':
        // Raspberry Pi just came online — start WebRTC
        _setStatus(ConnectionStatus.negotiating, 'Raspberry Pi connected — starting video...');
        await _startWebRTC();
        break;

      case 'publisher_offline':
        _setStatus(ConnectionStatus.waitingForPi, 'Raspberry Pi disconnected. Waiting...');
        await _closePeerConnection();
        break;

      case 'answer':
        // Raspberry Pi accepted our offer — set the answer
        await _handleAnswer(message);
        break;

      case 'ice_candidate':
        // Routing info from Raspberry Pi
        await _handleRemoteIceCandidate(message);
        break;

      case 'error':
        _setError(message['message'] ?? 'Unknown error from signaling server');
        break;
    }
  }

  void _onSignalingError(dynamic error) {
    _setError('WebSocket error: $error\n\nIs the signaling server running?');
  }

  void _onSignalingClosed() {
    if (!_disposed && status != ConnectionStatus.disconnected) {
      _setStatus(ConnectionStatus.error, 'Signaling server connection closed');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Create WebRTC peer connection and send offer to Raspberry Pi
  // ─────────────────────────────────────────────────────────────
  Future<void> _startWebRTC() async {
    try {
      // Close any existing peer connection
      await _closePeerConnection();

      // Create new peer connection
      _pc = await createPeerConnection(_iceServers);

      // ── Handle connection state changes ─────────────────────
      _pc!.onConnectionState = (state) {
        debugPrint('[WebRTC] Connection state: $state');
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _setStatus(ConnectionStatus.connected, 'Live — streaming from Raspberry Pi');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _setError('WebRTC connection failed.\n\nTry: Check both devices are on the same WiFi.');
        } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          _setStatus(ConnectionStatus.waitingForPi, 'Stream interrupted — reconnecting...');
        }
      };

      // ── Handle incoming video track from Raspberry Pi ───────
      _pc!.onTrack = (event) {
        if (event.track.kind == 'video' && event.streams.isNotEmpty) {
          debugPrint('[WebRTC] Video track received!');
          remoteRenderer?.srcObject = event.streams[0];
          notifyListeners();
        }
      };

      // ── Send our ICE candidates to Pi via signaling server ──
      _pc!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          _send({
            'type': 'ice_candidate',
            'candidate': {
              'candidate':     candidate.candidate,
              'sdpMid':        candidate.sdpMid,
              'sdpMLineIndex': candidate.sdpMLineIndex,
            },
          });
        }
      };

      // ── Add a receive-only video transceiver ─────────────────
      // This tells WebRTC: "I want to RECEIVE video, not send it"
      await _pc!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );

      // ── Create and send offer to Raspberry Pi ───────────────
      final offer = await _pc!.createOffer({
        'offerToReceiveVideo': true,
        'offerToReceiveAudio': false,
      });
      await _pc!.setLocalDescription(offer);

      _send({
        'type':    'offer',
        'sdp':     offer.sdp,
        'sdpType': offer.type,
      });

      debugPrint('[WebRTC] Offer sent to Raspberry Pi');
    } catch (e) {
      _setError('WebRTC setup failed: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> message) async {
    if (_pc == null) return;
    try {
      final answer = RTCSessionDescription(
        message['sdp'] as String,
        message['sdpType'] as String,
      );
      await _pc!.setRemoteDescription(answer);
      debugPrint('[WebRTC] Answer applied');
    } catch (e) {
      _setError('Failed to apply SDP answer: $e');
    }
  }

  Future<void> _handleRemoteIceCandidate(Map<String, dynamic> message) async {
    if (_pc == null) return;
    try {
      final c = message['candidate'] as Map<String, dynamic>;
      final candidate = RTCIceCandidate(
        c['candidate'] as String?,
        c['sdpMid'] as String?,
        c['sdpMLineIndex'] as int?,
      );
      await _pc!.addCandidate(candidate);
    } catch (e) {
      debugPrint('[WebRTC] Failed to add ICE candidate: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  void _send(Map<String, dynamic> data) {
    try {
      _channel?.sink.add(jsonEncode(data));
    } catch (e) {
      debugPrint('[Signaling] Send failed: $e');
    }
  }

  void _setStatus(ConnectionStatus s, String msg) {
    if (_disposed) return;
    status = s;
    statusMessage = msg;
    errorMessage = null;
    notifyListeners();
  }

  void _setError(String msg) {
    if (_disposed) return;
    status = ConnectionStatus.error;
    statusMessage = 'Error';
    errorMessage = msg;
    notifyListeners();
  }

  Future<void> _closePeerConnection() async {
    if (_pc != null) {
      try { await _pc!.close(); } catch (_) {}
      _pc = null;
    }
  }

  Future<void> _cleanup() async {
    await _wsSubscription?.cancel();
    _wsSubscription = null;
    await _closePeerConnection();
    try { await _channel?.sink.close(); } catch (_) {}
    _channel = null;
    remoteRenderer?.dispose();
    remoteRenderer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _cleanup();
    super.dispose();
  }
}
