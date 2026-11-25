import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/calls.dart';
import '../services/db.dart';
import '../services/notify.dart';
import '../widgets.dart';
import 'chats.dart';
import 'contacts.dart';
import 'group.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _voiceMode = false;
  bool _showPanel = false;
  bool _recording = false;
  bool _cancelRecording = false;
  DateTime? _recStart;
  Timer? _recTimer;
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  String? _playingId;

  DocumentReference<Map<String, dynamic>> get _chatRef => Db.chats.doc(widget.chatId);

  @override
  void initState() {
    super.initState();
    Notify.openChatId = widget.chatId;
    Db.markRead(widget.chatId).catchError((_) {});
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
    _focus.addListener(() {
      if (_focus.hasFocus && _showPanel) setState(() => _showPanel = false);
    });
  }

  @override
  void dispose() {
    if (Notify.openChatId == widget.chatId) Notify.openChatId = null;
    Db.markRead(widget.chatId).catchError((_) {});
    _recTimer?.cancel();
    _recorder.dispose();
    _player.dispose();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    setState(() {});
    try {
      await Db.sendMessage(widget.chatId, type: 'text', text: t);
    } catch (e) {
      if (mounted) toast(context, 'Not sent: $e');
    }
  }

  Future<void> _sendImage(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 60);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final data = Db.b64(bytes);
    if (data.length > 900000) {
      if (mounted) toast(context, 'That photo is too large to send. Try another.');
      return;
    }
    setState(() => _showPanel = false);
    try {
      await Db.sendMessage(widget.chatId, type: 'image', data: data);
    } catch (e) {
      if (mounted) toast(context, 'Not sent: $e');
    }
  }

  Future<void> _startRecording() async {
    if (!await Permission.microphone.request().isGranted) {
      if (mounted) toast(context, 'Allow microphone to send voice messages');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 24000, sampleRate: 16000, numChannels: 1),
      path: path,
    );
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _cancelRecording = false;
      _recStart = DateTime.now();
    });
    _recTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (DateTime.now().difference(_recStart!).inSeconds >= 60) _stopRecording();
    });
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _recTimer?.cancel();
    final path = await _recorder.stop();
    final secs = DateTime.now().difference(_recStart!).inMilliseconds / 1000;
    final cancel = _cancelRecording;
    setState(() => _recording = false);
    if (path == null || cancel) return;
    if (secs < 1) {
      if (mounted) toast(context, 'Too short');
      return;
    }
    final file = File(path);
    final bytes = await file.readAsBytes();
    unawaited(file.delete().catchError((_) => file));
    try {
      await Db.sendMessage(widget.chatId, type: 'voice', data: Db.b64(bytes), duration: secs.round());
    } catch (e) {
      if (mounted) toast(context, 'Not sent: $e');
    }
  }

  Future<void> _playVoice(String id, String data) async {
    if (_playingId == id) {
      await _player.stop();
      setState(() => _playingId = null);
      return;
    }
    await _player.stop();
    setState(() => _playingId = id);
    await _player.play(BytesSource(Uint8List.fromList(Db.unb64(data))));
  }

  Future<void> _call(String otherUid, bool video) async {
    setState(() => _showPanel = false);
    await CallService.startCall(context, otherUid, video: video, chatId: widget.chatId);
  }

  void _messageMenu(String id, Map<String, dynamic> m) {
    final mine = m['sender'] == Db.uid;
    final t = m['time'];
    final recent = t is Timestamp && DateTime.now().difference(t.toDate()).inMinutes < 2;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Wrap(children: [
          if (m['type'] == 'text')
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: m['text'] ?? ''));
                Navigator.pop(c);
              },
            ),
          if (mine && recent)
            ListTile(
              leading: const Icon(Icons.undo),
              title: const Text('Recall'),
              onTap: () {
                Navigator.pop(c);
                Db.recall(widget.chatId, id);
              },
            ),
          if (m['type'] != 'text' && !(mine && recent))
            const ListTile(title: Text('No actions', style: TextStyle(color: Colors.black38))),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatRef.snapshots(),
      builder: (context, chatSnap) {
        final chat = chatSnap.data?.data() ?? {};
        final isGroup = chat['type'] == 'group';
        final members = List<String>.from(chat['members'] ?? []);
        final stillMember = chatSnap.data == null || members.contains(Db.uid);
        return FutureBuilder<ChatTitle>(
          future: chat.isEmpty ? null : ChatTitle.of(chat),
          builder: (context, title) {
            final other = title.data?.otherUid;
            return Scaffold(
              appBar: AppBar(
                title: Text(title.data?.name ?? ''),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    onPressed: () {
                      if (isGroup) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => GroupInfoScreen(chatId: widget.chatId)));
                      } else if (other != null) {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: other)));
                      }
                    },
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _focus.unfocus();
                        if (_showPanel) setState(() => _showPanel = false);
                      },
                      child: _messages(chat, isGroup),
                    ),
                  ),
                  if (stillMember) _inputBar(isGroup ? null : other) else
                    Container(
                      color: const Color(0xFFF7F7F7),
                      padding: const EdgeInsets.all(16),
                      child: const SafeArea(top: false, child: Center(child: Text('You are no longer in this group'))),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _messages(Map<String, dynamic> chat, bool isGroup) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _chatRef.collection('messages').orderBy('time', descending: true).limit(300).snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return Center(child: Text('${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isNotEmpty && docs.first.data()['sender'] != Db.uid) {
          final unread = ((chat['unread'] as Map?)?[Db.uid] as num?)?.toInt() ?? 0;
          if (unread > 0) Db.markRead(widget.chatId).catchError((_) {});
        }
        // "Read" receipt on my latest message in direct chats.
        Timestamp? otherRead;
        if (!isGroup) {
          final readAt = (chat['readAt'] as Map?) ?? {};
          for (final e in readAt.entries) {
            if (e.key != Db.uid && e.value is Timestamp) otherRead = e.value as Timestamp;
          }
        }
        final Timestamp? othersRead = otherRead;
        final myLatest = docs.where((d) => d.data()['sender'] == Db.uid && d.data()['type'] != 'system').firstOrNull;

        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(vertical: 12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final prev = i + 1 < docs.length ? docs[i + 1].data() : null;
            final showTime = _gap(prev?['time'], m['time']);
            String? receipt;
            if (myLatest != null && d.id == myLatest.id && !isGroup) {
              final t = m['time'];
              receipt = (othersRead != null && t is Timestamp && othersRead.compareTo(t) >= 0) ? 'Read' : 'Sent';
            }
            return Column(
              children: [
                if (showTime)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(longTime(m['time']), style: const TextStyle(color: Colors.black38, fontSize: 12)),
                  ),
                _bubble(d.id, m, isGroup),
                if (receipt != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 66, top: 2),
                      child: Text(receipt, style: const TextStyle(fontSize: 11, color: Colors.black38)),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  bool _gap(dynamic prev, dynamic cur) {
    if (cur is! Timestamp) return false;
    if (prev is! Timestamp) return true;
    return cur.toDate().difference(prev.toDate()).inMinutes >= 5;
  }

  Widget _bubble(String id, Map<String, dynamic> m, bool isGroup) {
    final type = m['type'] ?? 'text';
    if (type == 'system' || type == 'recalled') {
      final text = type == 'recalled'
          ? (m['sender'] == Db.uid ? 'You recalled a message' : '"${m['senderName']}" recalled a message')
          : m['text'] ?? '';
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
        child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black38, fontSize: 12.5)),
      );
    }
    final mine = m['sender'] == Db.uid;
    Widget content;
    switch (type) {
      case 'image':
        final bytes = Db.unb64(m['data'] ?? '');
        content = GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _PhotoView(bytes: bytes))),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180, maxHeight: 240),
              child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
        );
      case 'voice':
        final secs = (m['duration'] as num?)?.toInt() ?? 0;
        final playing = _playingId == id;
        content = GestureDetector(
          onTap: () => _playVoice(id, m['data'] ?? ''),
          child: _box(
            mine,
            SizedBox(
              width: 60 + (secs.clamp(1, 60) * 2.5),
              child: Row(
                mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
                textDirection: mine ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  Icon(playing ? Icons.pause : Icons.graphic_eq, size: 20),
                  const SizedBox(width: 6),
                  Text('$secs"'),
                ],
              ),
            ),
          ),
        );
      case 'call':
        content = _box(mine, Row(mainAxisSize: MainAxisSize.min, children: [
          Icon((m['text'] ?? '').toString().contains('Video') ? Icons.videocam_outlined : Icons.call_outlined, size: 18),
          const SizedBox(width: 6),
          Flexible(child: Text(m['text'] ?? '')),
        ]));
      default:
        content = _box(mine, Text(m['text'] ?? '', style: const TextStyle(fontSize: 16)));
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: Db.user(m['sender'] ?? ''),
      builder: (context, u) {
        final avatar = Avatar(data: u.data?['avatar'], name: u.data?['name'] ?? m['senderName'] ?? '', size: 40);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!mine)
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: m['sender']))),
                  child: avatar,
                ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (isGroup && !mine)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(m['senderName'] ?? '', style: const TextStyle(fontSize: 12, color: Colors.black45)),
                      ),
                    GestureDetector(onLongPress: () => _messageMenu(id, m), child: content),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (mine) avatar,
            ],
          ),
        );
      },
    );
  }

  Widget _box(bool mine, Widget child) => Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.66),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: mine ? kBubbleMine : Colors.white, borderRadius: BorderRadius.circular(6)),
        child: child,
      );

  Widget _inputBar(String? otherUid) {
    final hasText = _text.text.trim().isNotEmpty;
    final elapsed = _recStart == null ? 0 : DateTime.now().difference(_recStart!).inSeconds;
    return Container(
      color: const Color(0xFFF7F7F7),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_recording)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _cancelRecording ? 'Release to cancel' : 'Recording ${elapsed}s  ·  slide up to cancel',
                  style: TextStyle(color: _cancelRecording ? Colors.red : Colors.black54),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(_voiceMode ? Icons.keyboard : Icons.mic_none),
                    onPressed: () => setState(() {
                      _voiceMode = !_voiceMode;
                      _showPanel = false;
                      if (!_voiceMode) _focus.requestFocus();
                    }),
                  ),
                  Expanded(
                    child: _voiceMode
                        ? GestureDetector(
                            onLongPressStart: (_) => _startRecording(),
                            onLongPressMoveUpdate: (d) {
                              final cancel = d.offsetFromOrigin.dy < -60;
                              if (cancel != _cancelRecording) setState(() => _cancelRecording = cancel);
                            },
                            onLongPressEnd: (_) => _stopRecording(),
                            child: Container(
                              height: 42,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _recording ? const Color(0xFFD5D5D5) : Colors.white,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(_recording ? 'Release to send' : 'Hold to talk',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          )
                        : Container(
                            constraints: const BoxConstraints(minHeight: 42),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
                            child: TextField(
                              controller: _text,
                              focusNode: _focus,
                              minLines: 1,
                              maxLines: 5,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(border: InputBorder.none, isDense: true),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                  ),
                  if (hasText && !_voiceMode)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, right: 4, bottom: 2),
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(60, 38), padding: EdgeInsets.zero),
                        onPressed: _sendText,
                        child: const Text('Send'),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        _focus.unfocus();
                        setState(() => _showPanel = !_showPanel);
                      },
                    ),
                ],
              ),
            ),
            if (_showPanel)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                child: Wrap(
                  spacing: 22,
                  runSpacing: 16,
                  children: [
                    _panelItem(Icons.photo, 'Album', () => _sendImage(ImageSource.gallery)),
                    _panelItem(Icons.camera_alt, 'Camera', () => _sendImage(ImageSource.camera)),
                    if (otherUid != null) _panelItem(Icons.call, 'Voice call', () => _call(otherUid, false)),
                    if (otherUid != null) _panelItem(Icons.videocam, 'Video call', () => _call(otherUid, true)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _panelItem(IconData icon, String label, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Column(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: Colors.black87, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      );
}

class _PhotoView extends StatelessWidget {
  const _PhotoView({required this.bytes});
  final Uint8List bytes;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Center(child: InteractiveViewer(child: Image.memory(bytes))),
        ),
      );
}
