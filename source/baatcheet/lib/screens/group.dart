import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../widgets.dart';
import 'chat.dart';
import 'contacts.dart';

/// Pick contacts. Returns the selected uids.
class PickContactsScreen extends StatefulWidget {
  const PickContactsScreen({super.key, required this.title, this.exclude = const [], this.askName = false});
  final String title;
  final List<String> exclude;
  final bool askName;
  @override
  State<PickContactsScreen> createState() => _PickContactsScreenState();
}

class _PickContactsScreenState extends State<PickContactsScreen> {
  final _selected = <String>{};
  final _name = TextEditingController();
  List<MapEntry<String, Map<String, dynamic>>>? _contacts;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    () async {
      final ids = (await Db.contactIds()).where((i) => !widget.exclude.contains(i)).toList();
      final list = <MapEntry<String, Map<String, dynamic>>>[];
      for (final id in ids) {
        list.add(MapEntry(id, await Db.user(id)));
      }
      list.sort((a, b) => (a.value['name'] ?? '').toString().compareTo((b.value['name'] ?? '').toString()));
      if (mounted) setState(() => _contacts = list);
    }();
  }

  Future<void> _done() async {
    if (_selected.isEmpty) return;
    if (!widget.askName) return Navigator.pop(context, _selected.toList());
    final name = _name.text.trim().isEmpty ? 'Group chat' : _name.text.trim();
    setState(() => _busy = true);
    try {
      final id = await Db.createGroup(name, _selected.toList());
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: id)));
    } catch (e) {
      if (mounted) toast(context, 'Could not create group: $e');
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 34)),
              onPressed: _selected.isEmpty || _busy ? null : _done,
              child: Text(_selected.isEmpty ? 'Done' : 'Done (${_selected.length})'),
            ),
          ),
        ],
      ),
      body: _contacts == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              if (widget.askName)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(hintText: 'Group name', border: InputBorder.none, prefixIcon: Icon(Icons.edit)),
                  ),
                ),
              const SizedBox(height: 8),
              if (_contacts!.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Text('No contacts to add', textAlign: TextAlign.center)),
              for (final c in _contacts!)
                Material(
                  color: Colors.white,
                  child: CheckboxListTile(
                    value: _selected.contains(c.key),
                    activeColor: kGreen,
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: Avatar(data: c.value['avatar'], name: c.value['name'] ?? '', size: 40),
                    title: Text(c.value['name'] ?? ''),
                    onChanged: (v) => setState(() => v == true ? _selected.add(c.key) : _selected.remove(c.key)),
                  ),
                ),
            ]),
    );
  }
}

class NewGroupScreen extends StatelessWidget {
  const NewGroupScreen({super.key});
  @override
  Widget build(BuildContext context) => const PickContactsScreen(title: 'New group chat', askName: true);
}

class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: Db.chats.doc(chatId).snapshots(),
      builder: (context, snap) {
        final g = snap.data?.data() ?? {};
        final members = List<String>.from(g['members'] ?? []);
        final admins = List<String>.from(g['admins'] ?? []);
        final isAdmin = admins.contains(Db.uid);
        return Scaffold(
          appBar: AppBar(title: Text('Chat Info (${members.length})')),
          body: ListView(children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 14,
                children: [
                  for (final m in members)
                    FutureBuilder<Map<String, dynamic>>(
                      future: Db.user(m),
                      builder: (context, u) => GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(uid: m))),
                        child: SizedBox(
                          width: 56,
                          child: Column(children: [
                            Avatar(data: u.data?['avatar'], name: u.data?['name'] ?? '', size: 52),
                            const SizedBox(height: 4),
                            Text(u.data?['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: () async {
                      final add = await Navigator.push<List<String>>(
                        context,
                        MaterialPageRoute(builder: (_) => PickContactsScreen(title: 'Add members', exclude: members)),
                      );
                      if (add != null && add.isNotEmpty) await Db.addGroupMembers(chatId, add);
                    },
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.add, color: Colors.black38),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              child: ListTile(
                title: const Text('Group Name'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(g['name'] ?? '', style: const TextStyle(color: Colors.black45)),
                  if (isAdmin) const Icon(Icons.chevron_right, color: Colors.black26),
                ]),
                onTap: !isAdmin
                    ? null
                    : () async {
                        final c = TextEditingController(text: g['name'] ?? '');
                        final name = await showDialog<String>(
                          context: context,
                          builder: (d) => AlertDialog(
                            title: const Text('Group name'),
                            content: TextField(controller: c, autofocus: true),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
                            ],
                          ),
                        );
                        if (name != null && name.isNotEmpty) {
                          await Db.chats.doc(chatId).update({'name': name});
                          await Db.sendMessage(chatId, type: 'system', text: '${Db.me?['name']} renamed the group to "$name"');
                        }
                      },
              ),
            ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              child: ListTile(
                title: const Center(child: Text('Leave group', style: TextStyle(color: Colors.red))),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: const Text('Leave this group?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Leave')),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await Db.leaveGroup(chatId);
                    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
              ),
            ),
          ]),
        );
      },
    );
  }
}
