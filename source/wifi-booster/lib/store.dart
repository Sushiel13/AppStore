import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'analysis.dart';

/// Saves speed test history and settings on the phone.
class Store {
  static SharedPreferences? _p;

  static Future<void> init() async => _p = await SharedPreferences.getInstance();

  static List<SpeedResult> history() {
    final raw = _p?.getStringList('history') ?? const [];
    final out = <SpeedResult>[];
    for (final r in raw) {
      try {
        out.add(SpeedResult.fromJson(jsonDecode(r) as Map<String, dynamic>));
      } catch (_) {}
    }
    return out;
  }

  static Future<void> addResult(SpeedResult r) async {
    final list = [jsonEncode(r.toJson()), ...?_p?.getStringList('history')];
    await _p?.setStringList('history', list.take(50).toList());
  }

  static Future<void> clearHistory() async => _p?.remove('history');

  static double? plan() => _p?.getDouble('plan');

  static Future<void> setPlan(double? v) async {
    if (v == null || v <= 0) {
      await _p?.remove('plan');
    } else {
      await _p?.setDouble('plan', v);
    }
  }

  static bool seenIntro() => _p?.getBool('intro') ?? false;

  static Future<void> setSeenIntro() async => _p?.setBool('intro', true);
}
