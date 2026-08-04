import '../../core/ssh_manager.dart';
import '../../models/server.dart';

class ShareProtocol {
  static Map<String, Object?> systemInfoToJson(SystemInfo info) {
    return {
      'osInfo': info.osInfo,
      'osId': info.osId,
      'osName': info.osName,
      'osVersion': info.osVersion,
      'osFamily': info.osFamily,
      'packageManager': info.packageManager,
      'serviceManager': info.serviceManager,
      'firewallBackend': info.firewallBackend,
      'kernelVersion': info.kernelVersion,
      'uptime': info.uptime,
      'cpuCores': info.cpuCores,
      'memoryTotal': info.memoryTotal,
      'diskTotal': info.diskTotal,
    };
  }

  static SystemInfo systemInfoFromJson(Map<String, Object?> json) {
    return SystemInfo(
      osInfo: json['osInfo']!.toString(),
      osId: json['osId']?.toString() ?? '',
      osName: json['osName']?.toString() ?? '',
      osVersion: json['osVersion']?.toString() ?? '',
      osFamily: json['osFamily']?.toString() ?? '',
      packageManager: json['packageManager']?.toString() ?? '',
      serviceManager: json['serviceManager']?.toString() ?? '',
      firewallBackend: json['firewallBackend']?.toString() ?? '',
      kernelVersion: json['kernelVersion']!.toString(),
      uptime: json['uptime']!.toString(),
      cpuCores: (json['cpuCores'] as num?)?.toInt() ?? 0,
      memoryTotal: json['memoryTotal']!.toString(),
      diskTotal: json['diskTotal']!.toString(),
    );
  }

  static Map<String, Object?> resourceUsageToJson(ResourceUsage usage) {
    return {
      'cpuUsage': usage.cpuUsage,
      'memoryUsed': usage.memoryUsed,
      'memoryTotal': usage.memoryTotal,
      'memoryPercent': usage.memoryPercent,
      'diskUsed': usage.diskUsed,
      'diskTotal': usage.diskTotal,
      'diskPercent': usage.diskPercent,
      'networkUpload': usage.networkUpload,
      'networkDownload': usage.networkDownload,
      'activeConnections': usage.activeConnections,
      'gpuDevices': usage.gpuDevices.map((gpu) {
        return {
          'index': gpu.index,
          'vendor': gpu.vendor,
          'name': gpu.name,
          'utilizationPercent': gpu.utilizationPercent,
          'memoryUsed': gpu.memoryUsed,
          'memoryTotal': gpu.memoryTotal,
          'memoryPercent': gpu.memoryPercent,
          'temperature': gpu.temperature,
          'note': gpu.note,
        };
      }).toList(),
    };
  }

  static ResourceUsage resourceUsageFromJson(Map<String, Object?> json) {
    return ResourceUsage(
      cpuUsage: (json['cpuUsage'] as num?)?.toDouble() ?? 0,
      memoryUsed: json['memoryUsed']!.toString(),
      memoryTotal: json['memoryTotal']!.toString(),
      memoryPercent: (json['memoryPercent'] as num?)?.toDouble() ?? 0,
      diskUsed: json['diskUsed']!.toString(),
      diskTotal: json['diskTotal']!.toString(),
      diskPercent: (json['diskPercent'] as num?)?.toDouble() ?? 0,
      networkUpload: json['networkUpload']!.toString(),
      networkDownload: json['networkDownload']!.toString(),
      activeConnections: (json['activeConnections'] as num?)?.toInt() ?? 0,
      gpuDevices: (json['gpuDevices'] as List?)
              ?.whereType<Map>()
              .map((item) => GpuDeviceUsage(
                index: (item['index'] as num?)?.toInt() ?? 0,
                vendor: item['vendor']?.toString() ?? 'unknown',
                name: item['name']?.toString() ?? 'GPU',
                utilizationPercent:
                    (item['utilizationPercent'] as num?)?.toDouble() ?? 0,
                memoryUsed: item['memoryUsed']?.toString() ?? '0',
                memoryTotal: item['memoryTotal']?.toString() ?? '0',
                memoryPercent:
                    (item['memoryPercent'] as num?)?.toDouble() ?? 0,
                temperature: item['temperature']?.toString(),
                note: item['note']?.toString(),
              ))
              .toList() ??
          const <GpuDeviceUsage>[],
    );
  }

  static Map<String, Object?> processInfoToJson(ProcessInfo info) {
    return {
      'pid': info.pid,
      'name': info.name,
      'cpuPercent': info.cpuPercent,
      'memoryPercent': info.memoryPercent,
      'status': info.status,
      'user': info.user,
      'command': info.command,
    };
  }

  static ProcessInfo processInfoFromJson(Map<String, Object?> json) {
    return ProcessInfo(
      pid: (json['pid'] as num?)?.toInt() ?? 0,
      name: json['name']!.toString(),
      cpuPercent: (json['cpuPercent'] as num?)?.toDouble() ?? 0,
      memoryPercent: (json['memoryPercent'] as num?)?.toDouble() ?? 0,
      status: json['status']!.toString(),
      user: json['user']!.toString(),
      command: json['command']!.toString(),
    );
  }

  static Map<String, Object?> portInfoToJson(PortInfo info) {
    return {
      'port': info.port,
      'protocol': info.protocol,
      'pid': info.pid,
      'processName': info.processName,
      'address': info.address,
    };
  }

  static PortInfo portInfoFromJson(Map<String, Object?> json) {
    return PortInfo(
      port: json['port']!.toString(),
      protocol: json['protocol']!.toString(),
      pid: json['pid']!.toString(),
      processName: json['processName']!.toString(),
      address: json['address']!.toString(),
    );
  }

  static Map<String, Object?> serviceInfoToJson(ServiceInfo info) {
    return {
      'name': info.name,
      'status': info.status,
      'isEnabled': info.isEnabled,
      'description': info.description,
    };
  }

  static ServiceInfo serviceInfoFromJson(Map<String, Object?> json) {
    return ServiceInfo(
      name: json['name']!.toString(),
      status: json['status']!.toString(),
      isEnabled: (json['isEnabled'] as bool?) ?? false,
      description: json['description']!.toString(),
    );
  }

  static Map<String, Object?> firewallRuleToJson(FirewallRule info) {
    return {
      'id': info.id,
      'action': info.action,
      'protocol': info.protocol,
      'source': info.source,
      'destination': info.destination,
      'port': info.port,
    };
  }

  static FirewallRule firewallRuleFromJson(Map<String, Object?> json) {
    return FirewallRule(
      id: json['id']!.toString(),
      action: json['action']!.toString(),
      protocol: json['protocol']!.toString(),
      source: json['source']?.toString(),
      destination: json['destination']?.toString(),
      port: json['port']?.toString(),
    );
  }

  static Map<String, Object?> dockerContainerToJson(DockerContainer info) {
    return {
      'id': info.id,
      'name': info.name,
      'status': info.status,
      'image': info.image,
      'ports': info.ports,
      'cpuUsage': info.cpuUsage,
      'memoryUsage': info.memoryUsage,
    };
  }

  static DockerContainer dockerContainerFromJson(Map<String, Object?> json) {
    return DockerContainer(
      id: json['id']!.toString(),
      name: json['name']!.toString(),
      status: json['status']!.toString(),
      image: json['image']!.toString(),
      ports: (json['ports'] as List?)?.map((item) => item.toString()).toList() ?? const <String>[],
      cpuUsage: json['cpuUsage']!.toString(),
      memoryUsage: json['memoryUsage']!.toString(),
    );
  }

  static Map<String, Object?> dockerImageToJson(DockerImage info) {
    return {
      'id': info.id,
      'name': info.name,
      'tag': info.tag,
      'size': info.size,
      'created': info.created,
    };
  }

  static DockerImage dockerImageFromJson(Map<String, Object?> json) {
    return DockerImage(
      id: json['id']!.toString(),
      name: json['name']!.toString(),
      tag: json['tag']!.toString(),
      size: json['size']!.toString(),
      created: json['created']!.toString(),
    );
  }

  static Map<String, Object?> fileInfoToJson(FileInfo info) {
    return {
      'name': info.name,
      'path': info.path,
      'isDirectory': info.isDirectory,
      'size': info.size,
      'modified': info.modified,
      'permissions': info.permissions,
    };
  }

  static FileInfo fileInfoFromJson(Map<String, Object?> json) {
    return FileInfo(
      name: json['name']!.toString(),
      path: json['path']!.toString(),
      isDirectory: (json['isDirectory'] as bool?) ?? false,
      size: json['size']!.toString(),
      modified: json['modified']!.toString(),
      permissions: json['permissions']!.toString(),
    );
  }

  static Map<String, Object?> directoryResolutionToJson(DirectoryResolution item) {
    return {
      'requestedPath': item.requestedPath,
      'resolvedPath': item.resolvedPath,
      'exists': item.exists,
    };
  }

  static DirectoryResolution directoryResolutionFromJson(Map<String, Object?> json) {
    return DirectoryResolution(
      requestedPath: json['requestedPath']!.toString(),
      resolvedPath: json['resolvedPath']!.toString(),
      exists: (json['exists'] as bool?) ?? false,
    );
  }

  static Map<String, Object?> fileListResultToJson(FileListResult item) {
    return {
      'resolvedPath': item.resolvedPath,
      'files': item.files.map(fileInfoToJson).toList(),
    };
  }

  static FileListResult fileListResultFromJson(Map<String, Object?> json) {
    final files = (json['files'] as List?)
            ?.whereType<Map>()
            .map((item) => fileInfoFromJson(item.cast<String, Object?>()))
            .toList() ??
        const <FileInfo>[];
    return FileListResult(
      files: files,
      resolvedPath: json['resolvedPath']!.toString(),
    );
  }
}
