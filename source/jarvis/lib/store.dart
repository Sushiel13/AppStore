import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ChatMsg {
  final bool me;
  final String text;
  final DateTime time;
  ChatMsg(this.me, this.text, [DateTime? time]) : time = time ?? DateTime.now();

  Map<String, dynamic> toJson() => {'me': me, 'text': text, 'time': time.toIso8601String()};
  static ChatMsg fromJson(Map<String, dynamic> j) =>
      ChatMsg(j['me'] as bool, j['text'] as String, DateTime.tryParse(j['time'] as String? ?? ''));
}

class Reminder {
  final int id;
  final String text;
  final DateTime when;
  Reminder(this.id, this.text, this.when);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'when': when.toIso8601String()};
  static Reminder fromJson(Map<String, dynamic> j) =>
      Reminder(j['id'] as int, j['text'] as String, DateTime.parse(j['when'] as String));
}

/// All settings and saved data, kept on the phone in SharedPreferences.
class Store {
  static late SharedPreferences _p;

  static Future<void> init() async {
    _p = await SharedPreferences.getInstance();
  }

  // Settings
  static bool get speak => _p.getBool('speak') ?? true;
  static set speak(bool v) => _p.setBool('speak', v);

  static bool get autoListen => _p.getBool('autoListen') ?? false;
  static set autoListen(bool v) => _p.setBool('autoListen', v);

  static String get speechLocale => _p.getString('speechLocale') ?? 'en_IN';
  static set speechLocale(String v) => _p.setString('speechLocale', v);

  static String get city => _p.getString('city') ?? '';
  static set city(String v) => _p.setString('city', v);

  static String get countryCode => _p.getString('countryCode') ?? '91';
  static set countryCode(String v) => _p.setString('countryCode', v);

  static String get userName => _p.getString('userName') ?? '';
  static set userName(String v) => _p.setString('userName', v);

  /// none, gemini, openai
  static String get aiProvider => _p.getString('aiProvider') ?? 'none';
  static set aiProvider(String v) => _p.setString('aiProvider', v);

  static String get aiKey => _p.getString('aiKey') ?? '';
  static set aiKey(String v) => _p.setString('aiKey', v);

  static String get aiModel => _p.getString('aiModel') ?? '';
  static set aiModel(String v) => _p.setString('aiModel', v);

  static String get aiBaseUrl => _p.getString('aiBaseUrl') ?? '';
  static set aiBaseUrl(String v) => _p.setString('aiBaseUrl', v);

  // Lists
  static List<String> list(String name) => _p.getStringList('list_$name') ?? [];
  static Future<void> setList(String name, List<String> items) => _p.setStringList('list_$name', items);

  static List<String> get notes => _p.getStringList('notes') ?? [];
  static set notes(List<String> v) => _p.setStringList('notes', v);

  static List<Reminder> get reminders {
    final raw = _p.getString('reminders');
    if (raw == null) return [];
    final all = (jsonDecode(raw) as List)
        .map((e) => Reminder.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return all.where((r) => r.when.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.when.compareTo(b.when));
  }

  static set reminders(List<Reminder> v) =>
      _p.setString('reminders', jsonEncode(v.map((e) => e.toJson()).toList()));

  static int nextId() {
    final id = (_p.getInt('nextId') ?? 100) + 1;
    _p.setInt('nextId', id);
    return id;
  }

  static List<ChatMsg> get history {
    final raw = _p.getString('history');
    if (raw == null) return [];
    return (jsonDecode(raw) as List)
        .map((e) => ChatMsg.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static set history(List<ChatMsg> v) {
    final keep = v.length > 80 ? v.sublist(v.length - 80) : v;
    _p.setString('history', jsonEncode(keep.map((e) => e.toJson()).toList()));
  }
}
