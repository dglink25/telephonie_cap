import 'package:flutter/material.dart';

class RTCVideoRenderer {
  dynamic srcObject;

  Future<void> initialize() async {}

  void dispose() {}
}
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
    return Container(
      color: Colors.black,
      child: const Center(
        child: Text(
          'Vidéo non disponible sur navigateur',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ),
    );
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

// ── Stub classes for web ──────────────────────────────────────────
class RTCPeerConnection {
  Function(dynamic)? onTrack;
  Function(dynamic)? onIceCandidate;
  Function(dynamic)? onIceConnectionState;

  Future<void> addTrack(dynamic track, dynamic stream) async {}
  Future<RTCSessionDescription> createOffer([Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('', 'offer');
  Future<RTCSessionDescription> createAnswer([Map<String, dynamic>? constraints]) async =>
      RTCSessionDescription('', 'answer');
  Future<void> setLocalDescription(RTCSessionDescription desc) async {}
  Future<void> setRemoteDescription(RTCSessionDescription desc) async {}
  Future<void> addCandidate(RTCIceCandidate candidate) async {}
  Future<void> close() async {}
}

class RTCSessionDescription {
  final String? sdp;
  final String? type;
  RTCSessionDescription(this.sdp, this.type);
}

class RTCIceCandidate {
  final String? candidate;
  final String? sdpMid;
  final int? sdpMLineIndex;
  RTCIceCandidate(this.candidate, this.sdpMid, this.sdpMLineIndex);
}

class MediaStream {
  List<dynamic> getTracks() => [];
  List<dynamic> getAudioTracks() => [];
  List<dynamic> getVideoTracks() => [];
  Future<void> dispose() async {}
}

class Helper {
  static Future<void> switchCamera(dynamic track) async {}
}

// Stub for navigator.mediaDevices.getUserMedia
final _stubNavigator = _StubNavigator();
_StubNavigator get navigator => _stubNavigator;

class _StubNavigator {
  _StubMediaDevices get mediaDevices => _StubMediaDevices();
}

class _StubMediaDevices {
  Future<MediaStream> getUserMedia(Map<String, dynamic> constraints) async =>
      MediaStream();
}

Future<RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> config) async =>
    RTCPeerConnection();