import 'package:flutter/services.dart';

/// Talks to the Android side (MainActivity.kt) for things Flutter can't do alone.
class Native {
  static const _ch = MethodChannel('jarvis/native');

  static Future<void> setAlarm(int hour, int minute, String? label) =>
      _ch.invokeMethod('setAlarm', {'hour': hour, 'minute': minute, 'label': label});

  static Future<void> setTimer(int seconds, String? label) =>
      _ch.invokeMethod('setTimer', {'seconds': seconds, 'label': label});

  static Future<void> showAlarms() => _ch.invokeMethod('showAlarms');

  static Future<void> torch(bool on) => _ch.invokeMethod('torch', {'on': on});

  static Future<Map<String, dynamic>> battery() async {
    final r = await _ch.invokeMethod('battery');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<List<AppInfo>> apps() async {
    final r = await _ch.invokeMethod('apps');
    return (r as List)
        .map((e) => AppInfo(e['name'] as String, e['package'] as String))
        .toList();
  }

  static Future<void> launch(String package) => _ch.invokeMethod('launch', {'package': package});

  /// Opens a link or URI. If [package] is given it tries that app first.
  static Future<void> open(String uri, {String? package}) =>
      _ch.invokeMethod('open', {'uri': uri, 'package': package});

  static Future<void> dial(String number) => _ch.invokeMethod('dial', {'number': number});

  static Future<void> sms(String number, String body) =>
      _ch.invokeMethod('sms', {'number': number, 'body': body});

  /// Starts a system screen by its intent action, e.g. android.settings.WIFI_SETTINGS.
  static Future<void> action(String action) => _ch.invokeMethod('action', {'action': action});

  /// direction: up, down, mute, unmute
  static Future<void> volume(String direction) => _ch.invokeMethod('volume', {'direction': direction});
}

class AppInfo {
  final String name;
  final String package;
  AppInfo(this.name, this.package);
}
