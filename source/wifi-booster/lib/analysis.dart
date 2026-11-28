// Pure Wi-Fi logic: channels, signal quality, congestion and the fix list.
// No Flutter imports here so it can be unit tested.

import 'dart:math' as math;

class WifiNow {
  final bool wifiEnabled;
  final bool connected;
  final String ssid;
  final String bssid;
  final int rssi;
  final int linkSpeed;
  final int frequency;
  final int? txSpeed;
  final int? rxSpeed;
  final int? standard;
  final int? maxTx;
  final String gateway;
  final String ip;
  final List<String> dns;
  final bool? privateDns;
  final String privateDnsName;

  const WifiNow({
    this.wifiEnabled = true,
    this.connected = true,
    this.ssid = '',
    this.bssid = '',
    this.rssi = -60,
    this.linkSpeed = 0,
    this.frequency = 0,
    this.txSpeed,
    this.rxSpeed,
    this.standard,
    this.maxTx,
    this.gateway = '',
    this.ip = '',
    this.dns = const [],
    this.privateDns,
    this.privateDnsName = '',
  });

  factory WifiNow.fromMap(Map<String, dynamic> m) => WifiNow(
        wifiEnabled: m['wifiEnabled'] == true,
        connected: m['connected'] == true,
        ssid: (m['ssid'] ?? '') as String,
        bssid: (m['bssid'] ?? '') as String,
        rssi: (m['rssi'] ?? -127) as int,
        linkSpeed: (m['linkSpeed'] ?? 0) as int,
        frequency: (m['frequency'] ?? 0) as int,
        txSpeed: m['txSpeed'] as int?,
        rxSpeed: m['rxSpeed'] as int?,
        standard: m['standard'] as int?,
        maxTx: m['maxTx'] as int?,
        gateway: (m['gateway'] ?? '') as String,
        ip: (m['ip'] ?? '') as String,
        dns: ((m['dns'] ?? const []) as List).map((e) => e.toString()).toList(),
        privateDns: m['privateDns'] as bool?,
        privateDnsName: (m['privateDnsName'] ?? '') as String,
      );

  int get channel => channelOf(frequency);
  String get band => bandOf(frequency);

  /// Best guess of the real link rate: Android reports -1 for unknown values.
  int get bestLink {
    final c = [linkSpeed, txSpeed ?? 0, rxSpeed ?? 0].where((v) => v > 0);
    return c.isEmpty ? 0 : c.reduce(math.max);
  }
}

class Network {
  final String ssid;
  final String bssid;
  final int level;
  final int frequency;
  final int width;

  const Network({this.ssid = '', this.bssid = '', required this.level, required this.frequency, this.width = 20});

  factory Network.fromMap(Map<String, dynamic> m) => Network(
        ssid: (m['ssid'] ?? '') as String,
        bssid: (m['bssid'] ?? '') as String,
        level: (m['level'] ?? -100) as int,
        frequency: (m['frequency'] ?? 0) as int,
        width: (m['width'] ?? 20) as int,
      );

  int get channel => channelOf(frequency);
  String get band => bandOf(frequency);
  String get name => ssid.isEmpty ? '(hidden network)' : ssid;
}

class SpeedResult {
  final double download; // Mbps
  final double upload; // Mbps
  final double ping; // ms
  final double jitter; // ms
  final DateTime time;
  final String ssid;

  SpeedResult({required this.download, required this.upload, required this.ping, required this.jitter, required this.time, this.ssid = ''});

  Map<String, dynamic> toJson() => {
        'd': download,
        'u': upload,
        'p': ping,
        'j': jitter,
        't': time.millisecondsSinceEpoch,
        's': ssid,
      };

  factory SpeedResult.fromJson(Map<String, dynamic> m) => SpeedResult(
        download: (m['d'] as num).toDouble(),
        upload: (m['u'] as num).toDouble(),
        ping: (m['p'] as num).toDouble(),
        jitter: (m['j'] as num?)?.toDouble() ?? 0,
        time: DateTime.fromMillisecondsSinceEpoch(m['t'] as int),
        ssid: (m['s'] ?? '') as String,
      );
}

int channelOf(int f) {
  if (f == 2484) return 14;
  if (f >= 2412 && f < 2484) return (f - 2407) ~/ 5;
  if (f >= 5955 && f <= 7115) return (f - 5950) ~/ 5;
  if (f >= 4910 && f <= 5895) return (f - 5000) ~/ 5;
  return 0;
}

String bandOf(int f) {
  if (f >= 2400 && f < 2500) return '2.4 GHz';
  if (f >= 4900 && f < 5900) return '5 GHz';
  if (f >= 5925 && f < 7200) return '6 GHz';
  return '';
}

String standardName(int? s) {
  switch (s) {
    case 1:
      return 'Wi-Fi (a/b/g, old)';
    case 4:
      return 'Wi-Fi 4 (802.11n)';
    case 5:
      return 'Wi-Fi 5 (802.11ac)';
    case 6:
      return 'Wi-Fi 6 (802.11ax)';
    case 7:
      return 'WiGig (802.11ad)';
    case 8:
      return 'Wi-Fi 7 (802.11be)';
    default:
      return 'Unknown';
  }
}

class Signal {
  final String label;
  final int percent;
  final int grade; // 0 weak, 1 fair, 2 good, 3 excellent
  const Signal(this.label, this.percent, this.grade);
}

Signal signalOf(int rssi) {
  final pct = (((rssi + 90) / 60) * 100).round().clamp(0, 100).toInt();
  if (rssi >= -55) return Signal('Excellent', pct, 3);
  if (rssi >= -67) return Signal('Good', pct, 2);
  if (rssi >= -75) return Signal('Fair', pct, 1);
  return Signal('Weak', pct, 0);
}

double _weight(int level) => ((level + 95) / 45).clamp(0.1, 1.0).toDouble();

/// How busy each 2.4 GHz channel (1-13) is. Channels 4 apart or closer overlap.
Map<int, double> load24(List<Network> nets, {String excludeBssid = ''}) {
  final out = <int, double>{for (var c = 1; c <= 13; c++) c: 0};
  for (final n in nets) {
    if (n.band != '2.4 GHz' || (excludeBssid.isNotEmpty && n.bssid == excludeBssid)) continue;
    final ch = n.channel;
    for (var c = 1; c <= 13; c++) {
      final d = (c - ch).abs();
      if (d <= 4) out[c] = out[c]! + _weight(n.level) * (5 - d) / 5;
    }
  }
  return out;
}

/// The channels a router should use on 2.4 GHz: only these three don't overlap.
const nonOverlapping24 = [1, 6, 11];

/// Common 5 GHz channels that work on most routers and phones in India (no radar wait).
const common5 = [36, 40, 44, 48, 149, 153, 157, 161, 165];

/// How busy each 5 GHz channel is (networks on the same 20 MHz channel, or covering it with a wide channel).
Map<int, double> load5(List<Network> nets, {String excludeBssid = ''}) {
  final out = <int, double>{};
  for (final n in nets) {
    if (n.band != '5 GHz' || (excludeBssid.isNotEmpty && n.bssid == excludeBssid)) continue;
    final span = (n.width ~/ 20).clamp(1, 8).toInt();
    final base = _blockStart(n.channel, span);
    for (var i = 0; i < span; i++) {
      final c = base + i * 4;
      out[c] = (out[c] ?? 0) + _weight(n.level);
    }
  }
  return out;
}

int _blockStart(int ch, int span) {
  if (span <= 1) return ch;
  final idx = ch >= 149 ? (ch - 149) ~/ 4 : (ch - 36) ~/ 4;
  final start = (idx ~/ span) * span;
  return (ch >= 149 ? 149 : 36) + start * 4;
}

int best24(List<Network> nets, {String excludeBssid = ''}) {
  final l = load24(nets, excludeBssid: excludeBssid);
  return nonOverlapping24.reduce((a, b) => l[a]! <= l[b]! ? a : b);
}

int best5(List<Network> nets, {String excludeBssid = ''}) {
  final l = load5(nets, excludeBssid: excludeBssid);
  return common5.reduce((a, b) => (l[a] ?? 0) <= (l[b] ?? 0) ? a : b);
}

enum FixAction { none, wifiPanel, wifiSettings, routerPage, privateDns, location }

class Fix {
  final String title;
  final String detail;
  final int impact; // 3 high, 2 medium, 1 tip
  final FixAction action;
  final String actionLabel;
  const Fix(this.title, this.detail, this.impact, [this.action = FixAction.none, this.actionLabel = '']);
}

class Diagnosis {
  final int score;
  final String verdict;
  final List<Fix> fixes;
  const Diagnosis(this.score, this.verdict, this.fixes);
}

String _ms(double v) => '${v.round()} ms';
String mbps(double v) => v >= 100 ? v.round().toString() : v.toStringAsFixed(1);

Diagnosis diagnose({
  required WifiNow wifi,
  List<Network>? nearby,
  double? routerMs,
  double? internetMs,
  SpeedResult? speed,
  double? planMbps,
}) {
  final fixes = <Fix>[];

  if (!wifi.wifiEnabled || !wifi.connected) {
    fixes.add(const Fix('Connect to Wi-Fi', 'Your phone is not on Wi-Fi right now, so there is nothing to boost. Turn on Wi-Fi and join your network, then run the check again.', 3, FixAction.wifiPanel, 'Open Wi-Fi'));
    return Diagnosis(0, 'Not connected', fixes);
  }

  final sig = signalOf(wifi.rssi);
  final on24 = wifi.band == '2.4 GHz';
  final nets = nearby ?? const <Network>[];

  // 1. Signal strength
  if (sig.grade == 0) {
    fixes.add(Fix('Weak signal (${wifi.rssi} dBm)',
        'This is the biggest reason for slow Wi-Fi. Move closer to the router, or move the router: keep it high up, in the middle of the home, out of cupboards and away from the TV, microwave, mirrors and metal. Walls between you and the router cut speed a lot. If one room is always weak, a mesh system or Wi-Fi extender is the real fix.',
        3));
  } else if (sig.grade == 1) {
    fixes.add(Fix('Signal is only fair (${wifi.rssi} dBm)',
        'You are at the edge of good coverage. Moving a few metres closer, or putting the router higher and in the open, can double your speed. Use the Signal tab to walk around and find the best spot.',
        2));
  }

  // 2. Band
  final same5 = nets.where((n) => n.band != '2.4 GHz' && n.ssid.isNotEmpty && n.ssid == wifi.ssid && n.level >= -75).toList();
  final other5 = nets.where((n) => n.band != '2.4 GHz' && n.ssid.isNotEmpty && n.ssid != wifi.ssid && n.ssid.toLowerCase().startsWith(wifi.ssid.toLowerCase()) && wifi.ssid.isNotEmpty && n.level >= -75).toList();
  if (on24 && same5.isNotEmpty) {
    fixes.add(Fix('Switch to 5 GHz',
        'Your router also sends "${wifi.ssid}" on 5 GHz and it reaches you well (${same5.first.level} dBm), but your phone is stuck on slower 2.4 GHz. 5 GHz is usually 2 to 4 times faster near the router. Turn Wi-Fi off and on, or turn on "Band steering" / "Smart Connect" in the router settings.',
        3, FixAction.wifiPanel, 'Reconnect'));
  } else if (on24 && other5.isNotEmpty) {
    fixes.add(Fix('Join "${other5.first.ssid}" (5 GHz)',
        'Your router has a separate 5 GHz network, "${other5.first.ssid}", with a good signal here (${other5.first.level} dBm). It is usually much faster than the 2.4 GHz one you are on. Join it from Wi-Fi settings.',
        3, FixAction.wifiPanel, 'Open Wi-Fi'));
  } else if (on24 && nets.isNotEmpty) {
    fixes.add(const Fix('You are on 2.4 GHz',
        '2.4 GHz travels further through walls but is slower and more crowded. If your router supports 5 GHz (most dual-band routers do), turn it on in the router settings and use it in rooms near the router.',
        1, FixAction.routerPage, 'Router settings'));
  }

  // 3. Channel congestion
  if (nets.isNotEmpty && wifi.channel > 0) {
    if (on24) {
      final l = load24(nets, excludeBssid: wifi.bssid);
      final best = best24(nets, excludeBssid: wifi.bssid);
      final mine = l[wifi.channel] ?? 0;
      final diff = mine - (l[best] ?? 0);
      if (best != wifi.channel && diff >= 0.8) {
        fixes.add(Fix('Change router channel to $best',
            'Your router is on channel ${wifi.channel}, which is crowded by neighbours\' Wi-Fi. Channel $best is the quietest here. Open your router settings, go to Wireless / Wi-Fi, set the 2.4 GHz channel to $best (not "Auto") and save.',
            diff >= 2 ? 3 : 2, FixAction.routerPage, 'Router settings'));
      }
    } else if (wifi.band == '5 GHz') {
      final l = load5(nets, excludeBssid: wifi.bssid);
      final best = best5(nets, excludeBssid: wifi.bssid);
      final mine = l[wifi.channel] ?? 0;
      if (best != wifi.channel && mine - (l[best] ?? 0) >= 1.0) {
        fixes.add(Fix('Change 5 GHz channel to $best',
            'Other networks share your channel ${wifi.channel}. Channel $best is free here. In your router settings, set the 5 GHz channel to $best and save.',
            2, FixAction.routerPage, 'Router settings'));
      }
    }
  }

  // 4. Router vs internet delay
  final wifiIsFine = routerMs != null && routerMs < 15;
  if (routerMs != null && routerMs >= 30) {
    fixes.add(Fix('Slow link to your router (${_ms(routerMs)})',
        'Your phone takes too long to reach the router itself, so the problem is inside your home: distance, walls or interference. A good link is under 10 ms. Move closer, change the channel, or restart the router.',
        routerMs >= 80 ? 3 : 2));
  }
  if (wifiIsFine && internetMs != null && internetMs >= 80) {
    fixes.add(Fix('Your internet line is slow, not your Wi-Fi',
        'Your phone reaches the router quickly (${_ms(routerMs!)}) but the internet takes ${_ms(internetMs)}. Restart the modem/router (unplug for 30 seconds). If it stays slow, call your internet provider. A booster app or new router won\'t fix this.',
        2));
  }

  // 5. Speed vs plan and link
  if (speed != null) {
    final link = wifi.bestLink;
    if (planMbps != null && planMbps > 0) {
      final pct = (speed.download / planMbps * 100).round();
      if (pct < 50) {
        if (link > 0 && link < planMbps * 1.5) {
          fixes.add(Fix('Wi-Fi can\'t carry your full plan',
              'You pay for ${mbps(planMbps)} Mbps but got ${mbps(speed.download)} Mbps ($pct%). Your Wi-Fi link is only $link Mbps, so the Wi-Fi is the limit. Get closer, use 5 GHz, or connect a laptop or TV by cable.',
              3));
        } else {
          fixes.add(Fix('You get only $pct% of your plan',
              'You pay for ${mbps(planMbps)} Mbps but got ${mbps(speed.download)} Mbps, even though your Wi-Fi link ($link Mbps) is fast enough. Restart the router; check for other devices downloading or streaming; if it continues, raise a complaint with your provider.',
              2));
        }
      }
    }
    if (speed.ping >= 100) {
      fixes.add(Fix('High delay (${_ms(speed.ping)})',
          'Calls, games and video may lag. Pause big downloads and updates on other devices, restart the router, and try again.',
          2));
    }
    if (speed.jitter >= 30) {
      fixes.add(Fix('Unsteady connection (jitter ${_ms(speed.jitter)})',
          'The delay keeps jumping, which makes video calls break up. This usually means interference or a busy network. Change the router channel or move closer.',
          1));
    }
  }

  // 6. Old standard / slow link with good signal
  if (sig.grade >= 2 && wifi.bestLink > 0 && wifi.bestLink < 80) {
    final old = (wifi.standard != null && wifi.standard! <= 4);
    fixes.add(Fix('Slow Wi-Fi link (${wifi.bestLink} Mbps)',
        old
            ? 'You are on ${standardName(wifi.standard)}, an older Wi-Fi type. If your router is more than 5 years old, a Wi-Fi 5 or Wi-Fi 6 router will be much faster.'
            : 'Your signal is good but the link speed is low. Restart the router, and in its settings set the channel width to 40 MHz on 2.4 GHz or 80 MHz on 5 GHz.',
        2, FixAction.routerPage, 'Router settings'));
  }

  // 7. DNS
  if (wifi.privateDns == false) {
    fixes.add(const Fix('Use a fast DNS',
        'Websites open a little quicker with a fast, private DNS. In Settings, search "Private DNS", choose "Private DNS provider hostname" and enter one.one.one.one (Cloudflare) or dns.google.',
        1, FixAction.privateDns, 'Open settings'));
  }

  fixes.sort((a, b) => b.impact.compareTo(a.impact));
  var score = 100;
  for (final f in fixes) {
    score -= f.impact == 3 ? 22 : f.impact == 2 ? 11 : 3;
  }
  score = score.clamp(5, 100).toInt();
  if (score < 100 && fixes.any((f) => f.impact >= 2)) {
    fixes.add(const Fix('Restart your router',
        'Unplug the router for 30 seconds and plug it back in. It clears memory and often picks a better channel. Doing this once a week helps.',
        1));
  }

  final verdict = score >= 85
      ? 'Your Wi-Fi is in great shape'
      : score >= 65
          ? 'Good, with room to boost'
          : score >= 40
              ? 'Your Wi-Fi needs a boost'
              : 'Your Wi-Fi is struggling';
  return Diagnosis(score, verdict, fixes);
}
