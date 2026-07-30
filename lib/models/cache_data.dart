import 'server.dart';

class CacheData {
  final String serverId;
  final DateTime timestamp;
  final Map<String, String> scopeUpdatedAt;
  final SystemInfo? systemInfo;
  final ResourceUsage? resourceUsage;
  final List<ProcessInfo>? processes;
  final List<PortInfo>? ports;
  final List<ServiceInfo>? services;
  final List<FirewallRule>? firewallRules;
  final bool? firewallEnabled;
  final List<DockerContainer>? dockerContainers;
  final List<DockerImage>? dockerImages;
  final List<FileInfo>? files;
  final String? currentPath;

  CacheData({
    required this.serverId,
    required this.timestamp,
    Map<String, String>? scopeUpdatedAt,
    this.systemInfo,
    this.resourceUsage,
    this.processes,
    this.ports,
    this.services,
    this.firewallRules,
    this.firewallEnabled,
    this.dockerContainers,
    this.dockerImages,
    this.files,
    this.currentPath,
  }) : scopeUpdatedAt = scopeUpdatedAt ?? <String, String>{};

  bool isFresh(Duration maxAge) {
    return DateTime.now().difference(timestamp) < maxAge;
  }

  CacheData copyWith({
    DateTime? timestamp,
    Map<String, String>? scopeUpdatedAt,
    SystemInfo? systemInfo,
    ResourceUsage? resourceUsage,
    List<ProcessInfo>? processes,
    List<PortInfo>? ports,
    List<ServiceInfo>? services,
    List<FirewallRule>? firewallRules,
    bool? firewallEnabled,
    List<DockerContainer>? dockerContainers,
    List<DockerImage>? dockerImages,
    List<FileInfo>? files,
    String? currentPath,
  }) {
    return CacheData(
      serverId: serverId,
      timestamp: timestamp ?? this.timestamp,
      scopeUpdatedAt: scopeUpdatedAt ?? this.scopeUpdatedAt,
      systemInfo: systemInfo ?? this.systemInfo,
      resourceUsage: resourceUsage ?? this.resourceUsage,
      processes: processes ?? this.processes,
      ports: ports ?? this.ports,
      services: services ?? this.services,
      firewallRules: firewallRules ?? this.firewallRules,
      firewallEnabled: firewallEnabled ?? this.firewallEnabled,
      dockerContainers: dockerContainers ?? this.dockerContainers,
      dockerImages: dockerImages ?? this.dockerImages,
      files: files ?? this.files,
      currentPath: currentPath ?? this.currentPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'serverId': serverId,
      'timestamp': timestamp.toIso8601String(),
      'scopeUpdatedAt': scopeUpdatedAt,
      'systemInfo': systemInfo != null ? {
        'osInfo': systemInfo!.osInfo,
        'kernelVersion': systemInfo!.kernelVersion,
        'uptime': systemInfo!.uptime,
        'cpuCores': systemInfo!.cpuCores,
        'memoryTotal': systemInfo!.memoryTotal,
        'diskTotal': systemInfo!.diskTotal,
      } : null,
      'resourceUsage': resourceUsage != null ? {
        'cpuUsage': resourceUsage!.cpuUsage,
        'memoryUsed': resourceUsage!.memoryUsed,
        'memoryTotal': resourceUsage!.memoryTotal,
        'memoryPercent': resourceUsage!.memoryPercent,
        'diskUsed': resourceUsage!.diskUsed,
        'diskTotal': resourceUsage!.diskTotal,
        'diskPercent': resourceUsage!.diskPercent,
        'networkUpload': resourceUsage!.networkUpload,
        'networkDownload': resourceUsage!.networkDownload,
        'activeConnections': resourceUsage!.activeConnections,
      } : null,
      'processes': processes?.map((p) => {
        'pid': p.pid,
        'name': p.name,
        'cpuPercent': p.cpuPercent,
        'memoryPercent': p.memoryPercent,
        'status': p.status,
        'user': p.user,
        'command': p.command,
      }).toList(),
      'ports': ports?.map((p) => {
        'port': p.port,
        'protocol': p.protocol,
        'pid': p.pid,
        'processName': p.processName,
        'address': p.address,
      }).toList(),
      'services': services?.map((s) => {
        'name': s.name,
        'status': s.status,
        'isEnabled': s.isEnabled,
        'description': s.description,
      }).toList(),
      'firewallRules': firewallRules?.map((r) => {
        'id': r.id,
        'action': r.action,
        'protocol': r.protocol,
        'source': r.source,
        'destination': r.destination,
        'port': r.port,
      }).toList(),
      'firewallEnabled': firewallEnabled,
      'dockerContainers': dockerContainers?.map((c) => {
        'id': c.id,
        'name': c.name,
        'status': c.status,
        'image': c.image,
        'ports': c.ports,
        'cpuUsage': c.cpuUsage,
        'memoryUsage': c.memoryUsage,
      }).toList(),
      'dockerImages': dockerImages?.map((i) => {
        'id': i.id,
        'name': i.name,
        'tag': i.tag,
        'size': i.size,
        'created': i.created,
      }).toList(),
      'files': files?.map((f) => {
        'name': f.name,
        'path': f.path,
        'isDirectory': f.isDirectory,
        'size': f.size,
        'modified': f.modified,
        'permissions': f.permissions,
      }).toList(),
      'currentPath': currentPath,
    };
  }

  factory CacheData.fromJson(Map<String, dynamic> json) {
    return CacheData(
      serverId: json['serverId'],
      timestamp: DateTime.parse(json['timestamp']),
      scopeUpdatedAt: Map<String, String>.from(json['scopeUpdatedAt'] ?? const <String, String>{}),
      systemInfo: json['systemInfo'] != null ? SystemInfo(
        osInfo: json['systemInfo']['osInfo'],
        kernelVersion: json['systemInfo']['kernelVersion'],
        uptime: json['systemInfo']['uptime'],
        cpuCores: json['systemInfo']['cpuCores'],
        memoryTotal: json['systemInfo']['memoryTotal'],
        diskTotal: json['systemInfo']['diskTotal'],
      ) : null,
      resourceUsage: json['resourceUsage'] != null ? ResourceUsage(
        cpuUsage: json['resourceUsage']['cpuUsage'],
        memoryUsed: json['resourceUsage']['memoryUsed'],
        memoryTotal: json['resourceUsage']['memoryTotal'],
        memoryPercent: json['resourceUsage']['memoryPercent'],
        diskUsed: json['resourceUsage']['diskUsed'],
        diskTotal: json['resourceUsage']['diskTotal'],
        diskPercent: json['resourceUsage']['diskPercent'],
        networkUpload: json['resourceUsage']['networkUpload'],
        networkDownload: json['resourceUsage']['networkDownload'],
        activeConnections: json['resourceUsage']['activeConnections'],
      ) : null,
      processes: (json['processes'] as List?)?.map((j) => ProcessInfo(
        pid: j['pid'],
        name: j['name'],
        cpuPercent: j['cpuPercent'],
        memoryPercent: j['memoryPercent'],
        status: j['status'],
        user: j['user'],
        command: j['command'],
      )).toList(),
      ports: (json['ports'] as List?)?.map((j) => PortInfo(
        port: j['port'],
        protocol: j['protocol'],
        pid: j['pid'],
        processName: j['processName'],
        address: j['address'],
      )).toList(),
      services: (json['services'] as List?)?.map((j) => ServiceInfo(
        name: j['name'],
        status: j['status'],
        isEnabled: j['isEnabled'],
        description: j['description'],
      )).toList(),
      firewallRules: (json['firewallRules'] as List?)?.map((j) => FirewallRule(
        id: j['id'],
        action: j['action'],
        protocol: j['protocol'],
        source: j['source'],
        destination: j['destination'],
        port: j['port'],
      )).toList(),
      firewallEnabled: json['firewallEnabled'],
      dockerContainers: (json['dockerContainers'] as List?)?.map((j) => DockerContainer(
        id: j['id'],
        name: j['name'],
        status: j['status'],
        image: j['image'],
        ports: List<String>.from(j['ports']),
        cpuUsage: j['cpuUsage'],
        memoryUsage: j['memoryUsage'],
      )).toList(),
      dockerImages: (json['dockerImages'] as List?)?.map((j) => DockerImage(
        id: j['id'],
        name: j['name'],
        tag: j['tag'],
        size: j['size'],
        created: j['created'],
      )).toList(),
      files: (json['files'] as List?)?.map((j) => FileInfo(
        name: j['name'],
        path: j['path'],
        isDirectory: j['isDirectory'],
        size: j['size'],
        modified: j['modified'],
        permissions: j['permissions'],
      )).toList(),
      currentPath: json['currentPath'],
    );
  }
}
