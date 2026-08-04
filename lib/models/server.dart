class Server {
  final String id;
  final String name;
  final String ip;
  final int port;
  final String username;
  final String password;
  final String? privateKey;
  final String group;
  final List<String> tags;
  final bool isOnline;
  final String? osInfo;
  final String? osId;
  final String? osName;
  final String? osVersion;
  final String? osFamily;
  final String? packageManager;
  final String? serviceManager;
  final String? firewallBackend;
  final String? kernelVersion;
  final String? uptime;

  Server({
    required this.id,
    required this.name,
    required this.ip,
    required this.port,
    required this.username,
    required this.password,
    this.privateKey,
    this.group = '默认分组',
    this.tags = const [],
    this.isOnline = false,
    this.osInfo,
    this.osId,
    this.osName,
    this.osVersion,
    this.osFamily,
    this.packageManager,
    this.serviceManager,
    this.firewallBackend,
    this.kernelVersion,
    this.uptime,
  });

  Server copyWith({
    String? id,
    String? name,
    String? ip,
    int? port,
    String? username,
    String? password,
    String? privateKey,
    String? group,
    List<String>? tags,
    bool? isOnline,
    String? osInfo,
    String? osId,
    String? osName,
    String? osVersion,
    String? osFamily,
    String? packageManager,
    String? serviceManager,
    String? firewallBackend,
    String? kernelVersion,
    String? uptime,
  }) {
    return Server(
      id: id ?? this.id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      privateKey: privateKey ?? this.privateKey,
      group: group ?? this.group,
      tags: tags ?? this.tags,
      isOnline: isOnline ?? this.isOnline,
      osInfo: osInfo ?? this.osInfo,
      osId: osId ?? this.osId,
      osName: osName ?? this.osName,
      osVersion: osVersion ?? this.osVersion,
      osFamily: osFamily ?? this.osFamily,
      packageManager: packageManager ?? this.packageManager,
      serviceManager: serviceManager ?? this.serviceManager,
      firewallBackend: firewallBackend ?? this.firewallBackend,
      kernelVersion: kernelVersion ?? this.kernelVersion,
      uptime: uptime ?? this.uptime,
    );
  }

  String get osDisplayLabel {
    final primary = (osName?.trim().isNotEmpty ?? false)
        ? osName!.trim()
        : (osInfo?.trim().isNotEmpty ?? false)
            ? osInfo!.trim()
            : '未知 Linux';
    final version = osVersion?.trim() ?? '';
    if (version.isNotEmpty && !primary.contains(version)) {
      return '$primary $version';
    }
    return primary;
  }

  String get platformSummary {
    final parts = <String>[
      osDisplayLabel,
      if (osFamily?.trim().isNotEmpty ?? false) osFamily!.trim(),
      if (packageManager?.trim().isNotEmpty ?? false) 'pkg:${packageManager!.trim()}',
      if (firewallBackend?.trim().isNotEmpty ?? false) 'fw:${firewallBackend!.trim()}',
    ];
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ip': ip,
      'port': port,
      'username': username,
      'password': password,
      'privateKey': privateKey,
      'group': group,
      'tags': tags,
      'isOnline': isOnline,
      'osInfo': osInfo,
      'osId': osId,
      'osName': osName,
      'osVersion': osVersion,
      'osFamily': osFamily,
      'packageManager': packageManager,
      'serviceManager': serviceManager,
      'firewallBackend': firewallBackend,
      'kernelVersion': kernelVersion,
      'uptime': uptime,
    };
  }

  factory Server.fromJson(Map<String, dynamic> json) {
    return Server(
      id: json['id'],
      name: json['name'],
      ip: json['ip'],
      port: json['port'],
      username: json['username'],
      password: json['password'],
      privateKey: json['privateKey'],
      group: json['group'] ?? '默认分组',
      tags: List<String>.from(json['tags'] ?? []),
      isOnline: json['isOnline'] ?? false,
      osInfo: json['osInfo'],
      osId: json['osId'],
      osName: json['osName'],
      osVersion: json['osVersion'],
      osFamily: json['osFamily'],
      packageManager: json['packageManager'],
      serviceManager: json['serviceManager'],
      firewallBackend: json['firewallBackend'],
      kernelVersion: json['kernelVersion'],
      uptime: json['uptime'],
    );
  }
}

class SystemInfo {
  final String osInfo;
  final String osId;
  final String osName;
  final String osVersion;
  final String osFamily;
  final String packageManager;
  final String serviceManager;
  final String firewallBackend;
  final String kernelVersion;
  final String uptime;
  final int cpuCores;
  final String memoryTotal;
  final String diskTotal;

  SystemInfo({
    required this.osInfo,
    this.osId = '',
    this.osName = '',
    this.osVersion = '',
    this.osFamily = '',
    this.packageManager = '',
    this.serviceManager = '',
    this.firewallBackend = '',
    required this.kernelVersion,
    required this.uptime,
    required this.cpuCores,
    required this.memoryTotal,
    required this.diskTotal,
  });

  String get osDisplayLabel {
    final primary = osName.trim().isNotEmpty
        ? osName.trim()
        : osInfo.trim().isNotEmpty
            ? osInfo.trim()
            : '未知 Linux';
    if (osVersion.trim().isNotEmpty && !primary.contains(osVersion.trim())) {
      return '$primary ${osVersion.trim()}';
    }
    return primary;
  }
}

class LinuxPlatformSupport {
  static String detectFamily({
    required String osId,
    required String osInfo,
    String idLike = '',
  }) {
    final joined = '$osId $idLike $osInfo'.toLowerCase();
    if (joined.contains('ubuntu') || joined.contains('debian')) {
      return 'debian';
    }
    if (joined.contains('rhel') ||
        joined.contains('redhat') ||
        joined.contains('centos') ||
        joined.contains('rocky') ||
        joined.contains('almalinux') ||
        joined.contains('fedora') ||
        joined.contains('ol ') ||
        joined.contains('oracle linux')) {
      return 'redhat';
    }
    if (joined.contains('suse') || joined.contains('opensuse')) {
      return 'suse';
    }
    if (joined.contains('arch')) {
      return 'arch';
    }
    if (joined.contains('alpine')) {
      return 'alpine';
    }
    return 'linux';
  }

  static String detectPackageManager({
    required String family,
    required List<String> availableCommands,
  }) {
    if (availableCommands.contains('apt-get')) return 'apt';
    if (availableCommands.contains('dnf')) return 'dnf';
    if (availableCommands.contains('yum')) return 'yum';
    if (availableCommands.contains('zypper')) return 'zypper';
    if (availableCommands.contains('pacman')) return 'pacman';
    if (availableCommands.contains('apk')) return 'apk';
    switch (family) {
      case 'debian':
        return 'apt';
      case 'redhat':
        return 'yum';
      case 'suse':
        return 'zypper';
      case 'arch':
        return 'pacman';
      case 'alpine':
        return 'apk';
      default:
        return 'unknown';
    }
  }

  static String detectServiceManager(List<String> availableCommands) {
    if (availableCommands.contains('systemctl')) {
      return 'systemd';
    }
    if (availableCommands.contains('service')) {
      return 'sysvinit';
    }
    return 'unknown';
  }

  static String detectFirewallBackend(List<String> availableCommands) {
    if (availableCommands.contains('ufw')) {
      return 'ufw';
    }
    if (availableCommands.contains('firewall-cmd')) {
      return 'firewalld';
    }
    if (availableCommands.contains('iptables')) {
      return 'iptables';
    }
    return 'none';
  }

  static String resolveInstallPackageName(String toolName, String packageManager) {
    switch (toolName) {
      case 'dig':
        return packageManager == 'apt' ? 'dnsutils' : 'bind-utils';
      case 'nc':
        if (packageManager == 'apt') return 'netcat-openbsd';
        if (packageManager == 'apk') return 'netcat-openbsd';
        return 'nmap-ncat';
      case 'iproute2':
        if (packageManager == 'yum' || packageManager == 'dnf') return 'iproute';
        return 'iproute2';
      case 'docker':
        if (packageManager == 'apt') return 'docker.io';
        return 'docker';
      case 'ufw':
        if (packageManager == 'yum' || packageManager == 'dnf') return 'firewalld';
        return 'ufw';
      case 'pip':
        if (packageManager == 'apk') return 'py3-pip';
        return 'python3-pip';
      case 'python3':
        if (packageManager == 'apk') return 'python3';
        return 'python3';
      default:
        return toolName;
    }
  }

  static String buildInstallCommand({
    required String packageManager,
    required String toolName,
  }) {
    if (toolName == 'uv') {
      return _buildUvInstallCommand();
    }
    final packageName = resolveInstallPackageName(toolName, packageManager);
    switch (packageManager) {
      case 'apt':
        return _buildAptInstallCommand(packageName);
      case 'dnf':
        return 'dnf install -y $packageName';
      case 'yum':
        return 'yum install -y $packageName';
      case 'zypper':
        return 'zypper --non-interactive install $packageName';
      case 'pacman':
        return 'pacman -Sy --noconfirm $packageName';
      case 'apk':
        return 'apk add --no-cache $packageName';
      default:
        return 'echo "Unsupported package manager: $packageManager"';
    }
  }

  static String _buildAptInstallCommand(String packageName) {
    return "bash -lc '"
        "set -e; "
        "export DEBIAN_FRONTEND=noninteractive; "
        "if apt-get install -y $packageName; then "
        "  exit 0; "
        "fi; "
        "if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then "
        "  apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources "
        "          -o Dir::Etc::sourceparts=/dev/null "
        "          -o Acquire::AllowReleaseInfoChange=true "
        "          update; "
        "  apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list.d/ubuntu.sources "
        "          -o Dir::Etc::sourceparts=/dev/null "
        "          install -y $packageName; "
        "elif [ -f /etc/apt/sources.list ]; then "
        "  apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list "
        "          -o Dir::Etc::sourceparts=/dev/null "
        "          -o Acquire::AllowReleaseInfoChange=true "
        "          update; "
        "  apt-get -o Dir::Etc::sourcelist=/etc/apt/sources.list "
        "          -o Dir::Etc::sourceparts=/dev/null "
        "          install -y $packageName; "
        "else "
        "  echo \"APT 软件源不可用，请先检查系统软件源配置\"; "
        "  exit 1; "
        "fi"
        "'";
  }

  static String _buildUvInstallCommand() {
    return 'bash -lc \''
        'if command -v curl >/dev/null 2>&1; then '
        'curl -LsSf https://astral.sh/uv/install.sh | sh; '
        'elif command -v wget >/dev/null 2>&1; then '
        'wget -qO- https://astral.sh/uv/install.sh | sh; '
        'else '
        'echo "uv 安装需要 curl 或 wget"; exit 1; '
        'fi'
        '\'';
  }

  static String buildServiceCommand({
    required String serviceManager,
    required String serviceName,
    required String action,
  }) {
    final normalizedService = serviceName.endsWith('.service')
        ? serviceName
        : '$serviceName.service';
    if (serviceManager == 'systemd') {
      return 'systemctl $action $normalizedService';
    }
    return 'service $serviceName $action';
  }

  static String buildServiceLogCommand({
    required String serviceManager,
    required String serviceName,
    int lines = 80,
  }) {
    final normalizedService = serviceName.endsWith('.service')
        ? serviceName
        : '$serviceName.service';
    if (serviceManager == 'systemd') {
      return 'journalctl -u $normalizedService -n $lines --no-pager 2>/dev/null';
    }
    return 'tail -n $lines /var/log/messages 2>/dev/null || tail -n $lines /var/log/syslog 2>/dev/null';
  }

  static String buildUfwCommand({
    required String action,
    String? port,
    String? protocol,
    String? source,
    String? ruleNumber,
    String? ruleAction,
  }) {
    final normalizedPort = port?.trim();
    final normalizedProtocol = protocol?.trim().toLowerCase();
    final normalizedSource = source?.trim();
    final ruleVerb = ruleAction?.trim().toLowerCase() ?? 'allow';

    String buildRuleCommand(String verb) {
      if (normalizedSource != null && normalizedSource.isNotEmpty) {
        if (normalizedPort != null && normalizedPort.isNotEmpty) {
          return '$verb from $normalizedSource to any port $normalizedPort'
              '${normalizedProtocol == null || normalizedProtocol.isEmpty ? '' : ' proto $normalizedProtocol'}';
        }
        return '$verb from $normalizedSource';
      }
      if (normalizedPort != null && normalizedPort.isNotEmpty) {
        return '$verb $normalizedPort/${normalizedProtocol ?? 'tcp'}';
      }
      throw Exception('Firewall rule requires port or source');
    }

    switch (action) {
      case 'enable':
        return 'ufw enable';
      case 'disable':
        return 'ufw disable';
      case 'allow':
        return 'ufw ${buildRuleCommand('allow')}';
      case 'deny':
        return 'ufw ${buildRuleCommand('deny')}';
      case 'delete':
        if (ruleNumber != null && ruleNumber.trim().isNotEmpty) {
          return 'ufw --force delete ${ruleNumber.trim()}';
        }
        return 'ufw delete ${buildRuleCommand(ruleVerb)}';
      case 'reset':
        return 'ufw reset';
      default:
        throw Exception('Unknown firewall action');
    }
  }

  static String buildFirewalldCommand({
    required String action,
    String? port,
    String? protocol,
    String? source,
    String? ruleAction,
  }) {
    final normalizedPort = port?.trim();
    final normalizedProtocol = (protocol?.trim().isEmpty ?? true)
        ? 'tcp'
        : protocol!.trim().toLowerCase();
    final normalizedSource = source?.trim();
    final verb = (ruleAction?.trim().toLowerCase() ?? action).toLowerCase();
    final richAction = verb == 'deny' ? 'reject' : 'accept';

    String buildRichRule() {
      if (normalizedPort != null && normalizedPort.isNotEmpty) {
        final sourceSegment = normalizedSource == null || normalizedSource.isEmpty
            ? ''
            : ' source address="$normalizedSource"';
        return 'rule family="ipv4"$sourceSegment port port="$normalizedPort" protocol="$normalizedProtocol" $richAction';
      }
      if (normalizedSource != null && normalizedSource.isNotEmpty) {
        return 'rule family="ipv4" source address="$normalizedSource" $richAction';
      }
      throw Exception('Firewall rule requires port or source');
    }

    switch (action) {
      case 'enable':
        return 'systemctl enable --now firewalld';
      case 'disable':
        return 'systemctl disable --now firewalld';
      case 'allow':
        if ((normalizedSource == null || normalizedSource.isEmpty) &&
            normalizedPort != null &&
            normalizedPort.isNotEmpty) {
          return 'firewall-cmd --permanent --add-port=$normalizedPort/$normalizedProtocol && firewall-cmd --reload';
        }
        return 'firewall-cmd --permanent --add-rich-rule=\'${buildRichRule()}\' && firewall-cmd --reload';
      case 'deny':
        return 'firewall-cmd --permanent --add-rich-rule=\'${buildRichRule()}\' && firewall-cmd --reload';
      case 'delete':
        if ((normalizedSource == null || normalizedSource.isEmpty) &&
            verb == 'allow' &&
            normalizedPort != null &&
            normalizedPort.isNotEmpty) {
          return 'firewall-cmd --permanent --remove-port=$normalizedPort/$normalizedProtocol && firewall-cmd --reload';
        }
        return 'firewall-cmd --permanent --remove-rich-rule=\'${buildRichRule()}\' && firewall-cmd --reload';
      case 'reset':
        throw Exception('当前 firewalld 后端暂不支持一键重置，请手动清理规则');
      default:
        throw Exception('Unknown firewall action');
    }
  }
}

class GpuDeviceUsage {
  final int index;
  final String vendor;
  final String name;
  final double utilizationPercent;
  final String memoryUsed;
  final String memoryTotal;
  final double memoryPercent;
  final String? temperature;
  final String? note;

  const GpuDeviceUsage({
    required this.index,
    required this.vendor,
    required this.name,
    required this.utilizationPercent,
    required this.memoryUsed,
    required this.memoryTotal,
    required this.memoryPercent,
    this.temperature,
    this.note,
  });
}

class ResourceUsage {
  final double cpuUsage;
  final String memoryUsed;
  final String memoryTotal;
  final double memoryPercent;
  final String diskUsed;
  final String diskTotal;
  final double diskPercent;
  final String networkUpload;
  final String networkDownload;
  final int activeConnections;
  final List<GpuDeviceUsage> gpuDevices;

  ResourceUsage({
    required this.cpuUsage,
    required this.memoryUsed,
    required this.memoryTotal,
    required this.memoryPercent,
    required this.diskUsed,
    required this.diskTotal,
    required this.diskPercent,
    required this.networkUpload,
    required this.networkDownload,
    required this.activeConnections,
    this.gpuDevices = const <GpuDeviceUsage>[],
  });

  bool get hasGpu => gpuDevices.isNotEmpty;

  GpuDeviceUsage? get primaryGpu => gpuDevices.isEmpty ? null : gpuDevices.first;
}

class ProcessInfo {
  final int pid;
  final String name;
  final double cpuPercent;
  final double memoryPercent;
  final String status;
  final String user;
  final String command;

  ProcessInfo({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memoryPercent,
    required this.status,
    required this.user,
    required this.command,
  });
}

class PortInfo {
  final String port;
  final String protocol;
  final String pid;
  final String processName;
  final String address;

  PortInfo({
    required this.port,
    required this.protocol,
    required this.pid,
    required this.processName,
    required this.address,
  });
}

class FirewallRule {
  final String id;
  final String action;
  final String protocol;
  final String? source;
  final String? destination;
  final String? port;

  FirewallRule({
    required this.id,
    required this.action,
    required this.protocol,
    this.source,
    this.destination,
    this.port,
  });
}

class ServiceInfo {
  final String name;
  final String status;
  final bool isEnabled;
  final String description;

  ServiceInfo({
    required this.name,
    required this.status,
    required this.isEnabled,
    required this.description,
  });
}

class DockerContainer {
  final String id;
  final String name;
  final String status;
  final String image;
  final List<String> ports;
  final String cpuUsage;
  final String memoryUsage;

  DockerContainer({
    required this.id,
    required this.name,
    required this.status,
    required this.image,
    required this.ports,
    required this.cpuUsage,
    required this.memoryUsage,
  });
}

class DockerImage {
  final String id;
  final String name;
  final String tag;
  final String size;
  final String created;

  DockerImage({
    required this.id,
    required this.name,
    required this.tag,
    required this.size,
    required this.created,
  });
}

class FileInfo {
  final String name;
  final String path;
  final bool isDirectory;
  final String size;
  final String modified;
  final String permissions;

  FileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.permissions,
  });
}

class ToolInfo {
  final String name;
  final String category;
  final String description;
  final String command;
  final bool isInstalled;

  ToolInfo({
    required this.name,
    required this.category,
    required this.description,
    required this.command,
    this.isInstalled = false,
  });

  ToolInfo copyWith({
    String? name,
    String? category,
    String? description,
    String? command,
    bool? isInstalled,
  }) {
    return ToolInfo(
      name: name ?? this.name,
      category: category ?? this.category,
      description: description ?? this.description,
      command: command ?? this.command,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }
}

class OperationLog {
  final String id;
  final String command;
  final String serverId;
  final String serverName;
  final DateTime timestamp;
  final String result;

  OperationLog({
    required this.id,
    required this.command,
    required this.serverId,
    required this.serverName,
    required this.timestamp,
    required this.result,
  });
}

enum AiTaskStatus {
  analyzing,
  waitingConfirm,
  running,
  success,
  failed,
  interrupted,
}

enum AiStepStatus {
  pending,
  waitingConfirm,
  running,
  success,
  failed,
  skipped,
  interrupted,
}

enum AiRiskLevel {
  safe,
  low,
  medium,
  high,
}

enum AiMessageRole {
  user,
  assistant,
  summary,
}

class LlmProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final int maxTokens;
  final bool enabled;
  final bool isDefault;

  const LlmProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.maxTokens = 4096,
    this.enabled = true,
    this.isDefault = false,
  });

  String get maskedApiKey {
    if (apiKey.isEmpty) {
      return '';
    }
    if (apiKey.length <= 8) {
      return '*' * apiKey.length;
    }
    return '${apiKey.substring(0, 3)}${'*' * (apiKey.length - 5)}${apiKey.substring(apiKey.length - 2)}';
  }

  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    int? maxTokens,
    bool? enabled,
    bool? isDefault,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      maxTokens: maxTokens ?? this.maxTokens,
      enabled: enabled ?? this.enabled,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'model': model,
      'maxTokens': maxTokens,
      'enabled': enabled,
      'isDefault': isDefault,
    };
  }

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    return LlmProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: json['apiKey'] as String,
      model: json['model'] as String,
      maxTokens: (json['maxTokens'] as int?) ?? 4096,
      enabled: (json['enabled'] as bool?) ?? true,
      isDefault: (json['isDefault'] as bool?) ?? false,
    );
  }
}

class AiTaskRecord {
  final String id;
  final String serverId;
  final String serverName;
  final String prompt;
  final String analysis;
  final String finalAnswer;
  final AiTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? errorMessage;

  const AiTaskRecord({
    required this.id,
    required this.serverId,
    required this.serverName,
    required this.prompt,
    required this.analysis,
    this.finalAnswer = '',
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.errorMessage,
  });

  AiTaskRecord copyWith({
    String? id,
    String? serverId,
    String? serverName,
    String? prompt,
    String? analysis,
    String? finalAnswer,
    AiTaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? errorMessage,
  }) {
    return AiTaskRecord(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      prompt: prompt ?? this.prompt,
      analysis: analysis ?? this.analysis,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AiSessionRecord {
  final String id;
  final String serverId;
  final String serverName;
  final String title;
  final String compressedContext;
  final AiTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? errorMessage;

  const AiSessionRecord({
    required this.id,
    required this.serverId,
    required this.serverName,
    required this.title,
    this.compressedContext = '',
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.errorMessage,
  });

  AiSessionRecord copyWith({
    String? id,
    String? serverId,
    String? serverName,
    String? title,
    String? compressedContext,
    AiTaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? errorMessage,
  }) {
    return AiSessionRecord(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      serverName: serverName ?? this.serverName,
      title: title ?? this.title,
      compressedContext: compressedContext ?? this.compressedContext,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AiMessageRecord {
  final String id;
  final String sessionId;
  final AiMessageRole role;
  final String content;
  final String finalAnswer;
  final String analysis;
  final AiTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? errorMessage;

  const AiMessageRecord({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.content,
    this.finalAnswer = '',
    this.analysis = '',
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.errorMessage,
  });

  AiMessageRecord copyWith({
    String? id,
    String? sessionId,
    AiMessageRole? role,
    String? content,
    String? finalAnswer,
    String? analysis,
    AiTaskStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? errorMessage,
  }) {
    return AiMessageRecord(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      role: role ?? this.role,
      content: content ?? this.content,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      analysis: analysis ?? this.analysis,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AiStepRecord {
  final String id;
  final String taskId;
  final String title;
  final String command;
  final String summary;
  final AiStepStatus status;
  final AiRiskLevel riskLevel;
  final bool requiresConfirmation;
  final int orderIndex;
  final String output;
  final String errorOutput;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const AiStepRecord({
    required this.id,
    required this.taskId,
    required this.title,
    required this.command,
    required this.summary,
    required this.status,
    required this.riskLevel,
    required this.requiresConfirmation,
    required this.orderIndex,
    this.output = '',
    this.errorOutput = '',
    this.startedAt,
    this.finishedAt,
  });

  AiStepRecord copyWith({
    String? id,
    String? taskId,
    String? title,
    String? command,
    String? summary,
    AiStepStatus? status,
    AiRiskLevel? riskLevel,
    bool? requiresConfirmation,
    int? orderIndex,
    String? output,
    String? errorOutput,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    return AiStepRecord(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      title: title ?? this.title,
      command: command ?? this.command,
      summary: summary ?? this.summary,
      status: status ?? this.status,
      riskLevel: riskLevel ?? this.riskLevel,
      requiresConfirmation: requiresConfirmation ?? this.requiresConfirmation,
      orderIndex: orderIndex ?? this.orderIndex,
      output: output ?? this.output,
      errorOutput: errorOutput ?? this.errorOutput,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }
}
