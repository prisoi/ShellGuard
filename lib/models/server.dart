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
      kernelVersion: kernelVersion ?? this.kernelVersion,
      uptime: uptime ?? this.uptime,
    );
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
      kernelVersion: json['kernelVersion'],
      uptime: json['uptime'],
    );
  }
}

class SystemInfo {
  final String osInfo;
  final String kernelVersion;
  final String uptime;
  final int cpuCores;
  final String memoryTotal;
  final String diskTotal;

  SystemInfo({
    required this.osInfo,
    required this.kernelVersion,
    required this.uptime,
    required this.cpuCores,
    required this.memoryTotal,
    required this.diskTotal,
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
  });
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
