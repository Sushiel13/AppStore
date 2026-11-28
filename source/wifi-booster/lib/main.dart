import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analysis.dart';
import 'native.dart';
import 'speedtest.dart';
import 'store.dart';

const bg = Color(0xFF070F24);
const card = Color(0xFF101B3A);
const line = Color(0xFF1E2B52);
const cyan = Color(0xFF22D3EE);
const green = Color(0xFF34D399);
const amber = Color(0xFFFBBF24);
const red = Color(0xFFF87171);
const muted = Color(0xFF94A3C8);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  runApp(const BoosterApp());
}

class BoosterApp extends StatelessWidget {
  const BoosterApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: cyan, brightness: Brightness.dark).copyWith(
      primary: cyan,
      secondary: green,
      surface: card,
    );
    return MaterialApp(
      title: 'WiFi Booster',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: bg,
        cardTheme: const CardThemeData(color: card, elevation: 0, margin: EdgeInsets.zero),
        appBarTheme: const AppBarTheme(backgroundColor: bg, elevation: 0, centerTitle: false),
        navigationBarTheme: const NavigationBarThemeData(backgroundColor: Color(0xFF0B1531), indicatorColor: Color(0x3322D3EE)),
      ),
      home: const Home(),
    );
  }
}

Color gradeColor(int g) => [red, amber, cyan, green][g.clamp(0, 3).toInt()];

Color scoreColor(int s) => s >= 85 ? green : s >= 65 ? cyan : s >= 40 ? amber : red;

String friendlyError(Object e) {
  if (e is PlatformException) return e.message ?? e.code;
  if (e is Cancelled) return 'Test stopped.';
  final s = e.toString();
  if (s.contains('Failed host lookup') || s.contains('SocketException')) return 'No internet connection. Check that Wi-Fi is on and connected.';
  return s;
}

Future<void> runFixAction(BuildContext context, FixAction a, String gateway) async {
  try {
    switch (a) {
      case FixAction.wifiPanel:
        await Native.openWifiPanel();
      case FixAction.wifiSettings:
        await Native.openSettings('android.settings.WIFI_SETTINGS');
      case FixAction.routerPage:
        if (gateway.isEmpty) {
          await Native.openUrl('http://192.168.1.1');
        } else {
          await Native.openUrl('http://$gateway');
        }
      case FixAction.privateDns:
        await Native.openSettings('android.settings.WIRELESS_SETTINGS');
      case FixAction.location:
        await Native.requestLocation();
      case FixAction.none:
        break;
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}

// ---------------------------------------------------------------- Home

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  int tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _intro());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) Perm.refresh();
  }

  Future<void> _intro() async {
    await Perm.refresh();
    if (Store.seenIntro() || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.wifi_tethering, color: cyan, size: 40),
            const SizedBox(height: 12),
            const Text('Make your Wi-Fi faster, for real', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            const Text(
              'Tap Boost and the app checks your signal, the channels your neighbours use, the delay to your router and your real internet speed. Then it tells you exactly what is slowing you down and how to fix it.\n\n'
              'Android needs the Location permission for any app to see Wi-Fi names and nearby networks. Your location is never stored or sent anywhere.',
              style: TextStyle(color: muted, height: 1.5),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  await Store.setSeenIntro();
                  await Native.requestLocation();
                  await Perm.refresh();
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Padding(padding: EdgeInsets.all(12), child: Text('Allow and start')),
              ),
            ),
            TextButton(
              onPressed: () async {
                await Store.setSeenIntro();
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: tab,
          children: [
            const BoostPage(),
            const SpeedPage(),
            SignalPage(active: tab == 2),
            const NearbyPage(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.rocket_launch_outlined), selectedIcon: Icon(Icons.rocket_launch), label: 'Boost'),
          NavigationDestination(icon: Icon(Icons.speed_outlined), selectedIcon: Icon(Icons.speed), label: 'Speed'),
          NavigationDestination(icon: Icon(Icons.network_wifi_outlined), selectedIcon: Icon(Icons.network_wifi), label: 'Signal'),
          NavigationDestination(icon: Icon(Icons.wifi_find_outlined), selectedIcon: Icon(Icons.wifi_find), label: 'Nearby'),
        ],
      ),
    );
  }
}

/// Location permission state shared by all pages.
class Perm {
  static final granted = ValueNotifier<bool>(false);
  static final serviceOn = ValueNotifier<bool>(true);

  static Future<void> refresh() async {
    try {
      granted.value = await Native.hasLocation();
      serviceOn.value = await Native.locationOn();
    } catch (_) {}
  }
}

class PermissionCard extends StatelessWidget {
  const PermissionCard({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Perm.granted,
      builder: (context, granted, _) => ValueListenableBuilder<bool>(
        valueListenable: Perm.serviceOn,
        builder: (context, on, _) {
          if (granted && on) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0x22FBBF24), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0x55FBBF24))),
              child: Row(
                children: [
                  const Icon(Icons.location_on_outlined, color: amber),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      granted
                          ? 'Turn on Location so the app can see your Wi-Fi name and nearby networks. Nothing about your location is saved.'
                          : 'Allow Location so the app can see your Wi-Fi name and nearby networks. Android requires this; nothing is saved.',
                      style: const TextStyle(fontSize: 13, height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () async {
                      if (!granted) {
                        final ok = await Native.requestLocation();
                        if (!ok) await Native.appSettings();
                      } else {
                        await Native.openSettings('android.settings.LOCATION_SOURCE_SETTINGS');
                      }
                      await Perm.refresh();
                    },
                    child: Text(granted ? 'Turn on' : 'Allow'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Boost

enum BoostStep { wifi, scan, router, speed }

class BoostPage extends StatefulWidget {
  const BoostPage({super.key});

  @override
  State<BoostPage> createState() => _BoostPageState();
}

class _BoostPageState extends State<BoostPage> with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
  WifiNow? wifi;
  bool running = false;
  BoostStep? step;
  double liveMbps = 0;
  String phase = '';
  Diagnosis? result;
  SpeedResult? speed;
  double? routerMs;
  String? error;
  SpeedTest? test;

  @override
  void initState() {
    super.initState();
    _loadWifi();
    Perm.granted.addListener(_loadWifi);
  }

  @override
  void dispose() {
    Perm.granted.removeListener(_loadWifi);
    pulse.dispose();
    test?.cancel();
    super.dispose();
  }

  Future<void> _loadWifi() async {
    try {
      final w = await Native.wifiInfo();
      if (mounted) setState(() => wifi = w);
    } catch (_) {}
  }

  Future<void> boost() async {
    HapticFeedback.mediumImpact();
    setState(() {
      running = true;
      error = null;
      result = null;
      step = BoostStep.wifi;
      liveMbps = 0;
    });
    try {
      final w = await Native.wifiInfo();
      setState(() => wifi = w);
      if (!w.connected) {
        setState(() => result = diagnose(wifi: w));
        return;
      }

      setState(() => step = BoostStep.scan);
      List<Network>? nets;
      if (await Native.hasLocation()) {
        try {
          nets = await Native.scan();
        } catch (_) {}
      }

      setState(() => step = BoostStep.router);
      final rMs = await SpeedTest.routerPing(w.gateway);
      setState(() => routerMs = rMs);

      setState(() => step = BoostStep.speed);
      final t = test = SpeedTest();
      setState(() => phase = 'Ping');
      final p = await t.ping();
      setState(() => phase = 'Download');
      final d = await t.download(onProgress: (m, _) {
        if (mounted) setState(() => liveMbps = m);
      });
      setState(() {
        phase = 'Upload';
        liveMbps = 0;
      });
      final u = await t.upload(onProgress: (m, _) {
        if (mounted) setState(() => liveMbps = m);
      });
      final s = SpeedResult(download: d, upload: u, ping: p.ping, jitter: p.jitter, time: DateTime.now(), ssid: w.ssid);
      await Store.addResult(s);
      SpeedPage.changed.value++;

      final dx = diagnose(wifi: w, nearby: nets, routerMs: rMs, internetMs: p.ping, speed: s, planMbps: Store.plan());
      if (!mounted) return;
      setState(() {
        speed = s;
        result = dx;
      });
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          running = false;
          step = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Row(
          children: [
            Icon(Icons.wifi_tethering, color: cyan),
            SizedBox(width: 10),
            Text('WiFi Speed Booster', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 16),
        const PermissionCard(),
        _networkCard(),
        const SizedBox(height: 28),
        Center(child: running ? _progress() : (result == null ? _boostButton() : _scoreRing(result!))),
        const SizedBox(height: 24),
        if (error != null)
          Text(error!, style: const TextStyle(color: red), textAlign: TextAlign.center),
        if (result != null && !running) ..._results(result!),
        if (result == null && !running && error == null)
          const Text(
            'Boost checks your signal, band, channel crowding, router delay and real internet speed, then shows the fixes that will make the biggest difference.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, height: 1.5),
          ),
      ],
    );
  }

  Widget _networkCard() {
    final w = wifi ?? const WifiNow(connected: false);
    final connected = w.connected;
    final sig = connected ? signalOf(w.rssi) : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: (sig != null ? gradeColor(sig.grade) : muted).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(connected ? Icons.wifi : Icons.wifi_off, color: sig != null ? gradeColor(sig.grade) : muted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    !connected ? 'Not on Wi-Fi' : (w.ssid.isEmpty ? 'Connected to Wi-Fi' : w.ssid),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    !connected
                        ? 'Connect to your Wi-Fi to boost it'
                        : '${sig!.label} signal · ${w.band.isEmpty ? '' : '${w.band} · '}${w.bestLink > 0 ? '${w.bestLink} Mbps link' : ''}',
                    style: const TextStyle(color: muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            if (!connected)
              TextButton(onPressed: () => Native.openWifiPanel(), child: const Text('Connect'))
            else
              Text('${sig!.percent}%', style: TextStyle(color: gradeColor(sig.grade), fontWeight: FontWeight.w800, fontSize: 18)),
          ],
        ),
      ),
    );
  }

  Widget _boostButton() {
    return GestureDetector(
      onTap: boost,
      child: AnimatedBuilder(
        animation: pulse,
        builder: (context, child) {
          final t = pulse.value;
          return SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final o in [0.0, 0.5])
                  Opacity(
                    opacity: (1 - ((t + o) % 1)).clamp(0.0, 1.0).toDouble() * 0.5,
                    child: Container(
                      width: 170 + 70 * ((t + o) % 1),
                      height: 170 + 70 * ((t + o) % 1),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cyan, width: 2)),
                    ),
                  ),
                child!,
              ],
            ),
          );
        },
        child: Container(
          width: 170,
          height: 170,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: Color(0x6622D3EE), blurRadius: 40, spreadRadius: 4)],
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.rocket_launch, size: 44, color: Colors.white),
              SizedBox(height: 6),
              Text('BOOST', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: 3, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _progress() {
    const labels = {
      BoostStep.wifi: 'Reading your Wi-Fi',
      BoostStep.scan: 'Scanning nearby networks',
      BoostStep.router: 'Checking your router',
      BoostStep.speed: 'Testing real speed',
    };
    final cur = step?.index ?? 0;
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const SizedBox(width: 200, height: 200, child: CircularProgressIndicator(strokeWidth: 6, color: cyan, backgroundColor: line)),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (step == BoostStep.speed && liveMbps > 0) ...[
                    Text(mbps(liveMbps), style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
                    Text('Mbps · $phase', style: const TextStyle(color: muted)),
                  ] else
                    const Icon(Icons.wifi_find, size: 48, color: cyan),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        for (final s in BoostStep.values)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  s.index < cur ? Icons.check_circle : (s.index == cur ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  size: 18,
                  color: s.index <= cur ? cyan : muted,
                ),
                const SizedBox(width: 8),
                SizedBox(width: 200, child: Text(labels[s]!, style: TextStyle(color: s.index <= cur ? Colors.white : muted))),
              ],
            ),
          ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => test?.cancel(),
          child: const Text('Stop'),
        ),
      ],
    );
  }

  Widget _scoreRing(Diagnosis d) {
    return Column(
      children: [
        SizedBox(
          width: 200,
          height: 200,
          child: CustomPaint(
            painter: RingPainter(d.score / 100, scoreColor(d.score)),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${d.score}', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: scoreColor(d.score))),
                  const Text('Wi-Fi score', style: TextStyle(color: muted)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(d.verdict, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: boost, icon: const Icon(Icons.refresh), label: const Text('Boost again')),
      ],
    );
  }

  List<Widget> _results(Diagnosis d) {
    final s = speed;
    return [
      if (s != null)
        Row(
          children: [
            Expanded(child: Stat('Download', mbps(s.download), 'Mbps', Icons.arrow_downward)),
            const SizedBox(width: 8),
            Expanded(child: Stat('Upload', mbps(s.upload), 'Mbps', Icons.arrow_upward)),
            const SizedBox(width: 8),
            Expanded(child: Stat('Ping', s.ping.round().toString(), 'ms', Icons.timer_outlined)),
            const SizedBox(width: 8),
            Expanded(child: Stat('Router', routerMs == null ? '–' : routerMs!.round().toString(), 'ms', Icons.router_outlined)),
          ],
        ),
      const SizedBox(height: 24),
      Text(d.fixes.isEmpty ? 'Nothing to fix' : 'Your boost plan', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      Text(
        d.fixes.isEmpty ? 'Your signal, channel and speed all look good. Enjoy!' : 'Do these in order. The top ones make the biggest difference.',
        style: const TextStyle(color: muted),
      ),
      const SizedBox(height: 12),
      for (final f in d.fixes) Padding(padding: const EdgeInsets.only(bottom: 10), child: FixCard(f, gateway: wifi?.gateway ?? '')),
      if (Store.plan() == null && s != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextButton.icon(
            onPressed: () async {
              await askPlan(context);
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.tune),
            label: const Text('Add your internet plan speed for a better check'),
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        'No app can make the radio in your phone or router faster by itself. These fixes are what actually speed up Wi-Fi.',
        textAlign: TextAlign.center,
        style: TextStyle(color: muted, fontSize: 12, height: 1.4),
      ),
    ];
  }
}

class FixCard extends StatelessWidget {
  final Fix fix;
  final String gateway;
  const FixCard(this.fix, {super.key, required this.gateway});

  @override
  Widget build(BuildContext context) {
    final c = fix.impact == 3 ? red : fix.impact == 2 ? amber : cyan;
    final label = fix.impact == 3 ? 'BIG BOOST' : fix.impact == 2 ? 'BOOST' : 'TIP';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(label, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(fix.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              ],
            ),
            const SizedBox(height: 8),
            Text(fix.detail, style: const TextStyle(color: muted, height: 1.45, fontSize: 13.5)),
            if (fix.action != FixAction.none) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  onPressed: () => runFixAction(context, fix.action, gateway),
                  child: Text(fix.actionLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class Stat extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  const Stat(this.label, this.value, this.unit, this.icon, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Icon(icon, size: 16, color: cyan),
          const SizedBox(height: 4),
          FittedBox(child: Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          Text('$label · $unit', style: const TextStyle(color: muted, fontSize: 10.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  final double value;
  final Color color;
  RingPainter(this.value, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(10, 10, size.width - 20, size.height - 20);
    final base = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, math.pi * 0.75, math.pi * 1.5, false, base);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, math.pi * 0.75, math.pi * 1.5 * value.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(RingPainter old) => old.value != value || old.color != color;
}

Future<void> askPlan(BuildContext context) async {
  final ctl = TextEditingController(text: Store.plan()?.round().toString() ?? '');
  final v = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: card,
      title: const Text('Your internet plan'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Plan speed', suffixText: 'Mbps', hintText: 'e.g. 100'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Save')),
      ],
    ),
  );
  if (v != null) await Store.setPlan(double.tryParse(v.trim()));
}

// ---------------------------------------------------------------- Speed

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key});
  static final changed = ValueNotifier<int>(0);

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  bool running = false;
  String phase = '';
  double live = 0;
  double? ping, jit, down, up;
  String? error;
  SpeedTest? test;

  @override
  void initState() {
    super.initState();
    SpeedPage.changed.addListener(_refresh);
  }

  @override
  void dispose() {
    SpeedPage.changed.removeListener(_refresh);
    test?.cancel();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> run() async {
    setState(() {
      running = true;
      error = null;
      ping = jit = down = up = null;
      live = 0;
      phase = 'Ping';
    });
    final t = test = SpeedTest();
    try {
      final p = await t.ping();
      setState(() {
        ping = p.ping;
        jit = p.jitter;
        phase = 'Download';
      });
      final d = await t.download(onProgress: (m, _) {
        if (mounted) setState(() => live = m);
      });
      setState(() {
        down = d;
        phase = 'Upload';
        live = 0;
      });
      final u = await t.upload(onProgress: (m, _) {
        if (mounted) setState(() => live = m);
      });
      setState(() => up = u);
      String ssid = '';
      try {
        ssid = (await Native.wifiInfo()).ssid;
      } catch (_) {}
      await Store.addResult(SpeedResult(download: d, upload: u, ping: p.ping, jitter: p.jitter, time: DateTime.now(), ssid: ssid));
      HapticFeedback.heavyImpact();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() {
          running = false;
          phase = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hist = Store.history();
    final plan = Store.plan();
    final shown = running ? live : (down ?? 0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Row(
          children: [
            const Expanded(child: Text('Speed test', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            TextButton.icon(
              onPressed: () async {
                await askPlan(context);
                setState(() {});
              },
              icon: const Icon(Icons.tune, size: 18),
              label: Text(plan == null ? 'Set plan' : 'Plan ${plan.round()} Mbps'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 260,
            height: 240,
            child: CustomPaint(
              painter: GaugePainter(shown),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 20),
                    Text(shown > 0 ? mbps(shown) : '–', style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900)),
                    Text(running ? 'Mbps · $phase' : 'Mbps download', style: const TextStyle(color: muted)),
                    if (!running && down != null && plan != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${(down! / plan * 100).round()}% of your plan', style: TextStyle(color: down! / plan >= 0.7 ? green : amber, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Stat('Download', down == null ? '–' : mbps(down!), 'Mbps', Icons.arrow_downward)),
            const SizedBox(width: 8),
            Expanded(child: Stat('Upload', up == null ? '–' : mbps(up!), 'Mbps', Icons.arrow_upward)),
            const SizedBox(width: 8),
            Expanded(child: Stat('Ping', ping == null ? '–' : ping!.round().toString(), 'ms', Icons.timer_outlined)),
            const SizedBox(width: 8),
            Expanded(child: Stat('Jitter', jit == null ? '–' : jit!.round().toString(), 'ms', Icons.show_chart)),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: running
              ? OutlinedButton(onPressed: () => test?.cancel(), child: const Text('Stop'))
              : FilledButton.icon(onPressed: run, icon: const Icon(Icons.play_arrow), label: Text(down == null ? 'Start test' : 'Test again')),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: red), textAlign: TextAlign.center)),
        const SizedBox(height: 8),
        const Text('Uses Cloudflare\'s public speed test servers. A test uses about 30–150 MB of data.', textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 28),
        if (hist.isNotEmpty) ...[
          Row(
            children: [
              const Expanded(child: Text('History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
              TextButton(
                onPressed: () async {
                  await Store.clearHistory();
                  setState(() {});
                },
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final h in hist.take(20))
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(h.ssid.isEmpty ? 'Wi-Fi' : h.ssid, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                        Text(_when(h.time), style: const TextStyle(color: muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  Text('↓ ${mbps(h.download)}  ↑ ${mbps(h.upload)}  ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${h.ping.round()} ms', style: const TextStyle(color: muted, fontSize: 12)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  String _when(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]}, ${two(t.hour)}:${two(t.minute)}';
  }
}

class GaugePainter extends CustomPainter {
  final double value;
  GaugePainter(this.value);

  static const marks = [0, 5, 10, 25, 50, 100, 250, 500, 1000];

  double frac(double v) => (math.log(1 + v) / math.log(1001)).clamp(0.0, 1.0).toDouble();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2 + 10);
    final radius = math.min(size.width, size.height) / 2 - 16;
    final r = Rect.fromCircle(center: c, radius: radius);
    const start = math.pi * 0.75;
    const sweep = math.pi * 1.5;
    canvas.drawArc(r, start, sweep, false, Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round);
    final f = frac(value);
    if (f > 0) {
      canvas.drawArc(r, start, sweep * f, false, Paint()
        ..shader = const SweepGradient(colors: [cyan, Color(0xFF3B82F6), green], startAngle: 0, endAngle: math.pi * 2).createShader(r)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round);
    }
    for (final m in marks) {
      final a = start + sweep * frac(m.toDouble());
      final p = c + Offset(math.cos(a), math.sin(a)) * (radius - 26);
      final tp = TextPainter(
        text: TextSpan(text: '$m', style: const TextStyle(color: muted, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(GaugePainter old) => old.value != value;
}

// ---------------------------------------------------------------- Signal

class SignalPage extends StatefulWidget {
  final bool active;
  const SignalPage({super.key, required this.active});

  @override
  State<SignalPage> createState() => _SignalPageState();
}

class _SignalPageState extends State<SignalPage> {
  Timer? timer;
  WifiNow? w;
  final readings = <int>[];

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(SignalPage old) {
    super.didUpdateWidget(old);
    if (widget.active && timer == null) _start();
    if (!widget.active) _stop();
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  void _start() {
    _tick();
    timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _stop() {
    timer?.cancel();
    timer = null;
  }

  Future<void> _tick() async {
    try {
      final now = await Native.wifiInfo();
      if (!mounted) return;
      setState(() {
        w = now;
        if (now.connected) {
          readings.add(now.rssi);
          if (readings.length > 60) readings.removeAt(0);
        }
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final now = w ?? const WifiNow(connected: false, wifiEnabled: false);
    final connected = now.connected;
    final sig = connected ? signalOf(now.rssi) : null;
    final col = sig == null ? muted : gradeColor(sig.grade);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text('Signal finder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Walk around your home. Where the number is highest is the best spot for your phone, laptop or TV, and shows where the router reaches poorly.', style: TextStyle(color: muted, height: 1.4)),
        const SizedBox(height: 16),
        const PermissionCard(),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Text(connected ? (now.ssid.isEmpty ? 'Your Wi-Fi' : now.ssid) : 'Not on Wi-Fi', style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text(sig == null ? '–' : '${sig.percent}%', style: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, color: col)),
                Text(sig == null ? 'Connect to Wi-Fi' : '${sig.label} · ${now.rssi} dBm', style: TextStyle(color: col, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: (sig?.percent ?? 0) / 100, minHeight: 12, color: col, backgroundColor: line),
                ),
                const SizedBox(height: 16),
                SizedBox(height: 80, width: double.infinity, child: CustomPaint(painter: SparkPainter(List.of(readings)))),
                const SizedBox(height: 4),
                const Text('Last 60 seconds', style: TextStyle(color: muted, fontSize: 11)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (connected)
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  _row('Band', now.band.isEmpty ? '–' : now.band),
                  _row('Channel', now.channel == 0 ? '–' : '${now.channel}'),
                  _row('Link speed', now.bestLink > 0 ? '${now.bestLink} Mbps' : '–'),
                  if (now.maxTx != null && now.maxTx! > 0) _row('Best possible link', '${now.maxTx} Mbps'),
                  _row('Wi-Fi type', standardName(now.standard)),
                  _row('Phone IP', now.ip.isEmpty ? '–' : now.ip),
                  _row('Router', now.gateway.isEmpty ? '–' : now.gateway),
                  _row('DNS', now.privateDns == true ? 'Private: ${now.privateDnsName.isEmpty ? 'automatic' : now.privateDnsName}' : (now.dns.isEmpty ? '–' : now.dns.take(2).join(', '))),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text('What the numbers mean', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        _legend(green, 'Excellent: -55 dBm or better', 'Full speed. Great for 4K video and gaming.'),
        _legend(cyan, 'Good: -56 to -67 dBm', 'Fast and reliable for calls and HD video.'),
        _legend(amber, 'Fair: -68 to -75 dBm', 'Works, but speed drops. Move a little closer.'),
        _legend(red, 'Weak: below -75 dBm', 'Slow and drops out. Move closer or add an extender.'),
      ],
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: muted))),
            Flexible(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );

  Widget _legend(Color c, String t, String d) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 5), decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: '$t\n', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: d, style: const TextStyle(color: muted)),
              ])),
            ),
          ],
        ),
      );
}

class SparkPainter extends CustomPainter {
  final List<int> v;
  SparkPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final level in [-55, -67, -75]) {
      final y = _y(level, size);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (v.length < 2) return;
    final path = Path();
    for (var i = 0; i < v.length; i++) {
      final x = size.width * i / 59;
      final y = _y(v[i], size);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, Paint()
      ..color = gradeColor(signalOf(v.last).grade)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round);
  }

  double _y(int rssi, Size s) => s.height * (1 - ((rssi + 95) / 65).clamp(0.0, 1.0));

  @override
  bool shouldRepaint(SparkPainter old) => true;
}

// ---------------------------------------------------------------- Nearby

class NearbyPage extends StatefulWidget {
  const NearbyPage({super.key});

  @override
  State<NearbyPage> createState() => _NearbyPageState();
}

class _NearbyPageState extends State<NearbyPage> {
  List<Network>? nets;
  WifiNow? me;
  bool scanning = false;
  String? error;
  String band = '2.4 GHz';

  Future<void> scan() async {
    setState(() {
      scanning = true;
      error = null;
    });
    try {
      if (!await Native.hasLocation()) {
        final ok = await Native.requestLocation();
        await Perm.refresh();
        if (!ok) throw PlatformException(code: 'permission', message: 'Allow Location to see nearby networks.');
      }
      final w = await Native.wifiInfo();
      final n = await Native.scan();
      n.sort((a, b) => b.level.compareTo(a.level));
      if (!mounted) return;
      setState(() {
        me = w;
        nets = n;
        if (w.connected && w.band.isNotEmpty && w.band != '6 GHz') band = w.band;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = nets;
    final mine = me;
    final shownNets = list?.where((n) => n.band == band).toList() ?? const <Network>[];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text('Nearby networks', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text('Neighbours on the same channel slow each other down. Find the quietest channel and set it on your router.', style: TextStyle(color: muted, height: 1.4)),
        const SizedBox(height: 16),
        const PermissionCard(),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: scanning ? null : scan,
            icon: scanning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.wifi_find),
            label: Text(scanning ? 'Scanning…' : (list == null ? 'Scan now' : 'Scan again')),
          ),
        ),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: red))),
        if (list != null) ...[
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '2.4 GHz', label: Text('2.4 GHz')),
              ButtonSegment(value: '5 GHz', label: Text('5 GHz')),
            ],
            selected: {band},
            onSelectionChanged: (s) => setState(() => band = s.first),
          ),
          const SizedBox(height: 16),
          _recommendation(list, mine),
          const SizedBox(height: 16),
          if (band == '2.4 GHz')
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Channel crowding', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 140,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: ChannelPainter(
                          load24(list, excludeBssid: mine?.bssid ?? ''),
                          mine != null && mine.band == '2.4 GHz' ? mine.channel : 0,
                          best24(list, excludeBssid: mine?.bssid ?? ''),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Row(
                      children: [
                        _Dot(cyan, 'Your channel'),
                        SizedBox(width: 16),
                        _Dot(green, 'Best channel'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text('${shownNets.length} networks on $band', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          for (final n in shownNets) _netTile(n, mine),
        ],
      ],
    );
  }

  Widget _recommendation(List<Network> list, WifiNow? mine) {
    final ex = mine?.bssid ?? '';
    final is24 = band == '2.4 GHz';
    final best = is24 ? best24(list, excludeBssid: ex) : best5(list, excludeBssid: ex);
    final myCh = mine != null && mine.connected && mine.band == band ? mine.channel : 0;
    final good = myCh == best || (is24 ? (load24(list, excludeBssid: ex)[myCh] ?? 99) - (load24(list, excludeBssid: ex)[best] ?? 0) < 0.8 : (load5(list, excludeBssid: ex)[myCh] ?? 0) - (load5(list, excludeBssid: ex)[best] ?? 0) < 1.0);
    final text = myCh == 0
        ? 'The quietest $band channel here is $best.'
        : good
            ? 'Your router\'s channel $myCh is a good choice. No change needed.'
            : 'Your router is on channel $myCh. Switch it to channel $best for less interference.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (myCh != 0 && good ? green : cyan).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(myCh != 0 && good ? Icons.check_circle : Icons.tips_and_updates, color: myCh != 0 && good ? green : cyan),
              const SizedBox(width: 10),
              Expanded(child: Text('Best channel: $best', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(height: 1.4)),
          if (myCh != 0 && !good) ...[
            const SizedBox(height: 6),
            const Text('Open your router settings → Wireless / Wi-Fi → Channel, choose it (not Auto) and save. The router login is usually printed on its sticker.', style: TextStyle(color: muted, fontSize: 13, height: 1.4)),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () => runFixAction(context, FixAction.routerPage, mine?.gateway ?? ''),
              child: const Text('Open router settings'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _netTile(Network n, WifiNow? mine) {
    final sig = signalOf(n.level);
    final isMine = mine != null && mine.bssid.isNotEmpty && n.bssid == mine.bssid;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isMine ? cyan : Colors.transparent),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi, color: gradeColor(sig.grade), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isMine ? '${n.name} (you)' : n.name, style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                Text('Channel ${n.channel} · ${n.width} MHz', style: const TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
          Text('${n.level} dBm', style: TextStyle(color: gradeColor(sig.grade), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  final Color c;
  final String t;
  const _Dot(this.c, this.t);

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(t, style: const TextStyle(color: muted, fontSize: 12)),
        ],
      );
}

class ChannelPainter extends CustomPainter {
  final Map<int, double> load;
  final int mine;
  final int best;
  ChannelPainter(this.load, this.mine, this.best);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(1.0, load.values.fold<double>(0, math.max));
    const n = 13;
    final slot = size.width / n;
    final chartH = size.height - 18;
    for (var c = 1; c <= n; c++) {
      final v = load[c] ?? 0;
      final h = math.max(3.0, chartH * v / maxV);
      final x = (c - 1) * slot + slot * 0.18;
      final color = c == mine ? cyan : c == best ? green : const Color(0xFF3A4A7A);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, chartH - h, slot * 0.64, h), const Radius.circular(4)),
        Paint()..color = color,
      );
      final tp = TextPainter(
        text: TextSpan(text: '$c', style: TextStyle(color: c == mine || c == best ? Colors.white : muted, fontSize: 10, fontWeight: c == best ? FontWeight.w800 : FontWeight.w400)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + slot * 0.32 - tp.width / 2, chartH + 4));
    }
  }

  @override
  bool shouldRepaint(ChannelPainter old) => true;
}
