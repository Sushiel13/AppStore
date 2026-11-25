import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../screens/chat.dart';
import '../screens/chats.dart';
import 'db.dart';

/// Local notifications for new messages and incoming calls.
///
/// The free Firebase plan has no Cloud Functions, so there is no server push:
/// alerts arrive while the app is open or still running in the background.
class Notify {
  Notify._();
  static final _plugin = FlutterLocalNotificationsPlugin();
  static StreamSubscription? _sub;
  static String? openChatId;
  static bool _first = true;

  static const _msgChannel = AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'New chat messages',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _callChannel = AndroidNotificationDetails(
    'calls',
    'Calls',
    channelDescription: 'Incoming voice and video calls',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true,
  );

  static Future<void> init() async {
    await _plugin.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (r) {
        final p = r.payload;
        if (p != null && p.startsWith('chat:')) {
          navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ChatScreen(chatId: p.substring(5))));
        }
      },
    );
  }

  static Future<void> requestPermission() async {
    await Permission.notification.request();
  }

  static void watchChats() {
    _sub?.cancel();
    _first = true;
    _sub = Db.chats.where('members', arrayContains: Db.uid).snapshots().listen((snap) {
      if (_first) {
        _first = false;
        return;
      }
      for (final ch in snap.docChanges) {
        if (ch.type == DocumentChangeType.removed) continue;
        final d = ch.doc.data();
        if (d == null) continue;
        final sender = d['lastSender'] ?? '';
        final unread = ((d['unread'] as Map?)?[Db.uid] as num?)?.toInt() ?? 0;
        if (sender == '' || sender == Db.uid || unread == 0) continue;
        if (ch.doc.id == openChatId) continue;
        if (ch.doc.metadata.hasPendingWrites) continue;
        _showMessage(ch.doc.id, d, unread);
      }
    }, onError: (_) {});
  }

  static Future<void> _showMessage(String chatId, Map<String, dynamic> chat, int unread) async {
    final title = await ChatTitle.of(chat);
    await _plugin.show(
      chatId.hashCode & 0x7fffffff,
      unread > 1 ? '${title.name} ($unread)' : title.name,
      chat['lastText'] ?? '',
      const NotificationDetails(android: _msgChannel),
      payload: 'chat:$chatId',
    );
  }

  static Future<void> showCall(String callId, String name, bool video) => _plugin.show(
        callId.hashCode & 0x7fffffff,
        name,
        video ? 'Incoming video call' : 'Incoming voice call',
        const NotificationDetails(android: _callChannel),
        payload: 'call:$callId',
      );

  static Future<void> cancelCall(String callId) => _plugin.cancel(callId.hashCode & 0x7fffffff);

  static void stop() {
    _sub?.cancel();
    _sub = null;
  }
}
