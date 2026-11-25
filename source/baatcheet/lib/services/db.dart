import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// All Firestore access for the app.
///
/// Data model (works on the free Spark plan: no Cloud Storage, no Functions):
///   users/{uid}                 name, chatId, about, avatar (base64), searchKey
///   users/{uid}/contacts/{uid2} addedAt
///   requests/{from_to}          from, to, fromName, note, time
///   chats/{chatId}              type, members, name, avatar, admins,
///                               lastText, lastTime, lastSender, unread{uid:n}, readAt{uid:ts}
///   chats/{chatId}/messages/{id} sender, senderName, type, text, data, duration, time
///   moments/{id}                author, authorName, text, images[], audience[], likes[], comments[], time
///   calls/{id}                  caller, callee, video, status, offer, answer, time
class Db {
  Db._();
  static final fs = FirebaseFirestore.instance;
  static final auth = FirebaseAuth.instance;

  static String get uid => auth.currentUser!.uid;

  static CollectionReference<Map<String, dynamic>> get users => fs.collection('users');
  static CollectionReference<Map<String, dynamic>> get chats => fs.collection('chats');
  static CollectionReference<Map<String, dynamic>> get moments => fs.collection('moments');
  static CollectionReference<Map<String, dynamic>> get requests => fs.collection('requests');
  static CollectionReference<Map<String, dynamic>> get calls => fs.collection('calls');

  static CollectionReference<Map<String, dynamic>> contactsOf(String u) =>
      users.doc(u).collection('contacts');

  // ---------- profile cache ----------
  static final Map<String, Map<String, dynamic>> _userCache = {};
  static Map<String, dynamic>? me;

  static Future<Map<String, dynamic>?> loadMe() async {
    final d = await users.doc(uid).get();
    me = d.data();
    if (me != null) _userCache[uid] = me!;
    return me;
  }

  static Future<Map<String, dynamic>> user(String u) async {
    if (_userCache.containsKey(u)) return _userCache[u]!;
    final d = await users.doc(u).get();
    final data = d.data() ?? {'name': 'Unknown'};
    _userCache[u] = data;
    return data;
  }

  static void cacheUser(String u, Map<String, dynamic> data) => _userCache[u] = data;

  static Future<bool> chatIdTaken(String chatId) async {
    final q = await users.where('chatId', isEqualTo: chatId.toLowerCase()).limit(1).get();
    return q.docs.isNotEmpty && q.docs.first.id != uid;
  }

  static Future<void> saveProfile({
    required String name,
    required String chatId,
    String about = '',
    String? avatar,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'chatId': chatId.trim().toLowerCase(),
      'about': about.trim(),
      'searchKey': name.trim().toLowerCase(),
      'updated': FieldValue.serverTimestamp(),
    };
    if (avatar != null) data['avatar'] = avatar;
    await users.doc(uid).set(data, SetOptions(merge: true));
    await loadMe();
  }

  // ---------- contacts & requests ----------
  static Future<Map<String, dynamic>?> findByChatId(String chatId) async {
    final q = await users.where('chatId', isEqualTo: chatId.trim().toLowerCase()).limit(1).get();
    if (q.docs.isEmpty) return null;
    return {'uid': q.docs.first.id, ...q.docs.first.data()};
  }

  static Future<bool> isContact(String other) async {
    final d = await contactsOf(uid).doc(other).get();
    return d.exists;
  }

  static Future<void> sendRequest(String to, String note) async {
    await requests.doc('${uid}_$to').set({
      'from': uid,
      'to': to,
      'fromName': me?['name'] ?? '',
      'note': note,
      'time': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> acceptRequest(String from) async {
    final batch = fs.batch();
    batch.set(contactsOf(uid).doc(from), {'addedAt': FieldValue.serverTimestamp()});
    batch.set(contactsOf(from).doc(uid), {'addedAt': FieldValue.serverTimestamp()});
    batch.delete(requests.doc('${from}_$uid'));
    await batch.commit();
    final chatId = directChatId(from);
    await chats.doc(chatId).set({
      'type': 'direct',
      'members': [uid, from]..sort(),
      'lastText': 'You are now friends. Say hello!',
      'lastTime': FieldValue.serverTimestamp(),
      'lastSender': '',
    }, SetOptions(merge: true));
  }

  static Future<void> declineRequest(String from) => requests.doc('${from}_$uid').delete();

  static Future<void> removeContact(String other) async {
    final batch = fs.batch();
    batch.delete(contactsOf(uid).doc(other));
    batch.delete(contactsOf(other).doc(uid));
    await batch.commit();
  }

  static Future<List<String>> contactIds() async {
    final q = await contactsOf(uid).get();
    return q.docs.map((d) => d.id).toList();
  }

  // ---------- chats ----------
  static String directChatId(String other) {
    final l = [uid, other]..sort();
    return l.join('_');
  }

  static Future<String> openDirect(String other) async {
    final id = directChatId(other);
    await chats.doc(id).set({
      'type': 'direct',
      'members': [uid, other]..sort(),
    }, SetOptions(merge: true));
    return id;
  }

  static Future<String> createGroup(String name, List<String> members) async {
    final all = {...members, uid}.toList();
    final ref = chats.doc();
    await ref.set({
      'type': 'group',
      'name': name.trim(),
      'members': all,
      'admins': [uid],
      'createdBy': uid,
      'lastText': '${me?['name'] ?? 'Someone'} created the group',
      'lastTime': FieldValue.serverTimestamp(),
      'lastSender': '',
    });
    await ref.collection('messages').add({
      'sender': uid,
      'senderName': me?['name'] ?? '',
      'type': 'system',
      'text': '${me?['name'] ?? 'Someone'} created the group "$name"',
      'time': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  static Future<void> addGroupMembers(String chatId, List<String> add) async {
    await chats.doc(chatId).update({'members': FieldValue.arrayUnion(add)});
    final names = <String>[];
    for (final u in add) {
      names.add((await user(u))['name'] ?? '');
    }
    await sendMessage(chatId, type: 'system', text: '${me?['name']} added ${names.join(', ')}');
  }

  static Future<void> leaveGroup(String chatId) async {
    await sendMessage(chatId, type: 'system', text: '${me?['name']} left the group');
    await chats.doc(chatId).update({
      'members': FieldValue.arrayRemove([uid]),
      'admins': FieldValue.arrayRemove([uid]),
    });
  }

  static Future<void> sendMessage(
    String chatId, {
    required String type,
    String text = '',
    String? data,
    int? duration,
  }) async {
    final chatRef = chats.doc(chatId);
    final chat = (await chatRef.get()).data() ?? {};
    final members = List<String>.from(chat['members'] ?? []);
    final msg = <String, dynamic>{
      'sender': uid,
      'senderName': me?['name'] ?? '',
      'type': type,
      'text': text,
      'time': FieldValue.serverTimestamp(),
    };
    if (data != null) msg['data'] = data;
    if (duration != null) msg['duration'] = duration;
    await chatRef.collection('messages').add(msg);

    final preview = switch (type) {
      'image' => '[Photo]',
      'voice' => '[Voice ${duration ?? 0}s]',
      'call' => text,
      'system' => text,
      _ => text,
    };
    final update = <String, dynamic>{
      'lastText': chat['type'] == 'group' && type != 'system' ? '${me?['name']}: $preview' : preview,
      'lastTime': FieldValue.serverTimestamp(),
      'lastSender': type == 'system' ? '' : uid,
      'readAt.$uid': FieldValue.serverTimestamp(),
    };
    for (final m in members) {
      if (m != uid) update['unread.$m'] = FieldValue.increment(1);
    }
    await chatRef.update(update);
  }

  static Future<void> markRead(String chatId) async {
    await chats.doc(chatId).update({
      'unread.$uid': 0,
      'readAt.$uid': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> recall(String chatId, String messageId) async {
    await chats.doc(chatId).collection('messages').doc(messageId).update({
      'type': 'recalled',
      'text': '',
      'data': FieldValue.delete(),
    });
  }

  // ---------- moments ----------
  /// Moment ids sort newest-first, so a plain query returns the latest posts
  /// without needing a composite index.
  static String newestFirstId() {
    final inv = 9999999999999 - DateTime.now().millisecondsSinceEpoch;
    return '${inv.toString().padLeft(13, '0')}_$uid';
  }

  static Future<void> postMoment(String text, List<String> images) async {
    final audience = [...await contactIds(), uid];
    await moments.doc(newestFirstId()).set({
      'author': uid,
      'authorName': me?['name'] ?? '',
      'text': text.trim(),
      'images': images,
      'audience': audience,
      'likes': <String>[],
      'comments': <Map<String, dynamic>>[],
      'time': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> toggleLike(String id, bool liked) => moments.doc(id).update({
        'likes': liked ? FieldValue.arrayRemove([uid]) : FieldValue.arrayUnion([uid]),
      });

  static Future<void> comment(String id, String text) => moments.doc(id).update({
        'comments': FieldValue.arrayUnion([
          {
            'uid': uid,
            'name': me?['name'] ?? '',
            'text': text.trim(),
            'at': DateTime.now().millisecondsSinceEpoch,
          }
        ]),
      });

  // ---------- helpers ----------
  static String b64(Uint8List bytes) => base64Encode(bytes);
  static Uint8List unb64(String s) => base64Decode(s);
}
