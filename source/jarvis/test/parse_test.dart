import 'package:flutter_test/flutter_test.dart';
import 'package:jarvis/parse.dart';

void main() {
  final now = DateTime(2026, 11, 27, 14, 0); // Friday 2 PM

  group('clock times', () {
    ClockTime c(String s) => findClock(normalize(s), now)!.value;

    test('am/pm', () {
      expect(c('set alarm for 6:30 am').when, DateTime(2026, 11, 28, 6, 30));
      expect(c('at 5 pm').when, DateTime(2026, 11, 27, 17, 0));
      expect(c('at 5 p.m.').when, DateTime(2026, 11, 27, 17, 0));
      expect(c('7 am').hour, 7);
      expect(c('at 630 am').minute, 30);
      expect(c('at 6 30').minute, 30);
    });
    test('bare hour picks next one', () {
      expect(c('at 6').when, DateTime(2026, 11, 27, 18, 0));
      expect(c('at 11').when, DateTime(2026, 11, 27, 23, 0));
      expect(c('at 18:45').when, DateTime(2026, 11, 27, 18, 45));
    });
    test('tomorrow and parts of day', () {
      expect(c('tomorrow at 9').when, DateTime(2026, 11, 28, 9, 0));
      expect(c('at 9 tomorrow night').when, DateTime(2026, 11, 28, 21, 0));
      expect(c('at 8 tonight').when, DateTime(2026, 11, 27, 20, 0));
      expect(c('at noon').when, DateTime(2026, 11, 28, 12, 0));
      expect(c('at seven in the morning').when, DateTime(2026, 11, 28, 7, 0));
    });
    test('durations are not times', () {
      expect(findClock(normalize('for 10 minutes'), now), isNull);
      expect(findClock(normalize('buy 2 eggs'), now), isNull);
    });
  });

  group('durations', () {
    Duration d(String s) => findDuration(normalize(s))!.value;
    test('basic', () {
      expect(d('timer for 10 minutes'), const Duration(minutes: 10));
      expect(d('1 hour 30 minutes'), const Duration(minutes: 90));
      expect(d('90 sec'), const Duration(seconds: 90));
      expect(d('half an hour'), const Duration(minutes: 30));
      expect(d('an hour'), const Duration(hours: 1));
      expect(d('five minutes'), const Duration(minutes: 5));
    });
  });

  group('when', () {
    test('in X', () {
      final w = findWhen(normalize('in 20 minutes to call mom'), now)!;
      expect(w.value, now.add(const Duration(minutes: 20)));
      expect(w.rest, 'to call mom');
    });
    test('at X', () {
      final w = findWhen(normalize('call mom at 5 pm'), now)!;
      expect(w.value, DateTime(2026, 11, 27, 17, 0));
      expect(w.rest, 'call mom');
    });
  });

  group('maths', () {
    test('sums', () {
      expect(calculate('25 x 4'), 100);
      expect(calculate('what is 12 plus 7'), 19);
      expect(calculate('18% of 2500'), 450);
      expect(calculate('what is 18 percent of 2500'), 450);
      expect(calculate('(2+3)*4'), 20);
      expect(calculate('100 divided by 8'), 12.5);
      expect(calculate('2 ^ 10'), 1024);
      expect(calculate('square root of 144'), closeTo(12, 1e-9));
    });
    test('not sums', () {
      expect(calculate('call mom'), isNull);
      expect(calculate('2026'), isNull);
      expect(calculate('open whatsapp'), isNull);
    });
    test('format', () {
      expect(formatNumber(12), '12');
      expect(formatNumber(12.5), '12.5');
      expect(formatNumber(1 / 3), '0.3333');
    });
  });

  test('formatting', () {
    expect(formatTime(0, 5), '12:05 AM');
    expect(formatTime(18, 30), '6:30 PM');
    expect(formatDuration(const Duration(minutes: 90)), '1 hour 30 minutes');
    expect(formatWhen(DateTime(2026, 11, 28, 9), now), 'tomorrow at 9:00 AM');
  });
}
