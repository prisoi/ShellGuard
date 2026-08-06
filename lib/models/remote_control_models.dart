enum RemoteAuditCategory {
  connection,
  operation,
  ai,
  terminal,
}

class AccessTokenRecord {
  final String id;
  final String tokenValue;
  final String note;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;
  final int connectionCount;

  const AccessTokenRecord({
    required this.id,
    required this.tokenValue,
    required this.note,
    required this.createdAt,
    required this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
    this.connectionCount = 0,
  });

  bool get isRevoked => revokedAt != null;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isAvailable => !isRevoked && !isExpired;

  String get maskedValue {
    if (tokenValue.length <= 10) {
      return tokenValue;
    }
    return '${tokenValue.substring(0, 6)}...${tokenValue.substring(tokenValue.length - 4)}';
  }

  AccessTokenRecord copyWith({
    String? id,
    String? tokenValue,
    String? note,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? lastUsedAt,
    DateTime? revokedAt,
    int? connectionCount,
  }) {
    return AccessTokenRecord(
      id: id ?? this.id,
      tokenValue: tokenValue ?? this.tokenValue,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      revokedAt: revokedAt ?? this.revokedAt,
      connectionCount: connectionCount ?? this.connectionCount,
    );
  }
}

class RemoteAuditRecord {
  final String id;
  final String? accessTokenId;
  final String accessTokenNote;
  final RemoteAuditCategory category;
  final String action;
  final String summary;
  final String detail;
  final String sourceHost;
  final String sourceLabel;
  final String sharedGroupId;
  final String sharedGroupName;
  final String sharedServerId;
  final String sharedServerName;
  final bool success;
  final DateTime createdAt;

  const RemoteAuditRecord({
    required this.id,
    this.accessTokenId,
    this.accessTokenNote = '',
    required this.category,
    required this.action,
    required this.summary,
    this.detail = '',
    this.sourceHost = '',
    this.sourceLabel = '',
    this.sharedGroupId = '',
    this.sharedGroupName = '',
    this.sharedServerId = '',
    this.sharedServerName = '',
    required this.success,
    required this.createdAt,
  });

  String get sessionId {
    final match = RegExp(r'\[\[session_id:([^\]]+)\]\]').firstMatch(detail);
    return match?.group(1)?.trim() ?? '';
  }

  String get taggedServerName {
    final match = RegExp(r'\[\[server_name:([^\]]+)\]\]').firstMatch(detail);
    return match?.group(1)?.trim() ?? '';
  }

  String get connectionId {
    final match = RegExp(r'\[\[connection_id:([^\]]+)\]\]').firstMatch(detail);
    return match?.group(1)?.trim() ?? '';
  }

  String get normalizedDetail {
    return detail
        .replaceAll(RegExp(r'\[\[session_id:[^\]]+\]\]\n?'), '')
        .replaceAll(RegExp(r'\[\[server_name:[^\]]+\]\]\n?'), '')
        .replaceAll(RegExp(r'\[\[connection_id:[^\]]+\]\]\n?'), '')
        .trim();
  }

  String get displayServerName {
    if (sharedServerName.trim().isNotEmpty) {
      return sharedServerName.trim();
    }
    return taggedServerName;
  }

  String get displayGroupName => sharedGroupName.trim();

  String get displaySource {
    final parts = <String>[
      if (sourceHost.trim().isNotEmpty) sourceHost.trim(),
      if (sourceLabel.trim().isNotEmpty) sourceLabel.trim(),
    ];
    return parts.join(' · ');
  }

  String get auditGroupLabel {
    if (category == RemoteAuditCategory.ai) {
      return 'AI助力';
    }
    if (action.startsWith('readonly_')) {
      return '只读访问';
    }
    final lowerAction = action.toLowerCase();
    final lowerSummary = summary.toLowerCase();
    if (lowerAction.contains('firewall') ||
        lowerSummary.contains('ufw ') ||
        lowerSummary.contains('firewall-cmd') ||
        lowerSummary.contains('iptables ')) {
      return '防火墙';
    }
    if (lowerAction.contains('docker') ||
        lowerSummary.contains('docker ')) {
      return 'Docker';
    }
    if (lowerAction.contains('process') ||
        lowerSummary.contains('kill ') ||
        lowerSummary.contains('ps ')) {
      return '进程';
    }
    if (lowerAction.contains('service') ||
        lowerSummary.contains('systemctl ') ||
        lowerSummary.contains('service ')) {
      return '服务';
    }
    if (lowerAction.contains('file') ||
        lowerSummary.contains('mkdir ') ||
        lowerSummary.contains('mv ') ||
        lowerSummary.contains('rm ') ||
        lowerSummary.contains('cat ') ||
        lowerSummary.contains('tee ')) {
      return '文件';
    }
    if (category == RemoteAuditCategory.connection) {
      return '连接';
    }
    if (category == RemoteAuditCategory.terminal) {
      return 'SSH终端';
    }
    return '普通操作';
  }

  String get timelineTitle {
    if (category == RemoteAuditCategory.ai) {
      return switch (action) {
        'create_session' => '创建会话',
        'user_prompt' => '用户提问',
        'execute_step' => '执行步骤',
        'step_skipped' => '跳过步骤',
        'assistant_answer' => '最终回答',
        'review_iteration' => '复盘续执行',
        'plan_failed' => '规划失败',
        _ => action,
      };
    }
    if (category == RemoteAuditCategory.connection) {
      return switch (action) {
        'verify_token' => '导入校验',
        'share_connect' => '共享连接开始',
        'terminal_connect' => '终端连接',
        _ => action,
      };
    }
    if (category == RemoteAuditCategory.terminal) {
      return switch (action) {
        'terminal_open' => '打开终端',
        'terminal_command' => '输入命令',
        'terminal_interrupt' => '发送中断',
        'terminal_close' => '关闭终端',
        _ => action,
      };
    }
    if (action.startsWith('readonly_')) {
      return switch (action) {
        'readonly_dashboard' => '查看资源概览',
        'readonly_processes' => '查看进程列表',
        'readonly_ports' => '查看端口列表',
        'readonly_services' => '查看服务列表',
        'readonly_firewall' => '查看防火墙规则',
        'readonly_docker' => '查看 Docker 状态',
        'readonly_files_resolve' => '解析目录',
        'readonly_files_list' => '查看文件列表',
        'readonly_files_stat' => '读取文件信息',
        _ => '只读访问',
      };
    }
    return action;
  }
}

class AccessTokenValidationResult {
  final bool valid;
  final String message;
  final String? tokenId;
  final String tokenNote;
  final DateTime? expiresAt;

  const AccessTokenValidationResult({
    required this.valid,
    required this.message,
    this.tokenId,
    this.tokenNote = '',
    this.expiresAt,
  });
}
