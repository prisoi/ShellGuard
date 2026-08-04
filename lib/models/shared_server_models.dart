class SharedServerRecord {
  final String id;
  final String groupId;
  final String remoteServerId;
  final String displayName;

  const SharedServerRecord({
    required this.id,
    required this.groupId,
    required this.remoteServerId,
    required this.displayName,
  });

  SharedServerRecord copyWith({
    String? id,
    String? groupId,
    String? remoteServerId,
    String? displayName,
  }) {
    return SharedServerRecord(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      remoteServerId: remoteServerId ?? this.remoteServerId,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'groupId': groupId,
      'remoteServerId': remoteServerId,
      'displayName': displayName,
    };
  }

  factory SharedServerRecord.fromJson(Map<String, Object?> json) {
    return SharedServerRecord(
      id: json['id']!.toString(),
      groupId: json['groupId']!.toString(),
      remoteServerId: json['remoteServerId']!.toString(),
      displayName: json['displayName']!.toString(),
    );
  }
}

class SharedGroupRecord {
  final String id;
  final String displayName;
  final String sourceHostIp;
  final int sourcePort;
  final String sourceGroupName;
  final DateTime importedAt;
  final List<SharedServerRecord> servers;

  const SharedGroupRecord({
    required this.id,
    required this.displayName,
    required this.sourceHostIp,
    required this.sourcePort,
    required this.sourceGroupName,
    required this.importedAt,
    this.servers = const [],
  });

  SharedGroupRecord copyWith({
    String? id,
    String? displayName,
    String? sourceHostIp,
    int? sourcePort,
    String? sourceGroupName,
    DateTime? importedAt,
    List<SharedServerRecord>? servers,
  }) {
    return SharedGroupRecord(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      sourceHostIp: sourceHostIp ?? this.sourceHostIp,
      sourcePort: sourcePort ?? this.sourcePort,
      sourceGroupName: sourceGroupName ?? this.sourceGroupName,
      importedAt: importedAt ?? this.importedAt,
      servers: servers ?? this.servers,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'sourceHostIp': sourceHostIp,
      'sourcePort': sourcePort,
      'sourceGroupName': sourceGroupName,
      'importedAt': importedAt.toIso8601String(),
      'servers': servers.map((item) => item.toJson()).toList(),
    };
  }

  factory SharedGroupRecord.fromJson(Map<String, Object?> json) {
    final rawServers = json['servers'];
    return SharedGroupRecord(
      id: json['id']!.toString(),
      displayName: json['displayName']!.toString(),
      sourceHostIp: json['sourceHostIp']!.toString(),
      sourcePort: (json['sourcePort'] as num).toInt(),
      sourceGroupName: json['sourceGroupName']!.toString(),
      importedAt: DateTime.parse(json['importedAt']!.toString()),
      servers: rawServers is List
          ? rawServers
                .whereType<Map>()
                .map((item) => SharedServerRecord.fromJson(item.cast<String, Object?>()))
                .toList()
          : const <SharedServerRecord>[],
    );
  }
}

class SharedExportServer {
  final String serverId;
  final String serverName;

  const SharedExportServer({
    required this.serverId,
    required this.serverName,
  });

  Map<String, Object?> toJson() {
    return {
      'serverId': serverId,
      'serverName': serverName,
    };
  }

  factory SharedExportServer.fromJson(Map<String, Object?> json) {
    return SharedExportServer(
      serverId: json['serverId']!.toString(),
      serverName: json['serverName']!.toString(),
    );
  }
}

class SharedGroupExportPayload {
  final String groupName;
  final String hostIp;
  final int port;
  final List<SharedExportServer> servers;

  const SharedGroupExportPayload({
    required this.groupName,
    required this.hostIp,
    required this.port,
    required this.servers,
  });

  Map<String, Object?> toJson() {
    return {
      'schema': 'shellguard_shared_group',
      'version': 1,
      'groupName': groupName,
      'hostIp': hostIp,
      'port': port,
      'servers': servers.map((item) => item.toJson()).toList(),
    };
  }

  factory SharedGroupExportPayload.fromJson(Map<String, Object?> json) {
    final rawServers = json['servers'];
    return SharedGroupExportPayload(
      groupName: json['groupName']!.toString(),
      hostIp: json['hostIp']?.toString() ?? '',
      port: (json['port'] as num?)?.toInt() ?? 8848,
      servers: rawServers is List
          ? rawServers
                .whereType<Map>()
                .map((item) => SharedExportServer.fromJson(item.cast<String, Object?>()))
                .toList()
          : const <SharedExportServer>[],
    );
  }
}
