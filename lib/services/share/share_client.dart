import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/ssh_manager.dart';
import '../../models/server.dart';
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

  ShareClient({
    required this.baseUri,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<bool> healthCheck() async {
    try {
      final response = await _client.get(_uri('/health')).timeout(
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

  Future<SharedDashboardSnapshot> fetchDashboard(String serverId) async {
    final jsonMap = await _postJson('/api/share/dashboard', {'serverId': serverId});
    return SharedDashboardSnapshot(
      systemInfo: ShareProtocol.systemInfoFromJson(
        (jsonMap['systemInfo'] as Map).cast<String, Object?>(),
      ),
      resourceUsage: ShareProtocol.resourceUsageFromJson(
        (jsonMap['resourceUsage'] as Map).cast<String, Object?>(),
      ),
    );
  }

  Future<List<ProcessInfo>> fetchProcesses(String serverId) async {
    final jsonMap = await _postJson('/api/share/processes', {'serverId': serverId});
    return _decodeList(jsonMap['processes'], ShareProtocol.processInfoFromJson);
  }

  Future<List<PortInfo>> fetchPorts(String serverId) async {
    final jsonMap = await _postJson('/api/share/ports', {'serverId': serverId});
    return _decodeList(jsonMap['ports'], ShareProtocol.portInfoFromJson);
  }

  Future<List<ServiceInfo>> fetchServices(String serverId) async {
    final jsonMap = await _postJson('/api/share/services', {'serverId': serverId});
    return _decodeList(jsonMap['services'], ShareProtocol.serviceInfoFromJson);
  }

  Future<(List<FirewallRule>, bool)> fetchFirewall(String serverId) async {
    final jsonMap = await _postJson('/api/share/firewall', {'serverId': serverId});
    return (
      _decodeList(jsonMap['rules'], ShareProtocol.firewallRuleFromJson),
      (jsonMap['enabled'] as bool?) ?? false,
    );
  }

  Future<(List<DockerContainer>, List<DockerImage>, bool)> fetchDocker(String serverId) async {
    final jsonMap = await _postJson('/api/share/docker', {'serverId': serverId});
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
  }) async {
    final jsonMap = await _postJson('/api/share/files/resolve', {
      'serverId': serverId,
      'path': path,
      'fallbackToParent': fallbackToParent,
    });
    return ShareProtocol.directoryResolutionFromJson(jsonMap);
  }

  Future<FileListResult> listFilesSnapshot({
    required String serverId,
    required String path,
  }) async {
    final jsonMap = await _postJson('/api/share/files/list', {
      'serverId': serverId,
      'path': path,
    });
    return ShareProtocol.fileListResultFromJson(jsonMap);
  }

  Future<String> createDirectory({
    required String serverId,
    required String path,
  }) async {
    final jsonMap = await _postJson('/api/share/files/mkdir', {
      'serverId': serverId,
      'path': path,
    });
    return jsonMap['result']?.toString() ?? '';
  }

  Future<String> writeFile({
    required String serverId,
    required String path,
    required String content,
  }) async {
    final jsonMap = await _postJson('/api/share/files/write', {
      'serverId': serverId,
      'path': path,
      'content': content,
    });
    return jsonMap['result']?.toString() ?? '';
  }

  Future<String> deleteFile({
    required String serverId,
    required String path,
  }) async {
    final jsonMap = await _postJson('/api/share/files/delete', {
      'serverId': serverId,
      'path': path,
    });
    return jsonMap['result']?.toString() ?? '';
  }

  Future<String> renameFile({
    required String serverId,
    required String oldPath,
    required String newPath,
  }) async {
    final jsonMap = await _postJson('/api/share/files/rename', {
      'serverId': serverId,
      'oldPath': oldPath,
      'newPath': newPath,
    });
    return jsonMap['result']?.toString() ?? '';
  }

  Future<int?> statRemoteFileSize({
    required String serverId,
    required String path,
  }) async {
    final jsonMap = await _postJson('/api/share/files/stat', {
      'serverId': serverId,
      'path': path,
    });
    return (jsonMap['size'] as num?)?.toInt();
  }

  Future<String> executeCommand({
    required String serverId,
    required String command,
    bool privileged = false,
    bool userShell = false,
  }) async {
    final jsonMap = await _postJson('/api/share/command/execute', {
      'serverId': serverId,
      'command': command,
      'privileged': privileged,
      'userShell': userShell,
    });
    return jsonMap['result']?.toString() ?? '';
  }

  Future<void> uploadFile({
    required String serverId,
    required String remotePath,
    required String localPath,
    void Function(int bytesWritten)? onProgress,
    TransferCancellationToken? cancelToken,
  }) async {
    final request = http.StreamedRequest(
      'POST',
      _uri('/api/share/files/upload').replace(
        queryParameters: {
          'serverId': serverId,
          'remotePath': remotePath,
        },
      ),
    );
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
  }) async {
    final request = http.Request(
      'GET',
      _uri('/api/share/files/download').replace(
        queryParameters: {
          'serverId': serverId,
          'remotePath': remotePath,
        },
      ),
    );
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

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> payload,
  ) async {
    final response = await _client
        .post(
          _uri(path),
          headers: {'content-type': 'application/json'},
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
