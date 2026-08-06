import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/ssh_manager.dart';
import '../../models/remote_control_models.dart';
import '../../models/server.dart';
import '../../models/share_listener_config.dart';
import '../../services/storage_service.dart';
import 'share_auth.dart';
import 'share_audit_service.dart';
import 'share_protocol.dart';

class _SharedTerminalOutputChunk {
  final int seq;
  final String text;

  const _SharedTerminalOutputChunk({
    required this.seq,
    required this.text,
  });

  Map<String, Object?> toJson() {
    return {
      'seq': seq,
      'text': text,
    };
  }
}

class _SharedTerminalSessionState {
  static const int _maxTranscriptChars = 16000;

  final String sessionId;
  final String serverId;
  final String serverName;
  final String sourceHost;
  final String sourceLabel;
  final String sharedGroupId;
  final String sharedGroupName;
  final AccessTokenRecord? token;
  final ShareAuditService auditService;
  final SshManager manager;
  final SshTerminalSessionHandle handle;

  final List<_SharedTerminalOutputChunk> _chunks = <_SharedTerminalOutputChunk>[];
  final List<Completer<void>> _waiters = <Completer<void>>[];
  final StringBuffer _pendingInput = StringBuffer();
  final StringBuffer _transcript = StringBuffer();

  int _nextSeq = 0;
  int? _exitCode;
  bool _disconnected = false;
  bool _closed = false;
  bool _transcriptTruncated = false;
  bool _lastInputEndedWithNewline = false;

  _SharedTerminalSessionState({
    required this.sessionId,
    required this.serverId,
    required this.serverName,
    required this.sourceHost,
    required this.sourceLabel,
    required this.sharedGroupId,
    required this.sharedGroupName,
    required this.token,
    required this.auditService,
    required this.manager,
    required this.handle,
  });

  bool get isClosed => _closed;

  Future<void> logSessionOpened() {
    return _logAudit(
      action: 'terminal_open',
      summary: '打开 SSH 终端',
      detail: 'server=$serverName',
      success: true,
    );
  }

  void addOutput(String text) {
    if (text.isEmpty || _closed) {
      return;
    }
    _chunks.add(_SharedTerminalOutputChunk(seq: ++_nextSeq, text: text));
    _appendTranscript('[out] ', text);
    _notifyWaiters();
  }

  Future<void> write(String data) async {
    if (_closed || data.isEmpty) {
      return;
    }
    handle.write(data);
    _appendTranscript('[in] ', _sanitizeInputForTranscript(data));
    await _captureInputAudit(data);
  }

  void resize(int columns, int rows, [int pixelWidth = 0, int pixelHeight = 0]) {
    if (_closed) {
      return;
    }
    handle.resize(columns, rows, pixelWidth, pixelHeight);
  }

  Future<Map<String, Object?>> read({
    required int afterSeq,
    required int waitMs,
  }) async {
    _chunks.removeWhere((item) => item.seq <= afterSeq);
    if (_chunks.isEmpty && !_closed) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      try {
        await waiter.future.timeout(Duration(milliseconds: waitMs));
      } on TimeoutException {
        // Long-poll timeout means there is no new terminal output yet.
      } finally {
        _waiters.remove(waiter);
      }
    }
    return {
      'chunks': _chunks.map((item) => item.toJson()).toList(),
      'closed': _closed,
      'exitCode': _exitCode,
      'disconnected': _disconnected,
    };
  }

  Future<void> closeFromClient() async {
    await _finish(
      invokeHandleClose: true,
      disconnected: false,
      closeSummary: '客户端关闭 SSH 终端',
    );
  }

  Future<void> closeFromRemote(SshTerminalSessionResult result) async {
    await _finish(
      invokeHandleClose: false,
      exitCode: result.exitCode,
      disconnected: result.disconnected,
      closeSummary: result.disconnected ? 'SSH 终端连接断开' : 'SSH 终端结束',
    );
  }

  Future<void> _finish({
    required bool invokeHandleClose,
    required bool disconnected,
    required String closeSummary,
    int? exitCode,
  }) async {
    if (_closed) {
      return;
    }
    _closed = true;
    _disconnected = disconnected;
    _exitCode = exitCode;
    if (invokeHandleClose) {
      try {
        await handle.close();
      } catch (error) {
        addOutput('\r\n[ShellGuard] 关闭共享终端时发生异常：$error\r\n');
      }
    }
    await _logAudit(
      action: 'terminal_close',
      summary: closeSummary,
      detail: _buildCloseDetail(),
      success: !disconnected,
    );
    _notifyWaiters();
    manager.disconnect();
  }

  Future<void> _captureInputAudit(String data) async {
    for (final rune in data.runes) {
      if (rune == 3) {
        final partial = _pendingInput.toString().trim();
        _pendingInput.clear();
        _lastInputEndedWithNewline = false;
        await _logAudit(
          action: 'terminal_interrupt',
          summary: 'Ctrl+C',
          detail: partial.isEmpty ? '用户发送中断信号' : '中断前输入：$partial',
          success: true,
        );
        continue;
      }

      if (rune == 13 || rune == 10) {
        if (_lastInputEndedWithNewline) {
          continue;
        }
        final command = _pendingInput.toString().trim();
        _pendingInput.clear();
        _lastInputEndedWithNewline = true;
        if (command.isNotEmpty) {
          await _logAudit(
            action: 'terminal_command',
            summary: command,
            detail: '用户在 SSH 终端中执行命令',
            success: true,
          );
        }
        continue;
      }

      _lastInputEndedWithNewline = false;
      if (rune == 8 || rune == 127) {
        final current = _pendingInput.toString();
        if (current.isNotEmpty) {
          _pendingInput
            ..clear()
            ..write(current.substring(0, current.length - 1));
        }
        continue;
      }

      if (rune >= 32) {
        _pendingInput.write(String.fromCharCode(rune));
      }
    }
  }

  Future<void> _logAudit({
    required String action,
    required String summary,
    required String detail,
    required bool success,
  }) {
    return auditService.log(
      category: RemoteAuditCategory.terminal,
      action: action,
      summary: summary,
      detail: _decorateDetail(detail),
      sourceHost: sourceHost,
      sourceLabel: sourceLabel,
      sharedGroupId: sharedGroupId,
      sharedGroupName: sharedGroupName,
      sharedServerId: serverId,
      sharedServerName: serverName,
      success: success,
      token: token,
    );
  }

  String _decorateDetail(String detail) {
    return [
      '[[session_id:$sessionId]]',
      '[[server_name:$serverName]]',
      detail.trim(),
    ].where((item) => item.isNotEmpty).join('\n');
  }

  String _buildCloseDetail() {
    final transcript = _transcript.toString().trim();
    final detail = StringBuffer();
    if (transcript.isNotEmpty) {
      detail.writeln('transcript:');
      detail.writeln(transcript);
    }
    if (_exitCode != null) {
      detail.writeln('exit_code=$_exitCode');
    }
    if (_disconnected) {
      detail.writeln('disconnected=true');
    }
    return detail.toString().trim();
  }

  void _appendTranscript(String prefix, String text) {
    if (_transcriptTruncated || text.isEmpty) {
      return;
    }
    final next = '$prefix$text';
    final remain = _maxTranscriptChars - _transcript.length;
    if (remain <= 0) {
      _transcriptTruncated = true;
      _transcript.write('\n[transcript truncated]');
      return;
    }
    if (next.length <= remain) {
      _transcript.write(next);
      return;
    }
    _transcript.write(next.substring(0, remain));
    _transcript.write('\n[transcript truncated]');
    _transcriptTruncated = true;
  }

  String _sanitizeInputForTranscript(String text) {
    return text
        .replaceAll('\u0003', '^C')
        .replaceAll('\r', '\n');
  }

  void _notifyWaiters() {
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
    _waiters.clear();
  }
}

class ShareListenerService {
  final StorageService storageService;
  final ShareAuthenticator authenticator;
  late final ShareAuditService _auditService;
  final Map<String, _SharedTerminalSessionState> _terminalSessions = {};
  final Set<String> _activeConnectionIds = <String>{};

  HttpServer? _server;
  ShareListenerConfig _config = const ShareListenerConfig();
  String? _lastError;

  ShareListenerService({
    required this.storageService,
    ShareAuthenticator? authenticator,
  }) : authenticator =
            authenticator ?? TokenShareAuthenticator(storageService: storageService) {
    _auditService = ShareAuditService(storageService: storageService);
  }

  bool get isRunning => _server != null;
  ShareListenerConfig get config => _config;
  String? get lastError => _lastError;

  Future<void> start(ShareListenerConfig config) async {
    await stop();
    _config = config;
    _lastError = null;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, config.port);
      _server!.listen((request) {
        unawaited(_handleRequest(request));
      });
    } catch (error) {
      _lastError = error.toString();
      rethrow;
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    final sessions = _terminalSessions.values.toList();
    _terminalSessions.clear();
    _activeConnectionIds.clear();
    for (final session in sessions) {
      await session.closeFromClient();
    }
    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.path == '/health') {
        await _writeJson(request.response, {
          'ok': true,
          'running': isRunning,
          'port': _config.port,
        });
        return;
      }

      final authResult = await authenticator.authorize(request, _config);
      if (!authResult.allowed) {
        request.response.statusCode = authResult.statusCode;
        request.response.headers.contentType = ContentType.text;
        request.response.write(authResult.message);
        await request.response.close();
        return;
      }

      switch (request.uri.path) {
        case '/api/share/token/verify':
          await _handleVerifyToken(request, authResult.token);
          return;
        case '/api/share/audit/log':
          await _handleRemoteAuditLog(request, authResult.token);
          return;
        case '/api/share/connection/start':
          await _handleConnectionStart(request, authResult.token);
          return;
        case '/api/share/connection/close':
          await _handleConnectionClose(request, authResult.token);
          return;
        case '/api/share/terminal/open':
          await _handleOpenTerminalSession(request, authResult.token);
          return;
        case '/api/share/terminal/read':
          await _handleReadTerminalSession(request);
          return;
        case '/api/share/terminal/write':
          await _handleWriteTerminalSession(request);
          return;
        case '/api/share/terminal/resize':
          await _handleResizeTerminalSession(request);
          return;
        case '/api/share/terminal/close':
          await _handleCloseTerminalSession(request);
          return;
        case '/api/share/dashboard':
          await _handleDashboard(request, authResult.token);
          return;
        case '/api/share/processes':
          await _handleProcesses(request, authResult.token);
          return;
        case '/api/share/ports':
          await _handlePorts(request, authResult.token);
          return;
        case '/api/share/services':
          await _handleServices(request, authResult.token);
          return;
        case '/api/share/firewall':
          await _handleFirewall(request, authResult.token);
          return;
        case '/api/share/docker':
          await _handleDocker(request, authResult.token);
          return;
        case '/api/share/files/resolve':
          await _handleResolveDirectory(request, authResult.token);
          return;
        case '/api/share/files/list':
          await _handleListFiles(request, authResult.token);
          return;
        case '/api/share/files/mkdir':
          await _handleSimpleFileCommand(
            request,
            authResult.token,
            (manager, body) => manager.createDirectory(body['path']!.toString()),
          );
          return;
        case '/api/share/files/write':
          await _handleSimpleFileCommand(
            request,
            authResult.token,
            (manager, body) => manager.writeFile(
              body['path']!.toString(),
              body['content']?.toString() ?? '',
            ),
          );
          return;
        case '/api/share/files/delete':
          await _handleSimpleFileCommand(
            request,
            authResult.token,
            (manager, body) => manager.deleteFile(body['path']!.toString()),
          );
          return;
        case '/api/share/files/rename':
          await _handleSimpleFileCommand(
            request,
            authResult.token,
            (manager, body) => manager.renameFile(
              body['oldPath']!.toString(),
              body['newPath']!.toString(),
            ),
          );
          return;
        case '/api/share/files/stat':
          await _handleFileStat(request, authResult.token);
          return;
        case '/api/share/files/upload':
          await _handleFileUpload(request, authResult.token);
          return;
        case '/api/share/files/download':
          await _handleFileDownload(request, authResult.token);
          return;
        case '/api/share/command/execute':
          await _handleExecuteCommand(request, authResult.token);
          return;
        default:
          request.response.statusCode = HttpStatus.notFound;
          await request.response.close();
      }
    } catch (error) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.headers.contentType = ContentType.text;
      request.response.write(error.toString());
      await request.response.close();
    }
  }

  Future<void> _handleDashboard(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final systemInfo = await manager.getSystemInfo();
      final resourceUsage = await manager.getResourceUsage();
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: 'readonly_dashboard',
        summary: '查看资源概览',
      );
      await _writeJson(request.response, {
        'systemInfo': ShareProtocol.systemInfoToJson(systemInfo),
        'resourceUsage': ShareProtocol.resourceUsageToJson(resourceUsage),
      });
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleVerifyToken(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    if (token == null) {
      throw Exception('token 校验失败');
    }
    await storageService.markAccessTokenUsed(token.id);
    await _auditService.log(
      category: RemoteAuditCategory.connection,
      action: 'verify_token',
      summary: '共享 token 校验成功',
      detail: token.note,
      sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
      sourceLabel: request.headers.value('x-shellguard-client') ?? '',
      success: true,
      token: token,
    );
    await _writeJson(request.response, {
      'valid': true,
      'tokenId': token.id,
      'tokenNote': token.note,
      'expiresAt': token.expiresAt.toIso8601String(),
    });
  }

  Future<void> _handleRemoteAuditLog(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final categoryName = body['category']?.toString() ?? RemoteAuditCategory.operation.name;
    final action = body['action']?.toString().trim() ?? '';
    final summary = body['summary']?.toString().trim() ?? '';
    if (action.isEmpty || summary.isEmpty) {
      throw Exception('审计 action 或 summary 缺失');
    }

    final remoteServerId = body['serverId']?.toString().trim() ?? '';
    final providedServerName = body['serverName']?.toString().trim() ?? '';
    String sharedServerName = providedServerName;
    if (remoteServerId.isNotEmpty && sharedServerName.isEmpty) {
      try {
        final server = await _loadServer(remoteServerId);
        sharedServerName = server.name;
      } catch (_) {}
    }

    final category = RemoteAuditCategory.values.firstWhere(
      (item) => item.name == categoryName,
      orElse: () => RemoteAuditCategory.operation,
    );
    await _auditService.log(
      category: category,
      action: action,
      summary: summary,
      detail: body['detail']?.toString() ?? '',
      sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
      sourceLabel: request.headers.value('x-shellguard-client') ?? '',
      sharedGroupId: body['sharedGroupId']?.toString() ?? '',
      sharedGroupName: body['sharedGroupName']?.toString() ?? '',
      sharedServerId: remoteServerId,
      sharedServerName: sharedServerName,
      success: (body['success'] as bool?) ?? true,
      token: token,
    );
    await _writeJson(request.response, {'ok': true});
  }

  Future<void> _handleConnectionStart(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final connectionId = body['connectionId']?.toString().trim() ?? '';
    if (connectionId.isEmpty) {
      throw Exception('connectionId 缺失');
    }
    final tokenKey = '${token?.id ?? 'anonymous'}::$connectionId';
    if (_activeConnectionIds.contains(tokenKey)) {
      await _writeJson(request.response, {'ok': true, 'reused': true});
      return;
    }
    _activeConnectionIds.add(tokenKey);
    if (token != null) {
      await storageService.markAccessTokenUsed(token.id);
    }
    final remoteServerId = body['serverId']?.toString().trim() ?? '';
    var serverName = body['serverName']?.toString().trim() ?? '';
    if (remoteServerId.isNotEmpty && serverName.isEmpty) {
      try {
        serverName = (await _loadServer(remoteServerId)).name;
      } catch (_) {}
    }
    await _auditService.log(
      category: RemoteAuditCategory.connection,
      action: 'share_connect',
      summary: '共享会话开始连接',
      detail: '[[connection_id:$connectionId]]',
      sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
      sourceLabel: request.headers.value('x-shellguard-client') ?? '',
      sharedGroupId: body['sharedGroupId']?.toString() ?? '',
      sharedGroupName: body['sharedGroupName']?.toString() ?? '',
      sharedServerId: remoteServerId,
      sharedServerName: serverName,
      success: true,
      token: token,
    );
    await _writeJson(request.response, {'ok': true, 'reused': false});
  }

  Future<void> _handleConnectionClose(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final connectionId = body['connectionId']?.toString().trim() ?? '';
    if (connectionId.isNotEmpty) {
      _activeConnectionIds.remove('${token?.id ?? 'anonymous'}::$connectionId');
    }
    await _writeJson(request.response, {'ok': true});
  }

  Future<void> _handleOpenTerminalSession(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final handle = await manager.openShellSession(
        columns: (body['columns'] as num?)?.toInt() ?? 120,
        rows: (body['rows'] as num?)?.toInt() ?? 32,
      );
      final serverName = body['serverName']?.toString().trim().isNotEmpty == true
          ? body['serverName']!.toString().trim()
          : server.name;
      final session = _SharedTerminalSessionState(
        sessionId: handle.sessionId,
        serverId: server.id,
        serverName: serverName,
        sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
        sourceLabel: request.headers.value('x-shellguard-client') ?? '',
        sharedGroupId: body['sharedGroupId']?.toString() ?? '',
        sharedGroupName: body['sharedGroupName']?.toString() ?? '',
        token: token,
        auditService: _auditService,
        manager: manager,
        handle: handle,
      );
      _terminalSessions[handle.sessionId] = session;
      await _auditService.log(
        category: RemoteAuditCategory.connection,
        action: 'terminal_connect',
        summary: '共享 SSH 终端连接成功',
        detail: '[[session_id:${handle.sessionId}]]\n[[server_name:$serverName]]',
        sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
        sourceLabel: request.headers.value('x-shellguard-client') ?? '',
        sharedGroupId: body['sharedGroupId']?.toString() ?? '',
        sharedGroupName: body['sharedGroupName']?.toString() ?? '',
        sharedServerId: server.id,
        sharedServerName: serverName,
        success: true,
        token: token,
      );
      session.handle.stream.listen(
        session.addOutput,
        onError: (Object error) => session.addOutput(error.toString()),
      );
      unawaited(
        session.handle.done.then((result) async {
          await session.closeFromRemote(result);
          _terminalSessions.remove(session.sessionId);
        }),
      );
      await session.logSessionOpened();
      await _writeJson(request.response, {
        'sessionId': handle.sessionId,
      });
    } catch (_) {
      manager.disconnect();
      rethrow;
    }
  }

  Future<void> _handleReadTerminalSession(HttpRequest request) async {
    final body = await _readBody(request);
    final session = _resolveTerminalSession(body['sessionId']?.toString());
    final payload = await session.read(
      afterSeq: (body['afterSeq'] as num?)?.toInt() ?? 0,
      waitMs: (body['waitMs'] as num?)?.toInt() ?? 2500,
    );
    if (session.isClosed) {
      _terminalSessions.remove(session.sessionId);
    }
    await _writeJson(request.response, payload);
  }

  Future<void> _handleWriteTerminalSession(HttpRequest request) async {
    final body = await _readBody(request);
    final session = _resolveTerminalSession(body['sessionId']?.toString());
    await session.write(body['data']?.toString() ?? '');
    await _writeJson(request.response, {'ok': true});
  }

  Future<void> _handleResizeTerminalSession(HttpRequest request) async {
    final body = await _readBody(request);
    final session = _resolveTerminalSession(body['sessionId']?.toString());
    session.resize(
      (body['columns'] as num?)?.toInt() ?? 120,
      (body['rows'] as num?)?.toInt() ?? 32,
      (body['pixelWidth'] as num?)?.toInt() ?? 0,
      (body['pixelHeight'] as num?)?.toInt() ?? 0,
    );
    await _writeJson(request.response, {'ok': true});
  }

  Future<void> _handleCloseTerminalSession(HttpRequest request) async {
    final body = await _readBody(request);
    final session = _resolveTerminalSession(body['sessionId']?.toString());
    await session.closeFromClient();
    _terminalSessions.remove(session.sessionId);
    await _writeJson(request.response, {'ok': true});
  }

  Future<void> _handleProcesses(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    await _handleListResponse(
      request,
      token: token,
      fetch: (manager) => manager.getProcessList(),
      itemToJson: ShareProtocol.processInfoToJson,
      key: 'processes',
      auditAction: 'readonly_processes',
      auditSummary: '查看进程列表',
    );
  }

  Future<void> _handlePorts(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    await _handleListResponse(
      request,
      token: token,
      fetch: (manager) => manager.getPortList(),
      itemToJson: ShareProtocol.portInfoToJson,
      key: 'ports',
      auditAction: 'readonly_ports',
      auditSummary: '查看端口列表',
    );
  }

  Future<void> _handleServices(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    await _handleListResponse(
      request,
      token: token,
      fetch: (manager) => manager.getServiceList(),
      itemToJson: ShareProtocol.serviceInfoToJson,
      key: 'services',
      auditAction: 'readonly_services',
      auditSummary: '查看服务列表',
    );
  }

  Future<void> _handleFirewall(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final rules = await manager.getFirewallRules();
      final enabled = await manager.getFirewallEnabled();
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: 'readonly_firewall',
        summary: '查看防火墙规则',
        detail: 'enabled=$enabled\nrules=${rules.length}',
      );
      await _writeJson(request.response, {
        'enabled': enabled,
        'rules': rules.map(ShareProtocol.firewallRuleToJson).toList(),
      });
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleDocker(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final installed = await manager.isDockerInstalled();
      final containers = installed ? await manager.getDockerContainers() : const <DockerContainer>[];
      final images = installed ? await manager.getDockerImages() : const <DockerImage>[];
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: 'readonly_docker',
        summary: '查看 Docker 状态',
        detail: 'installed=$installed\ncontainers=${containers.length}\nimages=${images.length}',
      );
      await _writeJson(request.response, {
        'dockerInstalled': installed,
        'containers': containers.map(ShareProtocol.dockerContainerToJson).toList(),
        'images': images.map(ShareProtocol.dockerImageToJson).toList(),
      });
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleResolveDirectory(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final result = await manager.resolveDirectory(
        body['path']?.toString(),
        fallbackToParent: (body['fallbackToParent'] as bool?) ?? false,
      );
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: 'readonly_files_resolve',
        summary: '解析目录',
        detail: result.resolvedPath,
      );
      await _writeJson(
        request.response,
        ShareProtocol.directoryResolutionToJson(result),
      );
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleListFiles(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final result = await manager.listFilesSnapshot(body['path']!.toString());
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: 'readonly_files_list',
        summary: '查看文件列表',
        detail: '${result.resolvedPath}\ncount=${result.files.length}',
      );
      await _writeJson(
        request.response,
        ShareProtocol.fileListResultToJson(result),
      );
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleSimpleFileCommand(
    HttpRequest request,
    AccessTokenRecord? token,
    Future<String> Function(SshManager manager, Map<String, Object?> body) action,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final result = await action(manager, body);
      await _auditService.log(
        category: RemoteAuditCategory.operation,
        action: 'file_operation',
        summary: body['path']?.toString() ??
            '${body['oldPath'] ?? ''} -> ${body['newPath'] ?? ''}',
        detail: result,
        sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
        sourceLabel: request.headers.value('x-shellguard-client') ?? '',
        sharedGroupId: body['sharedGroupId']?.toString() ?? '',
        sharedGroupName: body['sharedGroupName']?.toString() ?? '',
        sharedServerId: server.id,
        sharedServerName: body['serverName']?.toString().trim().isNotEmpty == true
            ? body['serverName']!.toString().trim()
            : server.name,
        success: true,
        token: token,
      );
      await _writeJson(request.response, {'result': result});
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleFileStat(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final size = await manager.statRemoteFileSize(body['path']!.toString());
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: 'readonly_files_stat',
        summary: '读取文件信息',
        detail: '${body['path']?.toString() ?? ''}\nsize=${size ?? -1}',
      );
      await _writeJson(request.response, {'size': size});
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleExecuteCommand(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final command = body['command']!.toString();
      final privileged = (body['privileged'] as bool?) ?? false;
      final userShell = (body['userShell'] as bool?) ?? false;
      late final String result;
      if (privileged && userShell) {
        result = await manager.executePrivilegedUserCommandStream(command).then((handle) => handle.result).then((value) => value.stdout + value.stderr);
      } else if (privileged) {
        result = await manager.executePrivilegedCommand(command);
      } else if (userShell) {
        result = await manager.executeUserCommand(command);
      } else {
        result = await manager.executeCommand(command);
      }
      await _auditService.log(
        category: RemoteAuditCategory.operation,
        action: 'execute_command',
        summary: command,
        detail: result,
        sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
        sourceLabel: request.headers.value('x-shellguard-client') ?? '',
        sharedGroupId: body['sharedGroupId']?.toString() ?? '',
        sharedGroupName: body['sharedGroupName']?.toString() ?? '',
        sharedServerId: server.id,
        sharedServerName: body['serverName']?.toString().trim().isNotEmpty == true
            ? body['serverName']!.toString().trim()
            : server.name,
        success: true,
        token: token,
      );
      await _writeJson(request.response, {'result': result});
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleFileUpload(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final serverId = request.uri.queryParameters['serverId'];
    final remotePath = request.uri.queryParameters['remotePath'];
    final serverName = request.uri.queryParameters['serverName'] ?? '';
    final sharedGroupId = request.uri.queryParameters['sharedGroupId'] ?? '';
    final sharedGroupName = request.uri.queryParameters['sharedGroupName'] ?? '';
    if (serverId == null || serverId.isEmpty || remotePath == null || remotePath.isEmpty) {
      throw Exception('serverId 或 remotePath 缺失');
    }
    final server = await _loadServer(serverId);
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    final tempDir = await Directory.systemTemp.createTemp('shellguard-share-upload-');
    final tempFile = File('${tempDir.path}/upload.bin');
    try {
      final sink = tempFile.openWrite();
      await for (final chunk in request) {
        sink.add(chunk);
      }
      await sink.close();
      await manager.uploadLocalFile(tempFile.path, remotePath);
      await _auditService.log(
        category: RemoteAuditCategory.operation,
        action: 'file_upload',
        summary: remotePath,
        detail: '共享上传完成',
        sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
        sourceLabel: request.headers.value('x-shellguard-client') ?? '',
        sharedGroupId: sharedGroupId,
        sharedGroupName: sharedGroupName,
        sharedServerId: server.id,
        sharedServerName: serverName.trim().isNotEmpty ? serverName.trim() : server.name,
        success: true,
        token: token,
      );
      await _writeJson(request.response, {'ok': true});
    } finally {
      manager.disconnect();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _handleFileDownload(
    HttpRequest request,
    AccessTokenRecord? token,
  ) async {
    final serverId = request.uri.queryParameters['serverId'];
    final remotePath = request.uri.queryParameters['remotePath'];
    final serverName = request.uri.queryParameters['serverName'] ?? '';
    final sharedGroupId = request.uri.queryParameters['sharedGroupId'] ?? '';
    final sharedGroupName = request.uri.queryParameters['sharedGroupName'] ?? '';
    if (serverId == null || serverId.isEmpty || remotePath == null || remotePath.isEmpty) {
      throw Exception('serverId 或 remotePath 缺失');
    }
    final server = await _loadServer(serverId);
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    final tempDir = await Directory.systemTemp.createTemp('shellguard-share-download-');
    final tempFile = File('${tempDir.path}/download.bin');
    try {
      await manager.downloadRemoteFile(remotePath, tempFile.path);
      await _auditService.log(
        category: RemoteAuditCategory.operation,
        action: 'file_download',
        summary: remotePath,
        detail: '共享下载完成',
        sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
        sourceLabel: request.headers.value('x-shellguard-client') ?? '',
        sharedGroupId: sharedGroupId,
        sharedGroupName: sharedGroupName,
        sharedServerId: server.id,
        sharedServerName: serverName.trim().isNotEmpty ? serverName.trim() : server.name,
        success: true,
        token: token,
      );
      request.response.statusCode = HttpStatus.ok;
      request.response.headers.contentType = ContentType.binary;
      await request.response.addStream(tempFile.openRead());
      await request.response.close();
    } finally {
      manager.disconnect();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _handleListResponse<T>(
    HttpRequest request, {
    required AccessTokenRecord? token,
    required Future<List<T>> Function(SshManager manager) fetch,
    required Map<String, Object?> Function(T item) itemToJson,
    required String key,
    required String auditAction,
    required String auditSummary,
  }) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final list = await fetch(manager);
      await _logReadOnlyAudit(
        request: request,
        token: token,
        body: body,
        server: server,
        action: auditAction,
        summary: auditSummary,
        detail: 'count=${list.length}',
      );
      await _writeJson(
        request.response,
        {key: list.map(itemToJson).toList()},
      );
    } finally {
      manager.disconnect();
    }
  }

  Future<Map<String, Object?>> _readBody(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) {
      return <String, Object?>{};
    }
    return (json.decode(raw) as Map).cast<String, Object?>();
  }

  Future<Server> _loadServer(String serverId) async {
    final servers = await storageService.loadServers();
    for (final server in servers) {
      if (server.id == serverId) {
        return server;
      }
    }
    throw Exception('未找到可共享的服务器: $serverId');
  }

  Future<void> _connectOrThrow(SshManager manager, Server server) async {
    final connected = await manager.connect(server);
    if (!connected) {
      throw Exception(manager.errorMessage ?? '连接到共享服务器失败');
    }
  }

  Future<void> _writeJson(HttpResponse response, Map<String, Object?> jsonMap) async {
    response.statusCode = HttpStatus.ok;
    response.headers.contentType = ContentType.json;
    response.write(json.encode(jsonMap));
    await response.close();
  }

  _SharedTerminalSessionState _resolveTerminalSession(String? sessionId) {
    final normalized = sessionId?.trim() ?? '';
    if (normalized.isEmpty || !_terminalSessions.containsKey(normalized)) {
      throw Exception('共享终端会话不存在或已结束');
    }
    return _terminalSessions[normalized]!;
  }

  Future<void> _logReadOnlyAudit({
    required HttpRequest request,
    required AccessTokenRecord? token,
    required Map<String, Object?> body,
    required Server server,
    required String action,
    required String summary,
    String detail = '',
  }) {
    final serverName = body['serverName']?.toString().trim();
    return _auditService.log(
      category: RemoteAuditCategory.operation,
      action: action,
      summary: summary,
      detail: detail,
      sourceHost: request.connectionInfo?.remoteAddress.address ?? '',
      sourceLabel: request.headers.value('x-shellguard-client') ?? '',
      sharedGroupId: body['sharedGroupId']?.toString() ?? '',
      sharedGroupName: body['sharedGroupName']?.toString() ?? '',
      sharedServerId: server.id,
      sharedServerName: (serverName?.isNotEmpty ?? false) ? serverName! : server.name,
      success: true,
      token: token,
    );
  }
}
