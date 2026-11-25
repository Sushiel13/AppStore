import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/db.dart';
import '../widgets.dart';
import 'contacts.dart';

const _link = Color(0xFF576B95);

class MomentsScreen extends StatelessWidget {
  const MomentsScreen({super.key, this.onlyUser});
  final String? onlyUser;

  @override
  Widget build(BuildContext context) {
    final me = Db.me ?? {};
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(onlyUser == null ? 'Moments' : 'My Moments'),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PostMomentScreen())),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.moments.where('audience', arrayContains: Db.uid).limit(80).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('${snap.error}'));
          var docs = snap.data?.docs ?? [];
          if (onlyUser != null) docs = docs.where((d) => d.data()['author'] == onlyUser).toList();
          return ListView.separated(
            itemCount: docs.length + 1,
            separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 0.5, color: Color(0xFFEEEEEE)),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Container(
                  height: 220,
                  margin: const EdgeInsets.only(bottom: 30),
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      height: 200,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)]),
                      ),
                    ),
                    Positioned(
                      right: 16,
                      bottom: -6,
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 14, right: 12),
                          child: Text(me['name'] ?? '',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, shadows: [Shadow(blurRadius: 4)])),
                        ),
                        Avatar(data: me['avatar'], name: me['name'] ?? '', size: 68),
                      ]),
                    ),
                  ]),
                );
              }
              return MomentCard(id: docs[i - 1].id, m: docs[i - 1].data());
            },
          );
        },
      ),
    );
  }
}

class MomentCard extends StatelessWidget {
  const MomentCard({super.key, required this.id, required this.m});
  final String id;
  final Map<String, dynamic> m;

  @override
  Widget build(BuildContext context) {
    final images = List<String>.from(m['images'] ?? []);
    final likes = List<String>.from(m['likes'] ?? []);
    final comments = List<Map>.from(m['comments'] ?? []);
    final liked = likes.contains(Db.uid);
    final mine = m['author'] == Db.uid;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FutureBuilder<Map<String, dynamic>>(
          future: Db.user(m['author']),
          builder: (context, u) => GestureDetector(
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: m['author']))),
            child: Avatar(data: u.data?['avatar'], name: m['authorName'] ?? '', size: 44),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(m['authorName'] ?? '', style: const TextStyle(color: _link, fontWeight: FontWeight.w600, fontSize: 16)),
            if ((m['text'] ?? '').toString().isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(m['text'], style: const TextStyle(fontSize: 15.5))),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ImageGrid(images: images),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Text(longTime(m['time']), style: const TextStyle(color: Colors.black38, fontSize: 12)),
              if (mine)
                TextButton(
                  style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 10)),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (d) => AlertDialog(
                        title: const Text('Delete this post?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true) await Db.moments.doc(id).delete();
                  },
                  child: const Text('Delete', style: TextStyle(color: _link, fontSize: 12)),
                ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? Colors.redAccent : _link, size: 20),
                onPressed: () => Db.toggleLike(id, liked),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.mode_comment_outlined, color: _link, size: 20),
                onPressed: () => _comment(context),
              ),
            ]),
            if (likes.isNotEmpty || comments.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(4)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (likes.isNotEmpty)
                    FutureBuilder<List<String>>(
                      future: Future.wait(likes.map((l) async => (await Db.user(l))['name']?.toString() ?? '')),
                      builder: (context, n) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Padding(padding: EdgeInsets.only(top: 2, right: 4), child: Icon(Icons.favorite_border, size: 15, color: _link)),
                        Expanded(child: Text((n.data ?? []).join(', '), style: const TextStyle(color: _link, fontWeight: FontWeight.w500))),
                      ]),
                    ),
                  if (likes.isNotEmpty && comments.isNotEmpty) const Divider(height: 12),
                  for (final c in comments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${c['name']}: ', style: const TextStyle(color: _link, fontWeight: FontWeight.w500)),
                        TextSpan(text: '${c['text']}'),
                      ])),
                    ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _comment(BuildContext context) async {
    final c = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(s).viewInsets.bottom + 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Comment', border: OutlineInputBorder(), isDense: true),
              onSubmitted: (v) => Navigator.pop(s, v),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 40)),
            onPressed: () => Navigator.pop(s, c.text),
            child: const Text('Send'),
          ),
        ]),
      ),
    );
    if (text != null && text.trim().isNotEmpty) await Db.comment(id, text);
  }
}

class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});
  final List<String> images;

  @override
  Widget build(BuildContext context) {
    final bytes = images.map(Db.unb64).toList();
    if (bytes.length == 1) {
      return GestureDetector(
        onTap: () => _open(context, bytes[0]),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 260),
          child: Image.memory(bytes[0], fit: BoxFit.cover),
        ),
      );
    }
    return Wrap(spacing: 4, runSpacing: 4, children: [
      for (final b in bytes)
        GestureDetector(
          onTap: () => _open(context, b),
          child: Image.memory(b, width: 86, height: 86, fit: BoxFit.cover),
        ),
    ]);
  }

  void _open(BuildContext context, Uint8List b) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            body: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Center(child: InteractiveViewer(child: Image.memory(b))),
            ),
          ),
        ),
      );
}

class PostMomentScreen extends StatefulWidget {
  const PostMomentScreen({super.key});
  @override
  State<PostMomentScreen> createState() => _PostMomentScreenState();
}

class _PostMomentScreenState extends State<PostMomentScreen> {
  final _text = TextEditingController();
  final _images = <Uint8List>[];
  bool _busy = false;

  Future<void> _add() async {
    final left = 3 - _images.length;
    if (left <= 0) return;
    final files = await ImagePicker().pickMultiImage(maxWidth: 960, maxHeight: 960, imageQuality: 50);
    for (final f in files.take(left)) {
      _images.add(await f.readAsBytes());
    }
    setState(() {});
  }

  Future<void> _post() async {
    if (_text.text.trim().isEmpty && _images.isEmpty) return;
    final encoded = _images.map(Db.b64).toList();
    final total = encoded.fold<int>(0, (s, e) => s + e.length);
    if (total > 900000) return toast(context, 'Photos are too large together. Remove one.');
    setState(() => _busy = true);
    try {
      await Db.postMoment(_text.text, encoded);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Could not post: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 34)),
              onPressed: _busy ? null : _post,
              child: const Text('Post'),
            ),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        TextField(
          controller: _text,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(hintText: 'Thoughts at this moment...', border: InputBorder.none),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < _images.length; i++)
            Stack(children: [
              Image.memory(_images[i], width: 96, height: 96, fit: BoxFit.cover),
              Positioned(
                right: 0,
                top: 0,
                child: GestureDetector(
                  onTap: () => setState(() => _images.removeAt(i)),
                  child: Container(color: Colors.black54, child: const Icon(Icons.close, color: Colors.white, size: 18)),
                ),
              ),
            ]),
          if (_images.length < 3)
            GestureDetector(
              onTap: _add,
              child: Container(width: 96, height: 96, color: const Color(0xFFF3F3F3), child: const Icon(Icons.add, size: 36, color: Colors.black38)),
            ),
        ]),
        const SizedBox(height: 16),
        const Text('Visible to all your current friends. Up to 3 photos.', style: TextStyle(color: Colors.black38, fontSize: 12)),
      ]),
    );
  }
}
