// Plain-Dart helpers that turn spoken phrases into times, durations and sums.
// No Flutter imports, so they are covered by unit tests in test/parse_test.dart.

const _numberWords = {
  'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6,
  'seven': 7, 'eight': 8, 'nine': 9, 'ten': 10, 'eleven': 11, 'twelve': 12,
  'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16, 'seventeen': 17,
  'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'twenty five': 25, 'thirty': 30,
  'forty': 40, 'forty five': 45, 'fifty': 50, 'sixty': 60, 'ninety': 90,
};

/// Lower-cases, tidies punctuation and turns number words into digits.
String normalize(String input) {
  var t = input.toLowerCase().trim();
  t = t.replaceAll(RegExp(r'a\.m\.?'), 'am').replaceAll(RegExp(r'p\.m\.?'), 'pm');
  t = t.replaceAll(RegExp(r"[!?,]"), ' ');
  t = t.replaceAll(RegExp(r'\.(?!\d)'), ' ');
  t = t.replaceAll(RegExp(r"\b(o'clock|oclock)\b"), '');
  // Longest phrases first so "twenty five" beats "twenty".
  final words = _numberWords.keys.toList()..sort((a, b) => b.length - a.length);
  for (final w in words) {
    t = t.replaceAll(RegExp('\\b$w\\b'), '${_numberWords[w]}');
  }
  t = t.replaceAll(RegExp(r'\bhalf an? hour\b'), '30 minutes');
  t = t.replaceAll(RegExp(r'\bhalf hour\b'), '30 minutes');
  t = t.replaceAll(RegExp(r'\bquarter of an? hour\b'), '15 minutes');
  t = t.replaceAllMapped(RegExp(r'\b(an|a) (hour|minute|second)\b'), (m) => '1 ${m[2]}');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

class Found<T> {
  final T value;
  final String rest; // the text with the matched part removed
  Found(this.value, this.rest);
}

final _durationPart = RegExp(
    r'(\d+(?:\.\d+)?)\s*(hours?|hrs?|h|minutes?|mins?|m|seconds?|secs?|s)\b');

/// Finds a duration such as "10 minutes", "1 hour 30 minutes", "90 sec".
Found<Duration>? findDuration(String t) {
  final matches = _durationPart.allMatches(t).toList();
  if (matches.isEmpty) return null;
  var seconds = 0.0;
  for (final m in matches) {
    final n = double.parse(m.group(1)!);
    final u = m.group(2)!;
    if (u.startsWith('h')) {
      seconds += n * 3600;
    } else if (u.startsWith('m')) {
      seconds += n * 60;
    } else {
      seconds += n;
    }
  }
  var rest = t;
  for (final m in matches.reversed) {
    rest = rest.replaceRange(m.start, m.end, ' ');
  }
  rest = rest.replaceAll(RegExp(r'\b(for|in|and|after)\b(?=\s*$)'), ' ');
  return Found(Duration(seconds: seconds.round()), _tidy(rest));
}

class ClockTime {
  final int hour; // 0-23
  final int minute;
  final bool dayGiven; // "tomorrow" was said
  final DateTime when; // next matching moment
  ClockTime(this.hour, this.minute, this.dayGiven, this.when);
}

final _clock = RegExp(
    r'(?:\b(at|for|by)\s+)?\b(\d{1,2})(?:[:.](\d{2})|\s(\d{2})(?=\s*(?:am|pm)))?\s*(am|pm)?\b');

/// Finds a clock time such as "6:30 am", "at 7", "18:45", "9 pm tomorrow".
/// Bare numbers only count when "at"/"for"/"by", a colon, or am/pm is present.
Found<ClockTime>? findClock(String t, DateTime now) {
  var text = t.replaceAllMapped(
      RegExp(r'\b(\d{1,2})(\d{2})\s*(am|pm)\b'), (m) => '${m[1]}:${m[2]} ${m[3]}');
  text = text.replaceAllMapped(RegExp(r'\b(at|for|by) (\d{1,2}) ([0-5]\d)\b'),
      (m) => '${m[1]} ${m[2]}:${m[3]}');
  var addDays = 0;
  var dayGiven = false;
  String? hint;
  if (RegExp(r'\b(day after tomorrow)\b').hasMatch(text)) {
    addDays = 2;
    dayGiven = true;
    text = text.replaceAll('day after tomorrow', ' ');
  } else if (RegExp(r'\btomorrow\b').hasMatch(text)) {
    addDays = 1;
    dayGiven = true;
    text = text.replaceAll(RegExp(r'\btomorrow\b'), ' ');
  }
  if (RegExp(r'\btonight\b').hasMatch(text)) {
    hint = 'pm';
    text = text.replaceAll(RegExp(r'\btonight\b'), ' ');
  }
  final part = RegExp(r'\b(in the )?(morning|afternoon|evening|night)\b').firstMatch(text);
  if (part != null) {
    hint = part.group(2) == 'morning' ? 'am' : 'pm';
    text = text.replaceRange(part.start, part.end, ' ');
  }
  if (RegExp(r'\bnoon\b').hasMatch(text)) {
    text = text.replaceAll(RegExp(r'\b(at )?noon\b'), ' 12:00 pm ');
  }
  if (RegExp(r'\bmidnight\b').hasMatch(text)) {
    text = text.replaceAll(RegExp(r'\b(at )?midnight\b'), ' 12:00 am ');
  }

  for (final m in _clock.allMatches(text)) {
    final prep = m.group(1);
    final mm = m.group(3) ?? m.group(4);
    final ampm = m.group(5);
    if (prep == null && mm == null && m.group(5) == null) continue;
    // "for 10 minutes" is a duration, not a time.
    final after = text.substring(m.end);
    if (mm == null && m.group(5) == null &&
        RegExp(r'^\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?|days?)\b').hasMatch(after)) {
      continue;
    }
    var h = int.parse(m.group(2)!);
    final min = mm == null ? 0 : int.parse(mm);
    if (h > 23 || min > 59) continue;
    final mark = ampm ?? hint;

    List<int> hours;
    if (mark == 'am') {
      if (h > 12) continue;
      hours = [h == 12 ? 0 : h];
    } else if (mark == 'pm') {
      if (h > 12) continue;
      hours = [h == 12 ? 12 : h + 12];
    } else if (h >= 13 || h == 0) {
      hours = [h];
    } else {
      hours = [h, h == 12 ? 0 : h + 12];
    }

    DateTime? best;
    for (final hh in hours) {
      var c = DateTime(now.year, now.month, now.day + addDays, hh, min);
      if (!dayGiven && !c.isAfter(now)) c = c.add(const Duration(days: 1));
      if (best == null || c.isBefore(best)) best = c;
    }
    final rest = text.replaceRange(m.start, m.end, ' ');
    return Found(ClockTime(best!.hour, best.minute, dayGiven, best), _tidy(rest));
  }
  return null;
}

/// Finds when something should happen: "in 20 minutes" or a clock time.
Found<DateTime>? findWhen(String t, DateTime now) {
  final inMatch = RegExp(r'\b(in|after)\s+(\d+(?:\.\d+)?)\s*(hours?|hrs?|minutes?|mins?|seconds?|secs?)\b(\s*(and\s+)?\d+\s*(minutes?|mins?|seconds?|secs?)\b)?')
      .firstMatch(t);
  if (inMatch != null) {
    final d = findDuration(inMatch.group(0)!)!;
    final rest = t.replaceRange(inMatch.start, inMatch.end, ' ');
    return Found(now.add(d.value), _tidy(rest));
  }
  final c = findClock(t, now);
  if (c != null) return Found(c.value.when, c.rest);
  return null;
}

String _tidy(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

// ---------------------------------------------------------------- maths

/// Tries to work out a sum such as "25 x 4", "what is 12 plus 7", "15% of 2400".
/// Returns null when the text is not a sum.
double? calculate(String raw) {
  var t = normalize(raw);
  t = t.replaceAll(RegExp(r"^(what is|what's|whats|calculate|how much is|compute|tell me)\s+"), '');
  t = t.replaceAll(RegExp(r'\b(equal to|equals)\b\s*$'), '').trim();

  final pct = RegExp(r'^(\d+(?:\.\d+)?)\s*(%|percent|per cent)\s*of\s*(\d+(?:\.\d+)?)$').firstMatch(t);
  if (pct != null) {
    return double.parse(pct.group(1)!) * double.parse(pct.group(3)!) / 100;
  }
  final root = RegExp(r'^(the )?square root of (\d+(?:\.\d+)?)$').firstMatch(t);
  if (root != null) {
    final v = double.parse(root.group(2)!);
    return _sqrt(v);
  }
  final sq = RegExp(r'^(\d+(?:\.\d+)?) squared$').firstMatch(t);
  if (sq != null) {
    final v = double.parse(sq.group(1)!);
    return v * v;
  }

  t = t
      .replaceAll(RegExp(r'\bplus\b'), '+')
      .replaceAll(RegExp(r'\bminus\b'), '-')
      .replaceAll(RegExp(r'\b(times|into|multiplied by|multiply by|x)\b'), '*')
      .replaceAll('×', '*')
      .replaceAll(RegExp(r'\b(divided by|divide by|by|over)\b'), '/')
      .replaceAll('÷', '/')
      .replaceAll(RegExp(r'\b(to the power of|power)\b'), '^')
      .replaceAll(RegExp(r'\s+'), '');
  if (!RegExp(r'^[\d.+\-*/^()%]+$').hasMatch(t)) return null;
  if (!RegExp(r'\d[+\-*/^%]|\)[+\-*/^]').hasMatch(t)) return null;
  try {
    final p = _Calc(t);
    final v = p.expr();
    if (p.i != t.length) return null;
    if (v.isNaN || v.isInfinite) return null;
    return v;
  } catch (_) {
    return null;
  }
}

double _sqrt(double v) {
  if (v <= 0) return 0;
  var x = v;
  for (var i = 0; i < 60; i++) {
    x = (x + v / x) / 2;
  }
  return x;
}

class _Calc {
  final String s;
  int i = 0;
  _Calc(this.s);

  double expr() {
    var v = term();
    while (i < s.length && (s[i] == '+' || s[i] == '-')) {
      final op = s[i++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = power();
    while (i < s.length && (s[i] == '*' || s[i] == '/' || s[i] == '%')) {
      final op = s[i++];
      if (op == '%' && (i >= s.length || !RegExp(r'[\d(]').hasMatch(s[i]))) {
        v = v / 100; // "50%" on its own
        continue;
      }
      final r = power();
      if (op == '*') {
        v *= r;
      } else if (op == '/') {
        v /= r;
      } else {
        v %= r;
      }
    }
    return v;
  }

  double power() {
    final b = unary();
    if (i < s.length && s[i] == '^') {
      i++;
      final e = power();
      var r = 1.0;
      if (e == e.roundToDouble() && e >= 0 && e < 1000) {
        for (var k = 0; k < e; k++) {
          r *= b;
        }
        return r;
      }
      throw const FormatException('power');
    }
    return b;
  }

  double unary() {
    if (i < s.length && s[i] == '-') {
      i++;
      return -unary();
    }
    if (i < s.length && s[i] == '+') {
      i++;
      return unary();
    }
    return atom();
  }

  double atom() {
    if (i < s.length && s[i] == '(') {
      i++;
      final v = expr();
      if (i >= s.length || s[i] != ')') throw const FormatException('bracket');
      i++;
      return v;
    }
    final start = i;
    while (i < s.length && RegExp(r'[\d.]').hasMatch(s[i])) {
      i++;
    }
    if (start == i) throw const FormatException('number');
    return double.parse(s.substring(start, i));
  }
}

/// 12.0 -> "12", 3.14159 -> "3.14"
String formatNumber(double v) {
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  var s = v.toStringAsFixed(4);
  s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return s;
}

/// "6:05 PM"
String formatTime(int hour, int minute) {
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  final mm = minute.toString().padLeft(2, '0');
  return '$h12:$mm ${hour < 12 ? 'AM' : 'PM'}';
}

/// "1 hour 30 minutes"
String formatDuration(Duration d) {
  final parts = <String>[];
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  if (h > 0) parts.add('$h hour${h == 1 ? '' : 's'}');
  if (m > 0) parts.add('$m minute${m == 1 ? '' : 's'}');
  if (s > 0) parts.add('$s second${s == 1 ? '' : 's'}');
  return parts.isEmpty ? '0 seconds' : parts.join(' ');
}

/// "today at 6:05 PM", "tomorrow at 9:00 AM", "Mon 3 Dec at 7:00 AM"
String formatWhen(DateTime when, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  final diff = day.difference(today).inDays;
  final time = formatTime(when.hour, when.minute);
  if (diff == 0) return 'today at $time';
  if (diff == 1) return 'tomorrow at $time';
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${wd[when.weekday - 1]} ${when.day} ${mo[when.month - 1]} at $time';
}
