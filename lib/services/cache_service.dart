import '../models/cache_data.dart';
import '../models/server.dart';
import 'storage_service.dart';

class CacheService {
  static const String dashboardScope = 'dashboard';
  static const String dockerScope = 'docker';
  static const String firewallScope = 'firewall';
  static const String portsScope = 'ports';
  static const String processesScope = 'processes';
  static const String servicesScope = 'services';
  static const String filesScope = 'files';

  final StorageService _storageService;
  final Map<String, CacheData> _memoryCache = {};

  CacheService(this._storageService);

  Future<void> saveCache(CacheData cache) async {
    _memoryCache[cache.serverId] = cache;
    await _storageService.saveCache(cache);
  }

  Future<CacheData?> getCache(String serverId) async {
    if (_memoryCache.containsKey(serverId)) {
      return _memoryCache[serverId];
    }
    final cache = await _storageService.loadCache(serverId);
    if (cache != null) {
      _memoryCache[serverId] = cache;
    }
    return cache;
  }

  Future<void> updateCache(String serverId, {
    SystemInfo? systemInfo,
    ResourceUsage? resourceUsage,
    Map<String, bool>? installedTools,
    List<ProcessInfo>? processes,
    List<PortInfo>? ports,
    List<ServiceInfo>? services,
    List<FirewallRule>? firewallRules,
    bool? firewallEnabled,
    List<DockerContainer>? dockerContainers,
    List<DockerImage>? dockerImages,
    List<FileInfo>? files,
    String? currentPath,
  }) async {
    var cache = await getCache(serverId);
    cache ??= CacheData(serverId: serverId, timestamp: DateTime.now());

    final now = DateTime.now();
    final nextScopeUpdatedAt = Map<String, String>.from(cache.scopeUpdatedAt);
    if (systemInfo != null || resourceUsage != null) {
      nextScopeUpdatedAt[dashboardScope] = now.toIso8601String();
    }
    if (processes != null) {
      nextScopeUpdatedAt[processesScope] = now.toIso8601String();
    }
    if (ports != null) {
      nextScopeUpdatedAt[portsScope] = now.toIso8601String();
    }
    if (services != null) {
      nextScopeUpdatedAt[servicesScope] = now.toIso8601String();
    }
    if (firewallRules != null || firewallEnabled != null) {
      nextScopeUpdatedAt[firewallScope] = now.toIso8601String();
    }
    if (dockerContainers != null || dockerImages != null) {
      nextScopeUpdatedAt[dockerScope] = now.toIso8601String();
    }
    if (files != null || currentPath != null) {
      nextScopeUpdatedAt[filesScope] = now.toIso8601String();
    }

    final updatedCache = cache.copyWith(
      timestamp: now,
      scopeUpdatedAt: nextScopeUpdatedAt,
      systemInfo: systemInfo,
      resourceUsage: resourceUsage,
      installedTools: installedTools,
      processes: processes,
      ports: ports,
      services: services,
      firewallRules: firewallRules,
      firewallEnabled: firewallEnabled,
      dockerContainers: dockerContainers,
      dockerImages: dockerImages,
      files: files,
      currentPath: currentPath,
    );

    await saveCache(updatedCache);
  }

  Future<void> invalidateCache(String serverId) async {
    _memoryCache.remove(serverId);
    await _storageService.deleteCache(serverId);
  }

  Future<void> clearAllCache() async {
    _memoryCache.clear();
    await _storageService.clearAllCache();
  }

  bool isCacheFresh(String serverId, Duration maxAge) {
    final cache = _memoryCache[serverId];
    if (cache == null) return false;
    return cache.isFresh(maxAge);
  }

  CacheData? getCacheSync(String serverId) {
    return _memoryCache[serverId];
  }

  DateTime? getScopeUpdatedAt(CacheData? cache, String scope) {
    if (cache == null) {
      return null;
    }
    final raw = cache.scopeUpdatedAt[scope];
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
