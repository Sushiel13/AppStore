import 'dart:convert';

import 'package:http/http.dart' as http;

import 'store.dart';

/// Weather from Open-Meteo (free, no key, no sign-up).
class Weather {
  static const _codes = {
    0: 'clear sky', 1: 'mostly clear', 2: 'partly cloudy', 3: 'cloudy',
    45: 'foggy', 48: 'foggy', 51: 'light drizzle', 53: 'drizzle', 55: 'heavy drizzle',
    61: 'light rain', 63: 'rain', 65: 'heavy rain', 66: 'freezing rain', 67: 'freezing rain',
    71: 'light snow', 73: 'snow', 75: 'heavy snow', 77: 'snow grains',
    80: 'rain showers', 81: 'rain showers', 82: 'heavy rain showers',
    85: 'snow showers', 86: 'snow showers', 95: 'thunderstorms', 96: 'thunderstorms with hail',
    99: 'thunderstorms with hail',
  };

  static Future<String> report(String city, {bool tomorrow = false}) async {
    final geo = await http
        .get(Uri.https('geocoding-api.open-meteo.com', '/v1/search',
            {'name': city, 'count': '1', 'language': 'en', 'format': 'json'}))
        .timeout(const Duration(seconds: 12));
    final g = jsonDecode(geo.body) as Map<String, dynamic>;
    final results = g['results'] as List?;
    if (results == null || results.isEmpty) return "I couldn't find a place called $city.";
    final place = results.first as Map<String, dynamic>;
    final name = place['name'] as String;
    final f = await http
        .get(Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': '${place['latitude']}',
          'longitude': '${place['longitude']}',
          'current': 'temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m',
          'daily': 'temperature_2m_max,temperature_2m_min,precipitation_probability_max,weather_code',
          'timezone': 'auto',
          'forecast_days': '2',
        }))
        .timeout(const Duration(seconds: 12));
    final w = jsonDecode(f.body) as Map<String, dynamic>;
    final daily = w['daily'] as Map<String, dynamic>;
    final di = tomorrow ? 1 : 0;
    final hi = (daily['temperature_2m_max'] as List)[di];
    final lo = (daily['temperature_2m_min'] as List)[di];
    final rain = (daily['precipitation_probability_max'] as List)[di];
    final dayCode = (daily['weather_code'] as List)[di];
    if (tomorrow) {
      return 'Tomorrow in $name: ${_codes[dayCode] ?? 'mixed weather'}, '
          '${_r(lo)} to ${_r(hi)}°C, $rain% chance of rain.';
    }
    final c = w['current'] as Map<String, dynamic>;
    return 'In $name it is ${_r(c['temperature_2m'])}°C and ${_codes[c['weather_code']] ?? 'mixed'}, '
        'feels like ${_r(c['apparent_temperature'])}°C. Today ${_r(lo)} to ${_r(hi)}°C, '
        '$rain% chance of rain.';
  }

  static String _r(dynamic v) => (v as num).round().toString();
}

/// Optional AI answers for questions Jarvis can't handle on the phone.
/// Uses the person's own key: Google Gemini, or any OpenAI-compatible
/// service (OpenAI, Groq, OpenRouter, or Ollama/OpenJarvis on their own computer).
class Ai {
  static bool get enabled =>
      Store.aiProvider == 'gemini' && Store.aiKey.isNotEmpty ||
      Store.aiProvider == 'openai' && Store.aiBaseUrl.isNotEmpty;

  static String _system() {
    final now = DateTime.now();
    final who = Store.userName.isEmpty ? '' : " The user's name is ${Store.userName}.";
    return 'You are Jarvis, a friendly phone assistant. Reply in plain text, no markdown, '
        'in 1 to 3 short sentences that sound natural when read aloud. '
        'Current date and time: $now.$who';
  }

  /// [history] is a list of (isUser, text), oldest first, ending with the question.
  static Future<String> ask(List<(bool, String)> history) async {
    final recent = history.length > 10 ? history.sublist(history.length - 10) : history;
    if (Store.aiProvider == 'gemini') {
      final model = Store.aiModel.isEmpty ? 'gemini-2.5-flash' : Store.aiModel;
      final r = await http
          .post(
            Uri.https('generativelanguage.googleapis.com', '/v1beta/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': Store.aiKey},
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': _system()}
                ]
              },
              'contents': [
                for (final (me, text) in recent)
                  {
                    'role': me ? 'user' : 'model',
                    'parts': [
                      {'text': text}
                    ]
                  }
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (r.statusCode != 200) {
        final msg = (j['error'] as Map?)?['message'] ?? 'error ${r.statusCode}';
        throw Exception('Gemini: $msg');
      }
      final parts = ((j['candidates'] as List).first['content']['parts'] as List);
      return _clean(parts.map((p) => p['text'] ?? '').join());
    }

    var base = Store.aiBaseUrl.trim();
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    final r = await http
        .post(
          Uri.parse('$base/chat/completions'),
          headers: {
            'Content-Type': 'application/json',
            if (Store.aiKey.isNotEmpty) 'Authorization': 'Bearer ${Store.aiKey}',
          },
          body: jsonEncode({
            'model': Store.aiModel.isEmpty ? 'gpt-4o-mini' : Store.aiModel,
            'messages': [
              {'role': 'system', 'content': _system()},
              for (final (me, text) in recent) {'role': me ? 'user' : 'assistant', 'content': text},
            ],
          }),
        )
        .timeout(const Duration(seconds: 60));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      final msg = (j['error'] is Map ? j['error']['message'] : j['error']) ?? 'error ${r.statusCode}';
      throw Exception('AI: $msg');
    }
    return _clean((j['choices'] as List).first['message']['content'] as String);
  }

  static String _clean(String s) => s
      .replaceAll(RegExp(r'\*\*|__|`'), '')
      .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[*-]\s+', multiLine: true), '• ')
      .trim();
}
