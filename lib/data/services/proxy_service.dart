import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:socks5_proxy/socks_client.dart';
import '../../core/constants.dart';
import '../../core/utils.dart';
import '../../domain/models/proxy_config.dart';

class ProxyBenchmarkResult {
  final ProxyConfig proxy;
  final bool isWorking;
  final double speedBytesPerSec;
  final Duration latency;
  final String? errorMessage;

  const ProxyBenchmarkResult({
    required this.proxy,
    required this.isWorking,
    required this.speedBytesPerSec,
    required this.latency,
    this.errorMessage,
  });
}

class ProxyService {
  /// Create a Dio instance configured with the specified proxy
  Dio createDioWithProxy(ProxyConfig? proxy, {BaseOptions? baseOptions}) {
    final options = baseOptions ??
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(minutes: 60),
        );

    // Ensure default browser headers are always included
    for (final entry in AppConstants.defaultHttpHeaders.entries) {
      if (!options.headers.containsKey(entry.key)) {
        options.headers[entry.key] = entry.value;
      }
    }

    final dio = Dio(options);

    if (proxy == null || kIsWeb) {
      return dio;
    }

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (cert, host, port) => true;

        if (proxy.type == ProxyType.http) {
          client.findProxy = (uri) => 'PROXY ${proxy.host}:${proxy.port};';
          if (proxy.username != null && proxy.password != null) {
            client.addProxyCredentials(
              proxy.host,
              proxy.port,
              '',
              HttpClientBasicCredentials(proxy.username!, proxy.password!),
            );
          }
        } else if (proxy.type == ProxyType.socks5) {
          final address = InternetAddress.tryParse(proxy.host);
          if (address != null) {
            final settings = ProxySettings(
              address,
              proxy.port,
              username: proxy.username,
              password: proxy.password,
            );
            SocksTCPClient.assignToHttpClient(client, [settings]);
          } else {
            // Fallback for hostnames using findProxy PAC format
            client.findProxy = (uri) => 'SOCKS5 ${proxy.host}:${proxy.port}; SOCKS ${proxy.host}:${proxy.port};';
          }
        } else if (proxy.type == ProxyType.socks4) {
          client.findProxy = (uri) => 'SOCKS ${proxy.host}:${proxy.port};';
        }

        return client;
      },
    );

    return dio;
  }

  /// Test connectivity to a proxy server
  Future<ProxyBenchmarkResult> testProxy(
    ProxyConfig proxy, {
    String testUrl = 'https://cloudflare.com/cdn-cgi/trace',
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final stopwatch = Stopwatch()..start();
    final dio = createDioWithProxy(
      proxy,
      baseOptions: BaseOptions(
        connectTimeout: timeout,
        receiveTimeout: timeout,
      ),
    );

    try {
      final response = await dio.get(
        testUrl,
        options: Options(
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
      );
      stopwatch.stop();

      final isSuccess = response.statusCode != null && response.statusCode! >= 200;
      return ProxyBenchmarkResult(
        proxy: proxy,
        isWorking: isSuccess,
        speedBytesPerSec: 0.0,
        latency: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return ProxyBenchmarkResult(
        proxy: proxy,
        isWorking: false,
        speedBytesPerSec: 0.0,
        latency: stopwatch.elapsed,
        errorMessage: AppUtils.getHumanReadableError(e),
      );
    }
  }

  /// Benchmarks proxy speed by downloading a sample (up to 10 MB) from the ACTUAL download file URL.
  /// Sample size scales proportionally with file size (minimum 1 MB).
  Future<ProxyBenchmarkResult> benchmarkProxy({
    required ProxyConfig proxy,
    required String downloadUrl,
    int? expectedTotalBytes,
    CancelToken? cancelToken,
  }) async {
    int sampleSize = 10 * 1024 * 1024; // 10 MB default
    if (expectedTotalBytes != null && expectedTotalBytes > 0) {
      if (expectedTotalBytes < sampleSize) {
        sampleSize = (expectedTotalBytes * 0.5).toInt().clamp(1024 * 512, sampleSize);
      }
    }

    final dio = createDioWithProxy(
      proxy,
      baseOptions: BaseOptions(
        connectTimeout: const Duration(seconds: 6),
        receiveTimeout: const Duration(seconds: 15),
      ),
    );

    final stopwatch = Stopwatch()..start();
    int receivedBytes = 0;

    try {
      final response = await dio.get<ResponseBody>(
        downloadUrl,
        options: Options(
          responseType: ResponseType.stream,
          headers: {'range': 'bytes=0-${sampleSize - 1}'},
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );

      final stream = response.data?.stream;
      if (stream == null) throw Exception('No data stream');

      await for (final chunk in stream) {
        receivedBytes += chunk.length;
        if (receivedBytes >= sampleSize) break;
      }
      stopwatch.stop();

      final durationSec = stopwatch.elapsedMilliseconds / 1000.0;
      final speed = durationSec > 0 ? (receivedBytes / durationSec) : 0.0;

      return ProxyBenchmarkResult(
        proxy: proxy.copyWith(lastBenchmarkSpeed: speed),
        isWorking: true,
        speedBytesPerSec: speed,
        latency: Duration(milliseconds: stopwatch.elapsedMilliseconds),
      );
    } catch (e) {
      stopwatch.stop();
      return ProxyBenchmarkResult(
        proxy: proxy,
        isWorking: false,
        speedBytesPerSec: 0.0,
        latency: stopwatch.elapsed,
        errorMessage: AppUtils.getHumanReadableError(e),
      );
    }
  }
}
