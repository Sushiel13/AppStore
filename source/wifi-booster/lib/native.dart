import 'package:flutter/services.dart';

import 'analysis.dart';

/// Talks to the Android side (MainActivity.kt) for Wi-Fi details Flutter can't read alone.
class Native {
  static const _ch = MethodChannel('wifibooster/native');

  static Future<bool> hasLocation() async => (await _ch.invokeMethod('hasLocation')) == true;

  static Future<bool> locationOn() async => (await _ch.invokeMethod('locationOn')) == true;

  static Future<bool> requestLocation() async => (await _ch.invokeMethod('requestLocation')) == true;

  static Future<WifiNow> wifiInfo() async {
    final r = await _ch.invokeMethod('wifiInfo');
    return WifiNow.fromMap(Map<String, dynamic>.from(r as Map));
  }

  static Future<List<Network>> scan() async {
    final r = await _ch.invokeMethod('scan');
    return (r as List)
        .map((e) => Network.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  static Future<void> openSettings(String action) =>
      _ch.invokeMethod('openSettings', {'action': action});

  static Future<void> openWifiPanel() => _ch.invokeMethod('openWifiPanel');

  static Future<void> openUrl(String url) => _ch.invokeMethod('openUrl', {'url': url});

  static Future<void> appSettings() => _ch.invokeMethod('appSettings');
}
