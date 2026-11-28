import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

class Cancelled implements Exception {
  const Cancelled();
  @override
  String toString() => 'Test stopped.';
}

/// Real speed test against Cloudflare's public speed test servers (speed.cloudflare.com).
class SpeedTest {
  static const _host = 'https://speed.cloudflare.com';
  bool _cancel = false;

  void cancel() => _cancel = true;

  /// Internet delay: median of several tiny requests, plus jitter.
  Future<({double ping, double jitter})> ping({int count = 8}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final times = <double>[];
    try {
      for (var i = 0; i < count + 1 && !_cancel; i++) {
        final sw = Stopwatch()..start();
        final req = await client.getUrl(Uri.parse('$_host/__down?bytes=0&r=$i'));
        final res = await req.close();
        await res.drain<void>();
        sw.stop();
        if (i > 0) times.add(sw.elapsedMicroseconds / 1000); // first one includes connection setup
      }
    } finally {
      client.close(force: true);
    }
    if (_cancel) throw const Cancelled();
    if (times.isEmpty) throw const SocketException('No reply from the speed test server');
    return (ping: median(times), jitter: jitter(times));
  }

  /// Delay to the router itself. Uses a TCP connect: even a refused connection is a full round trip.
  static Future<double?> routerPing(String gateway, {int count = 6}) async {
    if (gateway.isEmpty) return null;
    final times = <double>[];
    for (var i = 0; i < count; i++) {
      for (final port in const [80, 53, 443]) {
        final sw = Stopwatch()..start();
        try {
          final s = await Socket.connect(gateway, port, timeout: const Duration(seconds: 2));
          sw.stop();
          s.destroy();
          times.add(sw.elapsedMicroseconds / 1000);
          break;
        } on SocketException catch (e) {
          sw.stop();
          // "Connection refused" comes back from the router, so it still measures the trip.
          final refused = e.osError?.errorCode == 111 || e.message.toLowerCase().contains('refused');
          if (refused) {
            times.add(sw.elapsedMicroseconds / 1000);
            break;
          }
        }
      }
    }
    if (times.isEmpty) return null;
    return median(times);
  }

  Future<double> download({required void Function(double mbps, double progress) onProgress, Duration length = const Duration(seconds: 8)}) {
    return _run(
      length: length,
      onProgress: onProgress,
      worker: (client, sw, add) async {
        while (!_cancel && sw.elapsed < length) {
          final req = await client.getUrl(Uri.parse('$_host/__down?bytes=25000000'));
          final res = await req.close();
          await for (final chunk in res) {
            add(chunk.length);
            if (_cancel || sw.elapsed >= length) break;
          }
        }
      },
    );
  }

  Future<double> upload({required void Function(double mbps, double progress) onProgress, Duration length = const Duration(seconds: 7)}) {
    final rnd = math.Random();
    final block = Uint8List(64 * 1024);
    for (var i = 0; i < block.length; i++) {
      block[i] = rnd.nextInt(256);
    }
    const blocksPerPost = 8; // 512 KB per request
    return _run(
      length: length,
      workers: 3,
      onProgress: onProgress,
      worker: (client, sw, add) async {
        while (!_cancel && sw.elapsed < length) {
          final req = await client.postUrl(Uri.parse('$_host/__up'));
          req.headers.contentType = ContentType.binary;
          req.contentLength = block.length * blocksPerPost;
          var aborted = false;
          for (var b = 0; b < blocksPerPost; b++) {
            if (_cancel || sw.elapsed >= length) {
              req.done.ignore();
              req.abort();
              aborted = true;
              break;
            }
            req.add(block);
            await req.flush();
            add(block.length);
          }
          if (aborted) break;
          final res = await req.close();
          await res.drain<void>();
        }
      },
    );
  }

  Future<double> _run({
    required Duration length,
    required void Function(double mbps, double progress) onProgress,
    required Future<void> Function(HttpClient client, Stopwatch sw, void Function(int) add) worker,
    int workers = 4,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..maxConnectionsPerHost = workers;
    final sw = Stopwatch()..start();
    const warm = Duration(milliseconds: 1200); // skip the slow start of each connection
    var bytes = 0;
    int? warmBytes;
    Duration? warmAt;

    void add(int n) {
      bytes += n;
      if (warmBytes == null && sw.elapsed >= warm) {
        warmBytes = bytes;
        warmAt = sw.elapsed;
      }
    }

    double current() {
      final wb = warmBytes;
      final wa = warmAt;
      if (wb != null && wa != null) {
        final secs = (sw.elapsed - wa).inMicroseconds / 1e6;
        if (secs > 0.3) return (bytes - wb) * 8 / 1e6 / secs;
      }
      final secs = sw.elapsed.inMicroseconds / 1e6;
      return secs <= 0 ? 0 : bytes * 8 / 1e6 / secs;
    }

    final timer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      onProgress(current(), (sw.elapsed.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0).toDouble());
    });

    Object? lastError;
    try {
      await Future.wait(List.generate(workers, (_) async {
        try {
          await worker(client, sw, add);
        } catch (e) {
          lastError = e;
        }
      }));
    } finally {
      timer.cancel();
      client.close(force: true);
    }
    if (_cancel && bytes == 0) throw const Cancelled();
    if (bytes == 0) throw lastError ?? const SocketException('Speed test failed');
    final result = current();
    onProgress(result, 1);
    return result;
  }
}

double median(List<double> v) {
  final s = [...v]..sort();
  final m = s.length ~/ 2;
  return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
}

double jitter(List<double> v) {
  if (v.length < 2) return 0;
  var sum = 0.0;
  for (var i = 1; i < v.length; i++) {
    sum += (v[i] - v[i - 1]).abs();
  }
  return sum / (v.length - 1);
}
