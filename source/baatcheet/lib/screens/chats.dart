import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/db.dart';
import '../widgets.dart';
import 'chat.dart';
import 'contacts.dart';
import 'group.dart';
import 'qr.dart';

class ChatsTab extends StatelessWidget {
  const ChatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BaatCheet'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline),
            color: const Color(0xFF4C4C4C),
            onSelected: (v) {
              final page = switch (v) {
                'group' => const NewGroupScreen(),
                'add' => const AddFriendScreen(),
                _ => const ScanScreen(),
              };
              Navigator.push(context, MaterialPageRoute(builder: (_) => page));
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'group', child: _MenuRow(Icons.chat, 'New group chat')),
              PopupMenuItem(value: 'add', child: _MenuRow(Icons.person_add, 'Add contacts')),
              PopupMenuItem(value: 'scan', child: _MenuRow(Icons.qr_code_scanner, 'Scan')),
            ],
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.chats.where('members', arrayContains: Db.uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Could not load chats\n${snap.error}', textAlign: TextAlign.center));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs.where((d) => d.data()['lastTime'] != null || d.data()['type'] == 'group').toList()
            ..sort((a, b) {
              final ta = a.data()['lastTime'];
              final tb = b.data()['lastTime'];
              if (ta is! Timestamp) return -1;
              if (tb is! Timestamp) return 1;
              return tb.compareTo(ta);
            });
          if (docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No chats yet.\nAdd a friend from Contacts or tap + to start.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black45)),
              ),
            );
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0.5, indent: 76, color: Color(0xFFE5E5E5)),
            itemBuilder: (context, i) => ChatTile(chatId: docs[i].id, chat: docs[i].data()),
          );
        },
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white)),
      ]);
}

/// Resolves the title and avatar for a chat (other person for direct chats).
class ChatTitle {
  ChatTitle(this.name, this.avatar, this.isGroup, this.otherUid);
  final String name;
  final String? avatar;
  final bool isGroup;
  final String? otherUid;

  static Future<ChatTitle> of(Map<String, dynamic> chat) async {
    if (chat['type'] == 'group') {
      final n = List.from(chat['members'] ?? []).length;
      return ChatTitle('${chat['name'] ?? 'Group'} ($n)', chat['avatar'], true, null);
    }
    final other = List<String>.from(chat['members'] ?? []).firstWhere((m) => m != Db.uid, orElse: () => Db.uid);
    final u = await Db.user(other);
    return ChatTitle(u['name'] ?? 'Unknown', u['avatar'], false, other);
  }
}

class ChatTile extends StatelessWidget {
  const ChatTile({super.key, required this.chatId, required this.chat});
  final String chatId;
  final Map<String, dynamic> chat;

  @override
  Widget build(BuildContext context) {
    final unread = ((chat['unread'] as Map?)?[Db.uid] as num?)?.toInt() ?? 0;
    return FutureBuilder<ChatTitle>(
      future: ChatTitle.of(chat),
      builder: (context, t) {
        final title = t.data;
        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: title == null
                ? null
                : () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: chatId))),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: unread > 0,
                    label: Text(unread > 99 ? '99+' : '$unread'),
                    child: Avatar(data: title?.avatar, name: title?.name ?? '', group: (title?.isGroup ?? false) && title?.avatar == null, size: 48),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(title?.name ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w500)),
                            ),
                            Text(shortTime(chat['lastTime']), style: const TextStyle(color: Colors.black38, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(chat['lastText'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black45, fontSize: 14)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
