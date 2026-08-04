import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/ssh_manager.dart';
import '../../models/server.dart';
import '../../models/share_listener_config.dart';
import '../../services/storage_service.dart';
import 'share_auth.dart';
import 'share_protocol.dart';

class ShareListenerService {
  final StorageService storageService;
  final ShareAuthenticator authenticator;

  HttpServer? _server;
  ShareListenerConfig _config = const ShareListenerConfig();
  String? _lastError;

  ShareListenerService({
    required this.storageService,
    ShareAuthenticator? authenticator,
  }) : authenticator = authenticator ?? const AllowAllShareAuthenticator();

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
        await request.response.close();
        return;
      }

      switch (request.uri.path) {
        case '/api/share/dashboard':
          await _handleDashboard(request);
          return;
        case '/api/share/processes':
          await _handleProcesses(request);
          return;
        case '/api/share/ports':
          await _handlePorts(request);
          return;
        case '/api/share/services':
          await _handleServices(request);
          return;
        case '/api/share/firewall':
          await _handleFirewall(request);
          return;
        case '/api/share/docker':
          await _handleDocker(request);
          return;
        case '/api/share/files/resolve':
          await _handleResolveDirectory(request);
          return;
        case '/api/share/files/list':
          await _handleListFiles(request);
          return;
        case '/api/share/files/mkdir':
          await _handleSimpleFileCommand(
            request,
            (manager, body) => manager.createDirectory(body['path']!.toString()),
          );
          return;
        case '/api/share/files/write':
          await _handleSimpleFileCommand(
            request,
            (manager, body) => manager.writeFile(
              body['path']!.toString(),
              body['content']?.toString() ?? '',
            ),
          );
          return;
        case '/api/share/files/delete':
          await _handleSimpleFileCommand(
            request,
            (manager, body) => manager.deleteFile(body['path']!.toString()),
          );
          return;
        case '/api/share/files/rename':
          await _handleSimpleFileCommand(
            request,
            (manager, body) => manager.renameFile(
              body['oldPath']!.toString(),
              body['newPath']!.toString(),
            ),
          );
          return;
        case '/api/share/files/stat':
          await _handleFileStat(request);
          return;
        case '/api/share/files/upload':
          await _handleFileUpload(request);
          return;
        case '/api/share/files/download':
          await _handleFileDownload(request);
          return;
        case '/api/share/command/execute':
          await _handleExecuteCommand(request);
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

  Future<void> _handleDashboard(HttpRequest request) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final systemInfo = await manager.getSystemInfo();
      final resourceUsage = await manager.getResourceUsage();
      await _writeJson(request.response, {
        'systemInfo': ShareProtocol.systemInfoToJson(systemInfo),
        'resourceUsage': ShareProtocol.resourceUsageToJson(resourceUsage),
      });
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleProcesses(HttpRequest request) async {
    await _handleListResponse(
      request,
      fetch: (manager) => manager.getProcessList(),
      itemToJson: ShareProtocol.processInfoToJson,
      key: 'processes',
    );
  }

  Future<void> _handlePorts(HttpRequest request) async {
    await _handleListResponse(
      request,
      fetch: (manager) => manager.getPortList(),
      itemToJson: ShareProtocol.portInfoToJson,
      key: 'ports',
    );
  }

  Future<void> _handleServices(HttpRequest request) async {
    await _handleListResponse(
      request,
      fetch: (manager) => manager.getServiceList(),
      itemToJson: ShareProtocol.serviceInfoToJson,
      key: 'services',
    );
  }

  Future<void> _handleFirewall(HttpRequest request) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final rules = await manager.getFirewallRules();
      final enabled = await manager.getFirewallEnabled();
      await _writeJson(request.response, {
        'enabled': enabled,
        'rules': rules.map(ShareProtocol.firewallRuleToJson).toList(),
      });
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleDocker(HttpRequest request) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final installed = await manager.isDockerInstalled();
      final containers = installed ? await manager.getDockerContainers() : const <DockerContainer>[];
      final images = installed ? await manager.getDockerImages() : const <DockerImage>[];
      await _writeJson(request.response, {
        'dockerInstalled': installed,
        'containers': containers.map(ShareProtocol.dockerContainerToJson).toList(),
        'images': images.map(ShareProtocol.dockerImageToJson).toList(),
      });
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleResolveDirectory(HttpRequest request) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final result = await manager.resolveDirectory(
        body['path']?.toString(),
        fallbackToParent: (body['fallbackToParent'] as bool?) ?? false,
      );
      await _writeJson(
        request.response,
        ShareProtocol.directoryResolutionToJson(result),
      );
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleListFiles(HttpRequest request) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final result = await manager.listFilesSnapshot(body['path']!.toString());
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
    Future<String> Function(SshManager manager, Map<String, Object?> body) action,
  ) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final result = await action(manager, body);
      await _writeJson(request.response, {'result': result});
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleFileStat(HttpRequest request) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final size = await manager.statRemoteFileSize(body['path']!.toString());
      await _writeJson(request.response, {'size': size});
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleExecuteCommand(HttpRequest request) async {
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
      await _writeJson(request.response, {'result': result});
    } finally {
      manager.disconnect();
    }
  }

  Future<void> _handleFileUpload(HttpRequest request) async {
    final serverId = request.uri.queryParameters['serverId'];
    final remotePath = request.uri.queryParameters['remotePath'];
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
      await _writeJson(request.response, {'ok': true});
    } finally {
      manager.disconnect();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<void> _handleFileDownload(HttpRequest request) async {
    final serverId = request.uri.queryParameters['serverId'];
    final remotePath = request.uri.queryParameters['remotePath'];
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
    required Future<List<T>> Function(SshManager manager) fetch,
    required Map<String, Object?> Function(T item) itemToJson,
    required String key,
  }) async {
    final body = await _readBody(request);
    final server = await _loadServer(body['serverId']!.toString());
    final manager = SshManager();
    await _connectOrThrow(manager, server);
    try {
      final list = await fetch(manager);
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
}
