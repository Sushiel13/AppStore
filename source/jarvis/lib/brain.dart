import 'dart:math';

import 'package:flutter/services.dart';

import 'native.dart';
import 'online.dart';
import 'parse.dart';
import 'phone.dart';
import 'store.dart';

/// Understands a request, does it on the phone and returns what to say back.
class Brain {
  String? _pending; // what the last question was about
  String _pendingText = '';
  List<Person> _choices = [];
  String _choiceAction = 'call';
  String _choiceMessage = '';
  List<AppInfo>? _apps;
  final _rand = Random();

  static const help = 'Here are some things I can do:\n'
      '• "Set an alarm for 6:30 am" or "Wake me up in 20 minutes"\n'
      '• "Set a timer for 10 minutes"\n'
      '• "Remind me to drink water in 30 minutes" or "…at 5 pm tomorrow"\n'
      '• "Call Mom", "WhatsApp Rahul saying I\'m on my way", "SMS Priya that I\'ll be late"\n'
      '• "Open YouTube", "Play lo-fi music", "Navigate to Phoenix Mall"\n'
      '• "Torch on", "Volume up", "Turn on Wi-Fi", "Battery"\n'
      '• "Weather", "Weather in Mumbai tomorrow"\n'
      '• "Note: car service on Monday", "Read my notes"\n'
      '• "Add milk and eggs to my shopping list", "Show shopping list"\n'
      '• "What is 18% of 2500", "Search for best biryani near me"\n'
      '• "Tell me a joke", "Flip a coin", "What time is it"';

  Future<String> handle(String raw, List<ChatMsg> history) async {
    try {
      return await _handle(raw, history);
    } on NoContactsPermission {
      return 'I need permission to read your contacts for that. You can allow it in the app settings.';
    } on PlatformException catch (e) {
      return "Sorry, that didn't work on this phone${e.message == null ? '' : ': ${e.message}'}.";
    } catch (e) {
      return 'Sorry, something went wrong: $e';
    }
  }

  static String _strip(String t) {
    var s = t;
    s = s.replaceAll(RegExp(r'^(hey|hi|ok|okay|hello)?\s*jarvis\b\s*'), '');
    s = s.replaceAll(RegExp(r'^(please|can you|could you|will you|would you|kindly)\s+'), '');
    s = s.replaceAll(RegExp(r'^(please)\s+'), '');
    s = s.replaceAll(RegExp(r'\s+(please|for me|jarvis)$'), '');
    s = s.replaceAll(RegExp(r'\s+(please|for me)$'), '');
    return s.trim();
  }

  /// Same cleanup on the original words, keeping their capital letters.
  static String _stripRaw(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(RegExp(r'^(hey|hi|ok|okay|hello)?[\s,]*jarvis\b[\s,]*', caseSensitive: false), '');
    s = s.replaceFirst(RegExp(r'^(please|can you|could you|will you|would you|kindly)\s+', caseSensitive: false), '');
    return s.trim();
  }

  Future<String> _handle(String raw, List<ChatMsg> history) async {
    final t = _strip(normalize(raw));
    final r = _stripRaw(raw);
    final now = DateTime.now();

    if (t.isEmpty) return 'Yes? How can I help?';

    // ---- answers to a question I just asked
    if (_pending != null) {
      final p = _pending!;
      if (RegExp(r'^(cancel|stop|never ?mind|forget it|no|nope|leave it)$').hasMatch(t)) {
        _pending = null;
        return 'Okay, cancelled.';
      }
      final ans = await _answerPending(p, t, r, now);
      if (ans != null) return ans;
      _pending = null;
    }

    // ---- small talk
    if (RegExp(r'^(hi|hii|hello|hey|namaste|yo|good (morning|afternoon|evening))$').hasMatch(t)) {
      final h = now.hour;
      final part = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
      final name = Store.userName.isEmpty ? '' : ', ${Store.userName}';
      return '$part$name! What can I do for you?';
    }
    if (RegExp(r'^(help|what can you do|what do you do|commands|how do i use you|what all can you do)').hasMatch(t)) {
      return help;
    }
    if (RegExp(r'^(who are you|what are you|what is your name|what.?s your name|your name)$').hasMatch(t)) {
      return "I'm Jarvis, your phone assistant. Ask me to set alarms, reminders, call people, open apps and more.";
    }
    if (RegExp(r'^how are you').hasMatch(t)) return "I'm running smoothly, thanks for asking! How can I help?";
    if (RegExp(r'^(thanks|thank you|thank u|thx|great|awesome|nice|cool|ok|okay|good)( jarvis| so much| very much)?$').hasMatch(t)) {
      return "You're welcome!";
    }
    if (RegExp(r'^(bye|goodbye|good night|see you)').hasMatch(t)) return 'Goodbye! Tap the mic whenever you need me.';

    // ---- name
    final setName = RegExp(r'^(my name is|call me|i am called)\s+(.+)$', caseSensitive: false).firstMatch(r);
    if (setName != null && !RegExp(r'^call me (back|later|when|at|in)\b').hasMatch(t)) {
      final name = setName.group(2)!.trim().replaceAll(RegExp(r'[.!]+$'), '');
      Store.userName = name;
      return 'Nice to meet you, $name!';
    }
    if (RegExp(r'^(what.?s|what is|do you know) my name').hasMatch(t)) {
      return Store.userName.isEmpty ? "You haven't told me yet. Say \"My name is …\"." : 'You are ${Store.userName}.';
    }

    // ---- home city
    final setCity = RegExp(r'^(set my city to|my city is|i live in|set (home )?city to|change (my )?city to)\s+(.+)$')
        .firstMatch(t);
    if (setCity != null) {
      final city = _title(setCity.group(5)!);
      Store.city = city;
      return 'Got it, your city is $city.';
    }

    // ---- notes
    if (RegExp(r'^(show|read|list|open|what are|check)\s+(all\s+)?(my\s+)?notes\b|^my notes$|^notes$').hasMatch(t)) {
      final n = Store.notes;
      if (n.isEmpty) return 'You have no notes yet. Say "Note: …" to add one.';
      return 'Your notes:\n${n.map((x) => '• $x').join('\n')}';
    }
    if (RegExp(r'^(clear|delete|remove|erase)\s+(all\s+)?(my\s+)?notes\b').hasMatch(t)) {
      Store.notes = [];
      return 'All notes deleted.';
    }
    if (RegExp(r'^(delete|remove)\s+(the\s+)?last note\b').hasMatch(t)) {
      final n = Store.notes;
      if (n.isEmpty) return 'There are no notes.';
      final last = n.removeLast();
      Store.notes = n;
      return 'Deleted "$last".';
    }
    final note = RegExp(r'^(take a note|make a note|note down|note that|add a note|save a note|write down|jot down|note)\b[\s:,-]*(that\s+)?(.+)$',
            caseSensitive: false)
        .firstMatch(r);
    if (note != null && RegExp(r'^(take a note|make a note|note|add a note|save a note|write down|jot down)').hasMatch(t)) {
      final text = _cap(note.group(3)!.trim());
      Store.notes = [...Store.notes, text];
      return 'Noted: $text';
    }

    // ---- lists (shopping, grocery, to-do …)
    final lt = t.replaceAll(RegExp(r'\bto[ -]do list\b'), 'todo list');
    const listName = r"([a-z-]+)";
    final addList = RegExp("^(?:add|put)\\s+(.+?)\\s+(?:to|in|on|onto)\\s+(?:my\\s+|the\\s+)?$listName\\s+list\$").firstMatch(lt);
    if (addList != null) {
      final name = addList.group(2)!;
      final items = addList.group(1)!.split(RegExp(r',|\band\b|&')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final list = Store.list(name);
      list.addAll(items);
      await Store.setList(name, list);
      return 'Added ${items.join(', ')} to your $name list. It has ${list.length} item${list.length == 1 ? '' : 's'}.';
    }
    final removeList = RegExp("^(?:remove|delete|tick off|cross off|cut)\\s+(.+?)\\s+from\\s+(?:my\\s+|the\\s+)?$listName\\s+list\$").firstMatch(lt);
    if (removeList != null) {
      final name = removeList.group(2)!;
      final item = removeList.group(1)!.trim();
      final list = Store.list(name);
      final i = list.indexWhere((e) => e.toLowerCase() == item);
      if (i < 0) return "$item isn't on your $name list.";
      list.removeAt(i);
      await Store.setList(name, list);
      return 'Removed $item from your $name list.';
    }
    final clearList = RegExp("^(?:clear|empty|delete)\\s+(?:my\\s+|the\\s+)?$listName\\s+list\$").firstMatch(lt);
    if (clearList != null) {
      await Store.setList(clearList.group(1)!, []);
      return 'Cleared your ${clearList.group(1)} list.';
    }
    final showList = RegExp("^(?:(?:show|read|what.?s on|what is on|check|open|see)\\s+(?:me\\s+)?(?:my\\s+|the\\s+)?|my\\s+)?$listName\\s+list\$").firstMatch(lt);
    if (showList != null) {
      final name = showList.group(1)!;
      final list = Store.list(name);
      if (list.isEmpty) return 'Your $name list is empty.';
      return 'Your $name list:\n${list.map((e) => '• $e').join('\n')}';
    }

    // ---- messages
    final msg = RegExp(
            r"^(?:send\s+)?(?:an?\s+)?(whatsapp|whats app|message|msg|sms|text)(?:\s+message)?\s+(?:to\s+)?(.+?)\s*(?:saying|that says|which says|that|telling|and say|:)\s+(.+)$",
            caseSensitive: false)
        .firstMatch(r);
    if (msg != null) {
      final how = msg.group(1)!.toLowerCase();
      return _message(how.contains('sms') || how == 'text' ? 'sms' : 'whatsapp', msg.group(2)!, msg.group(3)!);
    }
    final waOnly = RegExp(r'^(?:open\s+)?(?:whatsapp|whats app)\s+(?:to\s+|chat with\s+)?(.+)$').firstMatch(t);
    if (waOnly != null && !RegExp(r'^(app|web|status|settings)$').hasMatch(waOnly.group(1)!)) {
      return _message('whatsapp', waOnly.group(1)!, '');
    }

    // ---- calls
    final call = RegExp(r'^(?:make a\s+)?(?:call|dial|phone|ring)\s+(?:to\s+)?(.+?)(?:\s+(?:now|on mobile|on phone))?$').firstMatch(t);
    if (call != null) return _call(call.group(1)!);

    // ---- time and date
    if (RegExp(r"\b(what.?s the time|what is the time|what time is it|current time|time now|tell me the time|time please)\b|^time$")
        .hasMatch(t)) {
      return "It's ${formatTime(now.hour, now.minute)}.";
    }
    if (RegExp(r"\b(what.?s the date|what is the date|today.?s date|what day is (it|today)|which day is (it|today)|date today)\b|^date$")
        .hasMatch(t)) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
      return 'Today is ${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}.';
    }

    // ---- timer (before alarm so "timer" wins)
    if (RegExp(r'\b(timer|countdown|count down)\b').hasMatch(t)) {
      if (RegExp(r'\b(cancel|stop|delete|show|check)\b').hasMatch(t)) {
        await Native.showAlarms();
        return 'Opening your clock app, where you can see or stop timers.';
      }
      return _timer(t);
    }

    // ---- alarm
    if (RegExp(r'\b(alarm|alarms|wake me)\b').hasMatch(t)) {
      if (RegExp(r'\b(show|list|see|check|my alarms|cancel|delete|remove|turn off|switch off|stop)\b').hasMatch(t)) {
        await Native.showAlarms();
        return 'Here are your alarms in the clock app.';
      }
      return _alarm(t, now);
    }

    // ---- reminders
    if (RegExp(r'^(show|list|read|what are|check)\s+(all\s+)?(my\s+)?reminders?\b|^my reminders$').hasMatch(t)) {
      final list = Store.reminders;
      if (list.isEmpty) return 'You have no upcoming reminders.';
      return 'Your reminders:\n${list.map((x) => '• ${x.text} – ${formatWhen(x.when, now)}').join('\n')}';
    }
    if (RegExp(r'^(cancel|delete|clear|remove)\s+(all\s+)?(my\s+)?reminders?\b').hasMatch(t)) {
      final list = Store.reminders;
      for (final x in list) {
        await Reminders.cancel(x.id);
      }
      Store.reminders = [];
      return list.isEmpty ? 'You had no reminders.' : 'Cleared ${list.length} reminder${list.length == 1 ? '' : 's'}.';
    }
    final rem = RegExp(r'^(remind me|set (a )?reminder|add (a )?reminder|create (a )?reminder|reminder)\b\s*(to|that|about|for)?\s*(.*)$')
        .firstMatch(t);
    if (rem != null) return _reminder(rem.group(6) ?? '', now);

    // ---- torch
    if (RegExp(r'\b(torch|flashlight|flash light)\b|\bflash (on|off)\b|\b(on|off) (the )?flash\b').hasMatch(t)) {
      final off = RegExp(r'\b(off|band|bandh|stop|disable)\b').hasMatch(t);
      await Native.torch(!off);
      return off ? 'Torch off.' : 'Torch on.';
    }

    // ---- volume
    if (RegExp(r'\b(volume|mute|unmute|louder|quieter)\b').hasMatch(t)) {
      if (RegExp(r'\bunmute\b').hasMatch(t)) {
        await Native.volume('unmute');
        return 'Unmuted.';
      }
      if (RegExp(r'\bmute\b').hasMatch(t)) {
        await Native.volume('mute');
        return 'Media muted.';
      }
      final down = RegExp(r'\b(down|lower|decrease|reduce|less|quieter|kam)\b').hasMatch(t);
      final steps = RegExp(r'\b(lot|max|full|maximum)\b').hasMatch(t) ? 5 : 2;
      for (var i = 0; i < steps; i++) {
        await Native.volume(down ? 'down' : 'up');
      }
      return down ? 'Volume down.' : 'Volume up.';
    }

    // ---- switches Android only lets the person flip themselves
    final sw = RegExp(r'\b(turn|switch|put|enable|disable|start|stop)?\s*(on|off)?\s*(the\s+)?(wi-?fi|wifi|wireless|internet|mobile data|data|bluetooth|hotspot|location|gps|airplane mode|aeroplane mode|flight mode|do not disturb|dnd|brightness|dark mode)\b')
        .firstMatch(t);
    if (sw != null && (sw.group(1) != null || sw.group(2) != null || RegExp(r'\b(settings?|open)\b').hasMatch(t))) {
      return _setting(sw.group(4)!);
    }

    // ---- battery
    if (RegExp(r'\b(battery|charge level|charging)\b').hasMatch(t)) {
      final b = await Native.battery();
      final level = b['level'];
      final charging = b['charging'] == true;
      return 'Battery is at $level%${charging ? ' and charging' : ''}.';
    }

    // ---- weather
    if (RegExp(r'\b(weather|temperature|forecast|will it rain|is it raining|going to rain|umbrella|mausam)\b').hasMatch(t)) {
      final tomorrow = RegExp(r'\btomorrow\b').hasMatch(t);
      final m = RegExp(r"\b(?:in|at|for|of)\s+([a-z][a-z .'-]*?)(?:\s+(?:today|tomorrow|now|right now|this week))?$").firstMatch(t);
      var city = m?.group(1)?.trim() ?? '';
      if (RegExp(r'^(today|tomorrow|now|the morning|the evening|my city|here|my area)$').hasMatch(city)) city = '';
      if (city.isEmpty) city = Store.city;
      if (city.isEmpty) {
        _pending = 'weather_city';
        _pendingText = tomorrow ? 'tomorrow' : '';
        return 'Which city are you in? I\'ll remember it.';
      }
      return Weather.report(city, tomorrow: tomorrow);
    }

    // ---- maps
    final nav = RegExp(r'^(?:navigate|directions|take me|route|drive|how do i get|how to reach|how to go|way)\s*(?:me\s+)?(?:to|for)\s+(.+)$')
        .firstMatch(t);
    if (nav != null) {
      final place = nav.group(1)!;
      try {
        await Native.open('google.navigation:q=${Uri.encodeComponent(place)}', package: 'com.google.android.apps.maps');
      } on PlatformException {
        await Native.open('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(place)}');
      }
      return 'Starting directions to ${_title(place)}.';
    }
    final near = RegExp(r'^(?:find|show|search|where is|where are)?\s*(?:me\s+)?(?:an?\s+|the\s+)?(.+?)\s+(near me|nearby|around me|close by)$').firstMatch(t);
    final onMap = RegExp(r'^(?:show|find)\s+(.+?)\s+on (?:the\s+)?maps?$').firstMatch(t);
    if (near != null || onMap != null) {
      final what = near != null ? '${near.group(1)} near me' : onMap!.group(1)!;
      await Native.open('geo:0,0?q=${Uri.encodeComponent(what)}');
      return 'Showing $what on the map.';
    }

    // ---- music and videos
    final play = RegExp(r'^(?:play|put on)\s+(.+?)(?:\s+on\s+(youtube|youtube music|spotify|yt))?$').firstMatch(t);
    if (play != null) {
      final what = play.group(1)!;
      final where = play.group(2) ?? 'youtube';
      if (where == 'spotify') {
        try {
          await Native.open('spotify:search:${Uri.encodeComponent(what)}', package: 'com.spotify.music');
          return 'Searching Spotify for $what.';
        } on PlatformException {
          return "Spotify isn't installed.";
        }
      }
      if (where == 'youtube music') {
        await Native.open('https://music.youtube.com/search?q=${Uri.encodeComponent(what)}',
            package: 'com.google.android.apps.youtube.music');
        return 'Searching YouTube Music for $what.';
      }
      await Native.open('https://www.youtube.com/results?search_query=${Uri.encodeComponent(what)}',
          package: 'com.google.android.youtube');
      return 'Here is $what on YouTube.';
    }
    final yt = RegExp(r'^(?:search\s+)?(?:youtube|yt)\s+(?:for\s+)?(.+)$|^search\s+(.+?)\s+on\s+youtube$').firstMatch(t);
    if (yt != null) {
      final what = yt.group(1) ?? yt.group(2)!;
      await Native.open('https://www.youtube.com/results?search_query=${Uri.encodeComponent(what)}',
          package: 'com.google.android.youtube');
      return 'Searching YouTube for $what.';
    }

    // ---- open an app
    final open = RegExp(r'^(?:open|launch|start|run|go to)\s+(?:the\s+|my\s+)?(.+?)(?:\s+app)?$').firstMatch(t);
    if (open != null) return _open(open.group(1)!);

    // ---- maths
    final sum = calculate(t);
    if (sum != null) return formatNumber(sum);

    // ---- fun
    if (RegExp(r'\b(joke|make me laugh|something funny)\b').hasMatch(t)) {
      const jokes = [
        "Why don't programmers like nature? Too many bugs.",
        'I told my phone I needed a break. Now it keeps showing me KitKat ads.',
        'Why did the scarecrow win an award? He was outstanding in his field.',
        "I'm reading a book about anti-gravity. It's impossible to put down.",
        'Why did the computer go to the doctor? It had a virus.',
        "What do you call a fake noodle? An impasta.",
        'Why was the maths book sad? It had too many problems.',
        'My Wi-Fi went down for five minutes, so I talked to my family. They seem like nice people.',
      ];
      return jokes[_rand.nextInt(jokes.length)];
    }
    if (RegExp(r'\b(flip|toss) a coin\b|\bcoin (flip|toss)\b|heads or tails').hasMatch(t)) {
      return _rand.nextBool() ? 'Heads!' : 'Tails!';
    }
    if (RegExp(r'\b(roll|throw) (a )?(dice|die)\b').hasMatch(t)) return 'You rolled a ${_rand.nextInt(6) + 1}.';
    final pick = RegExp(r'\b(random number|pick a number)\b(?:.*?(\d+)\D+(\d+))?').firstMatch(t);
    if (pick != null) {
      final a = int.tryParse(pick.group(2) ?? '') ?? 1;
      final b = int.tryParse(pick.group(3) ?? '') ?? 100;
      final lo = min(a, b), hi = max(a, b);
      return '${lo + _rand.nextInt(hi - lo + 1)}';
    }

    // ---- web search
    final search = RegExp(r'^(?:search|google|look up|find|search for|google for)\s+(?:for\s+|about\s+)?(.+)$').firstMatch(t);
    if (search != null) return _search(search.group(1)!);

    // ---- anything else: AI if set up, otherwise offer a web search
    if (Ai.enabled) {
      final h = <(bool, String)>[
        for (final m in history) (m.me, m.text),
      ];
      if (h.isEmpty || h.last.$2 != raw) h.add((true, raw));
      return Ai.ask(h);
    }
    _pending = 'search';
    _pendingText = r;
    return "I can't answer that on my own. Shall I search Google for it? "
        '(Tip: add a free AI key in Settings and I can answer questions too.)';
  }

  Future<String?> _answerPending(String p, String t, String r, DateTime now) async {
    final yes = RegExp(r'^(yes|yeah|yep|yup|ok|okay|sure|please|do it|go ahead|haan|ha|han|ji|search)\b').hasMatch(t);
    switch (p) {
      case 'search':
        if (yes) {
          _pending = null;
          return _search(_pendingText);
        }
        return null;
      case 'weather_city':
        if (t.split(' ').length > 4) return null;
        _pending = null;
        final city = _title(t.replaceAll(RegExp(r'^(i am in|i.?m in|in|it.?s|my city is)\s+'), ''));
        Store.city = city;
        return Weather.report(city, tomorrow: _pendingText == 'tomorrow');
      case 'alarm':
        _pending = null;
        final c = findClock(t.contains(RegExp(r'\b(at|for)\b')) ? t : 'at $t', now);
        if (c == null) return "Sorry, I didn't get the time. Try \"Set an alarm for 6:30 am\".";
        return _setAlarm(c.value.hour, c.value.minute, now);
      case 'timer':
        _pending = null;
        return _timer(t);
      case 'reminder_time':
        _pending = null;
        final w = findWhen(t.contains(RegExp(r'\b(at|in|after|by)\b')) ? t : 'at $t', now);
        if (w == null) return "Sorry, I didn't get the time. Try \"in 30 minutes\" or \"at 5 pm\".";
        return _saveReminder(_pendingText, w.value, now);
      case 'reminder_text':
        _pending = null;
        return _reminder('$t $_pendingText', now);
      case 'pick':
        _pending = null;
        final n = int.tryParse(RegExp(r'\d+').firstMatch(t)?.group(0) ?? '');
        Person? chosen;
        if (n != null && n >= 1 && n <= _choices.length) {
          chosen = _choices[n - 1];
        } else if (RegExp(r'\bfirst\b').hasMatch(t)) {
          chosen = _choices.first;
        } else if (RegExp(r'\bsecond\b').hasMatch(t) && _choices.length > 1) {
          chosen = _choices[1];
        } else if (RegExp(r'\bthird\b').hasMatch(t) && _choices.length > 2) {
          chosen = _choices[2];
        } else {
          for (final c in _choices) {
            if (c.name.toLowerCase().contains(t)) chosen = c;
          }
        }
        if (chosen == null) return null;
        return _contactAction(chosen);
    }
    return null;
  }

  // ------------------------------------------------------------ actions

  Future<String> _timer(String t) async {
    final d = findDuration(t);
    if (d == null || d.value.inSeconds <= 0) {
      _pending = 'timer';
      return 'For how long?';
    }
    await Native.setTimer(d.value.inSeconds, null);
    return 'Timer set for ${formatDuration(d.value)}.';
  }

  Future<String> _alarm(String t, DateTime now) async {
    final inX = RegExp(r'\b(in|after)\s+\d').hasMatch(t) ? findDuration(t) : null;
    if (inX != null && inX.value.inMinutes > 0) {
      final at = now.add(inX.value);
      return _setAlarm(at.hour, at.minute, now);
    }
    final c = findClock(t.contains(RegExp(r'\b(at|for|by)\b')) ? t : t.replaceFirstMapped(RegExp(r'(\d)'), (m) => 'at ${m[1]}'), now);
    if (c == null) {
      _pending = 'alarm';
      return 'What time should I set the alarm for?';
    }
    return _setAlarm(c.value.hour, c.value.minute, now);
  }

  Future<String> _setAlarm(int hour, int minute, DateTime now) async {
    await Native.setAlarm(hour, minute, 'Jarvis');
    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final left = at.difference(now);
    final h = left.inHours, m = left.inMinutes % 60;
    final inText = h > 0 ? '$h hour${h == 1 ? '' : 's'} ${m > 0 ? 'and $m minute${m == 1 ? '' : 's'}' : ''}' : '$m minute${m == 1 ? '' : 's'}';
    return 'Alarm set for ${formatTime(hour, minute)}, ${inText.trim()} from now.';
  }

  Future<String> _reminder(String body, DateTime now) async {
    final b = body.trim();
    final w = findWhen(b, now);
    var task = (w?.rest ?? b)
        .replaceAll(RegExp(r'^(to|that|about|for|me)\s+'), '')
        .replaceAll(RegExp(r'\s+(at|on|in|by|to)$'), '')
        .trim();
    if (task.isEmpty && w == null) {
      _pending = 'reminder_text';
      _pendingText = b;
      return 'What should I remind you about?';
    }
    if (task.isEmpty) {
      _pending = 'reminder_text';
      _pendingText = b;
      return 'Sure. What should I remind you about?';
    }
    if (w == null) {
      _pending = 'reminder_time';
      _pendingText = task;
      return 'When should I remind you? For example "in 30 minutes" or "at 6 pm".';
    }
    return _saveReminder(task, w.value, now);
  }

  Future<String> _saveReminder(String task, DateTime when, DateTime now) async {
    if (!when.isAfter(now)) return 'That time has already passed. Try a time in the future.';
    final text = _cap(task);
    final r = Reminder(Store.nextId(), text, when);
    await Reminders.askPermission();
    await Reminders.schedule(r);
    Store.reminders = [...Store.reminders, r];
    return "Okay, I'll remind you to ${task.replaceAll(RegExp(r'\bmy\b'), 'your')} ${formatWhen(when, now)}.";
  }

  Future<String> _call(String who) async {
    final digits = who.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'^\+?\d{3,15}$').hasMatch(digits)) {
      await Native.dial(digits);
      return 'Calling $digits.';
    }
    _choiceAction = 'call';
    return _pickContact(who);
  }

  Future<String> _message(String how, String who, String text) async {
    _choiceAction = how;
    _choiceMessage = text.trim();
    final digits = who.replaceAll(RegExp(r'[\s-]'), '');
    if (RegExp(r'^\+?\d{6,15}$').hasMatch(digits)) return _contactAction(Person(digits, digits));
    return _pickContact(who.toLowerCase());
  }

  Future<String> _pickContact(String who) async {
    final name = who.replaceAll(RegExp(r"[^\w\s'.-]"), ' ').replaceAll(RegExp(r'^\s*(my|to)\s+'), '').trim();
    final found = await People.find(name);
    if (found.isEmpty) return "I couldn't find $name in your contacts.";
    if (found.length == 1) return _contactAction(found.first);
    _choices = found.take(4).toList();
    _pending = 'pick';
    final list = [for (var i = 0; i < _choices.length; i++) '${i + 1}. ${_choices[i].name}'].join('\n');
    return 'Which one?\n$list';
  }

  Future<String> _contactAction(Person p) async {
    switch (_choiceAction) {
      case 'call':
        await Native.dial(p.number);
        return 'Calling ${p.name}.';
      case 'sms':
        await Native.sms(p.number, _choiceMessage);
        return _choiceMessage.isEmpty
            ? 'Opening a text to ${p.name}.'
            : 'Your message to ${p.name} is ready. Tap send.';
      default:
        final n = People.international(p.number);
        final url = _choiceMessage.isEmpty ? 'https://wa.me/$n' : 'https://wa.me/$n?text=${Uri.encodeComponent(_choiceMessage)}';
        try {
          await Native.open(url, package: 'com.whatsapp');
        } on PlatformException {
          await Native.open(url);
        }
        return _choiceMessage.isEmpty
            ? 'Opening WhatsApp chat with ${p.name}.'
            : 'Your WhatsApp message to ${p.name} is ready. Tap send.';
    }
  }

  Future<String> _setting(String what) async {
    Future<void> go(List<String> actions) async {
      for (final a in actions) {
        try {
          await Native.action(a);
          return;
        } on PlatformException {
          continue;
        }
      }
      await Native.action('android.settings.SETTINGS');
    }

    const note = "Android doesn't let apps flip this for you, so here's the switch.";
    switch (what) {
      case 'wifi' || 'wi-fi' || 'wireless':
        await go(['android.settings.panel.action.WIFI', 'android.settings.WIFI_SETTINGS']);
        return 'Wi-Fi. $note';
      case 'internet' || 'mobile data' || 'data':
        await go(['android.settings.panel.action.INTERNET_CONNECTIVITY', 'android.settings.DATA_ROAMING_SETTINGS']);
        return 'Mobile data and internet. $note';
      case 'bluetooth':
        await go(['android.settings.BLUETOOTH_SETTINGS']);
        return 'Bluetooth. $note';
      case 'hotspot':
        await go(['android.settings.TETHER_SETTINGS', 'android.settings.WIRELESS_SETTINGS']);
        return 'Hotspot. $note';
      case 'location' || 'gps':
        await go(['android.settings.LOCATION_SOURCE_SETTINGS']);
        return 'Location. $note';
      case 'airplane mode' || 'aeroplane mode' || 'flight mode':
        await go(['android.settings.AIRPLANE_MODE_SETTINGS']);
        return 'Airplane mode. $note';
      case 'do not disturb' || 'dnd':
        await go(['android.settings.ZEN_MODE_SETTINGS', 'android.settings.SOUND_SETTINGS']);
        return 'Do Not Disturb. $note';
      case 'dark mode':
        await go(['android.settings.DARK_THEME_SETTINGS', 'android.settings.DISPLAY_SETTINGS']);
        return 'Dark mode. $note';
      default:
        await go(['android.settings.DISPLAY_SETTINGS']);
        return 'Display and brightness settings.';
    }
  }

  Future<String> _open(String name) async {
    final n = name.trim();
    const special = {
      'camera': 'android.media.action.STILL_IMAGE_CAMERA',
      'settings': 'android.settings.SETTINGS',
      'phone settings': 'android.settings.SETTINGS',
      'wifi settings': 'android.settings.WIFI_SETTINGS',
      'bluetooth settings': 'android.settings.BLUETOOTH_SETTINGS',
      'app settings': 'android.settings.APPLICATION_SETTINGS',
      'apps': 'android.settings.APPLICATION_SETTINGS',
      'battery settings': 'android.intent.action.POWER_USAGE_SUMMARY',
      'storage': 'android.settings.INTERNAL_STORAGE_SETTINGS',
      'video camera': 'android.media.action.VIDEO_CAMERA',
    };
    if (special.containsKey(n)) {
      await Native.action(special[n]!);
      return 'Opening ${_title(n)}.';
    }
    if (n == 'alarms' || n == 'alarm' || n == 'clock') {
      await Native.showAlarms();
      return 'Opening the clock.';
    }
    _apps ??= await Native.apps();
    final q = n.replaceAll(' ', '');
    AppInfo? best;
    var bestScore = 0;
    for (final a in _apps!) {
      final an = a.name.toLowerCase();
      final aq = an.replaceAll(' ', '');
      int s;
      if (an == n || aq == q) {
        s = 4;
      } else if (aq.startsWith(q)) {
        s = 3;
      } else if (an.split(' ').contains(n)) {
        s = 2;
      } else if (q.length >= 3 && aq.contains(q)) {
        s = 1;
      } else {
        continue;
      }
      if (s > bestScore || s == bestScore && best != null && a.name.length < best.name.length) {
        best = a;
        bestScore = s;
      }
    }
    if (best == null) {
      _apps = null; // refresh next time in case something was installed
      return "I couldn't find an app called $n.";
    }
    await Native.launch(best.package);
    return 'Opening ${best.name}.';
  }

  Future<String> _search(String q) async {
    await Native.open('https://www.google.com/search?q=${Uri.encodeComponent(q)}');
    return 'Searching Google for "$q".';
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  static String _title(String s) =>
      s.trim().split(RegExp(r'\s+')).map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
}
