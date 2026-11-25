import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/calls.dart';
import '../services/db.dart';
import '../services/notify.dart';
import '../widgets.dart';

const _iceServers = {
  'iceServers': [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
        'stun:stun2.l.google.com:19302',
      ]
    }
  ],
  'sdpSemantics': 'unified-plan',
};

class CallScreen extends StatefulWidget {
  const CallScreen({super.key, required this.callId, required this.otherUid, required this.video, required this.isCaller});
  final String callId;
  final String otherUid;
  final bool video;
  final bool isCaller;

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _local = RTCVideoRenderer();
  final _remote = RTCVideoRenderer();
  RTCPeerConnection? _pc;
  MediaStream? _stream;
  final _subs = <StreamSubscription>[];
  final _pendingCandidates = <RTCIceCandidate>[];
  bool _remoteSet = false;

  String _status = '';
  bool _accepted = false;
  bool _connected = false;
  bool _ended = false;
  bool _muted = false;
  bool _speaker = false;
  bool _cameraOff = false;
  DateTime? _connectedAt;
  Timer? _ticker;
  Timer? _timeout;
  Map<String, dynamic>? _other;

  DocumentReference<Map<String, dynamic>> get _ref => Db.calls.doc(widget.callId);

  @override
  void initState() {
    super.initState();
    CallService.inCall = true;
    _speaker = widget.video;
    _status = widget.isCaller ? 'Calling...' : (widget.video ? 'Incoming video call' : 'Incoming voice call');
    Db.user(widget.otherUid).then((u) {
      if (mounted) setState(() => _other = u);
    });
    _init();
  }

  Future<void> _init() async {
    await _local.initialize();
    await _remote.initialize();

    _subs.add(_ref.snapshots().listen(_onCallDoc));

    if (widget.isCaller) {
      await _setupMedia();
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      await _ref.update({'offer': {'sdp': offer.sdp, 'type': offer.type}});
      _listenCandidates('calleeCandidates');
      _timeout = Timer(const Duration(seconds: 45), () {
        if (!_accepted) _hangUp(status: 'missed');
      });
    } else {
      _timeout = Timer(const Duration(seconds: 50), () {
        if (!_accepted) _close();
      });
    }
  }

  Future<void> _setupMedia() async {
    _stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': widget.video ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    });
    _local.srcObject = _stream;
    _pc = await createPeerConnection(_iceServers);
    for (final t in _stream!.getTracks()) {
      await _pc!.addTrack(t, _stream!);
    }
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        _remote.srcObject = e.streams.first;
        if (mounted) setState(() {});
      }
    };
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _ref.collection(widget.isCaller ? 'callerCandidates' : 'calleeCandidates').add({
        'candidate': c.candidate,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      });
    };
    _pc!.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected && !_connected) {
        _connected = true;
        _connectedAt = DateTime.now();
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
        if (mounted) setState(() => _status = '');
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (mounted) setState(() => _status = 'Connection failed');
        _hangUp();
      }
    };
    await Helper.setSpeakerphoneOn(_speaker);
  }

  void _listenCandidates(String col) {
    _subs.add(_ref.collection(col).snapshots().listen((snap) {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final d = ch.doc.data()!;
        final c = RTCIceCandidate(d['candidate'], d['sdpMid'], d['sdpMLineIndex']);
        if (_remoteSet) {
          _pc?.addCandidate(c);
        } else {
          _pendingCandidates.add(c);
        }
      }
    }));
  }

  Future<void> _setRemote(Map d) async {
    await _pc!.setRemoteDescription(RTCSessionDescription(d['sdp'], d['type']));
    _remoteSet = true;
    for (final c in _pendingCandidates) {
      await _pc!.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  Future<void> _onCallDoc(DocumentSnapshot<Map<String, dynamic>> snap) async {
    final d = snap.data();
    if (d == null || _ended) return;
    final status = d['status'];
    if (widget.isCaller) {
      if (d['answer'] != null && !_remoteSet && _pc != null) {
        _accepted = true;
        _timeout?.cancel();
        if (mounted) setState(() => _status = 'Connecting...');
        await _setRemote(d['answer']);
      }
      if (status == 'declined') return _finish('Call declined', note: 'Declined');
      if (status == 'busy') return _finish('Busy', note: 'Busy');
    }
    if (status == 'ended' || status == 'missed') {
      _finish(_connected ? 'Call ended' : (widget.isCaller ? (status == 'missed' ? 'No answer' : 'Cancelled') : 'Missed call'),
          note: status == 'missed' ? 'No answer' : null);
    }
  }

  Future<void> _accept() async {
    if (!await CallService.ensurePermissions(widget.video)) {
      if (mounted) toast(context, 'Allow microphone${widget.video ? ' and camera' : ''} to answer');
      return;
    }
    Notify.cancelCall(widget.callId);
    setState(() {
      _accepted = true;
      _status = 'Connecting...';
    });
    _timeout?.cancel();
    await _setupMedia();
    // The offer may still be on its way if the callee answers very quickly.
    var d = (await _ref.get()).data() ?? {};
    for (var i = 0; i < 20 && d['offer'] == null; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      d = (await _ref.get()).data() ?? {};
    }
    if (d['offer'] == null) return _hangUp();
    await _setRemote(d['offer']);
    final answer = await _pc!.createAnswer({});
    await _pc!.setLocalDescription(answer);
    _listenCandidates('callerCandidates');
    await _ref.update({'answer': {'sdp': answer.sdp, 'type': answer.type}, 'status': 'accepted'});
  }

  Future<void> _decline() async {
    Notify.cancelCall(widget.callId);
    await _ref.update({'status': 'declined'}).catchError((_) {});
    _close();
  }

  Future<void> _hangUp({String status = 'ended'}) async {
    if (_ended) return;
    await _ref.update({'status': status}).catchError((_) {});
    _finish(status == 'missed' ? 'No answer' : (_connected ? 'Call ended' : 'Cancelled'), note: status == 'missed' ? 'No answer' : null);
  }

  /// Caller writes one summary line into the chat, like WeChat does.
  Future<void> _finish(String label, {String? note}) async {
    if (_ended) return;
    _ended = true;
    if (mounted) setState(() => _status = label);
    if (widget.isCaller) {
      final kind = widget.video ? 'Video call' : 'Voice call';
      String text;
      if (_connectedAt != null) {
        text = '$kind ${_fmt(DateTime.now().difference(_connectedAt!))}';
      } else {
        text = '$kind · ${note ?? 'Cancelled'}';
      }
      try {
        final chatId = await Db.openDirect(widget.otherUid);
        await Db.sendMessage(chatId, type: 'call', text: text);
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 900));
    _close();
  }

  void _close() {
    _ended = true;
    Notify.cancelCall(widget.callId);
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }

  @override
  void dispose() {
    CallService.inCall = false;
    _ticker?.cancel();
    _timeout?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _stream?.getTracks().forEach((t) => t.stop());
    _stream?.dispose();
    _pc?.close();
    _local.srcObject = null;
    _remote.srcObject = null;
    _local.dispose();
    _remote.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _other?['name'] ?? '';
    final showVideo = widget.video && _connected;
    final status = _connected && !_ended ? _fmt(DateTime.now().difference(_connectedAt!)) : _status;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1F1F1F),
        body: Stack(children: [
          if (showVideo)
            Positioned.fill(child: RTCVideoView(_remote, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
          if (widget.video && _stream != null && !_cameraOff)
            Positioned(
              right: 16,
              top: 50,
              width: 110,
              height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: RTCVideoView(_local, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 60),
              if (!showVideo) ...[
                Avatar(data: _other?['avatar'], name: name, size: 96),
                const SizedBox(height: 16),
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 10),
              Text(status, style: const TextStyle(color: Colors.white70, fontSize: 16)),
              const Spacer(),
              _controls(),
              const SizedBox(height: 40),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _controls() {
    if (!widget.isCaller && !_accepted) {
      return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _round(Icons.call_end, 'Decline', Colors.red, _decline),
        _round(widget.video ? Icons.videocam : Icons.call, 'Accept', kGreen, _accept),
      ]);
    }
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _round(_muted ? Icons.mic_off : Icons.mic, _muted ? 'Unmute' : 'Mute', _muted ? Colors.white : Colors.white24, () {
          _muted = !_muted;
          _stream?.getAudioTracks().forEach((t) => t.enabled = !_muted);
          setState(() {});
        }, dark: _muted),
        if (widget.video)
          _round(Icons.cameraswitch, 'Flip', Colors.white24, () {
            final v = _stream?.getVideoTracks();
            if (v != null && v.isNotEmpty) Helper.switchCamera(v.first);
          })
        else
          _round(_speaker ? Icons.volume_up : Icons.volume_down, 'Speaker', _speaker ? Colors.white : Colors.white24, () {
            _speaker = !_speaker;
            Helper.setSpeakerphoneOn(_speaker);
            setState(() {});
          }, dark: _speaker),
        if (widget.video)
          _round(_cameraOff ? Icons.videocam_off : Icons.videocam, 'Camera', _cameraOff ? Colors.white : Colors.white24, () {
            _cameraOff = !_cameraOff;
            _stream?.getVideoTracks().forEach((t) => t.enabled = !_cameraOff);
            setState(() {});
          }, dark: _cameraOff),
      ]),
      const SizedBox(height: 28),
      _round(Icons.call_end, 'Hang up', Colors.red, () => _hangUp()),
    ]);
  }

  Widget _round(IconData icon, String label, Color bg, VoidCallback onTap, {bool dark = false}) => Column(children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: dark ? Colors.black87 : Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);
}
