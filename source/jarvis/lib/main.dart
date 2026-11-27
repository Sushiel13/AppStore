import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'brain.dart';
import 'phone.dart';
import 'settings.dart';
import 'store.dart';

const kBg = Color(0xFF070B14);
const kCard = Color(0xFF111827);
const kAccent = Color(0xFF22D3EE);
const kAccent2 = Color(0xFF6366F1);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  try {
    await Reminders.init();
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kBg,
  ));
  runApp(const JarvisApp());
}

class JarvisApp extends StatelessWidget {
  const JarvisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kAccent,
          brightness: Brightness.dark,
          surface: kBg,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum Mode { idle, listening, thinking, speaking }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  final _brain = Brain();
  final _speech = SpeechToText();
  final _tts = FlutterTts();
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  List<ChatMsg> _msgs = [];
  Mode _mode = Mode.idle;
  bool _speechReady = false;
  String _heard = '';
  double _level = 0;

  static const _suggestions = [
    'Set an alarm for 6:30 am',
    'Remind me to drink water in 30 minutes',
    'Torch on',
    'Weather',
    'Open WhatsApp',
    'Add milk to my shopping list',
    'Set a timer for 10 minutes',
    'Battery',
    'Tell me a joke',
    'What can you do?',
  ];

  @override
  void initState() {
    super.initState();
    _msgs = Store.history;
    _setupTts();
    if (Store.autoListen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _listen());
    }
  }

  Future<void> _setupTts() async {
    try {
      await _tts.setLanguage(Store.speechLocale.replaceAll('_', '-'));
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      _tts.setCompletionHandler(() {
        if (mounted && _mode == Mode.speaking) setState(() => _mode = Mode.idle);
      });
      _tts.setCancelHandler(() {
        if (mounted && _mode == Mode.speaking) setState(() => _mode = Mode.idle);
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _pulse.dispose();
    _input.dispose();
    _scroll.dispose();
    _speech.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<bool> _initSpeech() async {
    if (_speechReady) return true;
    _speechReady = await _speech.initialize(
      onStatus: (s) {
        if ((s == 'done' || s == 'notListening') && _mode == Mode.listening && mounted) {
          final heard = _heard.trim();
          setState(() => _mode = Mode.idle);
          if (heard.isNotEmpty) _send(heard);
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _mode = Mode.idle);
        if (e.errorMsg != 'error_no_match' && e.errorMsg != 'error_speech_timeout') {
          _toast("Couldn't hear you (${e.errorMsg}).");
        }
      },
    );
    if (!_speechReady) _toast('Speech recognition is not available. Allow the microphone, or type instead.');
    return _speechReady;
  }

  Future<void> _listen() async {
    if (_mode == Mode.listening) {
      await _speech.stop();
      return;
    }
    await _tts.stop();
    if (!await _initSpeech()) return;
    HapticFeedback.lightImpact();
    setState(() {
      _heard = '';
      _level = 0;
      _mode = Mode.listening;
    });
    await _speech.listen(
      onResult: (SpeechRecognitionResult r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
      },
      onSoundLevelChange: (l) {
        if (mounted) setState(() => _level = ((l + 2) / 12).clamp(0.0, 1.0));
      },
      localeId: Store.speechLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  Future<void> _send(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    _input.clear();
    setState(() {
      _msgs.add(ChatMsg(true, q));
      _heard = '';
      _mode = Mode.thinking;
    });
    _toBottom();
    final reply = await _brain.handle(q, List.of(_msgs));
    if (!mounted) return;
    setState(() {
      _msgs.add(ChatMsg(false, reply));
      _mode = Mode.idle;
    });
    Store.history = _msgs;
    _toBottom();
    if (Store.speak) {
      setState(() => _mode = Mode.speaking);
      final spoken = reply.split('\n').first.replaceAll('•', '').replaceAll(RegExp(r'[“”"]'), '');
      try {
        await _tts.speak(reply.contains('\n') && reply.length > 200 ? spoken : reply.replaceAll('•', ''));
      } catch (_) {
        if (mounted) setState(() => _mode = Mode.idle);
      }
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _toast(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));
  }

  String get _status => switch (_mode) {
        Mode.listening => _heard.isEmpty ? 'Listening…' : _heard,
        Mode.thinking => 'Working on it…',
        Mode.speaking => 'Speaking… tap to stop',
        Mode.idle => _msgs.isEmpty ? 'Tap the orb and speak' : 'Tap the orb to talk',
      };

  @override
  Widget build(BuildContext context) {
    final empty = _msgs.isEmpty;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.6),
            radius: 1.3,
            colors: [Color(0xFF0E1A33), kBg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _topBar(),
              Expanded(
                child: empty
                    ? _welcome()
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                        itemCount: _msgs.length,
                        itemBuilder: (_, i) => _bubble(_msgs[i]),
                      ),
              ),
              _orbArea(compact: !empty),
              _chips(),
              _inputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 6, 0),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (r) => const LinearGradient(colors: [kAccent, kAccent2]).createShader(r),
            child: const Text('JARVIS',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: 4, color: Colors.white)),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'What can I say?',
            icon: const Icon(Icons.help_outline),
            onPressed: () => _send('What can you do?'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              await _setupTts();
              setState(() => _msgs = Store.history);
            },
          ),
        ],
      ),
    );
  }

  Widget _welcome() {
    final h = DateTime.now().hour;
    final hello = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    final name = Store.userName.isEmpty ? '' : ', ${Store.userName}';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$hello$name', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('How can I help today?',
                style: TextStyle(fontSize: 16, color: Colors.white.withValues(alpha: 0.6))),
          ],
        ),
      ),
    );
  }

  Widget _bubble(ChatMsg m) {
    return Align(
      alignment: m.me ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: m.text));
          _toast('Copied');
        },
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: m.me ? const LinearGradient(colors: [kAccent2, Color(0xFF4F46E5)]) : null,
            color: m.me ? null : kCard,
            border: m.me ? null : Border.all(color: kAccent.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(m.me ? 18 : 4),
              bottomRight: Radius.circular(m.me ? 4 : 18),
            ),
          ),
          child: Text(m.text, style: const TextStyle(fontSize: 15.5, height: 1.35)),
        ),
      ),
    );
  }

  Widget _orbArea({required bool compact}) {
    final size = compact ? 96.0 : 170.0;
    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 0, bottom: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (_mode == Mode.speaking) {
                _tts.stop();
                setState(() => _mode = Mode.idle);
              } else {
                _listen();
              }
            },
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, __) => CustomPaint(
                size: Size.square(size * 1.5),
                painter: OrbPainter(_pulse.value, _mode, _level),
                child: SizedBox(
                  width: size * 1.5,
                  height: size * 1.5,
                  child: Icon(
                    _mode == Mode.listening
                        ? Icons.graphic_eq
                        : _mode == Mode.speaking
                            ? Icons.volume_up
                            : Icons.mic,
                    size: size * 0.28,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _status,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _mode == Mode.listening ? kAccent : Colors.white.withValues(alpha: 0.6),
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        itemCount: _suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => ActionChip(
          label: Text(_suggestions[i]),
          backgroundColor: kCard,
          side: BorderSide(color: kAccent.withValues(alpha: 0.25)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          onPressed: () => _send(_suggestions[i]),
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _input,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                hintText: 'Type a command…',
                filled: true,
                fillColor: kCard,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: kAccent2),
            icon: const Icon(Icons.send_rounded),
            onPressed: () => _send(_input.text),
          ),
        ],
      ),
    );
  }
}

/// The glowing orb: rings breathe while idle and jump with your voice while listening.
class OrbPainter extends CustomPainter {
  final double t;
  final Mode mode;
  final double level;
  OrbPainter(this.t, this.mode, this.level);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 3;
    final active = mode != Mode.idle;
    final energy = mode == Mode.listening ? 0.25 + level * 0.75 : (active ? 0.5 : 0.25);

    // Outer glow
    canvas.drawCircle(
      c,
      r * (1.25 + 0.08 * sin(t * 2 * pi)),
      Paint()
        ..shader = RadialGradient(colors: [
          kAccent.withValues(alpha: 0.35 * energy + 0.1),
          kAccent.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r * 1.4)),
    );

    // Expanding rings
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final rr = r * (1.0 + p * (0.35 + energy * 0.25));
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = kAccent.withValues(alpha: (1 - p) * (active ? 0.6 : 0.3)),
      );
    }

    // Rotating arc
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(colors: const [kAccent, kAccent2, kAccent], transform: GradientRotation(t * 2 * pi))
          .createShader(Rect.fromCircle(center: c, radius: r * 1.08));
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 1.08), t * 2 * pi, pi * 1.2, false, arc);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 1.08), t * 2 * pi + pi, pi * 0.5, false, arc);

    // Core
    final pulse = mode == Mode.listening ? level * 0.08 : 0.02 * sin(t * 2 * pi);
    canvas.drawCircle(
      c,
      r * (0.92 + pulse),
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [Color(0xFF67E8F9), Color(0xFF2563EB), Color(0xFF1E1B4B)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
  }

  @override
  bool shouldRepaint(covariant OrbPainter old) => true;
}
