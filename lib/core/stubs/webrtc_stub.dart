import 'package:flutter/material.dart';

// ── Renderer ──────────────────────────────────────────────────────
class RTCVideoRenderer {
  dynamic srcObject;

  Future<void> initialize() async {}

  void dispose() {}
}

// ── RTCVideoView : MUST be a Widget ───────────────────────────────
class RTCVideoView extends StatelessWidget {
  final RTCVideoRenderer renderer;
  final int objectFit;
  final bool mirror;

  const RTCVideoView(
    this.renderer, {
    super.key,
    this.objectFit = RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
    this.mirror = false,
  });

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

// ── Enum-like constants ────────────────────────────────────────────
class RTCVideoViewObjectFit {
  static const int RTCVideoViewObjectFitCover = 0;
  static const int RTCVideoViewObjectFitContain = 1;
}

class RTCIceConnectionState {
  static const String RTCIceConnectionStateDisconnected = 'disconnected';
  static const String RTCIceConnectionStateFailed = 'failed';
}