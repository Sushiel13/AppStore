import 'package:flutter/material.dart';

import 'main.dart' show kAccent, kCard;
import 'online.dart';
import 'store.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _name = TextEditingController(text: Store.userName);
  final _city = TextEditingController(text: Store.city);
  final _cc = TextEditingController(text: Store.countryCode);
  final _key = TextEditingController(text: Store.aiKey);
  final _model = TextEditingController(text: Store.aiModel);
  final _base = TextEditingController(text: Store.aiBaseUrl);
  String _provider = Store.aiProvider;
  bool _hideKey = true;
  bool _testing = false;

  static const _locales = {
    'en_IN': 'English (India)',
    'en_US': 'English (US)',
    'en_GB': 'English (UK)',
    'hi_IN': 'हिंदी (Hindi)',
  };

  @override
  void dispose() {
    _save();
    for (final c in [_name, _city, _cc, _key, _model, _base]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    Store.userName = _name.text.trim();
    Store.city = _city.text.trim();
    Store.countryCode = _cc.text.trim();
    Store.aiProvider = _provider;
    Store.aiKey = _key.text.trim();
    Store.aiModel = _model.text.trim();
    Store.aiBaseUrl = _base.text.trim();
  }

  Future<void> _test() async {
    _save();
    setState(() => _testing = true);
    String result;
    try {
      result = await Ai.ask([(true, 'Say hello in five words.')]);
    } catch (e) {
      result = 'Failed: $e';
    }
    if (!mounted) return;
    setState(() => _testing = false);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('AI test'),
        content: Text(result),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 22, 16, 6),
        child: Text(title.toUpperCase(),
            style: const TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.4)),
      );

  Widget _field(TextEditingController c, String label,
      {String? hint, bool obscure = false, Widget? suffix, TextInputType? type}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: TextField(
        controller: c,
        obscureText: obscure,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: kCard,
          suffixIcon: suffix,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reminders = Store.reminders;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Colors.transparent),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          _section('You'),
          _field(_name, 'Your name', hint: 'So I can greet you'),
          _field(_city, 'Home city', hint: 'For the weather, e.g. Pune'),
          _field(_cc, 'Country calling code', hint: '91 for India', type: TextInputType.number),

          _section('Voice'),
          SwitchListTile(
            title: const Text('Speak replies out loud'),
            value: Store.speak,
            onChanged: (v) => setState(() => Store.speak = v),
          ),
          SwitchListTile(
            title: const Text('Start listening when I open the app'),
            value: Store.autoListen,
            onChanged: (v) => setState(() => Store.autoListen = v),
          ),
          ListTile(
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: _locales.containsKey(Store.speechLocale) ? Store.speechLocale : 'en_IN',
              underline: const SizedBox(),
              items: [
                for (final e in _locales.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => Store.speechLocale = v ?? 'en_IN'),
            ),
          ),

          _section('Smart answers (optional)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Phone tasks work without this. Add an AI key if you also want Jarvis to answer '
              'general questions. Your key stays on this phone and is only sent to the service you choose.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), height: 1.4),
            ),
          ),
          RadioListTile<String>(
            value: 'none',
            groupValue: _provider,
            title: const Text('Off'),
            onChanged: (v) => setState(() => _provider = v!),
          ),
          RadioListTile<String>(
            value: 'gemini',
            groupValue: _provider,
            title: const Text('Google Gemini'),
            subtitle: const Text('Free key from aistudio.google.com'),
            onChanged: (v) => setState(() => _provider = v!),
          ),
          RadioListTile<String>(
            value: 'openai',
            groupValue: _provider,
            title: const Text('OpenAI-compatible'),
            subtitle: const Text('OpenAI, Groq, OpenRouter, or Ollama / OpenJarvis on your computer'),
            onChanged: (v) => setState(() => _provider = v!),
          ),
          if (_provider == 'openai')
            _field(_base, 'Server address',
                hint: 'https://api.groq.com/openai/v1 or http://192.168.1.5:11434/v1', type: TextInputType.url),
          if (_provider != 'none') ...[
            _field(_key, _provider == 'openai' ? 'API key (blank for Ollama)' : 'API key',
                obscure: _hideKey,
                suffix: IconButton(
                  icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _hideKey = !_hideKey),
                )),
            _field(_model, 'Model',
                hint: _provider == 'gemini' ? 'gemini-2.5-flash' : 'e.g. llama-3.1-8b-instant, qwen3:4b'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt),
                label: const Text('Test connection'),
              ),
            ),
          ],

          _section('Reminders'),
          if (reminders.isEmpty)
            const ListTile(title: Text('No upcoming reminders')),
          for (final r in reminders)
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: Text(r.text),
              subtitle: Text('${r.when.day}/${r.when.month} ${TimeOfDay.fromDateTime(r.when).format(context)}'),
            ),

          _section('Data'),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear chat history'),
            onTap: () {
              Store.history = [];
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chat cleared')));
            },
          ),
          const ListTile(
            leading: Icon(Icons.lock_outline),
            title: Text('Private by design'),
            subtitle: Text('Notes, lists, reminders and chats are stored only on this phone. '
                'Nothing is sent anywhere except weather lookups and, if you turn it on, your AI questions.'),
          ),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Jarvis 1.0.0'),
            subtitle: Text('From AppBucket · appbucket.in'),
          ),
        ],
      ),
    );
  }
}
