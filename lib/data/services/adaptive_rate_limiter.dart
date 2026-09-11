import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';

/// Manages HTTP request pacing, detects CDN rate limits (HTTP 429),
/// parses standard `Retry-After` headers, and applies Additive Increase /
/// Multiplicative Decrease (AIMD) pacing across concurrent workers.
class AdaptiveRateLimiter {
  final Duration windowDuration;
  final Duration minPacingDelay;
  final Duration maxPacingDelay;
  final int successThresholdForRecovery;
  final math.Random _random;

  // Sliding window request timestamps
  final Queue<DateTime> _requestTimestamps = Queue<DateTime>();

  // Rate Limiting & AIMD state
  Duration _currentPacingDelay;
  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _nextAllowedRequestTime = DateTime.fromMillisecondsSinceEpoch(0);

  int _totalRequests = 0;
  int _totalRateLimits = 0;
  int _consecutiveRateLimits = 0;
  int _consecutiveSuccesses = 0;

  AdaptiveRateLimiter({
    this.windowDuration = const Duration(seconds: 10),
    this.minPacingDelay = Duration.zero,
    this.maxPacingDelay = const Duration(seconds: 10),
    this.successThresholdForRecovery = 15,
    Duration initialPacingDelay = Duration.zero,
    math.Random? random,
  })  : _currentPacingDelay = initialPacingDelay,
        _random = random ?? math.Random();

  /// Total requests recorded by this rate limiter.
  int get totalRequests => _totalRequests;

  /// Total HTTP 429 rate limit events recorded.
  int get totalRateLimits => _totalRateLimits;

  /// Number of consecutive 429 events without an intervening recovery.
  int get consecutiveRateLimits => _consecutiveRateLimits;

  /// Current inter-request pacing delay enforced across workers.
  Duration get currentPacingDelay => _currentPacingDelay;

  /// The timestamp until which all workers are held in cooldown.
  DateTime get cooldownUntil => _cooldownUntil;

  /// Whether the rate limiter is currently in an active cooldown.
  bool get isInCooldown => DateTime.now().isBefore(_cooldownUntil);

  /// Remaining cooldown duration, or [Duration.zero] if not in cooldown.
  Duration get remainingCooldown {
    final now = DateTime.now();
    if (_cooldownUntil.isAfter(now)) {
      return _cooldownUntil.difference(now);
    }
    return Duration.zero;
  }

  /// Number of requests made within the current sliding window.
  int get windowRequestCount {
    _pruneSlidingWindow(DateTime.now());
    return _requestTimestamps.length;
  }

  /// Estimated real-time requests per second calculated over the sliding window.
  double get currentRequestsPerSecond {
    final now = DateTime.now();
    _pruneSlidingWindow(now);
    if (_requestTimestamps.isEmpty) return 0.0;
    if (_requestTimestamps.length == 1) return 1.0;

    final oldest = _requestTimestamps.first;
    final spanMs = now.difference(oldest).inMilliseconds;
    if (spanMs <= 0) return _requestTimestamps.length.toDouble();

    return (_requestTimestamps.length / (spanMs / 1000.0));
  }

  /// Prunes timestamps that have fallen outside of [windowDuration].
  void _pruneSlidingWindow(DateTime now) {
    final cutoff = now.subtract(windowDuration);
    while (_requestTimestamps.isNotEmpty && _requestTimestamps.first.isBefore(cutoff)) {
      _requestTimestamps.removeFirst();
    }
  }

  /// Parses the standard HTTP `Retry-After` header value.
  ///
  /// Supports both delta-seconds (`"120"`) and HTTP-date (`"Fri, 31 Dec 2026 23:59:59 GMT"`).
  /// Returns `null` if the header is missing, malformed, or invalid.
  static Duration? parseRetryAfter(String? headerValue, [DateTime? now]) {
    if (headerValue == null) return null;
    final trimmed = headerValue.trim();
    if (trimmed.isEmpty) return null;

    // 1. Delta-seconds format (e.g. "30", "120")
    final seconds = int.tryParse(trimmed);
    if (seconds != null) {
      return Duration(seconds: math.max(0, seconds));
    }

    // 2. HTTP-Date format (RFC 1123 / RFC 850 / ANSI C)
    try {
      final httpDate = HttpDate.parse(trimmed);
      final current = (now ?? DateTime.now()).toUtc();
      final diff = httpDate.difference(current);
      if (diff.isNegative) {
        return Duration.zero;
      }
      return diff;
    } catch (_) {
      // Not a valid HTTP date string
      return null;
    }
  }

  /// Acquires permission to send a request.
  ///
  /// If the rate limiter is in cooldown (due to a 429) or pacing delay is active,
  /// this method asynchronously delays the calling worker until its scheduled slot.
  /// If [cancelToken] is cancelled while waiting, a [DioException] is thrown.
  Future<void> acquireToken({CancelToken? cancelToken}) async {
    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.cancel,
        error: 'Request cancelled during rate limit pacing',
      );
    }

    // Determine the scheduled slot for this request
    final now = DateTime.now();
    var scheduledSlot = now;

    if (_cooldownUntil.isAfter(scheduledSlot)) {
      scheduledSlot = _cooldownUntil;
    }
    if (_nextAllowedRequestTime.isAfter(scheduledSlot)) {
      scheduledSlot = _nextAllowedRequestTime;
    }

    // Advance the next permitted slot by the current inter-request pacing delay
    _nextAllowedRequestTime = scheduledSlot.add(_currentPacingDelay);

    final delay = scheduledSlot.difference(now);
    if (delay > Duration.zero) {
      if (cancelToken != null) {
        // Await with cancellation support
        final completer = Completer<void>();
        final timer = Timer(delay, () {
          if (!completer.isCompleted) completer.complete();
        });

        void onCancel() {
          timer.cancel();
          if (!completer.isCompleted) {
            completer.completeError(
              DioException(
                requestOptions: RequestOptions(path: ''),
                type: DioExceptionType.cancel,
                error: 'Request cancelled during rate limit pacing',
              ),
            );
          }
        }

        cancelToken.whenCancel.then((_) => onCancel());

        try {
          await completer.future;
        } finally {
          timer.cancel();
        }
      } else {
        await Future.delayed(delay);
      }
    }

    // Record request timestamp
    _recordRequest();
  }

  /// Records that a request was sent right now.
  void _recordRequest() {
    final now = DateTime.now();
    _totalRequests++;
    _requestTimestamps.addLast(now);
    _pruneSlidingWindow(now);
  }

  /// Reports that an HTTP 429 (Too Many Requests) was returned.
  ///
  /// Extracts and honors `Retry-After` if present in [headers].
  /// Otherwise, applies exponential backoff with random jitter.
  ///
  /// Also triggers Multiplicative Decrease: reduces request pacing frequency
  /// to 60% of the trigger rate (or increases inter-request delay).
  Duration reportRateLimit(Map<String, dynamic>? headers) {
    _totalRateLimits++;
    _consecutiveRateLimits++;
    _consecutiveSuccesses = 0;

    final now = DateTime.now();
    _pruneSlidingWindow(now);

    // 1. Determine Cooldown Duration
    String? retryAfterHeader;
    if (headers != null) {
      for (final entry in headers.entries) {
        if (entry.key.toLowerCase() == 'retry-after') {
          final val = entry.value;
          if (val is List && val.isNotEmpty) {
            retryAfterHeader = val.first.toString();
          } else if (val is String) {
            retryAfterHeader = val;
          }
          break;
        }
      }
    }

    final parsedRetryAfter = parseRetryAfter(retryAfterHeader, now);
    Duration cooldown;

    if (parsedRetryAfter != null && parsedRetryAfter > Duration.zero) {
      // Add minor jitter (100-300ms) to prevent thundering herd when retry-after expires
      final jitterMs = 100 + _random.nextInt(200);
      cooldown = parsedRetryAfter + Duration(milliseconds: jitterMs);
    } else {
      // Fallback: Exponential backoff 2^k seconds capped at 30 seconds + jitter
      final exponent = math.min(_consecutiveRateLimits, 5);
      final baseSeconds = math.pow(2, exponent).toInt();
      final jitterMs = 100 + _random.nextInt(400);
      cooldown = Duration(seconds: baseSeconds, milliseconds: jitterMs);
    }

    // Impose cooldown barrier across all workers
    final newCooldownTarget = now.add(cooldown);
    if (newCooldownTarget.isAfter(_cooldownUntil)) {
      _cooldownUntil = newCooldownTarget;
    }
    if (_cooldownUntil.isAfter(_nextAllowedRequestTime)) {
      _nextAllowedRequestTime = _cooldownUntil;
    }

    // 2. AIMD: Multiplicative Decrease on pacing
    // Calculate the trigger rate at the time of 429
    final triggerRate = currentRequestsPerSecond;
    if (triggerRate > 0) {
      // Reduce rate to 60% of trigger rate, floor at 0.5 req/sec
      final safeRate = math.max(triggerRate * 0.6, 0.5);
      final calculatedDelayMs = (1000.0 / safeRate).round();
      final newDelay = Duration(milliseconds: calculatedDelayMs);

      if (newDelay > _currentPacingDelay) {
        _currentPacingDelay = newDelay;
      }
    } else {
      // If we couldn't estimate trigger rate, increase pacing delay multiplicatively
      final currentMs = _currentPacingDelay.inMilliseconds;
      final newMs = currentMs == 0 ? 250 : (currentMs * 1.6).round();
      _currentPacingDelay = Duration(milliseconds: newMs);
    }

    // Clamp pacing delay within bounds
    if (_currentPacingDelay > maxPacingDelay) {
      _currentPacingDelay = maxPacingDelay;
    }
    if (_currentPacingDelay < minPacingDelay) {
      _currentPacingDelay = minPacingDelay;
    }

    return cooldown;
  }

  /// Reports that a request succeeded (HTTP 2xx).
  ///
  /// Tracks successful streaks and performs Additive Increase (reducing inter-request delay)
  /// when sufficient consecutive successes demonstrate network stability.
  void reportSuccess() {
    _consecutiveRateLimits = 0;
    _consecutiveSuccesses++;

    if (_currentPacingDelay > minPacingDelay &&
        _consecutiveSuccesses >= successThresholdForRecovery) {
      _consecutiveSuccesses = 0;
      // Additive Increase: reduce pacing delay by 50ms (or 10%)
      final currentMs = _currentPacingDelay.inMilliseconds;
      final stepMs = math.max(50, (currentMs * 0.1).round());
      final newMs = math.max(minPacingDelay.inMilliseconds, currentMs - stepMs);
      _currentPacingDelay = Duration(milliseconds: newMs);
    }
  }

  /// Resets the rate limiter state.
  void reset() {
    _requestTimestamps.clear();
    _currentPacingDelay = minPacingDelay;
    _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _nextAllowedRequestTime = DateTime.fromMillisecondsSinceEpoch(0);
    _totalRequests = 0;
    _totalRateLimits = 0;
    _consecutiveRateLimits = 0;
    _consecutiveSuccesses = 0;
  }
}

