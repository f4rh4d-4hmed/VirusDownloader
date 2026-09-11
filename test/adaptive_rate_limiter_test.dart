import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/data/services/adaptive_rate_limiter.dart';

void main() {
  group('AdaptiveRateLimiter - Retry-After Parsing', () {
    test('parses delta-seconds integer string', () {
      expect(AdaptiveRateLimiter.parseRetryAfter('120'), equals(const Duration(seconds: 120)));
      expect(AdaptiveRateLimiter.parseRetryAfter('0'), equals(Duration.zero));
      expect(AdaptiveRateLimiter.parseRetryAfter('  5  '), equals(const Duration(seconds: 5)));
    });

    test('parses standard RFC 1123 HTTP date', () {
      final now = DateTime.utc(2026, 9, 11, 12, 0, 0);
      final targetDate = DateTime.utc(2026, 9, 11, 12, 0, 45);
      final headerValue = HttpDate.format(targetDate); // e.g. "Fri, 11 Sep 2026 12:00:45 GMT"

      final parsed = AdaptiveRateLimiter.parseRetryAfter(headerValue, now);
      expect(parsed, isNotNull);
      expect(parsed, equals(const Duration(seconds: 45)));
    });

    test('returns Duration.zero for past HTTP date', () {
      final now = DateTime.utc(2026, 9, 11, 12, 0, 0);
      final pastDate = DateTime.utc(2026, 9, 11, 11, 59, 0);
      final headerValue = HttpDate.format(pastDate);

      final parsed = AdaptiveRateLimiter.parseRetryAfter(headerValue, now);
      expect(parsed, equals(Duration.zero));
    });

    test('returns null for missing, empty, or invalid header value', () {
      expect(AdaptiveRateLimiter.parseRetryAfter(null), isNull);
      expect(AdaptiveRateLimiter.parseRetryAfter(''), isNull);
      expect(AdaptiveRateLimiter.parseRetryAfter('   '), isNull);
      expect(AdaptiveRateLimiter.parseRetryAfter('invalid-string'), isNull);
    });
  });

  group('AdaptiveRateLimiter - Sliding Window & Frequency Tracking', () {
    test('tracks request counts and sliding window pruning', () async {
      final limiter = AdaptiveRateLimiter(
        windowDuration: const Duration(milliseconds: 200),
      );

      expect(limiter.totalRequests, equals(0));
      expect(limiter.windowRequestCount, equals(0));
      expect(limiter.currentRequestsPerSecond, equals(0.0));

      await limiter.acquireToken();
      expect(limiter.totalRequests, equals(1));
      expect(limiter.windowRequestCount, equals(1));

      await limiter.acquireToken();
      await limiter.acquireToken();
      expect(limiter.totalRequests, equals(3));
      expect(limiter.windowRequestCount, equals(3));

      // Wait for window expiration
      await Future.delayed(const Duration(milliseconds: 250));
      expect(limiter.windowRequestCount, equals(0));
      expect(limiter.totalRequests, equals(3)); // Total persists
    });
  });

  group('AdaptiveRateLimiter - AIMD Pacing & Cooldown Barrier', () {
    test('applies cooldown and pacing decrease on rate limit report', () {
      final limiter = AdaptiveRateLimiter(
        random: math.Random(42), // Fixed seed for reproducible jitter
        minPacingDelay: const Duration(milliseconds: 10),
      );

      expect(limiter.totalRateLimits, equals(0));
      expect(limiter.isInCooldown, isFalse);

      // Report 429 with explicit Retry-After header
      final headers = {
        'retry-after': ['2'],
      };
      final cooldown = limiter.reportRateLimit(headers);

      expect(limiter.totalRateLimits, equals(1));
      expect(limiter.consecutiveRateLimits, equals(1));
      expect(limiter.isInCooldown, isTrue);
      expect(cooldown.inSeconds, greaterThanOrEqualTo(2));
      expect(limiter.remainingCooldown.inMilliseconds, greaterThan(0));
      expect(limiter.currentPacingDelay, greaterThanOrEqualTo(const Duration(milliseconds: 250)));
    });

    test('handles fallback exponential backoff when Retry-After is absent', () {
      final limiter = AdaptiveRateLimiter(random: math.Random(1));

      final cooldown1 = limiter.reportRateLimit(null);
      expect(limiter.consecutiveRateLimits, equals(1));
      expect(cooldown1.inSeconds, greaterThanOrEqualTo(2));

      final cooldown2 = limiter.reportRateLimit({});
      expect(limiter.consecutiveRateLimits, equals(2));
      expect(cooldown2.inSeconds, greaterThanOrEqualTo(4));
    });

    test('recovers pacing delay through reportSuccess (Additive Increase)', () {
      final limiter = AdaptiveRateLimiter(
        initialPacingDelay: const Duration(milliseconds: 300),
        minPacingDelay: const Duration(milliseconds: 50),
        successThresholdForRecovery: 3,
      );

      expect(limiter.currentPacingDelay, equals(const Duration(milliseconds: 300)));

      // 1st success
      limiter.reportSuccess();
      expect(limiter.currentPacingDelay, equals(const Duration(milliseconds: 300)));

      // 2nd success
      limiter.reportSuccess();
      expect(limiter.currentPacingDelay, equals(const Duration(milliseconds: 300)));

      // 3rd success hits threshold -> additive step (50ms)
      limiter.reportSuccess();
      expect(limiter.currentPacingDelay.inMilliseconds, lessThan(300));
      expect(limiter.currentPacingDelay.inMilliseconds, equals(250));
    });

    test('cancelToken aborts acquireToken during cooldown or delay', () async {
      final limiter = AdaptiveRateLimiter();
      limiter.reportRateLimit({'retry-after': ['10']});

      final cancelToken = CancelToken();

      // Cancel after 30ms
      Future.delayed(const Duration(milliseconds: 30), () {
        cancelToken.cancel('User stopped download');
      });

      expect(
        limiter.acquireToken(cancelToken: cancelToken),
        throwsA(isA<DioException>().having((e) => e.type, 'type', DioExceptionType.cancel)),
      );
    });

    test('concurrent workers acquire paced slots sequentially', () async {
      final limiter = AdaptiveRateLimiter(
        initialPacingDelay: const Duration(milliseconds: 50),
      );

      final stopwatch = Stopwatch()..start();
      // Launch 3 workers in parallel
      await Future.wait([
        limiter.acquireToken(),
        limiter.acquireToken(),
        limiter.acquireToken(),
      ]);
      stopwatch.stop();

      // Worker 0: ~0ms, Worker 1: ~50ms, Worker 2: ~100ms
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(80));
      expect(limiter.totalRequests, equals(3));
    });

    test('reset restores initial state', () {
      final limiter = AdaptiveRateLimiter();
      limiter.reportRateLimit({'retry-after': ['5']});
      expect(limiter.totalRateLimits, equals(1));
      expect(limiter.isInCooldown, isTrue);

      limiter.reset();
      expect(limiter.totalRateLimits, equals(0));
      expect(limiter.isInCooldown, isFalse);
      expect(limiter.totalRequests, equals(0));
      expect(limiter.currentPacingDelay, equals(Duration.zero));
    });
  });
}
