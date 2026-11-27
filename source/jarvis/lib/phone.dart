import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'store.dart';

/// Reminders shown as phone notifications at the chosen time.
class Reminders {
  static final _n = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    await _n.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
    );
  }

  static Future<void> askPermission() async {
    final a = _n.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await a?.requestNotificationsPermission();
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription: 'Reminders you ask Jarvis for',
      importance: Importance.max,
      priority: Priority.high,
    ),
  );

  static Future<void> schedule(Reminder r) async {
    final when = tz.TZDateTime.from(r.when, tz.UTC);
    try {
      await _n.zonedSchedule(r.id, 'Reminder', r.text, when, _details,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    } on PlatformException {
      // Exact alarms not allowed on this phone: a few minutes' leeway is fine.
      await _n.zonedSchedule(r.id, 'Reminder', r.text, when, _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime);
    }
  }

  static Future<void> cancel(int id) => _n.cancel(id);
}

class Person {
  final String name;
  final String number;
  Person(this.name, this.number);
}

class NoContactsPermission implements Exception {}

/// Finds people in the phone's contacts by spoken name.
class People {
  static List<Contact>? _cache;

  static Future<List<Contact>> _all() async {
    if (_cache != null) return _cache!;
    if (!await FlutterContacts.requestPermission(readonly: true)) throw NoContactsPermission();
    _cache = await FlutterContacts.getContacts(withProperties: true);
    return _cache!;
  }

  /// Best matches for [query], best first. Only contacts with a phone number.
  static Future<List<Person>> find(String query) async {
    final q = query.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final squash = q.replaceAll(' ', '');
    final scored = <(int, Person)>[];
    for (final c in await _all()) {
      if (c.phones.isEmpty) continue;
      final n = c.displayName.toLowerCase().trim();
      if (n.isEmpty) continue;
      int score;
      if (n == q || n.replaceAll(' ', '') == squash) {
        score = 4;
      } else if (n.startsWith('$q ')) {
        score = 3;
      } else if (n.split(' ').contains(q)) {
        score = 2;
      } else if (q.length >= 3 && n.contains(q)) {
        score = 1;
      } else {
        continue;
      }
      final phone = c.phones.firstWhere((p) => p.isPrimary, orElse: () => c.phones.first);
      scored.add((score, Person(c.displayName, phone.number)));
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    if (scored.isEmpty) return [];
    final top = scored.first.$1;
    final seen = <String>{};
    return [
      for (final s in scored)
        if (s.$1 == top && seen.add(s.$2.name)) s.$2
    ];
  }

  /// Digits for wa.me links, with the home country code added when missing.
  static String international(String number) {
    var d = number.replaceAll(RegExp(r'[^\d+]'), '');
    if (d.startsWith('+')) return d.substring(1);
    if (d.startsWith('00')) return d.substring(2);
    final cc = Store.countryCode.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('0')) d = d.substring(1);
    if (d.length <= 10 && cc.isNotEmpty) return '$cc$d';
    return d;
  }
}
