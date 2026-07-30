import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/server.dart';

class SshService {
  SSHClient? _client;
  bool _isConnected = false;
  String? _errorMessage;

  bool get isConnected => _isConnected;
  String? get errorMessage => _errorMessage;

  Future<bool> connect(Server server) async {
    try {
      _errorMessage = null;
      final socket = await SSHSocket.connect(server.ip, server.port);

      _client = SSHClient(
        socket,
        username: server.username,
        onPasswordRequest: () => server.password,
      );

      await _client!.authenticated;
      _isConnected = true;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      _isConnected = false;
      return false;
    }
  }

  void disconnect() {
    if (_client != null) {
      _client!.close();
      _client = null;
    }
    _isConnected = false;
  }

  Future<String> executeCommand(String command) async {
    if (!_isConnected || _client == null) {
      throw Exception('SSH connection not established');
    }

    final result = await _client!.execute(command);
    return utf8.decode(result as Uint8List);
  }

  Future<SystemInfo> getSystemInfo() async {
    final osInfoResult = await executeCommand(
      'cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d "\\"" || cat /etc/issue 2>/dev/null | head -1 || uname -a',
    );

    final kernelResult = await executeCommand('uname -r');
    final uptimeResult = await executeCommand('uptime -p');
    final cpuCoresResult = await executeCommand('nproc');
    final memoryResult = await executeCommand(
      'free -h | grep Mem | awk \'{print \$2}\'',
    );
    final diskResult = await executeCommand(
      'df -h / | grep / | awk \'{print \$2}\'',
    );

    return SystemInfo(
      osInfo: osInfoResult.trim(),
      kernelVersion: kernelResult.trim(),
      uptime: uptimeResult.trim(),
      cpuCores: int.tryParse(cpuCoresResult.trim()) ?? 0,
      memoryTotal: memoryResult.trim(),
      diskTotal: diskResult.trim(),
    );
  }

  Future<ResourceUsage> getResourceUsage() async {
    final cpuResult = await executeCommand(
      'top -bn1 | grep "Cpu(s)" | sed "s/.*, *\\([0-9.]*\\)%* id.*/\\1/" | awk "{print 100 - \$1}"',
    );

    final memoryResult = await executeCommand(
      'free -h | grep Mem',
    );

    final diskResult = await executeCommand(
      'df -h / | grep /',
    );

    final networkResult = await executeCommand(
      'cat /proc/net/dev | grep -E "(eth|ens|wlan|virbr)" | head -1 | awk \'{print "TX:" \$10 " RX:" \$9}\'',
    );

    final connectionsResult = await executeCommand(
      'ss -tuln | wc -l',
    );

    final cpuUsage = double.tryParse(cpuResult.trim()) ?? 0.0;

    final memoryParts = memoryResult.trim().split(RegExp(r'\s+'));
    final memoryUsed = memoryParts.length > 2 ? memoryParts[2] : '0';
    final memoryTotal = memoryParts.length > 1 ? memoryParts[1] : '0';
    final double memoryPercent = memoryParts.length > 3
        ? ((double.tryParse(memoryParts[2].replaceAll('G', '')) ?? 0.0) /
            (double.tryParse(memoryParts[1].replaceAll('G', '')) ?? 1.0) *
            100.0)
        : 0.0;

    final diskParts = diskResult.trim().split(RegExp(r'\s+'));
    final diskUsed = diskParts.length > 2 ? diskParts[2] : '0';
    final diskTotal = diskParts.length > 1 ? diskParts[1] : '0';
    final diskPercent = double.tryParse(
          diskParts.length > 4 ? diskParts[4].replaceAll('%', '') : '0',
        ) ??
        0;

    return ResourceUsage(
      cpuUsage: cpuUsage.clamp(0.0, 100.0),
      memoryUsed: memoryUsed,
      memoryTotal: memoryTotal,
      memoryPercent: memoryPercent.clamp(0.0, 100.0),
      diskUsed: diskUsed,
      diskTotal: diskTotal,
      diskPercent: diskPercent,
      networkUpload: networkResult.contains('TX:')
          ? networkResult.split('TX:')[1].split(' ')[0]
          : '0',
      networkDownload: networkResult.contains('RX:')
          ? networkResult.split('RX:')[1].trim()
          : '0',
      activeConnections: int.tryParse(connectionsResult.trim()) ?? 0,
    );
  }

  Future<List<ProcessInfo>> getProcessList() async {
    final result = await executeCommand(
      'ps aux --sort=-%cpu | head -21 | tail -20',
    );

    final lines = result.trim().split('\n');
    final processes = <ProcessInfo>[];

    for (final line in lines) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 11) {
        processes.add(ProcessInfo(
          pid: int.tryParse(parts[1]) ?? 0,
          name: parts[10],
          cpuPercent: double.tryParse(parts[2]) ?? 0,
          memoryPercent: double.tryParse(parts[3]) ?? 0,
          status: parts[7],
          user: parts[0],
          command: line.substring(line.indexOf(parts[10])),
        ));
      }
    }

    return processes;
  }

  Future<List<PortInfo>> getPortList() async {
    final result = await executeCommand('ss -tulnp');

    final lines = result.trim().split('\n');
    final ports = <PortInfo>[];

    for (final line in lines) {
      if (line.isEmpty || line.startsWith('State')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 5) {
        final protocol = parts[0];
        final address = parts[4];
        final portParts = address.split(':');
        final port = portParts.isNotEmpty ? portParts.last : '';

        String pid = '';
        String processName = '';
        if (parts.length >= 7) {
          final pidPart = parts[6];
          if (pidPart.contains(',')) {
            final pidParts = pidPart.split(',');
            pid = pidParts[0].replaceAll('pid=', '');
            processName = pidParts[1].replaceAll('fd=', '');
          }
        }

        ports.add(PortInfo(
          port: port,
          protocol: protocol.contains('tcp') ? 'TCP' : 'UDP',
          pid: pid,
          processName: processName,
          address: address,
        ));
      }
    }

    return ports;
  }

  Future<List<FirewallRule>> getFirewallRules() async {
    final result = await executeCommand('sudo ufw status numbered 2>/dev/null || sudo iptables -L');

    final lines = result.trim().split('\n');
    final rules = <FirewallRule>[];
    int id = 1;

    for (final line in lines) {
      if (line.isEmpty || line.startsWith('Status') || line.startsWith('Chain')) continue;
      if (line.contains('ALLOW') || line.contains('DENY') || line.contains('REJECT')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        String action = 'ALLOW';
        String protocol = 'ALL';
        String? port;
        String? source;

        if (line.contains('DENY')) action = 'DENY';
        if (line.contains('REJECT')) action = 'REJECT';

        for (final part in parts) {
          if (part.contains('/')) {
            protocol = part.split('/')[1].toUpperCase();
            port = part.split('/')[0];
          } else if (part.contains('from')) {
            source = parts[parts.indexOf('from') + 1];
          }
        }

        rules.add(FirewallRule(
          id: id.toString(),
          action: action,
          protocol: protocol,
          source: source,
          destination: null,
          port: port,
        ));
        id++;
      }
    }

    return rules;
  }

  Future<String> manageFirewall({
    required String action,
    String? port,
    String? protocol,
    String? source,
  }) async {
    String command = 'sudo ufw ';

    switch (action) {
      case 'enable':
        command += 'enable';
        break;
      case 'disable':
        command += 'disable';
        break;
      case 'allow':
        if (port != null) {
          command += 'allow $port/${protocol ?? 'tcp'}';
        } else if (source != null) {
          command += 'allow from $source';
        }
        break;
      case 'deny':
        if (port != null) {
          command += 'deny $port/${protocol ?? 'tcp'}';
        } else if (source != null) {
          command += 'deny from $source';
        }
        break;
      case 'delete':
        if (port != null) {
          command += 'delete allow $port/${protocol ?? 'tcp'}';
        }
        break;
      case 'reset':
        command += 'reset';
        break;
      default:
        return 'Unknown action';
    }

    return await executeCommand(command);
  }

  Future<List<ServiceInfo>> getServiceList() async {
    final result = await executeCommand(
      'systemctl list-units --type=service --all --no-pager 2>/dev/null | head -30',
    );

    final lines = result.trim().split('\n');
    final services = <ServiceInfo>[];

    for (final line in lines) {
      if (line.isEmpty || line.startsWith('UNIT')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3) {
        final name = parts[0].replaceAll('.service', '');
        final status = parts[2];
        services.add(ServiceInfo(
          name: name,
          status: status,
          isEnabled: false,
          description: parts.sublist(3).join(' '),
        ));
      }
    }

    return services;
  }

  Future<String> manageService({
    required String serviceName,
    required String action,
  }) async {
    final command = 'sudo systemctl $action $serviceName.service';
    return await executeCommand(command);
  }

  Future<List<DockerContainer>> getDockerContainers() async {
    final result = await executeCommand(
      'docker ps -a --format "{{.ID}}|{{.Names}}|{{.Status}}|{{.Image}}|{{.Ports}}" 2>/dev/null || echo "Docker not installed"',
    );

    if (result.contains('Docker not installed')) {
      return [];
    }

    final lines = result.trim().split('\n');
    final containers = <DockerContainer>[];

    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length >= 5) {
        containers.add(DockerContainer(
          id: parts[0].substring(0, 12),
          name: parts[1],
          status: parts[2],
          image: parts[3],
          ports: parts[4].split(',').map((p) => p.trim()).where((p) => p.isNotEmpty).toList(),
          cpuUsage: '',
          memoryUsage: '',
        ));
      }
    }

    return containers;
  }

  Future<String> manageContainer({
    required String containerId,
    required String action,
  }) async {
    final command = 'docker $action $containerId';
    return await executeCommand(command);
  }

  Future<List<DockerImage>> getDockerImages() async {
    final result = await executeCommand(
      'docker images --format "{{.ID}}|{{.Repository}}|{{.Tag}}|{{.Size}}|{{.CreatedAt}}" 2>/dev/null || echo "Docker not installed"',
    );

    if (result.contains('Docker not installed')) {
      return [];
    }

    final lines = result.trim().split('\n');
    final images = <DockerImage>[];

    for (final line in lines) {
      final parts = line.split('|');
      if (parts.length >= 5) {
        images.add(DockerImage(
          id: parts[0].substring(0, 12),
          name: parts[1],
          tag: parts[2],
          size: parts[3],
          created: parts[4],
        ));
      }
    }

    return images;
  }

  Future<String> deleteImage({required String imageId}) async {
    final command = 'docker rmi $imageId';
    return await executeCommand(command);
  }

  Future<List<FileInfo>> listFiles(String path) async {
    final result = await executeCommand(
      'ls -la "$path" 2>/dev/null',
    );

    final lines = result.trim().split('\n');
    final files = <FileInfo>[];

    for (final line in lines) {
      if (line.isEmpty || line.startsWith('total')) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 9) {
        files.add(FileInfo(
          name: parts[8],
          path: '$path/${parts[8]}',
          isDirectory: parts[0].startsWith('d'),
          size: parts[4],
          modified: '${parts[5]} ${parts[6]} ${parts[7]}',
          permissions: parts[0],
        ));
      }
    }

    return files;
  }

  Future<String> createDirectory(String path) async {
    return await executeCommand('mkdir -p "$path"');
  }

  Future<String> deleteFile(String path) async {
    return await executeCommand('rm -rf "$path"');
  }

  Future<String> renameFile(String oldPath, String newPath) async {
    return await executeCommand('mv "$oldPath" "$newPath"');
  }

  Future<String> readFile(String path) async {
    return await executeCommand('cat "$path" 2>/dev/null');
  }

  Future<String> writeFile(String path, String content) async {
    final escapedContent = content.replaceAll('\'', '\\\'');
    return await executeCommand('echo \'$escapedContent\' > "$path"');
  }

  Future<String> getCurrentDirectory() async {
    return await executeCommand('pwd');
  }

  Future<bool> checkConnection() async {
    if (!_isConnected || _client == null) {
      return false;
    }
    try {
      await executeCommand('echo "OK"');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> installTool(String toolName) async {
    final command = 'sudo apt update && sudo apt install -y $toolName';
    return await executeCommand(command);
  }

  Future<bool> checkToolInstalled(String toolName) async {
    final result = await executeCommand('which $toolName 2>/dev/null');
    return result.trim().isNotEmpty;
  }
}