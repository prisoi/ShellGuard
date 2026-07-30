import 'dart:async';
import 'dart:collection';

import '../models/server.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';
import 'refresh_policy.dart';
import 'refresh_scope.dart';
import 'ssh_manager.dart';

class RefreshEvent {
  final String serverId;
  final RefreshScope scope;
  final bool force;
  final String reason;
  final String? filePath;

  const RefreshEvent({
    required this.serverId,
    required this.scope,
    this.force = false,
    required this.reason,
    this.filePath,
  });

  String get targetKey => '$serverId:${scope.key}:${filePath ?? ''}';
  String get dedupeKey => '$targetKey:${force ? 'force' : 'normal'}';
}

class SshEngine {
  SshEngine({
    required StorageService storageService,
    required CacheService cacheService,
    RefreshPolicy? refreshPolicy,
    this.maxConnections = 3,
  })  : _storageService = storageService,
        _cacheService = cacheService,
        _refreshPolicy = refreshPolicy ?? const RefreshPolicy();

  final StorageService _storageService;
  final CacheService _cacheService;
  final RefreshPolicy _refreshPolicy;
  final int maxConnections;
  final Queue<RefreshEvent> _queue = Queue<RefreshEvent>();
  final Set<String> _inFlight = <String>{};
  final Set<String> _inFlightTargets = <String>{};
  final Map<String, SshManager> _sessions = <String, SshManager>{};
  final Map<String, DateTime> _lastUsedAt = <String, DateTime>{};
  final Map<String, Server> _serverSnapshots = <String, Server>{};
  bool _started = false;
  bool _processing = false;

  bool get isStarted => _started;

  bool hasConnectedSession(String? serverId) {
    if (serverId == null || serverId.isEmpty) {
      return false;
    }
    final session = _sessions[serverId];
    return session != null &&
        session.isConnected &&
        session.currentServer?.id == serverId;
  }

  void start() {
    _started = true;
  }

  void rememberServer(Server server) {
    _serverSnapshots[server.id] = server;
  }

  Future<void> dispose() async {
    for (final session in _sessions.values) {
      session.disconnect();
    }
    _sessions.clear();
    _lastUsedAt.clear();
    _serverSnapshots.clear();
    _queue.clear();
    _inFlight.clear();
    _inFlightTargets.clear();
    _started = false;
  }

  Future<bool> ensureConnected(Server server) async {
    rememberServer(server);
    final session = await _ensureSession(server);
    if (session.isConnected && session.currentServer?.id == server.id) {
      return true;
    }
    final success = await session.connect(server);
    await _updateServerOnlineState(server.id, success);
    return success;
  }

  Future<void> enqueue(RefreshEvent event) async {
    if (!_started) {
      start();
    }

    if (event.force) {
      if (_inFlight.contains(event.dedupeKey) ||
          _queue.any((item) => item.dedupeKey == event.dedupeKey)) {
        return;
      }
      _queue.removeWhere(
        (item) => item.targetKey == event.targetKey && !item.force,
      );
    } else {
      if (_inFlightTargets.contains(event.targetKey) ||
          _queue.any((item) => item.targetKey == event.targetKey)) {
        return;
      }
    }

    _queue.add(event);
    unawaited(_processQueue());
  }

  Future<SshManager> _ensureSession(Server server) async {
    _serverSnapshots[server.id] = server;
    if (_sessions.containsKey(server.id)) {
      _lastUsedAt[server.id] = DateTime.now();
      return _sessions[server.id]!;
    }

    if (_sessions.length >= maxConnections) {
      final oldest = _lastUsedAt.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      if (oldest.isNotEmpty) {
        final oldestId = oldest.first.key;
        _sessions.remove(oldestId)?.disconnect();
        _lastUsedAt.remove(oldestId);
      }
    }

    final manager = SshManager();
    _sessions[server.id] = manager;
    _lastUsedAt[server.id] = DateTime.now();
    return manager;
  }

  Future<void> _processQueue() async {
    if (_processing) {
      return;
    }
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final event = _queue.removeFirst();
        _inFlight.add(event.dedupeKey);
        _inFlightTargets.add(event.targetKey);
        try {
          await _runEvent(event);
        } catch (_) {
        } finally {
          _inFlight.remove(event.dedupeKey);
          _inFlightTargets.remove(event.targetKey);
        }
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _runEvent(RefreshEvent event) async {
    final server = _serverSnapshots[event.serverId];
    if (server == null) {
      return;
    }

    final cache = await _cacheService.getCache(server.id);
    final updatedAt = _cacheService.getScopeUpdatedAt(cache, event.scope.key);
    final capability = await _storageService.getCapability(server.id);
    final usageScores = await _storageService.getUsageScore(window: const Duration(days: 7));
    final usageScore = usageScores['${server.id}:${event.scope.key}'] ?? 0;
    final minInterval = _refreshPolicy.resolveMinInterval(
      scope: event.scope,
      usageScore: usageScore,
      dockerInstalled: capability?['dockerInstalled'] as bool?,
    );

    if (!event.force && updatedAt != null && DateTime.now().difference(updatedAt) < minInterval) {
      return;
    }

    final session = await _ensureSession(server);
    final connected = await ensureConnected(server);
    if (!connected) {
      return;
    }

    switch (event.scope) {
      case RefreshScope.dashboard:
        await _refreshDashboard(server.id, session);
        break;
      case RefreshScope.docker:
        await _refreshDocker(server.id, session);
        break;
      case RefreshScope.firewall:
        await _refreshFirewall(server.id, session);
        break;
      case RefreshScope.ports:
        final ports = await session.getPortList();
        await _cacheService.updateCache(server.id, ports: ports);
        break;
      case RefreshScope.processes:
        final processes = await session.getProcessList();
        await _cacheService.updateCache(server.id, processes: processes);
        break;
      case RefreshScope.services:
        final services = await session.getServiceList();
        await _cacheService.updateCache(server.id, services: services);
        break;
      case RefreshScope.files:
        final path = event.filePath ?? cache?.currentPath ?? '/';
        final fileSnapshot = await session.listFilesSnapshot(path);
        await _cacheService.updateCache(
          server.id,
          files: fileSnapshot.files,
          currentPath: fileSnapshot.resolvedPath,
        );
        break;
    }
  }

  Future<void> _refreshDashboard(String serverId, SshManager session) async {
    final systemInfo = await session.getSystemInfo();
    final resourceUsage = await session.getResourceUsage();
    await _cacheService.updateCache(
      serverId,
      systemInfo: systemInfo,
      resourceUsage: resourceUsage,
    );
    await _storageService.saveServers(
      (await _storageService.loadServers()).map((server) {
        if (server.id != serverId) {
          return server;
        }
        return server.copyWith(
          isOnline: true,
          osInfo: systemInfo.osInfo,
          kernelVersion: systemInfo.kernelVersion,
          uptime: systemInfo.uptime,
        );
      }).toList(),
    );
  }

  Future<void> _refreshDocker(String serverId, SshManager session) async {
    final installed = await session.isDockerInstalled();
    await _storageService.upsertCapability(
      serverId: serverId,
      dockerInstalled: installed,
      checkedAt: DateTime.now(),
    );
    if (!installed) {
      await _cacheService.updateCache(serverId, dockerContainers: const [], dockerImages: const []);
      return;
    }

    final containers = await session.getDockerContainers();
    final images = await session.getDockerImages();
    await _cacheService.updateCache(
      serverId,
      dockerContainers: containers,
      dockerImages: images,
    );
  }

  Future<void> _refreshFirewall(String serverId, SshManager session) async {
    final rules = await session.getFirewallRules();
    final enabled = await session.getFirewallEnabled();
    await _cacheService.updateCache(
      serverId,
      firewallRules: rules,
      firewallEnabled: enabled,
    );
  }

  Future<void> _updateServerOnlineState(String serverId, bool isOnline) async {
    final servers = await _storageService.loadServers();
    final updated = servers.map((server) {
      if (server.id != serverId) {
        return server;
      }
      return server.copyWith(isOnline: isOnline);
    }).toList();
    await _storageService.saveServers(updated);
  }
}
