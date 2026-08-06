enum ShareAuthMode {
  none,
  token,
}

class ShareListenerConfig {
  final bool enabled;
  final int port;
  final ShareAuthMode authMode;
  final String? tokenHint;

  const ShareListenerConfig({
    this.enabled = false,
    this.port = 8848,
    this.authMode = ShareAuthMode.token,
    this.tokenHint,
  });

  ShareListenerConfig copyWith({
    bool? enabled,
    int? port,
    ShareAuthMode? authMode,
    String? tokenHint,
  }) {
    return ShareListenerConfig(
      enabled: enabled ?? this.enabled,
      port: port ?? this.port,
      authMode: authMode ?? this.authMode,
      tokenHint: tokenHint ?? this.tokenHint,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'enabled': enabled,
      'port': port,
      'authMode': authMode.name,
      'tokenHint': tokenHint,
    };
  }

  factory ShareListenerConfig.fromJson(Map<String, Object?> json) {
    return ShareListenerConfig(
      enabled: (json['enabled'] as bool?) ?? false,
      port: (json['port'] as int?) ?? 8848,
      authMode: _parseShareAuthMode(json['authMode']?.toString()),
      tokenHint: json['tokenHint']?.toString(),
    );
  }

  static ShareAuthMode _parseShareAuthMode(String? raw) {
    for (final mode in ShareAuthMode.values) {
      if (mode.name == raw) {
        return mode;
      }
    }
    return ShareAuthMode.token;
  }
}
