import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/ssh_manager.dart';
import '../../models/remote_control_models.dart';
import '../../models/server.dart';
import '../../models/terminal_session_models.dart';
import 'share_protocol.dart';

class SharedDashboardSnapshot {
  final SystemInfo systemInfo;
  final ResourceUsage resourceUsage;

  const SharedDashboardSnapshot({
    required this.systemInfo,
    required this.resourceUsage,
  });
}

class ShareClient {
  final Uri baseUri;
  final http.Client _client;
  final String accessToken;
  String? _activeConnectionId;

  ShareClient({
    required this.baseUri,
    this.accessToken = '',
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<bool> healthCheck() async {
    try {
      final response = await _client.get(_uri('/health'), headers: _buildHeaders()).timeout(
        const Duration(seconds: 5),
      );
      return response.statusCode == HttpStatus.ok;
    } on TimeoutException {
      throw Exception('连接共享侦听端口超时（${baseUri.host}:${baseUri.port}），请确认源端已开启共享侦听且网络可达');
    } on SocketException catch (error) {
      throw Exception('无法连接到共享侦听地址 ${baseUri.host}:${baseUri.port}：${error.message}');
    } on http.ClientException catch (error) {
      throw Exception('共享侦听请求失败：${error.message}');
    }
  }

  Future<AccessTokenValidationResult> verifyAccessToken() async {
    final jsonMap = await _postJson('/api/share/token/verify', const <String, Object?>{});
    return AccessTokenValidationResult(
      valid: (jsonMap['valid'] as bool?) ?? false,
      message: ((jsonMap['valid'] as bool?) ?? false) ? '验证成功' : '验证失败',
      tokenId: jsonMap['tokenId']?.toString(),
      tokenNote: jsonMap['tokenNote']?.toString() ?? '',
      expiresAt: jsonMap['expiresAt'] == null
          ? null
          : DateTime.tryParse(jsonMap['expiresAt']!.toString()),
    );
  }

  Future<SharedDashboardSnapshot> fetchDashboard(
    String serverId, {
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/dashboard',
      {
        'serverId': serverId,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return SharedDashboardSnapshot(
      systemInfo: ShareProtocol.systemInfoFromJson(
        (jsonMap['systemInfo'] as Map).cast<String, Object?>(),
      ),
      resourceUsage: ShareProtocol.resourceUsageFromJson(
        (jsonMap['resourceUsage'] as Map).cast<String, Object?>(),
      ),
    );
  }

  Future<List<ProcessInfo>> fetchProcesses(
    String serverId, {
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/processes',
      {
        'serverId': serverId,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return _decodeList(jsonMap['processes'], ShareProtocol.processInfoFromJson);
  }

  Future<List<PortInfo>> fetchPorts(
    String serverId, {
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/ports',
      {
        'serverId': serverId,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return _decodeList(jsonMap['ports'], ShareProtocol.portInfoFromJson);
  }

  Future<List<ServiceInfo>> fetchServices(
    String serverId, {
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/services',
      {
        'serverId': serverId,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return _decodeList(jsonMap['services'], ShareProtocol.serviceInfoFromJson);
  }

  Future<(List<FirewallRule>, bool)> fetchFirewall(
    String serverId, {
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/firewall',
      {
        'serverId': serverId,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return (
      _decodeList(jsonMap['rules'], ShareProtocol.firewallRuleFromJson),
      (jsonMap['enabled'] as bool?) ?? false,
    );
  }

  Future<(List<DockerContainer>, List<DockerImage>, bool)> fetchDocker(
    String serverId, {
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/docker',
      {
        'serverId': serverId,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return (
      _decodeList(jsonMap['containers'], ShareProtocol.dockerContainerFromJson),
      _decodeList(jsonMap['images'], ShareProtocol.dockerImageFromJson),
      (jsonMap['dockerInstalled'] as bool?) ?? false,
    );
  }

  Future<DirectoryResolution> resolveDirectory({
    required String serverId,
    String? path,
    bool fallbackToParent = false,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/resolve',
      {
        'serverId': serverId,
        'path': path,
        'fallbackToParent': fallbackToParent,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return ShareProtocol.directoryResolutionFromJson(jsonMap);
  }

  Future<FileListResult> listFilesSnapshot({
    required String serverId,
    required String path,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/list',
      {
        'serverId': serverId,
        'path': path,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return ShareProtocol.fileListResultFromJson(jsonMap);
  }

  Future<String> createDirectory({
    required String serverId,
    required String path,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/mkdir',
      {
        'serverId': serverId,
        'path': path,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return jsonMap['result']?.toString() ?? '';
  }

  Future<String> writeFile({
    required String serverId,
    required String path,
    required String content,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/write',
      {
        'serverId': serverId,
        'path': path,
        'content': content,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return jsonMap['result']?.toString() ?? '';
  }

  Future<String> deleteFile({
    required String serverId,
    required String path,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/delete',
      {
        'serverId': serverId,
        'path': path,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return jsonMap['result']?.toString() ?? '';
  }

  Future<String> renameFile({
    required String serverId,
    required String oldPath,
    required String newPath,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/rename',
      {
        'serverId': serverId,
        'oldPath': oldPath,
        'newPath': newPath,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return jsonMap['result']?.toString() ?? '';
  }

  Future<int?> statRemoteFileSize({
    required String serverId,
    required String path,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/files/stat',
      {
        'serverId': serverId,
        'path': path,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return (jsonMap['size'] as num?)?.toInt();
  }

  Future<String> executeCommand({
    required String serverId,
    required String command,
    bool privileged = false,
    bool userShell = false,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/command/execute',
      {
        'serverId': serverId,
        'command': command,
        'privileged': privileged,
        'userShell': userShell,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    return jsonMap['result']?.toString() ?? '';
  }

  Future<TerminalSessionHandle> openTerminalSession({
    required String serverId,
    required int columns,
    required int rows,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    final jsonMap = await _postJson(
      '/api/share/terminal/open',
      {
        'serverId': serverId,
        'columns': columns,
        'rows': rows,
        'serverName': serverName,
        'sharedGroupId': sharedGroupId,
        'sharedGroupName': sharedGroupName,
      },
      trackedServerId: serverId,
      trackedServerName: serverName,
      trackedGroupId: sharedGroupId,
      trackedGroupName: sharedGroupName,
    );
    final sessionId = jsonMap['sessionId']?.toString() ?? '';
    if (sessionId.isEmpty) {
      throw Exception('共享终端会话创建失败');
    }

    final controller = StreamController<String>.broadcast();
    final doneCompleter = Completer<TerminalSessionResult>();
    var isClosed = false;
    var afterSeq = 0;

    Future<void> pump() async {
      while (!isClosed) {
        try {
          final response = await _postJson('/api/share/terminal/read', {
            'sessionId': sessionId,
            'afterSeq': afterSeq,
            'waitMs': 2500,
          });
          final chunks = (response['chunks'] as List?)
                  ?.whereType<Map>()
                  .map((item) => item.cast<String, Object?>())
                  .toList() ??
              const <Map<String, Object?>>[];
          for (final chunk in chunks) {
            final seq = (chunk['seq'] as num?)?.toInt() ?? afterSeq;
            afterSeq = seq > afterSeq ? seq : afterSeq;
            final text = chunk['text']?.toString() ?? '';
            if (text.isNotEmpty && !controller.isClosed) {
              controller.add(text);
            }
          }
          final closed = (response['closed'] as bool?) ?? false;
          if (closed) {
            isClosed = true;
            if (!controller.isClosed) {
              await controller.close();
            }
            if (!doneCompleter.isCompleted) {
              doneCompleter.complete(
                TerminalSessionResult(
                  exitCode: (response['exitCode'] as num?)?.toInt(),
                  disconnected: (response['disconnected'] as bool?) ?? false,
                ),
              );
            }
            break;
          }
        } catch (error) {
          isClosed = true;
          if (!controller.isClosed) {
            controller.add('\r\n[ShellGuard] 共享终端读取失败：$error\r\n');
            await controller.close();
          }
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete(
              const TerminalSessionResult(
                exitCode: null,
                disconnected: true,
              ),
            );
          }
          break;
        }
      }
    }

    unawaited(pump());

    return TerminalSessionHandle(
      sessionId: sessionId,
      stream: controller.stream,
      done: doneCompleter.future,
      write: (data) {
        if (isClosed) {
          return;
        }
        unawaited(
          _postJson('/api/share/terminal/write', {
            'sessionId': sessionId,
            'data': data,
          }),
        );
      },
      resize: (nextColumns, nextRows, [pixelWidth = 0, pixelHeight = 0]) {
        if (isClosed) {
          return;
        }
        unawaited(
          _postJson('/api/share/terminal/resize', {
            'sessionId': sessionId,
            'columns': nextColumns,
            'rows': nextRows,
            'pixelWidth': pixelWidth,
            'pixelHeight': pixelHeight,
          }),
        );
      },
      close: () async {
        if (isClosed) {
          return;
        }
        isClosed = true;
        try {
          await _postJson('/api/share/terminal/close', {
            'sessionId': sessionId,
          });
        } finally {
          if (!controller.isClosed) {
            await controller.close();
          }
          if (!doneCompleter.isCompleted) {
            doneCompleter.complete(
              const TerminalSessionResult(
                exitCode: null,
                disconnected: false,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> logRemoteAudit({
    required RemoteAuditCategory category,
    required String action,
    required String summary,
    required String serverId,
    String serverName = '',
    String detail = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
    bool success = true,
  }) async {
    await _postJson('/api/share/audit/log', {
      'category': category.name,
      'action': action,
      'summary': summary,
      'detail': detail,
      'serverId': serverId,
      'serverName': serverName,
      'sharedGroupId': sharedGroupId,
      'sharedGroupName': sharedGroupName,
      'success': success,
    });
  }

  Future<void> uploadFile({
    required String serverId,
    required String remotePath,
    required String localPath,
    void Function(int bytesWritten)? onProgress,
    TransferCancellationToken? cancelToken,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    await _ensureConnectionMarker(
      serverId: serverId,
      serverName: serverName,
      sharedGroupId: sharedGroupId,
      sharedGroupName: sharedGroupName,
    );
    final request = http.StreamedRequest(
      'POST',
      _uri('/api/share/files/upload').replace(
        queryParameters: {
          'serverId': serverId,
          'remotePath': remotePath,
          'serverName': serverName,
          'sharedGroupId': sharedGroupId,
          'sharedGroupName': sharedGroupName,
        },
      ),
    );
    request.headers.addAll(_buildHeaders());
    final file = File(localPath);
    final totalBytes = await file.length();
    var sentBytes = 0;
    await for (final chunk in file.openRead()) {
      if (cancelToken?.isCancelled ?? false) {
        request.sink.close();
        throw const TransferCancelledException();
      }
      sentBytes += chunk.length;
      request.sink.add(chunk);
      onProgress?.call(sentBytes > totalBytes ? totalBytes : sentBytes);
    }
    await request.sink.close();
    final response = await _client.send(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(body.isEmpty ? '共享上传失败' : body);
    }
  }

  Future<void> downloadFile({
    required String serverId,
    required String remotePath,
    required String localPath,
    void Function(int bytesRead)? onProgress,
    TransferCancellationToken? cancelToken,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    await _ensureConnectionMarker(
      serverId: serverId,
      serverName: serverName,
      sharedGroupId: sharedGroupId,
      sharedGroupName: sharedGroupName,
    );
    final request = http.Request(
      'GET',
      _uri('/api/share/files/download').replace(
        queryParameters: {
          'serverId': serverId,
          'remotePath': remotePath,
          'serverName': serverName,
          'sharedGroupId': sharedGroupId,
          'sharedGroupName': sharedGroupName,
        },
      ),
    );
    request.headers.addAll(_buildHeaders());
    final response = await _client.send(request);
    if (response.statusCode != HttpStatus.ok) {
      final body = await response.stream.bytesToString();
      throw Exception(body.isEmpty ? '共享下载失败' : body);
    }
    final file = File(localPath);
    await file.parent.create(recursive: true);
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (cancelToken?.isCancelled ?? false) {
          throw const TransferCancelledException();
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received);
      }
    } finally {
      await sink.close();
    }
  }

  Uri _uri(String path) {
    return baseUri.resolve(path);
  }

  Future<void> closeConnectionMarker() async {
    final connectionId = _activeConnectionId;
    if (connectionId == null) {
      return;
    }
    _activeConnectionId = null;
    try {
      await _postJson(
        '/api/share/connection/close',
        {'connectionId': connectionId},
        skipConnectionEnsure: true,
      );
    } catch (_) {}
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> payload,
    {
    String? trackedServerId,
    String trackedServerName = '',
    String trackedGroupId = '',
    String trackedGroupName = '',
    bool skipConnectionEnsure = false,
  }) async {
    if (!skipConnectionEnsure && trackedServerId != null && trackedServerId.trim().isNotEmpty) {
      await _ensureConnectionMarker(
        serverId: trackedServerId,
        serverName: trackedServerName,
        sharedGroupId: trackedGroupId,
        sharedGroupName: trackedGroupName,
      );
    }
    final response = await _client
        .post(
          _uri(path),
          headers: _buildHeaders(),
          body: json.encode(payload),
        )
        .timeout(const Duration(seconds: 20), onTimeout: () {
          throw TimeoutException('共享请求超时');
        });
    if (response.statusCode != HttpStatus.ok) {
      throw Exception(response.body.isEmpty ? '共享请求失败' : response.body);
    }
    return (json.decode(response.body) as Map).cast<String, Object?>();
  }

  String formatConnectionLabel() {
    return '${baseUri.host}:${baseUri.port}';
  }

  Map<String, String> _buildHeaders() {
    return {
      'content-type': 'application/json',
      'x-shellguard-client': 'ShellGuard Desktop',
      ...?_activeConnectionId == null
          ? null
          : <String, String>{'x-shellguard-connection-id': _activeConnectionId!},
      if (accessToken.trim().isNotEmpty)
        HttpHeaders.authorizationHeader: 'Bearer ${accessToken.trim()}',
    };
  }

  Future<void> _ensureConnectionMarker({
    required String serverId,
    String serverName = '',
    String sharedGroupId = '',
    String sharedGroupName = '',
  }) async {
    if (_activeConnectionId != null) {
      return;
    }
    final connectionId =
        'conn_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final previous = _activeConnectionId;
    _activeConnectionId = connectionId;
    try {
      await _postJson(
        '/api/share/connection/start',
        {
          'connectionId': connectionId,
          'serverId': serverId,
          'serverName': serverName,
          'sharedGroupId': sharedGroupId,
          'sharedGroupName': sharedGroupName,
        },
        skipConnectionEnsure: true,
      );
    } catch (_) {
      _activeConnectionId = previous;
      rethrow;
    }
  }

  List<T> _decodeList<T>(
    Object? raw,
    T Function(Map<String, Object?> json) decoder,
  ) {
    if (raw is! List) {
      return <T>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => decoder(item.cast<String, Object?>()))
        .toList();
  }
}
