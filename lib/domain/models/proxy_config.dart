enum ProxyType {
  http,
  socks4,
  socks5,
}

class ProxyConfig {
  final String host;
  final int port;
  final ProxyType type;
  final String? username;
  final String? password;
  final double? lastBenchmarkSpeed; // bytes/sec

  const ProxyConfig({
    required this.host,
    required this.port,
    this.type = ProxyType.http,
    this.username,
    this.password,
    this.lastBenchmarkSpeed,
  });

  /// Parse from string such as:
  /// socks5://user:pass@127.0.0.1:1080
  /// http://192.168.1.1:8080
  /// socks4://127.0.0.1:9050
  /// 127.0.0.1:8080 (default http)
  static ProxyConfig? tryParse(String input) {
    var raw = input.trim();
    if (raw.isEmpty) return null;

    ProxyType type = ProxyType.http;
    if (raw.toLowerCase().startsWith('socks5://')) {
      type = ProxyType.socks5;
      raw = raw.substring('socks5://'.length);
    } else if (raw.toLowerCase().startsWith('socks4://')) {
      type = ProxyType.socks4;
      raw = raw.substring('socks4://'.length);
    } else if (raw.toLowerCase().startsWith('http://')) {
      type = ProxyType.http;
      raw = raw.substring('http://'.length);
    } else if (raw.toLowerCase().startsWith('https://')) {
      type = ProxyType.http;
      raw = raw.substring('https://'.length);
    }

    String? username;
    String? password;

    if (raw.contains('@')) {
      final parts = raw.split('@');
      final authPart = parts[0];
      raw = parts.sublist(1).join('@');

      if (authPart.contains(':')) {
        final authParts = authPart.split(':');
        username = Uri.decodeComponent(authParts[0]);
        password = Uri.decodeComponent(authParts.sublist(1).join(':'));
      } else {
        username = Uri.decodeComponent(authPart);
      }
    }

    // Strip trailing slash if present
    if (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }

    if (!raw.contains(':')) return null;

    final lastColon = raw.lastIndexOf(':');
    final host = raw.substring(0, lastColon).trim();
    final portStr = raw.substring(lastColon + 1).trim();
    final port = int.tryParse(portStr);

    if (host.isEmpty || port == null || port <= 0 || port > 65535) {
      return null;
    }

    return ProxyConfig(
      host: host,
      port: port,
      type: type,
      username: username,
      password: password,
    );
  }

  String get displayUrl {
    final auth = username != null ? '${username!}${password != null ? ':***' : ''}@' : '';
    return '${type.name}://$auth$host:$port';
  }

  String get originalUrl {
    final auth = username != null ? '$username${password != null ? ':$password' : ''}@' : '';
    return '${type.name}://$auth$host:$port';
  }

  ProxyConfig copyWith({
    String? host,
    int? port,
    ProxyType? type,
    String? username,
    String? password,
    double? lastBenchmarkSpeed,
  }) {
    return ProxyConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      type: type ?? this.type,
      username: username ?? this.username,
      password: password ?? this.password,
      lastBenchmarkSpeed: lastBenchmarkSpeed ?? this.lastBenchmarkSpeed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'host': host,
      'port': port,
      'type': type.index,
      'username': username,
      'password': password,
      'lastBenchmarkSpeed': lastBenchmarkSpeed,
    };
  }

  factory ProxyConfig.fromJson(Map<String, dynamic> json) {
    final typeIndex = json['type'] as int? ?? 0;
    final type = (typeIndex >= 0 && typeIndex < ProxyType.values.length)
        ? ProxyType.values[typeIndex]
        : ProxyType.http;

    return ProxyConfig(
      host: json['host'] as String? ?? '',
      port: json['port'] as int? ?? 8080,
      type: type,
      username: json['username'] as String?,
      password: json['password'] as String?,
      lastBenchmarkSpeed: (json['lastBenchmarkSpeed'] as num?)?.toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProxyConfig &&
          runtimeType == other.runtimeType &&
          host == other.host &&
          port == other.port &&
          type == other.type &&
          username == other.username &&
          password == other.password;

  @override
  int get hashCode => Object.hash(host, port, type, username, password);
}

