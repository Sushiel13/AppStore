import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../screens/call.dart';
import '../widgets.dart';
import 'db.dart';
import 'notify.dart';

/// 1-to-1 voice/video calls over WebRTC, using Firestore for signalling.
class CallService {
  CallService._();
  static StreamSubscription? _incoming;
  static bool inCall = false;
  static final _seen = <String>{};

  static Future<bool> _permissions(bool video) async {
    final perms = [Permission.microphone, if (video) Permission.camera];
    final res = await perms.request();
    return res.values.every((s) => s.isGranted);
  }

  static Future<void> startCall(BuildContext context, String other, {required bool video, String? chatId}) async {
    if (inCall) return;
    if (!await _permissions(video)) {
      if (context.mounted) toast(context, video ? 'Allow microphone and camera to call' : 'Allow microphone to call');
      return;
    }
    final ref = Db.calls.doc();
    await ref.set({
      'caller': Db.uid,
      'callerName': Db.me?['name'] ?? '',
      'callee': other,
      'video': video,
      'status': 'ringing',
      'time': FieldValue.serverTimestamp(),
    });
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CallScreen(callId: ref.id, otherUid: other, video: video, isCaller: true)),
    );
  }

  static void listenIncoming() {
    _incoming?.cancel();
    _incoming = Db.calls
        .where('callee', isEqualTo: Db.uid)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .listen((snap) async {
      for (final ch in snap.docChanges) {
        if (ch.type != DocumentChangeType.added) continue;
        final id = ch.doc.id;
        final d = ch.doc.data();
        if (d == null || _seen.contains(id)) continue;
        _seen.add(id);
        final t = d['time'];
        if (t is Timestamp && DateTime.now().difference(t.toDate()).inSeconds > 50) continue;
        if (inCall) {
          await ch.doc.reference.update({'status': 'busy'});
          continue;
        }
        final video = d['video'] == true;
        Notify.showCall(id, d['callerName'] ?? 'BaatCheet', video);
        navigatorKey.currentState?.push(MaterialPageRoute(
          builder: (_) => CallScreen(callId: id, otherUid: d['caller'], video: video, isCaller: false),
        ));
      }
    }, onError: (_) {});
  }

  static Future<bool> ensurePermissions(bool video) => _permissions(video);

  static void stopListening() {
    _incoming?.cancel();
    _incoming = null;
  }
}
