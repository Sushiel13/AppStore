import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../services/calls.dart';
import '../services/db.dart';
import '../services/notify.dart';
import '../widgets.dart';
import 'auth.dart';
import 'chats.dart';
import 'contacts.dart';
import 'moments.dart';
import 'qr.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Notify.requestPermission();
    Notify.watchChats();
    CallService.listenIncoming();
  }

  @override
  void dispose() {
    Notify.stop();
    CallService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [const ChatsTab(), const ContactsTab(), const DiscoverTab(), const MeTab()];
    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Db.chats.where('members', arrayContains: Db.uid).snapshots(),
        builder: (context, chatSnap) {
          var unread = 0;
          for (final d in chatSnap.data?.docs ?? const []) {
            final u = (d.data()['unread'] as Map?)?[Db.uid];
            if (u is num) unread += u.toInt();
          }
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Db.requests.where('to', isEqualTo: Db.uid).snapshots(),
            builder: (context, reqSnap) {
              final reqs = reqSnap.data?.docs.length ?? 0;
              return NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                backgroundColor: const Color(0xFFF7F7F7),
                indicatorColor: Colors.transparent,
                height: 62,
                destinations: [
                  NavigationDestination(
                    icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline)),
                    selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble, color: kGreen)),
                    label: 'Chats',
                  ),
                  NavigationDestination(
                    icon: Badge(isLabelVisible: reqs > 0, label: Text('$reqs'), child: const Icon(Icons.contacts_outlined)),
                    selectedIcon: Badge(isLabelVisible: reqs > 0, label: Text('$reqs'), child: const Icon(Icons.contacts, color: kGreen)),
                    label: 'Contacts',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.explore_outlined),
                    selectedIcon: Icon(Icons.explore, color: kGreen),
                    label: 'Discover',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person, color: kGreen),
                    label: 'Me',
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class DiscoverTab extends StatelessWidget {
  const DiscoverTab({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: ListView(
        children: [
          SectionTile(
            icon: Icons.camera,
            title: 'Moments',
            color: const Color(0xFFF2A33A),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MomentsScreen())),
          ),
          const SizedBox(height: 8),
          SectionTile(
            icon: Icons.qr_code_scanner,
            title: 'Scan',
            color: const Color(0xFF3D83F7),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ScanScreen())),
          ),
        ],
      ),
    );
  }
}

class MeTab extends StatefulWidget {
  const MeTab({super.key});
  @override
  State<MeTab> createState() => _MeTabState();
}

class _MeTabState extends State<MeTab> {
  @override
  Widget build(BuildContext context) {
    final me = Db.me ?? {};
    return Scaffold(
      backgroundColor: kBg,
      body: ListView(
        children: [
          Material(
            color: Colors.white,
            child: InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileSetupScreen(editing: true)));
                setState(() {});
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 72, 16, 36),
                child: Row(
                  children: [
                    Avatar(data: me['avatar'], name: me['name'] ?? '', size: 64),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(me['name'] ?? '', style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 6),
                          Text('BaatCheet ID: ${me['chatId'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code, color: Colors.black54),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyQrScreen())),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.black26),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SectionTile(
            icon: Icons.camera,
            title: 'My Moments',
            color: const Color(0xFFF2A33A),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MomentsScreen(onlyUser: Db.uid))),
          ),
          const SizedBox(height: 8),
          SectionTile(
            icon: Icons.info_outline,
            title: 'About BaatCheet',
            color: const Color(0xFF3D83F7),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'BaatCheet',
              applicationVersion: '1.0.0',
              children: const [Text('Chat, groups, Moments and calls with friends and family.')],
            ),
          ),
          const SizedBox(height: 8),
          SectionTile(
            icon: Icons.logout,
            title: 'Log out',
            color: Colors.redAccent,
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Log out?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Log out')),
                  ],
                ),
              );
              if (ok == true) {
                Notify.stop();
                CallService.stopListening();
                navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
                await Db.auth.signOut();
                navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const AuthGate()), (_) => false);
              }
            },
          ),
        ],
      ),
    );
  }
}
