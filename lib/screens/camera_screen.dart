// ============================================================
// EV SQUARE - Camera Screen
// The only screen in the app.
// Shows: logo, status, connect/disconnect buttons, live video.
// ============================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_service.dart';

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// IMPORTANT: Change this to your laptop's IP address!
//
// How to find it:
//   Open Command Prompt on Windows → type: ipconfig
//   Look for "IPv4 Address" under your WiFi adapter.
//   Example: 192.168.1.10
//
// Then replace 192.168.1.10 below with your actual IP:
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
const String kSignalingServerUrl = 'ws://192.168.1.10:8765';

// ── Colors ────────────────────────────────────────────────────
const _kBgColor     = Color(0xFF0A0E1A);   // Dark navy background
const _kCardColor   = Color(0xFF111827);   // Slightly lighter navy for cards
const _kBlue        = Color(0xFF0A84FF);   // Electric blue (brand color)
const _kGreen       = Color(0xFF30D158);   // Connected / success
const _kYellow      = Color(0xFFFFD60A);   // Warning / waiting
const _kRed         = Color(0xFFFF453A);   // Error / disconnected
const _kTextPrimary = Color(0xFFE8EEF7);   // Main text
const _kTextMuted   = Color(0xFF8BA0BC);   // Secondary text

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});
  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final WebRTCService _service;

  @override
  void initState() {
    super.initState();
    _service = WebRTCService();
    _service.addListener(_onServiceUpdate);
    // Force landscape when video is playing (optional)
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _service.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _onServiceUpdate() {
    // Rebuild the UI whenever the service state changes
    if (mounted) setState(() {});
  }

  void _onConnect() => _service.connect(kSignalingServerUrl);
  void _onDisconnect() => _service.disconnect();

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: _kBgColor,
      body: SafeArea(
        child: isLandscape ? _buildLandscape() : _buildPortrait(),
      ),
    );
  }

  // ── Portrait layout (phone held upright) ──────────────────────────────────
  Widget _buildPortrait() {
    return Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildStatusBar(),
        const SizedBox(height: 12),
        _buildVideoArea(aspectRatio: 4 / 3),
        const SizedBox(height: 16),
        _buildButtons(),
        const SizedBox(height: 8),
        if (_service.errorMessage != null) _buildErrorBox(),
        const SizedBox(height: 8),
        _buildHint(),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Landscape layout (phone held sideways — video fills screen) ───────────
  Widget _buildLandscape() {
    return Stack(
      children: [
        // Video fills entire screen in landscape
        Positioned.fill(
          child: _buildVideoArea(aspectRatio: null, fill: true),
        ),
        // Controls overlaid at top
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            color: Colors.black45,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildLogo(small: true),
                const Spacer(),
                _buildStatusChip(),
                const SizedBox(width: 12),
                _buildConnectButton(small: true),
                if (_service.status != ConnectionStatus.disconnected) ...[
                  const SizedBox(width: 8),
                  _buildDisconnectButton(small: true),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Header: logo + company name ───────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _buildLogo(),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('EV SQUARE', style: TextStyle(
                color: _kBlue, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 2,
              )),
              Text('Camera Viewer', style: TextStyle(
                color: _kTextMuted, fontSize: 12, letterSpacing: 1,
              )),
            ],
          ),
          const Spacer(),
          const Text('+91-80722-80522',
            style: TextStyle(color: _kTextMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildLogo({bool small = false}) {
    final size = small ? 28.0 : 40.0;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: _kBlue,
        borderRadius: BorderRadius.circular(small ? 6 : 10),
      ),
      child: Center(
        child: Text('EV',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: small ? 11 : 14,
          )),
      ),
    );
  }

  // ── Status bar ────────────────────────────────────────────────────────────
  Widget _buildStatusBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _kCardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _statusColor().withOpacity(0.4)),
        ),
        child: Row(
          children: [
            _buildStatusDot(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _service.statusMessage,
                style: const TextStyle(color: _kTextPrimary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor().withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _statusColor(), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusDot(),
          const SizedBox(width: 6),
          Text(_shortStatus(), style: TextStyle(
            color: _statusColor(), fontSize: 12, fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }

  Widget _buildStatusDot() {
    return Container(
      width: 8, height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: _statusColor()),
    );
  }

  Color _statusColor() => switch (_service.status) {
    ConnectionStatus.connected   => _kGreen,
    ConnectionStatus.connecting  => _kBlue,
    ConnectionStatus.negotiating => _kBlue,
    ConnectionStatus.waitingForPi => _kYellow,
    ConnectionStatus.error       => _kRed,
    ConnectionStatus.disconnected => _kTextMuted,
  };

  String _shortStatus() => switch (_service.status) {
    ConnectionStatus.connected    => 'LIVE',
    ConnectionStatus.connecting   => 'CONNECTING',
    ConnectionStatus.negotiating  => 'NEGOTIATING',
    ConnectionStatus.waitingForPi => 'WAITING',
    ConnectionStatus.error        => 'ERROR',
    ConnectionStatus.disconnected => 'OFFLINE',
  };

  // ── Video area ────────────────────────────────────────────────────────────
  Widget _buildVideoArea({double? aspectRatio, bool fill = false}) {
    Widget content;

    if (_service.status == ConnectionStatus.connected && _service.remoteRenderer != null) {
      // Show live video
      content = RTCVideoView(
        _service.remoteRenderer!,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
      );
    } else {
      // Show placeholder
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.videocam_off_outlined,
            color: _kTextMuted.withOpacity(0.4), size: 56),
          const SizedBox(height: 16),
          Text(_placeholderText(),
            textAlign: TextAlign.center,
            style: TextStyle(color: _kTextMuted.withOpacity(0.6), fontSize: 14)),
          if (_service.status == ConnectionStatus.connecting ||
              _service.status == ConnectionStatus.negotiating) ...[
            const SizedBox(height: 20),
            const SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: _kBlue,
              ),
            ),
          ],
        ],
      );
    }

    final decorated = Container(
      margin: fill ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: fill ? BorderRadius.zero : BorderRadius.circular(16),
        border: fill ? null : Border.all(
          color: _service.status == ConnectionStatus.connected
              ? _kGreen.withOpacity(0.4)
              : _kTextMuted.withOpacity(0.15),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: content,
    );

    if (fill) return decorated;
    if (aspectRatio != null) {
      return AspectRatio(aspectRatio: aspectRatio, child: decorated);
    }
    return decorated;
  }

  String _placeholderText() => switch (_service.status) {
    ConnectionStatus.disconnected  => 'Tap Connect to start live stream',
    ConnectionStatus.connecting    => 'Connecting to server...',
    ConnectionStatus.waitingForPi  => 'Waiting for\nRaspberry Pi...',
    ConnectionStatus.negotiating   => 'Starting video\nstream...',
    ConnectionStatus.error         => 'Connection failed\nSee error below',
    ConnectionStatus.connected     => '',
  };

  // ── Buttons ───────────────────────────────────────────────────────────────
  Widget _buildButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(child: _buildConnectButton()),
          if (_service.status != ConnectionStatus.disconnected) ...[
            const SizedBox(width: 12),
            Expanded(child: _buildDisconnectButton()),
          ],
        ],
      ),
    );
  }

  Widget _buildConnectButton({bool small = false}) {
    final enabled = _service.status == ConnectionStatus.disconnected ||
                    _service.status == ConnectionStatus.error;
    return SizedBox(
      height: small ? 34 : 48,
      child: ElevatedButton.icon(
        onPressed: enabled ? _onConnect : null,
        icon: Icon(Icons.play_arrow_rounded, size: small ? 16 : 20),
        label: Text('Connect', style: TextStyle(fontSize: small ? 12 : 15)),
        style: ElevatedButton.styleFrom(
          backgroundColor: _kBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: _kBlue.withOpacity(0.3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildDisconnectButton({bool small = false}) {
    return SizedBox(
      height: small ? 34 : 48,
      child: OutlinedButton.icon(
        onPressed: _onDisconnect,
        icon: Icon(Icons.stop_circle_outlined, size: small ? 16 : 20),
        label: Text('Disconnect', style: TextStyle(fontSize: small ? 12 : 15)),
        style: OutlinedButton.styleFrom(
          foregroundColor: _kRed,
          side: const BorderSide(color: _kRed, width: 0.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ── Error box ─────────────────────────────────────────────────────────────
  Widget _buildErrorBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kRed.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kRed.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline, color: _kRed, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _service.errorMessage ?? '',
                style: const TextStyle(color: _kRed, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Hint text ─────────────────────────────────────────────────────────────
  Widget _buildHint() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        'Make sure your phone and Raspberry Pi are on the same WiFi network. '
        'The signaling server must be running on your laptop.',
        textAlign: TextAlign.center,
        style: TextStyle(color: _kTextMuted, fontSize: 11, height: 1.5),
      ),
    );
  }
}
