import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/refresh_scope.dart';
import '../core/ssh_engine.dart';
import '../core/ssh_manager.dart';
import '../models/cache_data.dart';
import '../models/server.dart';
import '../models/remote_control_models.dart';
import '../models/share_listener_config.dart';
import '../models/shared_server_models.dart';
import '../models/terminal_session_models.dart';
import '../services/ai_assistant_service.dart';
import '../services/cache_service.dart';
import '../services/license_limits_service.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';
import '../services/share/share_client.dart';
import '../services/share/share_listener_service.dart';

class BatchConnectivityCheckProgress {
  final int completed;
  final int total;
  final Server server;
  final bool? isOnline;

  const BatchConnectivityCheckProgress({
    required this.completed,
    required this.total,
    required this.server,
    this.isOnline,
  });
}

class BatchConnectivityCheckResult {
  final int checkedCount;
  final int onlineCount;
  final int offlineCount;
  final List<Server> failedServers;

  const BatchConnectivityCheckResult({
    required this.checkedCount,
    required this.onlineCount,
    required this.offlineCount,
    this.failedServers = const [],
  });
}

class ServerSelectionOption {
  final String id;
  final String title;
  final String subtitle;
  final bool isLocal;
  final bool isOnline;

  const ServerSelectionOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isLocal,
    required this.isOnline,
  });
}

class AppProvider extends ChangeNotifier {
  List<Server> _servers = [];
  Server? _selectedServer;
  List<SharedGroupRecord> _sharedGroups = [];
  SharedGroupRecord? _selectedSharedGroup;
  SharedServerRecord? _selectedSharedServer;
  bool _isLoading = false;
  String _errorMessage = '';
  final SshManager _sshManager = SshManager();
  final StorageService _storageService = StorageService();
  late final CacheService _cacheService;
  late final SshEngine _sshEngine;
  late final LlmService _llmService;
  late final AiAssistantService _aiAssistantService;
  late final ShareListenerService _shareListenerService;
  final LicenseLimitsService _licenseLimitsService = const LicenseLimitsService();
  RuntimeLicenseLimits _runtimeLimits = RuntimeLicenseLimits.free;
  List<String> _groups = [];
  CacheData? _currentCache;
  Timer? _dbRefreshTimer;
  String _currentScreen = 'dashboard';
  List<LlmProviderConfig> _llmProviders = [];
  List<AiSessionRecord> _aiSessions = [];
  final Map<String, List<AiMessageRecord>> _sessionMessages = {};
  final Map<String, Map<String, List<AiStepRecord>>> _sessionSteps = {};
  String? _activeAiSessionId;
  final Map<String, SshManager> _aiSessionManagers = {};
  final Map<String, ShareClient> _shareClients = {};
  ShareListenerConfig _shareListenerConfig = const ShareListenerConfig();
  bool _sharedConnected = false;
  List<AccessTokenRecord> _accessTokens = [];

  List<Server> get servers => _servers;
  List<SharedGroupRecord> get sharedGroups => _sharedGroups;
  Server? get selectedLocalServer => _selectedServer;
  SharedServerRecord? get selectedSharedServer => _selectedSharedServer;
  SharedGroupRecord? get selectedSharedGroup => _selectedSharedGroup;
  ShareClient? get currentShareClient =>
      isSharedSelection ? _selectedShareClient() : null;
  bool get isSharedSelection => _selectedSharedServer != null;
  ShareListenerConfig get shareListenerConfig => _shareListenerConfig;
  bool get isShareListenerRunning => _shareListenerService.isRunning;
  String? get shareListenerError => _shareListenerService.lastError;
  List<AccessTokenRecord> get accessTokens => _accessTokens;
  RuntimeLicenseLimits get runtimeLimits => _runtimeLimits;
  int get maxManagedServerCount => _runtimeLimits.maxManagedServers;
  int get maxConcurrentAccessTokenCount => _runtimeLimits.maxConcurrentAccessTokens;
  Duration get maxAccessTokenLifetime => _runtimeLimits.maxAccessTokenLifetime;
  int get activeAccessTokenCount => _accessTokens
      .where((token) => !token.isExpired && !token.isRevoked)
      .length;
  bool get canCreateAccessToken =>
      activeAccessTokenCount < maxConcurrentAccessTokenCount;
  Server? get selectedServer => isSharedSelection
      ? _buildSharedDisplayServer(_selectedSharedGroup!, _selectedSharedServer!)
      : _selectedServer;
  bool get isConnected {
    if (isSharedSelection) {
      return _sharedConnected;
    }
    final serverId = _selectedServer?.id;
    if (serverId == null) {
      return false;
    }
    return (_sshManager.isConnected &&
            _sshManager.currentServer?.id == serverId) ||
        _sshEngine.hasConnectedSession(serverId);
  }

  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;
  SshManager get sshManager => _sshManager;
  SshEngine get sshEngine => _sshEngine;
  CacheService get cacheService => _cacheService;
  StorageService get storageService => _storageService;
  CacheData? get currentCache => _currentCache;
  List<String> get groups => _groups;
  int get importedSharedServerCount => _sharedGroups.fold(
    0,
    (total, group) => total + group.servers.length,
  );
  int get totalManagedServerCount => _servers.length + importedSharedServerCount;
  int get remainingServerQuota => maxManagedServerCount - totalManagedServerCount;
  bool get canAddMoreServers => remainingServerQuota > 0;
  String get currentScreen => _currentScreen;
  List<LlmProviderConfig> get llmProviders => _llmProviders;
  SystemInfo? get currentSystemInfo => _currentCache?.systemInfo;
  List<AiSessionRecord> get aiSessions => _aiSessions;
  String? get activeAiSessionId => _activeAiSessionId;
  List<AiMessageRecord> get activeAiMessages => _activeAiSessionId == null
      ? const <AiMessageRecord>[]
      : (_sessionMessages[_activeAiSessionId] ?? const <AiMessageRecord>[]);
  Map<String, List<AiStepRecord>> get activeAiStepsByMessage => _activeAiSessionId == null
      ? const <String, List<AiStepRecord>>{}
      : (_sessionSteps[_activeAiSessionId] ?? const <String, List<AiStepRecord>>{});

  AiSessionRecord? get activeAiSession {
    if (_activeAiSessionId == null) {
      return null;
    }
    for (final session in _aiSessions) {
      if (session.id == _activeAiSessionId) {
        return session;
      }
    }
    return null;
  }

  LlmProviderConfig? get defaultLlmProvider {
    for (final provider in _llmProviders) {
      if (provider.isDefault && provider.enabled) {
        return provider;
      }
    }
    for (final provider in _llmProviders) {
      if (provider.enabled) {
        return provider;
      }
    }
    return null;
  }

  AppProvider() {
    _cacheService = CacheService(_storageService);
    _sshEngine = SshEngine(
      storageService: _storageService,
      cacheService: _cacheService,
    );
    _llmService = LlmService();
    _aiAssistantService = AiAssistantService(_storageService, _llmService);
    _shareListenerService = ShareListenerService(storageService: _storageService);
  }

  List<ServerSelectionOption> get serverSelectionOptions {
    final items = <ServerSelectionOption>[];
    for (final server in _servers) {
      items.add(
        ServerSelectionOption(
          id: server.id,
          title: server.name,
          subtitle: '${server.ip} · ${server.osDisplayLabel}',
          isLocal: true,
          isOnline: server.isOnline,
        ),
      );
    }
    for (final group in _sharedGroups) {
      for (final server in group.servers) {
        final display = _buildSharedDisplayServer(group, server);
        items.add(
          ServerSelectionOption(
            id: display.id,
            title: display.name,
            subtitle:
                '${group.displayName} @ ${group.sourceHostIp}:${group.sourcePort} · ${display.osDisplayLabel}',
            isLocal: false,
            isOnline: _sharedConnected && _selectedSharedServer?.id == server.id,
          ),
        );
      }
    }
    return items;
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _runtimeLimits = await _licenseLimitsService.loadRuntimeLimits();
      _servers = await _storageService.loadServers();
      _groups = await _storageService.loadGroups();
      _sharedGroups = await _storageService.loadImportedSharedGroups();
      _shareListenerConfig = await _storageService.loadShareListenerConfig();
      if (_shareListenerConfig.authMode == ShareAuthMode.none) {
        _shareListenerConfig = _shareListenerConfig.copyWith(
          authMode: ShareAuthMode.token,
          tokenHint: 'access-token',
        );
        await _storageService.saveShareListenerConfig(_shareListenerConfig);
      }
      _accessTokens = await _storageService.loadAccessTokens();
      await _enforceRuntimeLimits();
      final selectedId = await _storageService.loadSelectedServer();

      if (_groups.isEmpty) {
        _groups = ['默认分组'];
      }

      if (selectedId != null && selectedId.startsWith('shared::')) {
        _restoreSharedSelection(selectedId);
      } else if (selectedId != null) {
        for (final server in _servers) {
          if (server.id == selectedId) {
            _selectedServer = server;
            break;
          }
        }
      } else if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
      }

      if (selectedServer != null) {
        _currentCache = await _cacheService.getCache(selectedServer!.id);
      }
      _llmProviders = await _storageService.loadLlmProviderConfigs();
      await _loadAiSessions(notify: false);
      _sshEngine.start();
      if (_shareListenerConfig.enabled) {
        await _shareListenerService.start(_shareListenerConfig);
      }
      _startDbRefreshTimer();
    } catch (e) {
      _errorMessage = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> addServer(Server server) async {
    if (!canAddMoreServers) {
      _errorMessage =
          '个人免费版最多支持 $maxManagedServerCount 台总资源（本地 ${_servers.length} 台，共享 $importedSharedServerCount 台）';
      notifyListeners();
      throw Exception(_errorMessage);
    }
    final duplicate = _findDuplicateServer(server);
    if (duplicate != null) {
      throw Exception('已存在相同服务器：${duplicate.name}（${duplicate.ip} / ${duplicate.username}）');
    }

    _servers.add(server);
    await _storageService.saveServers(_servers);
    await _ensureGroupExists(server.group);
    notifyListeners();
    unawaited(_detectAndPersistServerPlatform(server.id));
  }

  Future<void> updateServer(Server updatedServer) async {
    final duplicate = _findDuplicateServer(updatedServer, ignoreId: updatedServer.id);
    if (duplicate != null) {
      throw Exception('已存在相同服务器：${duplicate.name}（${duplicate.ip} / ${duplicate.username}）');
    }
    final index = _servers.indexWhere((s) => s.id == updatedServer.id);
    if (index != -1) {
      _servers[index] = updatedServer;
      if (_selectedServer?.id == updatedServer.id) {
        _selectedServer = updatedServer;
      }
      await _storageService.saveServers(_servers);
      await _ensureGroupExists(updatedServer.group);
      notifyListeners();
      unawaited(_detectAndPersistServerPlatform(updatedServer.id));
      return;
    }
    notifyListeners();
  }

  Future<void> deleteServer(String serverId) async {
    _servers.removeWhere((s) => s.id == serverId);
    if (_selectedServer?.id == serverId) {
      _selectedServer = _servers.isNotEmpty ? _servers.first : null;
    }
    await _storageService.saveServers(_servers);
    await _cacheService.invalidateCache(serverId);
    if (_selectedServer != null) {
      await _storageService.saveSelectedServer(_selectedServer!.id);
    }
    notifyListeners();
  }

  Future<void> selectServer(Server server) async {
    _selectedServer = server;
    _selectedSharedGroup = null;
    _selectedSharedServer = null;
    _sharedConnected = false;
    _activeAiSessionId = null;
    _sshEngine.rememberServer(server);
    _currentCache = _cacheService.getCacheSync(server.id);
    notifyListeners();
    unawaited(_completeLocalServerSelection(server.id));
  }

  Future<void> selectServerById(String selectionId) async {
    if (selectionId.startsWith('shared::')) {
      final resolved = _resolveSharedSelectionByDisplayId(selectionId);
      if (resolved == null) {
        return;
      }
      await selectSharedServer(resolved.$1, resolved.$2);
      return;
    }
    final match = _servers.where((server) => server.id == selectionId);
    if (match.isNotEmpty) {
      await selectServer(match.first);
    }
  }

  Future<void> selectSharedServer(
    SharedGroupRecord group,
    SharedServerRecord server,
  ) async {
    _selectedSharedGroup = group;
    _selectedSharedServer = server;
    _selectedServer = null;
    _sharedConnected = false;
    _activeAiSessionId = null;
    final selectedId = _sharedSelectionDisplayId(group, server);
    _currentCache = _cacheService.getCacheSync(selectedId);
    notifyListeners();
    unawaited(_completeSharedServerSelection(group, server));
  }

  Future<bool> connectToServer() async {
    final connectSelectionId = selectedServer?.id;
    if (connectSelectionId == null) {
      _errorMessage = '请先选择服务器';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    if (isSharedSelection) {
      try {
        final success = await _ensureSharedConnection();
        _sharedConnected = success;
        final isStaleSelection = selectedServer?.id != connectSelectionId;
        if (isStaleSelection) {
          _isLoading = false;
          notifyListeners();
          return success;
        }
        if (success) {
          _errorMessage = '';
          await requestRefreshNow(_scopeForCurrentScreen(), reason: 'manual-shared-connect');
        } else {
          _errorMessage = '共享侦听端口连接失败';
        }
        _isLoading = false;
        notifyListeners();
        return success;
      } catch (error) {
        final isStaleSelection = selectedServer?.id != connectSelectionId;
        if (isStaleSelection) {
          _isLoading = false;
          notifyListeners();
          return false;
        }
        _errorMessage = error.toString();
        _isLoading = false;
        notifyListeners();
        return false;
      }
    }

    final success = await _sshManager.connect(_selectedServer!);
    final isStaleSelection = selectedServer?.id != connectSelectionId;

    if (success) {
      await _updateSelectedServerOnlineStatus(true);
      if (!isStaleSelection && _selectedServer != null) {
        _sshEngine.rememberServer(_selectedServer!);
        await _sshEngine.ensureConnected(_selectedServer!);
        await requestRefreshNow(RefreshScope.dashboard, reason: 'manual-connect');
      }
      await reloadServers(notify: false);
      await reloadSelectedServerCache(notify: false);
    } else {
      if (!isStaleSelection) {
        _errorMessage = _sshManager.errorMessage ?? '连接失败';
      }
      await _updateSelectedServerOnlineStatus(false);
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> ensureTerminalConnection() async {
    final connectSelectionId = selectedServer?.id;
    if (connectSelectionId == null) {
      _errorMessage = '请先选择服务器';
      notifyListeners();
      return false;
    }

    if (isSharedSelection) {
      try {
        _sharedConnected = await _ensureSharedConnection();
        final isStaleSelection = selectedServer?.id != connectSelectionId;
        if (isStaleSelection) {
          notifyListeners();
          return _sharedConnected;
        }
        if (!_sharedConnected) {
          _errorMessage = '共享侦听端口连接失败';
        } else {
          _errorMessage = '';
        }
        notifyListeners();
        return _sharedConnected;
      } catch (error) {
        if (selectedServer?.id != connectSelectionId) {
          notifyListeners();
          return false;
        }
        _errorMessage = error.toString();
        notifyListeners();
        return false;
      }
    }

    if (_sshManager.isConnected &&
        _sshManager.currentServer?.id == _selectedServer!.id) {
      return true;
    }

    final success = await _sshManager.connect(_selectedServer!);
    final isStaleSelection = selectedServer?.id != connectSelectionId;
    if (success) {
      if (!isStaleSelection) {
        _errorMessage = '';
      }
      await _updateSelectedServerOnlineStatus(true);
    } else {
      if (!isStaleSelection) {
        _errorMessage = _sshManager.errorMessage ?? '连接失败';
      }
      await _updateSelectedServerOnlineStatus(false);
    }
    notifyListeners();
    return success;
  }

  void disconnect() {
    if (isSharedSelection) {
      _sharedConnected = false;
    }
    _sshManager.disconnect();
    notifyListeners();
  }

  Future<void> refreshCache() async {
    await requestRefreshNow(_scopeForCurrentScreen(), reason: 'global-refresh');
  }

  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void setErrorMessage(String message) {
    _errorMessage = message;
    notifyListeners();
  }

  void clearErrorMessage() {
    _errorMessage = '';
    notifyListeners();
  }

  Future<void> addGroup(String groupName) async {
    final normalizedName = groupName.trim();
    if (normalizedName.isEmpty) {
      return;
    }

    if (!_groups.contains(normalizedName)) {
      _groups.add(normalizedName);
      await _storageService.saveGroups(_groups);
      notifyListeners();
    }
  }

  Future<void> renameGroup({
    required String oldName,
    required String newName,
  }) async {
    final normalizedOld = oldName.trim();
    final normalizedNew = newName.trim();
    if (normalizedOld.isEmpty || normalizedNew.isEmpty) {
      throw Exception('分组名称不能为空');
    }
    if (normalizedOld == '默认分组') {
      throw Exception('默认分组不支持重命名');
    }
    if (!_groups.contains(normalizedOld)) {
      throw Exception('分组不存在');
    }
    if (_groups.contains(normalizedNew) && normalizedNew != normalizedOld) {
      throw Exception('分组名称已存在');
    }

    _groups = _groups.map((group) {
      return group == normalizedOld ? normalizedNew : group;
    }).toList();
    _servers = _servers.map((server) {
      return server.group == normalizedOld
          ? server.copyWith(group: normalizedNew)
          : server;
    }).toList();
    if (_selectedServer != null && _selectedServer!.group == normalizedOld) {
      final index = _servers.indexWhere((server) => server.id == _selectedServer!.id);
      if (index != -1) {
        _selectedServer = _servers[index];
      }
    }
    await _storageService.saveServers(_servers);
    await _storageService.saveGroups(_groups);
    notifyListeners();
  }

  Future<void> deleteGroup(String groupName) async {
    final normalizedName = groupName.trim();
    if (normalizedName.isEmpty) {
      throw Exception('分组名称不能为空');
    }
    if (normalizedName == '默认分组') {
      throw Exception('默认分组不支持删除');
    }
    if (!_groups.contains(normalizedName)) {
      throw Exception('分组不存在');
    }

    _groups.removeWhere((group) => group == normalizedName);
    _servers = _servers.map((server) {
      return server.group == normalizedName
          ? server.copyWith(group: '默认分组')
          : server;
    }).toList();
    if (_selectedServer != null && _selectedServer!.group == normalizedName) {
      final index = _servers.indexWhere((server) => server.id == _selectedServer!.id);
      if (index != -1) {
        _selectedServer = _servers[index];
      }
    }
    await _storageService.saveServers(_servers);
    await _storageService.saveGroups(_groups);
    notifyListeners();
  }

  Future<void> saveOperationLog({
    required String command,
    required String result,
  }) async {
    final selected = selectedServer;
    if (selected == null) {
      return;
    }

    await _storageService.saveOperationLog(
      OperationLog(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        command: command,
        serverId: selected.id,
        serverName: selected.name,
        timestamp: DateTime.now(),
        result: result,
      ),
    );
  }

  Future<List<OperationLog>> loadRecentLogs({int limit = 50}) async {
    return _storageService.loadRecentOperationLogs(
      serverId: selectedServer?.id,
      limit: limit,
    );
  }

  Future<void> reloadSelectedServerCache({bool notify = true}) async {
    final selected = selectedServer;
    if (selected == null) {
      return;
    }
    _currentCache = await _cacheService.getCache(selected.id);
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> reloadServers({bool notify = true}) async {
    _servers = await _storageService.loadServers();
    _groups = await _storageService.loadGroups();
    _sharedGroups = await _storageService.loadImportedSharedGroups();
    if (_selectedServer != null) {
      final selected = _servers.where((server) => server.id == _selectedServer!.id).toList();
      if (selected.isNotEmpty) {
        _selectedServer = selected.first;
      } else {
        _selectedServer = _servers.isNotEmpty ? _servers.first : null;
      }
    } else if (_servers.isNotEmpty) {
      _selectedServer = _servers.first;
    }
    if (_selectedSharedServer != null && _selectedSharedGroup != null) {
      final resolved = _resolveSharedSelectionByDisplayId(
        _sharedSelectionDisplayId(_selectedSharedGroup!, _selectedSharedServer!),
      );
      if (resolved == null) {
        _selectedSharedGroup = null;
        _selectedSharedServer = null;
        _sharedConnected = false;
      } else {
        _selectedSharedGroup = resolved.$1;
        _selectedSharedServer = resolved.$2;
      }
    }
    if (notify) {
      notifyListeners();
    }
  }

  Future<BatchConnectivityCheckResult> batchCheckConnectivity({
    List<Server>? targets,
    void Function(BatchConnectivityCheckProgress progress)? onProgress,
  }) async {
    final targetServers = List<Server>.from(targets ?? _servers);
    if (targetServers.isEmpty) {
      return const BatchConnectivityCheckResult(
        checkedCount: 0,
        onlineCount: 0,
        offlineCount: 0,
      );
    }

    final failures = <Server>[];
    var onlineCount = 0;
    for (var index = 0; index < targetServers.length; index++) {
      final server = targetServers[index];
      onProgress?.call(
        BatchConnectivityCheckProgress(
          completed: index,
          total: targetServers.length,
          server: server,
        ),
      );
      final manager = SshManager();
      var isOnline = false;
      try {
        final connected = await manager
            .connect(server)
            .timeout(const Duration(seconds: 8));
        if (connected) {
          isOnline = await manager
              .checkConnection()
              .timeout(const Duration(seconds: 4), onTimeout: () => false);
        }
      } catch (_) {
        isOnline = false;
      } finally {
        manager.disconnect();
      }

      final serverIndex = _servers.indexWhere((item) => item.id == server.id);
      if (serverIndex != -1) {
        _servers[serverIndex] = _servers[serverIndex].copyWith(isOnline: isOnline);
      }
      if (isOnline) {
        onlineCount++;
      } else {
        failures.add(server);
      }
      if (_selectedServer?.id == server.id && serverIndex != -1) {
        _selectedServer = _servers[serverIndex];
      }
      onProgress?.call(
        BatchConnectivityCheckProgress(
          completed: index + 1,
          total: targetServers.length,
          server: server,
          isOnline: isOnline,
        ),
      );
    }

    await _storageService.saveServers(_servers);
    notifyListeners();
    return BatchConnectivityCheckResult(
      checkedCount: targetServers.length,
      onlineCount: onlineCount,
      offlineCount: targetServers.length - onlineCount,
      failedServers: failures,
    );
  }

  Future<void> onPageEnter(RefreshScope scope, {String? filePath}) async {
    final selected = selectedServer;
    if (selected == null) {
      return;
    }
    _currentScreen = scope.key;
    await _storageService.addUsageEvent(serverId: selected.id, pageKey: scope.key);
    await reloadSelectedServerCache(notify: false);
    notifyListeners();
    await requestRefreshIfStale(scope, reason: 'page-enter', filePath: filePath);
  }

  Future<void> requestRefreshIfStale(
    RefreshScope scope, {
    required String reason,
    String? filePath,
  }) async {
    final selected = selectedServer;
    if (selected == null) {
      return;
    }
    final serverId = selected.id;
    if (isSharedSelection) {
      final ready = await _ensureSharedConnection(notifyOnFailure: false);
      if (!ready) {
        notifyListeners();
        return;
      }
      try {
        await _refreshSharedScope(
          scope,
          filePath: filePath,
          force: false,
        );
      } catch (error) {
        _sharedConnected = false;
        _errorMessage = error.toString();
        notifyListeners();
      }
      return;
    }
    _sshEngine.rememberServer(_selectedServer!);
    final before = (await _cacheService.getCache(serverId))?.scopeUpdatedAt[scope.key];
    await _sshEngine.enqueue(
      RefreshEvent(
        serverId: serverId,
        scope: scope,
        reason: reason,
        filePath: filePath,
      ),
    );
    await _awaitScopeUpdate(serverId, scope.key, before);
  }

  Future<void> requestRefreshNow(
    RefreshScope scope, {
    required String reason,
    String? filePath,
  }) async {
    final selected = selectedServer;
    if (selected == null) {
      return;
    }
    final serverId = selected.id;
    if (isSharedSelection) {
      final ready = await _ensureSharedConnection();
      if (!ready) {
        _isLoading = false;
        notifyListeners();
        return;
      }
      try {
        await _refreshSharedScope(
          scope,
          filePath: filePath,
          force: true,
        );
        await reloadSelectedServerCache(notify: false);
        notifyListeners();
      } catch (error) {
        _sharedConnected = false;
        _errorMessage = error.toString();
        notifyListeners();
      }
      return;
    }
    _sshEngine.rememberServer(_selectedServer!);
    final before = (await _cacheService.getCache(serverId))?.scopeUpdatedAt[scope.key];
    await _sshEngine.enqueue(
      RefreshEvent(
        serverId: serverId,
        scope: scope,
        reason: reason,
        force: true,
        filePath: filePath,
      ),
    );
    await _awaitScopeUpdate(serverId, scope.key, before);
    await reloadSelectedServerCache(notify: false);
    await reloadServers(notify: false);
    notifyListeners();
  }

  void setCurrentScreen(String screen) {
    _currentScreen = screen;
    notifyListeners();
  }

  Future<void> saveLlmProvider(LlmProviderConfig config) async {
    await _storageService.saveLlmProviderConfig(config);
    _llmProviders = await _storageService.loadLlmProviderConfigs();
    notifyListeners();
  }

  Future<void> deleteLlmProvider(String id) async {
    await _storageService.deleteLlmProviderConfig(id);
    _llmProviders = await _storageService.loadLlmProviderConfigs();
    notifyListeners();
  }

  Future<LlmTestConnectionResult> testLlmProvider(
    LlmProviderConfig config,
  ) async {
    return _llmService.testConnection(config);
  }

  Future<bool> startAiPrompt(String prompt) async {
    final server = selectedServer;
    final llmProvider = defaultLlmProvider;
    if (server == null) {
      _errorMessage = '请先选择服务器';
      notifyListeners();
      return false;
    }
    if (llmProvider == null) {
      _errorMessage = '请先在系统设置中配置 LLM';
      notifyListeners();
      return false;
    }
    if (_activeAiSessionId == null) {
      final executor = await _buildAiExecutorForCurrentSelection(server.id);
      if (executor == null) {
        return false;
      }
      final snapshot = await _aiAssistantService.createSession(
        server: server,
        provider: llmProvider,
        executor: executor,
        initialPrompt: prompt,
        auditLogger: _buildAiAuditLoggerForCurrentSelection(),
        onChanged: _syncAiRuntimeState,
      );
      if (!isSharedSelection) {
        _aiSessionManagers[snapshot.session.id] =
            (executor as LocalAiCommandExecutor).manager;
      }
      _activeAiSessionId = snapshot.session.id;
    } else {
      final prepared = await _ensureAiSessionRuntime(
        sessionId: _activeAiSessionId!,
        server: server,
        provider: llmProvider,
      );
      if (!prepared) {
        return false;
      }
      await _aiAssistantService.appendUserPrompt(
        sessionId: _activeAiSessionId!,
        prompt: prompt,
        onChanged: _syncAiRuntimeState,
      );
    }
    await _loadAiSessions(notify: false);
    _syncAiRuntimeState();
    notifyListeners();
    return true;
  }

  Future<void> createAiSession() async {
    final server = selectedServer;
    final llmProvider = defaultLlmProvider;
    if (server == null || llmProvider == null) {
      return;
    }
    final executor = await _buildAiExecutorForCurrentSelection(server.id);
    if (executor == null) {
      return;
    }
    final snapshot = await _aiAssistantService.createSession(
      server: server,
      provider: llmProvider,
      executor: executor,
      auditLogger: _buildAiAuditLoggerForCurrentSelection(),
      onChanged: _syncAiRuntimeState,
    );
    if (!isSharedSelection) {
      _aiSessionManagers[snapshot.session.id] =
          (executor as LocalAiCommandExecutor).manager;
    }
    _activeAiSessionId = snapshot.session.id;
    await _loadAiSessions(notify: false);
    notifyListeners();
  }

  Future<void> approveAiStep(
    String sessionId,
    String messageId,
    String stepId, {
    bool execute = true,
  }) async {
    await _aiAssistantService.approveStep(
      sessionId,
      messageId,
      stepId,
      execute: execute,
    );
  }

  Future<void> interruptAiSession(String sessionId) async {
    await _aiAssistantService.interruptSession(
      sessionId,
      onChanged: _syncAiRuntimeState,
    );
    await _loadAiSessions(notify: false);
    notifyListeners();
  }

  Future<void> loadAiSessionMessages(String sessionId) async {
    final messages = await _storageService.loadAiMessages(sessionId);
    _sessionMessages[sessionId] = messages;
    final stepsByMessage = <String, List<AiStepRecord>>{};
    for (final message in messages) {
      if (message.role == AiMessageRole.assistant) {
        stepsByMessage[message.id] = await _storageService.loadAiMessageSteps(message.id);
      }
    }
    _sessionSteps[sessionId] = stepsByMessage;
    notifyListeners();
  }

  void selectAiSession(String sessionId) {
    _activeAiSessionId = sessionId;
    unawaited(loadAiSessionMessages(sessionId));
    notifyListeners();
  }

  Future<void> deleteAiSession(String sessionId) async {
    await _storageService.deleteAiSession(sessionId);
    _aiSessionManagers.remove(sessionId)?.disconnect();
    _aiAssistantService.removeRuntimeSession(sessionId);
    _sessionMessages.remove(sessionId);
    _sessionSteps.remove(sessionId);
    if (_activeAiSessionId == sessionId) {
      _activeAiSessionId = null;
    }
    await _loadAiSessions(notify: false);
    notifyListeners();
  }

  Future<void> renameAiSession(String sessionId, String title) async {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      return;
    }
    await _storageService.renameAiSession(sessionId, normalized);
    _aiSessions = _aiSessions.map((session) {
      if (session.id == sessionId) {
        return session.copyWith(
          title: normalized,
          updatedAt: DateTime.now(),
        );
      }
      return session;
    }).toList();
    final runtimeSnapshots = _aiAssistantService.runtimeSessions;
    for (final snapshot in runtimeSnapshots) {
      if (snapshot.session.id == sessionId) {
        _syncAiRuntimeState();
        break;
      }
    }
    notifyListeners();
  }

  Future<void> _ensureGroupExists(String groupName) async {
    final normalizedName = groupName.trim().isEmpty ? '默认分组' : groupName.trim();
    if (_groups.contains(normalizedName)) {
      return;
    }

    _groups.add(normalizedName);
    await _storageService.saveGroups(_groups);
  }

  Future<void> _updateSelectedServerOnlineStatus(bool isOnline) async {
    if (_selectedServer == null) {
      return;
    }
    final index = _servers.indexWhere((s) => s.id == _selectedServer!.id);
    if (index == -1) {
      return;
    }
    _servers[index] = _servers[index].copyWith(isOnline: isOnline);
    _selectedServer = _servers[index];
    await _storageService.saveServers(_servers);
  }

  RefreshScope _scopeForCurrentScreen() {
    switch (_currentScreen) {
      case 'docker':
        return RefreshScope.docker;
      case 'firewall':
        return RefreshScope.firewall;
      case 'ports':
        return RefreshScope.ports;
      case 'processes':
        return RefreshScope.processes;
      case 'services':
        return RefreshScope.services;
      case 'files':
        return RefreshScope.files;
      case 'dashboard':
      default:
        return RefreshScope.dashboard;
    }
  }

  void _startDbRefreshTimer() {
    _dbRefreshTimer?.cancel();
    _dbRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      await reloadSelectedServerCache(notify: true);
      await reloadServers(notify: true);
    });
  }

  Future<void> _loadAiSessions({bool notify = true}) async {
    final currentServerId = selectedServer?.id;
    _aiSessions = await _storageService.loadAiSessions(
      serverId: currentServerId,
      limit: 30,
    );
    _sessionMessages.removeWhere((sessionId, _) {
      return !_aiSessions.any((session) => session.id == sessionId);
    });
    _sessionSteps.removeWhere((sessionId, _) {
      return !_aiSessions.any((session) => session.id == sessionId);
    });
    for (final session in _aiSessions.take(5)) {
      final messages = await _storageService.loadAiMessages(session.id);
      _sessionMessages[session.id] = messages;
      final stepsByMessage = <String, List<AiStepRecord>>{};
      for (final message in messages) {
        if (message.role == AiMessageRole.assistant) {
          stepsByMessage[message.id] = await _storageService.loadAiMessageSteps(message.id);
        }
      }
      _sessionSteps[session.id] = stepsByMessage;
    }
    if (_activeAiSessionId != null &&
        !_aiSessions.any((session) => session.id == _activeAiSessionId)) {
      _activeAiSessionId = null;
    }
    _activeAiSessionId ??= _aiSessions.isEmpty ? null : _aiSessions.first.id;
    if (notify) {
      notifyListeners();
    }
  }

  void _syncAiRuntimeState() {
    final snapshots = _aiAssistantService.runtimeSessions;
    for (final snapshot in snapshots) {
      _sessionMessages[snapshot.session.id] = snapshot.messages;
      _sessionSteps[snapshot.session.id] = snapshot.stepsByMessageId;
    }
    unawaited(_loadAiSessions(notify: false).then((_) => notifyListeners()));
  }

  Future<bool> _ensureAiSessionRuntime({
    required String sessionId,
    required Server server,
    required LlmProviderConfig provider,
  }) async {
    if (_aiAssistantService.hasRuntimeSession(sessionId)) {
      if (isSharedSelection) {
        return true;
      }
      final existingManager = _aiSessionManagers[sessionId];
      if (existingManager != null &&
          existingManager.isConnected &&
          existingManager.currentServer?.id == server.id) {
        return true;
      }
    }

    final executor = await _buildAiExecutorForCurrentSelection(server.id);
    if (executor == null) {
      return false;
    }
    if (!isSharedSelection) {
      _aiSessionManagers[sessionId] = (executor as LocalAiCommandExecutor).manager;
    }

    AiSessionRecord? session;
    for (final item in _aiSessions) {
      if (item.id == sessionId) {
        session = item;
        break;
      }
    }
    if (session == null) {
      _errorMessage = '会话不存在';
      notifyListeners();
      return false;
    }
    final messages = _sessionMessages[sessionId] ?? await _storageService.loadAiMessages(sessionId);
    _sessionMessages[sessionId] = messages;
    final stepsByMessage = _sessionSteps[sessionId] ?? <String, List<AiStepRecord>>{};
    if (stepsByMessage.isEmpty) {
      for (final message in messages) {
        if (message.role == AiMessageRole.assistant) {
          stepsByMessage[message.id] = await _storageService.loadAiMessageSteps(message.id);
        }
      }
      _sessionSteps[sessionId] = stepsByMessage;
    }

    await _aiAssistantService.attachSessionRuntime(
      session: session,
      messages: messages,
      stepsByMessageId: stepsByMessage,
      server: server,
      provider: provider,
      executor: executor,
      auditLogger: _buildAiAuditLoggerForCurrentSelection(),
      onChanged: _syncAiRuntimeState,
    );
    return true;
  }

  Future<void> _awaitScopeUpdate(String serverId, String scopeKey, String? before) async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (selectedServer?.id != serverId) {
        return;
      }
      final cache = await _cacheService.getCache(serverId);
      final next = cache?.scopeUpdatedAt[scopeKey];
      if (next != null && next.isNotEmpty && next != before) {
        _currentCache = cache;
        notifyListeners();
        return;
      }
    }
  }

  Future<void> updateShareListenerConfig(ShareListenerConfig config) async {
    _shareListenerConfig = config;
    await _storageService.saveShareListenerConfig(config);
    notifyListeners();
  }

  Future<String> exportSharedGroupToJson({
    required String groupName,
    required List<Server> servers,
    required String targetPath,
  }) {
    return _storageService.exportSharedGroupToJson(
      groupName: groupName,
      port: _shareListenerConfig.port,
      servers: servers,
      targetPath: targetPath,
    );
  }

  Future<SharedGroupRecord> importSharedGroupFromJson({
    required String filePath,
    required String accessToken,
    String? displayNameOverride,
  }) async {
    final payload = await _storageService.readSharedGroupImportPayload(
      filePath: filePath,
    );
    final nextTotal = totalManagedServerCount + payload.servers.length;
    if (nextTotal > maxManagedServerCount) {
      throw Exception(
        '导入失败：当前已有 $totalManagedServerCount 台资源（本地 ${_servers.length} 台，共享 $importedSharedServerCount 台），'
        '该共享组包含 ${payload.servers.length} 台，导入后会超过免费版上限 $maxManagedServerCount 台',
      );
    }
    final client = ShareClient(
      baseUri: Uri.parse('http://${payload.hostIp.trim()}:${payload.port}'),
      accessToken: accessToken.trim(),
    );
    final validation = await client.verifyAccessToken();
    if (!validation.valid || validation.tokenId == null) {
      throw Exception(validation.message.isEmpty ? 'token 验证失败' : validation.message);
    }
    final group = await _storageService.importSharedGroupFromJson(
      filePath: filePath,
      displayNameOverride: displayNameOverride,
      accessToken: accessToken.trim(),
      accessTokenId: validation.tokenId ?? '',
      accessTokenNote: validation.tokenNote,
      verifiedAt: DateTime.now(),
      verifyStatus: 'verified',
    );
    _sharedGroups = await _storageService.loadImportedSharedGroups();
    notifyListeners();
    return group;
  }

  Future<void> renameSharedGroup({
    required String groupId,
    required String displayName,
  }) async {
    await _storageService.renameImportedSharedGroup(
      groupId: groupId,
      displayName: displayName,
    );
    _sharedGroups = await _storageService.loadImportedSharedGroups();
    if (_selectedSharedGroup?.id == groupId) {
      _selectedSharedGroup = _sharedGroups.where((item) => item.id == groupId).firstOrNull;
    }
    notifyListeners();
  }

  Future<void> deleteSharedGroup(String groupId) async {
    await _storageService.deleteImportedSharedGroup(groupId);
    _sharedGroups = await _storageService.loadImportedSharedGroups();
    if (_selectedSharedGroup?.id == groupId) {
      _selectedSharedGroup = null;
      _selectedSharedServer = null;
      _sharedConnected = false;
      if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
        await _storageService.saveSelectedServer(_selectedServer!.id);
        _currentCache = await _cacheService.getCache(_selectedServer!.id);
      }
    }
    notifyListeners();
  }

  Future<void> setShareListenerEnabled(bool enabled) async {
    final next = _shareListenerConfig.copyWith(enabled: enabled);
    await updateShareListenerConfig(next);
    if (enabled) {
      await _shareListenerService.start(next);
    } else {
      await _shareListenerService.stop();
    }
    notifyListeners();
  }

  Future<void> restartShareListener({int? port}) async {
    final next = _shareListenerConfig.copyWith(
      enabled: true,
      port: port ?? _shareListenerConfig.port,
    );
    await updateShareListenerConfig(next);
    await _shareListenerService.start(next);
    notifyListeners();
  }

  Future<bool> testShareEndpoint({
    required String host,
    required int port,
    String accessToken = '',
  }) async {
    final client = ShareClient(
      baseUri: Uri.parse('http://$host:$port'),
      accessToken: accessToken.trim(),
    );
    final success = await client.healthCheck();
    return success;
  }

  Future<AccessTokenRecord> createAccessToken({
    required String note,
    required DateTime expiresAt,
  }) async {
    if (!canCreateAccessToken) {
      throw Exception(
        '个人免费版同时最多保留 $maxConcurrentAccessTokenCount 个生效中的 access-token，请先删除或失效旧 token',
      );
    }
    final now = DateTime.now();
    final maxExpiresAt = now.add(maxAccessTokenLifetime);
    final normalizedExpiresAt = expiresAt.isAfter(maxExpiresAt)
        ? maxExpiresAt
        : expiresAt;
    final token = AccessTokenRecord(
      id: now.microsecondsSinceEpoch.toString(),
      tokenValue: _generateAccessTokenValue(now),
      note: note.trim(),
      createdAt: now,
      expiresAt: normalizedExpiresAt,
    );
    await _storageService.saveAccessToken(token);
    _accessTokens = await _storageService.loadAccessTokens();
    notifyListeners();
    return token;
  }

  Future<void> deleteAccessToken(String tokenId) async {
    await _storageService.deleteAccessToken(tokenId);
    _accessTokens = await _storageService.loadAccessTokens();
    notifyListeners();
  }

  Future<void> setAccessTokenRevoked(String tokenId, bool revoked) async {
    if (revoked) {
      await _storageService.revokeAccessToken(tokenId);
    } else {
      if (!canCreateAccessToken) {
        throw Exception(
          '个人免费版同时最多保留 $maxConcurrentAccessTokenCount 个生效中的 access-token，请先删除、失效或等待过期后再启用',
        );
      }
      await _storageService.reactivateAccessToken(tokenId);
    }
    _accessTokens = await _storageService.loadAccessTokens();
    notifyListeners();
  }

  Future<void> refreshRemoteControlState({bool notify = true}) async {
    _accessTokens = await _storageService.loadAccessTokens();
    await _enforceActiveAccessTokenLimit();
    if (notify) {
      notifyListeners();
    }
  }

  Future<List<RemoteAuditRecord>> loadRemoteAuditLogs({
    String? accessTokenId,
    RemoteAuditCategory? category,
    int limit = 200,
  }) async {
    final logs = await _storageService.loadRemoteAuditLogs(
      accessTokenId: accessTokenId,
      category: category,
      limit: limit,
    );
    _accessTokens = await _storageService.loadAccessTokens();
    notifyListeners();
    return logs;
  }

  Future<String> executeSelectedCommand(
    String command, {
    bool privileged = false,
    bool userShell = false,
  }) async {
    if (isSharedSelection) {
      final client = _selectedShareClient();
      final server = _selectedSharedServer!;
      return client.executeCommand(
        serverId: server.remoteServerId,
        command: command,
        privileged: privileged,
        userShell: userShell,
        serverName: server.displayName,
        sharedGroupId: _selectedSharedGroup!.id,
        sharedGroupName: _selectedSharedGroup!.displayName,
      );
    }
    await _ensureSelectedLocalManagerConnected();
    if (privileged) {
      return _sshManager.executePrivilegedCommand(command);
    }
    if (userShell) {
      return _sshManager.executeUserCommand(command);
    }
    return _sshManager.executeCommand(command);
  }

  bool get supportsInteractiveTerminal => selectedServer != null;

  Future<TerminalSessionHandle> openSelectedTerminalSession({
    int columns = 120,
    int rows = 32,
  }) async {
    if (isSharedSelection) {
      final ready = await _ensureSharedConnection();
      if (!ready) {
        throw Exception(_errorMessage.isEmpty ? '共享侦听端口连接失败' : _errorMessage);
      }
      final group = _selectedSharedGroup!;
      final server = _selectedSharedServer!;
      return _selectedShareClient().openTerminalSession(
        serverId: server.remoteServerId,
        columns: columns,
        rows: rows,
        serverName: server.displayName,
        sharedGroupId: group.id,
        sharedGroupName: group.displayName,
      );
    }
    await _ensureSelectedLocalManagerConnected();
    final localHandle = await _sshManager.openShellSession(
      columns: columns,
      rows: rows,
    );
    return TerminalSessionHandle(
      sessionId: localHandle.sessionId,
      stream: localHandle.stream,
      done: localHandle.done.then((result) {
        return TerminalSessionResult(
          exitCode: result.exitCode,
          disconnected: result.disconnected,
        );
      }),
      write: localHandle.write,
      resize: localHandle.resize,
      close: localHandle.close,
    );
  }

  Future<DirectoryResolution> resolveSelectedDirectory(
    String? path, {
    bool fallbackToParent = false,
  }) async {
    if (isSharedSelection) {
      return _selectedShareClient().resolveDirectory(
        serverId: _selectedSharedServer!.remoteServerId,
        path: path,
        fallbackToParent: fallbackToParent,
        serverName: _selectedSharedServer!.displayName,
        sharedGroupId: _selectedSharedGroup!.id,
        sharedGroupName: _selectedSharedGroup!.displayName,
      );
    }
    return _sshManager.resolveDirectory(
      path,
      fallbackToParent: fallbackToParent,
    );
  }

  Future<String> createDirectorySelected(String path) async {
    if (isSharedSelection) {
      return _selectedShareClient().createDirectory(
        serverId: _selectedSharedServer!.remoteServerId,
        path: path,
        serverName: _selectedSharedServer!.displayName,
        sharedGroupId: _selectedSharedGroup!.id,
        sharedGroupName: _selectedSharedGroup!.displayName,
      );
    }
    return _sshManager.createDirectory(path);
  }

  Future<String> writeFileSelected(String path, String content) async {
    if (isSharedSelection) {
      return _selectedShareClient().writeFile(
        serverId: _selectedSharedServer!.remoteServerId,
        path: path,
        content: content,
        serverName: _selectedSharedServer!.displayName,
        sharedGroupId: _selectedSharedGroup!.id,
        sharedGroupName: _selectedSharedGroup!.displayName,
      );
    }
    return _sshManager.writeFile(path, content);
  }

  Future<String> deleteFileSelected(String path) async {
    if (isSharedSelection) {
      return _selectedShareClient().deleteFile(
        serverId: _selectedSharedServer!.remoteServerId,
        path: path,
        serverName: _selectedSharedServer!.displayName,
        sharedGroupId: _selectedSharedGroup!.id,
        sharedGroupName: _selectedSharedGroup!.displayName,
      );
    }
    return _sshManager.deleteFile(path);
  }

  Future<String> renameFileSelected(String oldPath, String newPath) async {
    if (isSharedSelection) {
      return _selectedShareClient().renameFile(
        serverId: _selectedSharedServer!.remoteServerId,
        oldPath: oldPath,
        newPath: newPath,
        serverName: _selectedSharedServer!.displayName,
        sharedGroupId: _selectedSharedGroup!.id,
        sharedGroupName: _selectedSharedGroup!.displayName,
      );
    }
    return _sshManager.renameFile(oldPath, newPath);
  }

  Future<void> killProcess(int pid, {bool force = false}) async {
    final command = force ? 'kill -9 $pid' : 'kill $pid';
    await executeSelectedCommand(command, privileged: true);
  }

  Future<String> manageServiceSelected({
    required String serviceName,
    required String action,
  }) async {
    if (!isSharedSelection) {
      return _sshManager.manageService(serviceName: serviceName, action: action);
    }
    final serviceManager = _effectiveServiceManager();
    return executeSelectedCommand(
      LinuxPlatformSupport.buildServiceCommand(
        serviceManager: serviceManager,
        serviceName: serviceName,
        action: action,
      ),
      privileged: true,
    );
  }

  Future<String> getServiceLogsSelected(String serviceName, {int lines = 80}) async {
    if (!isSharedSelection) {
      return _sshManager.getServiceLogs(serviceName, lines: lines);
    }
    final serviceManager = _effectiveServiceManager();
    return executeSelectedCommand(
      LinuxPlatformSupport.buildServiceLogCommand(
        serviceManager: serviceManager,
        serviceName: serviceName,
        lines: lines,
      ),
      privileged: true,
    );
  }

  Future<String> createManagedServiceSelected({
    required String serviceName,
    required String execStart,
    required String workingDirectory,
    required String description,
    String? arguments,
    String? logPath,
  }) async {
    if (!isSharedSelection) {
      return _sshManager.createManagedService(
        serviceName: serviceName,
        execStart: execStart,
        workingDirectory: workingDirectory,
        description: description,
        arguments: arguments,
        logPath: logPath,
      );
    }
    if (_effectiveServiceManager() != 'systemd') {
      throw Exception('当前共享服务器未检测到 systemd，暂不支持自动创建托管服务');
    }
    final safeServiceName = serviceName.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final execLine = arguments == null || arguments.trim().isEmpty
        ? execStart.trim()
        : '${execStart.trim()} ${arguments.trim()}';
    final logDirective = logPath != null && logPath.trim().isNotEmpty
        ? '\nStandardOutput=append:${logPath.trim()}\nStandardError=append:${logPath.trim()}'
        : '';
    final serviceContent = '''
[Unit]
Description=${description.trim().isEmpty ? safeServiceName : description.trim()}
After=network.target

[Service]
Type=simple
WorkingDirectory=${workingDirectory.trim()}
ExecStart=$execLine
Restart=always$logDirective

[Install]
WantedBy=multi-user.target
''';
    final encoded = base64.encode(serviceContent.codeUnits);
    return executeSelectedCommand(
      'printf %s "$encoded" | base64 -d | tee "/etc/systemd/system/$safeServiceName.service" > /dev/null && systemctl daemon-reload && systemctl enable --now $safeServiceName.service',
      privileged: true,
    );
  }

  Future<String> manageContainerSelected({
    required String containerId,
    required String action,
  }) async {
    if (!isSharedSelection) {
      return _sshManager.manageContainer(containerId: containerId, action: action);
    }
    return executeSelectedCommand('docker $action $containerId', privileged: true);
  }

  Future<String> deleteImageSelected({required String imageId}) async {
    if (!isSharedSelection) {
      return _sshManager.deleteImage(imageId: imageId);
    }
    return executeSelectedCommand('docker rmi $imageId', privileged: true);
  }

  Future<String> manageFirewallSelected({
    required String action,
    String? port,
    String? protocol,
    String? source,
    String? ruleNumber,
    String? ruleAction,
  }) async {
    if (!isSharedSelection) {
      return _sshManager.manageFirewall(
        action: action,
        port: port,
        protocol: protocol,
        source: source,
        ruleNumber: ruleNumber,
        ruleAction: ruleAction,
      );
    }
    final firewallBackend = _effectiveFirewallBackend();
    final command = firewallBackend == 'firewalld'
        ? LinuxPlatformSupport.buildFirewalldCommand(
            action: action,
            port: port,
            protocol: protocol,
            source: source,
            ruleAction: ruleAction,
          )
        : LinuxPlatformSupport.buildUfwCommand(
            action: action,
            port: port,
            protocol: protocol,
            source: source,
            ruleNumber: ruleNumber,
            ruleAction: ruleAction,
          );
    return executeSelectedCommand(command, privileged: true);
  }

  String buildInstallToolCommand(String toolName) {
    return LinuxPlatformSupport.buildInstallCommand(
      packageManager: _effectivePackageManager(),
      toolName: toolName,
    );
  }

  String buildCheckToolCommand(String toolName) {
    switch (toolName) {
      case 'net-tools':
        return "sh -lc 'if command -v ifconfig >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1; then echo installed; fi'";
      case 'iproute2':
        return "sh -lc 'if command -v ip >/dev/null 2>&1; then echo installed; fi'";
      case 'pip':
        return "sh -lc 'if command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1; then echo installed; fi'";
      case 'nodejs':
        return "sh -lc 'if command -v node >/dev/null 2>&1 || command -v nodejs >/dev/null 2>&1; then echo installed; fi'";
      case 'ufw':
        return "sh -lc 'if command -v ufw >/dev/null 2>&1 || command -v firewall-cmd >/dev/null 2>&1; then echo installed; fi'";
      case 'uv':
        return "sh -lc 'if command -v uv >/dev/null 2>&1 || [ -x \"\$HOME/.local/bin/uv\" ]; then echo installed; fi'";
      default:
        return "sh -lc 'if command -v $toolName >/dev/null 2>&1; then echo installed; fi'";
    }
  }

  Future<String> installToolSelected(String toolName) async {
    final result = await executeSelectedCommand(
      buildInstallToolCommand(toolName),
      privileged: true,
    );
    final installed = await checkToolInstalledSelected(toolName);
    await _persistInstalledToolsForSelected({toolName: installed});
    return result;
  }

  Future<bool> checkToolInstalledSelected(String toolName) async {
    final result = await executeSelectedCommand(buildCheckToolCommand(toolName));
    return result.trim().contains('installed');
  }

  Map<String, bool> getSelectedInstalledToolsCache() {
    return Map<String, bool>.from(_currentCache?.installedTools ?? const <String, bool>{});
  }

  Future<Map<String, bool>> scanInstalledToolsSelected(
    Iterable<String> toolNames,
  ) async {
    final selected = selectedServer;
    if (selected == null) {
      throw Exception('请先选择服务器');
    }

    final results = <String, bool>{};
    for (final toolName in toolNames) {
      results[toolName] = await checkToolInstalledSelected(toolName);
    }
    await _persistInstalledToolsForSelected(results);
    return results;
  }

  Future<void> persistInstalledToolScanSelected(
    Map<String, bool> installedTools,
  ) async {
    await _persistInstalledToolsForSelected(installedTools);
  }

  Future<bool> _ensureSelectedLocalManagerConnected() async {
    if (isSharedSelection) {
      return true;
    }
    final selected = _selectedServer;
    if (selected == null) {
      throw Exception('No active server selected');
    }
    if (_sshManager.isConnected && _sshManager.currentServer?.id == selected.id) {
      return true;
    }
    final success = await _sshManager.connect(selected);
    if (!success) {
      throw Exception(_sshManager.errorMessage ?? 'SSH connection not established');
    }
    return true;
  }

  Future<void> _persistInstalledToolsForSelected(
    Map<String, bool> installedTools,
  ) async {
    final selected = selectedServer;
    if (selected == null || installedTools.isEmpty) {
      return;
    }
    final mergedInstalledTools = <String, bool>{
      ...?_currentCache?.installedTools,
      ...installedTools,
    };
    if (mergedInstalledTools.containsKey('docker')) {
      await _storageService.upsertCapability(
        serverId: selected.id,
        dockerInstalled: mergedInstalledTools['docker'],
        checkedAt: DateTime.now(),
      );
    }
    await _cacheService.updateCache(
      selected.id,
      installedTools: mergedInstalledTools,
    );
    if (selectedServer?.id == selected.id) {
      _currentCache = _cacheService.getCacheSync(selected.id);
    }
  }

  Future<void> _refreshSharedScope(
    RefreshScope scope, {
    String? filePath,
    required bool force,
  }) async {
    if (!isSharedSelection || _selectedSharedGroup == null || _selectedSharedServer == null) {
      return;
    }
    final group = _selectedSharedGroup!;
    final server = _selectedSharedServer!;
    final selectedId = _sharedSelectionDisplayId(group, server);
    final client = _selectedShareClient();
    _sharedConnected = true;
    switch (scope) {
      case RefreshScope.dashboard:
          final snapshot = await client.fetchDashboard(
            server.remoteServerId,
            serverName: server.displayName,
            sharedGroupId: group.id,
            sharedGroupName: group.displayName,
          );
          await _cacheService.updateCache(
          selectedId,
          systemInfo: snapshot.systemInfo,
          resourceUsage: snapshot.resourceUsage,
          );
          break;
      case RefreshScope.processes:
        final processes = await client.fetchProcesses(
          server.remoteServerId,
          serverName: server.displayName,
          sharedGroupId: group.id,
          sharedGroupName: group.displayName,
        );
        await _cacheService.updateCache(selectedId, processes: processes);
        break;
      case RefreshScope.ports:
        final ports = await client.fetchPorts(
          server.remoteServerId,
          serverName: server.displayName,
          sharedGroupId: group.id,
          sharedGroupName: group.displayName,
        );
        await _cacheService.updateCache(selectedId, ports: ports);
        break;
      case RefreshScope.services:
        final services = await client.fetchServices(
          server.remoteServerId,
          serverName: server.displayName,
          sharedGroupId: group.id,
          sharedGroupName: group.displayName,
        );
        await _cacheService.updateCache(selectedId, services: services);
        break;
      case RefreshScope.firewall:
        final firewall = await client.fetchFirewall(
          server.remoteServerId,
          serverName: server.displayName,
          sharedGroupId: group.id,
          sharedGroupName: group.displayName,
        );
        await _cacheService.updateCache(
          selectedId,
          firewallRules: firewall.$1,
          firewallEnabled: firewall.$2,
        );
        break;
      case RefreshScope.docker:
        final docker = await client.fetchDocker(
          server.remoteServerId,
          serverName: server.displayName,
          sharedGroupId: group.id,
          sharedGroupName: group.displayName,
        );
        await _storageService.upsertCapability(
          serverId: selectedId,
          dockerInstalled: docker.$3,
          checkedAt: DateTime.now(),
        );
        await _cacheService.updateCache(
          selectedId,
          dockerContainers: docker.$1,
          dockerImages: docker.$2,
        );
        break;
      case RefreshScope.files:
        final result = await client.listFilesSnapshot(
          serverId: server.remoteServerId,
          path: filePath ?? _currentCache?.currentPath ?? '/',
          serverName: server.displayName,
          sharedGroupId: group.id,
          sharedGroupName: group.displayName,
        );
        await _cacheService.updateCache(
          selectedId,
          files: result.files,
          currentPath: result.resolvedPath,
        );
        break;
    }
    _currentCache = await _cacheService.getCache(selectedId);
    if (force) {
      notifyListeners();
    }
  }

  Future<bool> _ensureSharedConnection({bool notifyOnFailure = true}) async {
    if (!isSharedSelection || _selectedSharedGroup == null) {
      return false;
    }
    final client = _selectedShareClient();
    try {
      final success = await client.healthCheck();
      _sharedConnected = success;
      _errorMessage = success ? '' : '共享侦听端口连接失败：${client.formatConnectionLabel()}';
      if (notifyOnFailure || success) {
        notifyListeners();
      }
      return success;
    } catch (error) {
      _sharedConnected = false;
      _errorMessage = error.toString();
      if (notifyOnFailure) {
        notifyListeners();
      }
      return false;
    }
  }

  Server _buildSharedDisplayServer(
    SharedGroupRecord group,
    SharedServerRecord server,
  ) {
    final cache = _cacheService.getCacheSync(_sharedSelectionDisplayId(group, server));
    return Server(
      id: _sharedSelectionDisplayId(group, server),
      name: server.displayName,
      ip: group.sourceHostIp,
      port: group.sourcePort,
      username: '',
      password: '',
      group: group.displayName,
      isOnline: _selectedSharedServer?.id == server.id ? _sharedConnected : false,
      osInfo: cache?.systemInfo?.osInfo,
      osId: cache?.systemInfo?.osId,
      osName: cache?.systemInfo?.osName,
      osVersion: cache?.systemInfo?.osVersion,
      osFamily: cache?.systemInfo?.osFamily,
      packageManager: cache?.systemInfo?.packageManager,
      serviceManager: cache?.systemInfo?.serviceManager,
      firewallBackend: cache?.systemInfo?.firewallBackend,
      kernelVersion: cache?.systemInfo?.kernelVersion,
      uptime: cache?.systemInfo?.uptime,
    );
  }

  String _effectivePackageManager() {
    final selected = selectedServer;
    return currentSystemInfo?.packageManager.isNotEmpty == true
        ? currentSystemInfo!.packageManager
        : (selected?.packageManager?.isNotEmpty == true ? selected!.packageManager! : 'apt');
  }

  String _effectiveServiceManager() {
    final selected = selectedServer;
    return currentSystemInfo?.serviceManager.isNotEmpty == true
        ? currentSystemInfo!.serviceManager
        : (selected?.serviceManager?.isNotEmpty == true ? selected!.serviceManager! : 'systemd');
  }

  String _effectiveFirewallBackend() {
    final selected = selectedServer;
    return currentSystemInfo?.firewallBackend.isNotEmpty == true
        ? currentSystemInfo!.firewallBackend
        : (selected?.firewallBackend?.isNotEmpty == true ? selected!.firewallBackend! : 'ufw');
  }

  Server? _findDuplicateServer(Server candidate, {String? ignoreId}) {
    final normalizedIp = candidate.ip.trim().toLowerCase();
    final normalizedUsername = candidate.username.trim().toLowerCase();
    for (final server in _servers) {
      if (ignoreId != null && server.id == ignoreId) {
        continue;
      }
      if (server.ip.trim().toLowerCase() == normalizedIp &&
          server.username.trim().toLowerCase() == normalizedUsername) {
        return server;
      }
    }
    return null;
  }

  Future<void> _detectAndPersistServerPlatform(String serverId) async {
    final index = _servers.indexWhere((server) => server.id == serverId);
    if (index == -1) {
      return;
    }
    final server = _servers[index];
    final tempManager = SshManager();
    try {
      final connected = await tempManager.connect(server);
      if (!connected) {
        return;
      }
      final systemInfo = await tempManager.getSystemInfo();
      final updatedServer = server.copyWith(
        osInfo: systemInfo.osInfo,
        osId: systemInfo.osId,
        osName: systemInfo.osName,
        osVersion: systemInfo.osVersion,
        osFamily: systemInfo.osFamily,
        packageManager: systemInfo.packageManager,
        serviceManager: systemInfo.serviceManager,
        firewallBackend: systemInfo.firewallBackend,
        kernelVersion: systemInfo.kernelVersion,
        uptime: systemInfo.uptime,
      );
      _servers[index] = updatedServer;
      if (_selectedServer?.id == updatedServer.id) {
        _selectedServer = updatedServer;
      }
      await _storageService.saveServers(_servers);
      notifyListeners();
    } catch (_) {
    } finally {
      tempManager.disconnect();
    }
  }

  Future<void> _completeLocalServerSelection(String serverId) async {
    try {
      await _storageService.saveSelectedServer(serverId);
      await _storageService.addUsageEvent(
        serverId: serverId,
        pageKey: 'server_switch',
      );
      final cache = await _cacheService.getCache(serverId);
      if (_selectedServer?.id != serverId) {
        return;
      }
      _currentCache = cache;
      await _loadAiSessions(notify: false);
      notifyListeners();
      await requestRefreshIfStale(
        _scopeForCurrentScreen(),
        reason: 'server-switch',
      );
    } catch (_) {}
  }

  Future<void> _completeSharedServerSelection(
    SharedGroupRecord group,
    SharedServerRecord server,
  ) async {
    final selectedId = _sharedSelectionDisplayId(group, server);
    try {
      await _storageService.saveSelectedServer(selectedId);
      final cache = await _cacheService.getCache(selectedId);
      if (_selectedSharedServer?.id != server.id ||
          _selectedSharedGroup?.id != group.id) {
        return;
      }
      _currentCache = cache;
      await _loadAiSessions(notify: false);
      notifyListeners();
      try {
        await requestRefreshIfStale(
          _scopeForCurrentScreen(),
          reason: 'shared-server-switch',
        );
      } catch (_) {
        // Shared selection can be imported before the source listener is reachable.
      }
    } catch (_) {}
  }

  String _sharedSelectionDisplayId(
    SharedGroupRecord group,
    SharedServerRecord server,
  ) {
    return 'shared::${group.id}::${server.id}';
  }

  (SharedGroupRecord, SharedServerRecord)? _resolveSharedSelectionByDisplayId(String displayId) {
    final parts = displayId.split('::');
    if (parts.length != 3) {
      return null;
    }
    final groupId = parts[1];
    final serverId = parts[2];
    for (final group in _sharedGroups) {
      if (group.id != groupId) {
        continue;
      }
      for (final server in group.servers) {
        if (server.id == serverId) {
          return (group, server);
        }
      }
    }
    return null;
  }

  void _restoreSharedSelection(String displayId) {
    final resolved = _resolveSharedSelectionByDisplayId(displayId);
    if (resolved == null) {
      return;
    }
    _selectedSharedGroup = resolved.$1;
    _selectedSharedServer = resolved.$2;
    _selectedServer = null;
  }

  ShareClient _selectedShareClient() {
    final group = _selectedSharedGroup!;
    final key = '${group.sourceHostIp}:${group.sourcePort}:${group.accessToken}';
    return _shareClients.putIfAbsent(
      key,
      () => ShareClient(
        baseUri: Uri.parse('http://${group.sourceHostIp}:${group.sourcePort}'),
        accessToken: group.accessToken,
      ),
    );
  }

  Future<AiCommandExecutor?> _buildAiExecutorForCurrentSelection(
    String expectedServerId,
  ) async {
    if (isSharedSelection) {
      final group = _selectedSharedGroup;
      final server = _selectedSharedServer;
      if (group == null || server == null) {
        _errorMessage = '共享服务器上下文缺失';
        notifyListeners();
        return null;
      }
      final ready = await _ensureSharedConnection();
      if (!ready) {
        return null;
      }
      return SharedAiCommandExecutor(
        runCommand: ({
          required String command,
          required bool privileged,
        }) {
          return _selectedShareClient().executeCommand(
            serverId: server.remoteServerId,
            command: command,
            privileged: privileged,
            userShell: true,
            serverName: server.displayName,
            sharedGroupId: group.id,
            sharedGroupName: group.displayName,
          );
        },
      );
    }

    final localServer = _selectedServer;
    if (localServer == null || localServer.id != expectedServerId) {
      _errorMessage = '请先选择服务器';
      notifyListeners();
      return null;
    }
    final sessionManager = SshManager();
    if (!(sessionManager.isConnected &&
        sessionManager.currentServer?.id == localServer.id)) {
      final connected = await sessionManager.connect(localServer);
      if (!connected) {
        _errorMessage = sessionManager.errorMessage ?? 'SSH 连接失败';
        notifyListeners();
        return null;
      }
    }
    return LocalAiCommandExecutor(sessionManager);
  }

  AiAuditLogger? _buildAiAuditLoggerForCurrentSelection() {
    if (!isSharedSelection) {
      return null;
    }
    final group = _selectedSharedGroup;
    final server = _selectedSharedServer;
    if (group == null || server == null) {
      return null;
    }
    return ({
      required String action,
      required String summary,
      String detail = '',
      bool success = true,
    }) async {
      await _selectedShareClient().logRemoteAudit(
        category: RemoteAuditCategory.ai,
        action: action,
        summary: summary,
        detail: detail,
        serverId: server.remoteServerId,
        serverName: server.displayName,
        sharedGroupId: group.id,
        sharedGroupName: group.displayName,
        success: success,
      );
      await refreshRemoteControlState(notify: false);
    };
  }

  String _generateAccessTokenValue(DateTime timestamp) {
    final micros = timestamp.microsecondsSinceEpoch.toRadixString(36);
    final millis = timestamp.millisecondsSinceEpoch.toRadixString(36);
    return 'sg_${micros}_$millis';
  }

  Future<void> _enforceRuntimeLimits() async {
    await _trimManagedResourcesToLimit();
    await _enforceActiveAccessTokenLimit();
  }

  Future<void> _trimManagedResourcesToLimit() async {
    if (totalManagedServerCount <= maxManagedServerCount) {
      return;
    }

    var nextServers = List<Server>.from(_servers);
    var nextSharedGroups = List<SharedGroupRecord>.from(_sharedGroups);
    final removedServerIds = <String>[];
    final removedSharedGroupIds = <String>[];

    int currentTotal() {
      return nextServers.length +
          nextSharedGroups.fold<int>(0, (sum, group) => sum + group.servers.length);
    }

    while (currentTotal() > maxManagedServerCount && nextServers.isNotEmpty) {
      nextServers.sort((a, b) => _serverSortValue(b).compareTo(_serverSortValue(a)));
      final removed = nextServers.removeAt(0);
      removedServerIds.add(removed.id);
    }

    while (currentTotal() > maxManagedServerCount && nextSharedGroups.isNotEmpty) {
      nextSharedGroups.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      final removed = nextSharedGroups.removeAt(0);
      removedSharedGroupIds.add(removed.id);
    }

    if (removedServerIds.isEmpty && removedSharedGroupIds.isEmpty) {
      return;
    }

    _servers = nextServers;
    _sharedGroups = nextSharedGroups;
    await _storageService.saveServers(_servers);
    for (final serverId in removedServerIds) {
      await _cacheService.invalidateCache(serverId);
    }
    for (final groupId in removedSharedGroupIds) {
      await _storageService.deleteImportedSharedGroup(groupId);
    }
  }

  Future<void> _enforceActiveAccessTokenLimit() async {
    final activeTokens = _accessTokens
        .where((token) => !token.isExpired && !token.isRevoked)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final overflowCount = activeTokens.length - maxConcurrentAccessTokenCount;
    if (overflowCount <= 0) {
      return;
    }
    for (final token in activeTokens.take(overflowCount)) {
      await _storageService.revokeAccessToken(token.id);
    }
    _accessTokens = await _storageService.loadAccessTokens();
  }

  BigInt _serverSortValue(Server server) {
    final numericId = BigInt.tryParse(server.id.trim());
    if (numericId != null) {
      return numericId;
    }
    return BigInt.zero;
  }

  @override
  void dispose() {
    _dbRefreshTimer?.cancel();
    _sshEngine.dispose();
    unawaited(_shareListenerService.stop());
    _sshManager.disconnect();
    for (final client in _shareClients.values) {
      unawaited(client.closeConnectionMarker());
    }
    for (final manager in _aiSessionManagers.values) {
      manager.disconnect();
    }
    super.dispose();
  }
}

extension on Iterable<SharedGroupRecord> {
  SharedGroupRecord? get firstOrNull => isEmpty ? null : first;
}
