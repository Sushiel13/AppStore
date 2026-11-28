import 'package:flutter_test/flutter_test.dart';
import 'package:wifibooster/analysis.dart';
import 'package:wifibooster/speedtest.dart';

void main() {
  test('channels from frequency', () {
    expect(channelOf(2412), 1);
    expect(channelOf(2437), 6);
    expect(channelOf(2462), 11);
    expect(channelOf(2484), 14);
    expect(channelOf(5180), 36);
    expect(channelOf(5745), 149);
    expect(channelOf(5955), 1);
    expect(bandOf(2437), '2.4 GHz');
    expect(bandOf(5180), '5 GHz');
    expect(bandOf(6115), '6 GHz');
  });

  test('signal grades', () {
    expect(signalOf(-50).label, 'Excellent');
    expect(signalOf(-60).label, 'Good');
    expect(signalOf(-70).label, 'Fair');
    expect(signalOf(-85).label, 'Weak');
    expect(signalOf(-20).percent, 100);
    expect(signalOf(-100).percent, 0);
  });

  test('best 2.4 GHz channel avoids crowded ones', () {
    final nets = [
      const Network(bssid: 'a', level: -45, frequency: 2412), // ch 1
      const Network(bssid: 'b', level: -50, frequency: 2412), // ch 1
      const Network(bssid: 'c', level: -55, frequency: 2437), // ch 6
      const Network(bssid: 'd', level: -60, frequency: 2442), // ch 7
    ];
    expect(best24(nets), 11);
  });

  test('best 5 GHz channel picks a free one', () {
    final nets = [
      const Network(bssid: 'a', level: -50, frequency: 5180, width: 80), // 36-48
      const Network(bssid: 'b', level: -60, frequency: 5745), // 149
    ];
    final best = best5(nets);
    expect([36, 40, 44, 48, 149].contains(best), isFalse);
  });

  test('suggests 5 GHz when stuck on 2.4 GHz', () {
    const wifi = WifiNow(ssid: 'Home', bssid: 'x', rssi: -60, linkSpeed: 72, frequency: 2437, gateway: '192.168.1.1');
    final d = diagnose(wifi: wifi, nearby: const [
      Network(ssid: 'Home', bssid: 'x', level: -60, frequency: 2437),
      Network(ssid: 'Home', bssid: 'y', level: -64, frequency: 5180),
    ]);
    expect(d.fixes.first.title, 'Switch to 5 GHz');
    expect(d.score, lessThan(85));
  });

  test('blames the internet line when the router is fast', () {
    const wifi = WifiNow(ssid: 'Home', rssi: -50, linkSpeed: 866, frequency: 5180);
    final d = diagnose(wifi: wifi, routerMs: 3, internetMs: 140);
    expect(d.fixes.any((f) => f.title.contains('internet line')), isTrue);
    expect(d.fixes.any((f) => f.title.contains('router (')), isFalse);
  });

  test('healthy Wi-Fi scores high', () {
    const wifi = WifiNow(ssid: 'Home', rssi: -48, linkSpeed: 866, frequency: 5180, privateDns: true);
    final s = SpeedResult(download: 180, upload: 90, ping: 12, jitter: 2, time: DateTime(2026));
    final d = diagnose(wifi: wifi, routerMs: 3, internetMs: 12, speed: s, planMbps: 200);
    expect(d.score, greaterThanOrEqualTo(85));
  });

  test('not connected', () {
    final d = diagnose(wifi: const WifiNow(connected: false));
    expect(d.score, 0);
    expect(d.fixes.single.action, FixAction.wifiPanel);
  });

  test('median and jitter', () {
    expect(median([5, 1, 3]), 3);
    expect(median([1, 2, 3, 4]), 2.5);
    expect(jitter([10, 20, 10]), 10);
  });
}
