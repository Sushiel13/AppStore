import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/calls.dart';
import '../services/db.dart';
import '../widgets.dart';
import 'chat.dart';
import 'qr.dart';

class ContactsTab extends StatelessWidget {
  const ContactsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddFriendScreen())),
          ),
        ],
      ),
      body: ListView(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Db.requests.where('to', isEqualTo: Db.uid).snapshots(),
            builder: (context, s) {
              final n = s.data?.docs.length ?? 0;
              return SectionTile(
                icon: Icons.person_add,
                title: 'New Friends',
                color: const Color(0xFFF2A33A),
                trailing: n > 0 ? Badge(label: Text('$n')) : null,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RequestsScreen())),
              );
            },
          ),
          const Divider(height: 0.5, indent: 72, color: Color(0xFFE5E5E5)),
          SectionTile(
            icon: Icons.groups,
            title: 'Group Chats',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupListScreen())),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Db.contactsOf(Db.uid).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              final ids = snap.data!.docs.map((d) => d.id).toList();
              if (ids.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No contacts yet. Tap the add icon above to find friends by ID or QR code.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)),
                );
              }
              return FutureBuilder<List<MapEntry<String, Map<String, dynamic>>>>(
                future: _load(ids),
                builder: (context, f) {
                  final list = f.data ?? [];
                  return Column(children: [
                    for (final e in list)
                      ContactRow(
                        uid: e.key,
                        user: e.value,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: e.key))),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('${ids.length} friends', style: const TextStyle(color: Colors.black38)),
                    ),
                  ]);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static Future<List<MapEntry<String, Map<String, dynamic>>>> _load(List<String> ids) async {
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    for (final id in ids) {
      out.add(MapEntry(id, await Db.user(id)));
    }
    out.sort((a, b) => (a.value['name'] ?? '').toString().toLowerCase().compareTo((b.value['name'] ?? '').toString().toLowerCase()));
    return out;
  }
}

class ContactRow extends StatelessWidget {
  const ContactRow({super.key, required this.uid, required this.user, this.onTap, this.trailing});
  final String uid;
  final Map<String, dynamic> user;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        child: ListTile(
          leading: Avatar(data: user['avatar'], name: user['name'] ?? '', size: 40),
          title: Text(user['name'] ?? ''),
          trailing: trailing,
          onTap: onTap,
        ),
      );
}

class RequestsScreen extends StatelessWidget {
  const RequestsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Friends')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.requests.where('to', isEqualTo: Db.uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No new friend requests', style: TextStyle(color: Colors.black45)));
          return ListView(
            children: [
              for (final d in docs)
                FutureBuilder<Map<String, dynamic>>(
                  future: Db.user(d.data()['from']),
                  builder: (context, u) => Material(
                    color: Colors.white,
                    child: ListTile(
                      leading: Avatar(data: u.data?['avatar'], name: d.data()['fromName'] ?? '', size: 44),
                      title: Text(d.data()['fromName'] ?? ''),
                      subtitle: Text((d.data()['note'] ?? '').toString().isEmpty ? 'Wants to be your friend' : d.data()['note']),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: d.data()['from']))),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        TextButton(onPressed: () => Db.declineRequest(d.data()['from']), child: const Text('Decline')),
                        FilledButton(
                          style: FilledButton.styleFrom(minimumSize: const Size(72, 36)),
                          onPressed: () async {
                            await Db.acceptRequest(d.data()['from']);
                            if (context.mounted) toast(context, 'Added ${d.data()['fromName']}');
                          },
                          child: const Text('Accept'),
                        ),
                      ]),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class GroupListScreen extends StatelessWidget {
  const GroupListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Group Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.chats.where('members', arrayContains: Db.uid).snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final groups = snap.data!.docs.where((d) => d.data()['type'] == 'group').toList();
          if (groups.isEmpty) return const Center(child: Text('No group chats yet', style: TextStyle(color: Colors.black45)));
          return ListView(children: [
            for (final g in groups)
              Material(
                color: Colors.white,
                child: ListTile(
                  leading: Avatar(data: g.data()['avatar'], group: g.data()['avatar'] == null, size: 40),
                  title: Text(g.data()['name'] ?? 'Group'),
                  subtitle: Text('${List.from(g.data()['members'] ?? []).length} members'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: g.id))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});
  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _q = TextEditingController();
  bool _busy = false;

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _busy = true);
    try {
      final u = await Db.findByChatId(q);
      if (!mounted) return;
      if (u == null) {
        toast(context, 'No user with ID "$q"');
      } else {
        Db.cacheUser(u['uid'], u);
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: u['uid'])));
      }
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Contacts')),
      body: ListView(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: TextField(
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Search by BaatCheet ID',
                border: InputBorder.none,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busy ? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)) : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQrScreen())),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('My ID: ${Db.me?['chatId'] ?? ''}  ', style: const TextStyle(color: Colors.black54)),
                const Icon(Icons.qr_code, size: 18, color: kGreen),
              ]),
            ),
          ),
          SectionTile(
            icon: Icons.qr_code_scanner,
            title: 'Scan QR Code',
            color: const Color(0xFF3D83F7),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
          ),
        ],
      ),
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.uid});
  final String uid;
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool? _friend;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final u = await Db.user(widget.uid);
    final f = widget.uid == Db.uid ? true : await Db.isContact(widget.uid);
    if (mounted) setState(() {
      _user = u;
      _friend = f;
    });
  }

  Future<void> _request() async {
    final note = TextEditingController(text: "I'm ${Db.me?['name'] ?? ''}");
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Send friend request'),
        content: TextField(controller: note, decoration: const InputDecoration(labelText: 'Message')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true) return;
    await Db.sendRequest(widget.uid, note.text.trim());
    if (mounted) {
      setState(() => _requested = true);
      toast(context, 'Request sent');
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = _user;
    final isMe = widget.uid == Db.uid;
    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_friend == true && !isMe)
            PopupMenuButton<String>(
              onSelected: (_) async {
                await Db.removeContact(widget.uid);
                if (context.mounted) Navigator.pop(context);
              },
              itemBuilder: (_) => const [PopupMenuItem(value: 'del', child: Text('Remove friend'))],
            ),
        ],
      ),
      body: u == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Row(children: [
                  Avatar(data: u['avatar'], name: u['name'] ?? '', size: 64),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(u['name'] ?? '', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('BaatCheet ID: ${u['chatId'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                      if ((u['about'] ?? '').toString().isNotEmpty)
                        Padding(padding: const EdgeInsets.only(top: 4), child: Text(u['about'], style: const TextStyle(color: Colors.black54))),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              if (_friend == true && !isMe) ...[
                _action(Icons.chat_bubble_outline, 'Messages', () async {
                  final id = await Db.openDirect(widget.uid);
                  if (context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: id)));
                }),
                const Divider(height: 0.5, color: Color(0xFFE5E5E5)),
                _action(Icons.call_outlined, 'Voice Call', () => CallService.startCall(context, widget.uid, video: false)),
                const Divider(height: 0.5, color: Color(0xFFE5E5E5)),
                _action(Icons.videocam_outlined, 'Video Call', () => CallService.startCall(context, widget.uid, video: true)),
              ] else if (_friend == false)
                _action(Icons.person_add_alt, _requested ? 'Request sent' : 'Add to Contacts', _requested ? null : _request),
            ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback? onTap) => Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, color: onTap == null ? Colors.black26 : const Color(0xFF576B95)),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(fontSize: 16, color: onTap == null ? Colors.black26 : const Color(0xFF576B95), fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );
}
