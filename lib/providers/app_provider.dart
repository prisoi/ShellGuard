import 'dart:convert';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/refresh_scope.dart';
import '../core/ssh_engine.dart';
import '../core/ssh_manager.dart';
import '../models/cache_data.dart';
import '../models/server.dart';
import '../models/share_listener_config.dart';
import '../models/shared_server_models.dart';
import '../services/ai_assistant_service.dart';
import '../services/cache_service.dart';
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
  static const int freeServerLimit = 10;

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
  bool get canAddMoreServers => _servers.length < freeServerLimit;
  String get currentScreen => _currentScreen;
  List<LlmProviderConfig> get llmProviders => _llmProviders;
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
          subtitle: server.ip,
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
            subtitle: '${group.displayName} @ ${group.sourceHostIp}:${group.sourcePort}',
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
      _servers = await _storageService.loadServers();
      _groups = await _storageService.loadGroups();
      _sharedGroups = await _storageService.loadImportedSharedGroups();
      _shareListenerConfig = await _storageService.loadShareListenerConfig();
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
      _errorMessage = '个人免费版最多支持 10 台服务器';
      notifyListeners();
      return;
    }

    _servers.add(server);
    await _storageService.saveServers(_servers);
    await _ensureGroupExists(server.group);
    notifyListeners();
  }

  Future<void> updateServer(Server updatedServer) async {
    final index = _servers.indexWhere((s) => s.id == updatedServer.id);
    if (index != -1) {
      _servers[index] = updatedServer;
      if (_selectedServer?.id == updatedServer.id) {
        _selectedServer = updatedServer;
      }
      await _storageService.saveServers(_servers);
      await _ensureGroupExists(updatedServer.group);
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
    await _storageService.saveSelectedServer(server.id);
    await _storageService.addUsageEvent(serverId: server.id, pageKey: 'server_switch');
    _currentCache = await _cacheService.getCache(server.id);
    await _loadAiSessions(notify: false);
    notifyListeners();
    await requestRefreshIfStale(_scopeForCurrentScreen(), reason: 'server-switch');
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
    await _storageService.saveSelectedServer(_sharedSelectionDisplayId(group, server));
    _currentCache = await _cacheService.getCache(
      _sharedSelectionDisplayId(group, server),
    );
    await _loadAiSessions(notify: false);
    notifyListeners();
    try {
      await requestRefreshIfStale(
        _scopeForCurrentScreen(),
        reason: 'shared-server-switch',
      );
    } catch (_) {
      // Shared selection can be imported before the source listener is reachable.
      // Keep the selection but avoid surfacing an uncaught async framework error.
    }
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
    if (isSharedSelection) {
      _errorMessage = '共享服务器暂不支持 AI 助力，请在源端直接使用。';
      notifyListeners();
      return false;
    }
    final server = _selectedServer;
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
      final sessionManager = SshManager();
      final connected = await sessionManager.connect(server);
      if (!connected) {
        _errorMessage = sessionManager.errorMessage ?? 'SSH 连接失败';
        notifyListeners();
        return false;
      }
      final snapshot = await _aiAssistantService.createSession(
        server: server,
        provider: llmProvider,
        sshManager: sessionManager,
        initialPrompt: prompt,
        onChanged: _syncAiRuntimeState,
      );
      _aiSessionManagers[snapshot.session.id] = sessionManager;
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
    if (isSharedSelection) {
      _errorMessage = '共享服务器暂不支持 AI 助力，请在源端直接使用。';
      notifyListeners();
      return;
    }
    final server = _selectedServer;
    final llmProvider = defaultLlmProvider;
    if (server == null || llmProvider == null) {
      return;
    }
    final sessionManager = SshManager();
    final connected = await sessionManager.connect(server);
    if (!connected) {
      _errorMessage = sessionManager.errorMessage ?? 'SSH 连接失败';
      notifyListeners();
      return;
    }
    final snapshot = await _aiAssistantService.createSession(
      server: server,
      provider: llmProvider,
      sshManager: sessionManager,
      onChanged: _syncAiRuntimeState,
    );
    _aiSessionManagers[snapshot.session.id] = sessionManager;
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
      final existingManager = _aiSessionManagers[sessionId];
      if (existingManager != null &&
          existingManager.isConnected &&
          existingManager.currentServer?.id == server.id) {
        return true;
      }
    }

    var sessionManager = _aiSessionManagers[sessionId];
    sessionManager ??= SshManager();
    if (!(sessionManager.isConnected && sessionManager.currentServer?.id == server.id)) {
      final connected = await sessionManager.connect(server);
      if (!connected) {
        _errorMessage = sessionManager.errorMessage ?? 'SSH 连接失败';
        notifyListeners();
        return false;
      }
    }
    _aiSessionManagers[sessionId] = sessionManager;

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
      sshManager: sessionManager,
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
    String? displayNameOverride,
  }) async {
    final group = await _storageService.importSharedGroupFromJson(
      filePath: filePath,
      displayNameOverride: displayNameOverride,
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
  }) async {
    final client = ShareClient(
      baseUri: Uri.parse('http://$host:$port'),
    );
    final success = await client.healthCheck();
    return success;
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
      );
    }
    if (privileged) {
      return _sshManager.executePrivilegedCommand(command);
    }
    if (userShell) {
      return _sshManager.executeUserCommand(command);
    }
    return _sshManager.executeCommand(command);
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
      );
    }
    return _sshManager.writeFile(path, content);
  }

  Future<String> deleteFileSelected(String path) async {
    if (isSharedSelection) {
      return _selectedShareClient().deleteFile(
        serverId: _selectedSharedServer!.remoteServerId,
        path: path,
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
    return executeSelectedCommand(
      'systemctl $action $serviceName.service',
      privileged: true,
    );
  }

  Future<String> getServiceLogsSelected(String serviceName, {int lines = 80}) async {
    if (!isSharedSelection) {
      return _sshManager.getServiceLogs(serviceName, lines: lines);
    }
    return executeSelectedCommand(
      'journalctl -u $serviceName.service -n $lines --no-pager 2>/dev/null',
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
    final normalizedPort = port?.trim();
    final normalizedProtocol = protocol?.trim().toLowerCase();
    final normalizedSource = source?.trim();
    final ruleVerb = ruleAction?.trim().toLowerCase() ?? 'allow';
    String command = 'ufw ';
    String buildRuleCommand(String verb) {
      if (normalizedSource != null && normalizedSource.isNotEmpty) {
        if (normalizedPort != null && normalizedPort.isNotEmpty) {
          return '$verb from $normalizedSource to any port $normalizedPort${normalizedProtocol == null || normalizedProtocol.isEmpty ? '' : ' proto $normalizedProtocol'}';
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
        command += 'enable';
        break;
      case 'disable':
        command += 'disable';
        break;
      case 'allow':
        command += buildRuleCommand('allow');
        break;
      case 'deny':
        command += buildRuleCommand('deny');
        break;
      case 'delete':
        if (ruleNumber != null) {
          command += '--force delete $ruleNumber';
        } else {
          command += 'delete ${buildRuleCommand(ruleVerb)}';
        }
        break;
      case 'reset':
        command += 'reset';
        break;
      default:
        throw Exception('Unknown firewall action');
    }
    return executeSelectedCommand(command, privileged: true);
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
        final snapshot = await client.fetchDashboard(server.remoteServerId);
        await _cacheService.updateCache(
          selectedId,
          systemInfo: snapshot.systemInfo,
          resourceUsage: snapshot.resourceUsage,
        );
        break;
      case RefreshScope.processes:
        final processes = await client.fetchProcesses(server.remoteServerId);
        await _cacheService.updateCache(selectedId, processes: processes);
        break;
      case RefreshScope.ports:
        final ports = await client.fetchPorts(server.remoteServerId);
        await _cacheService.updateCache(selectedId, ports: ports);
        break;
      case RefreshScope.services:
        final services = await client.fetchServices(server.remoteServerId);
        await _cacheService.updateCache(selectedId, services: services);
        break;
      case RefreshScope.firewall:
        final firewall = await client.fetchFirewall(server.remoteServerId);
        await _cacheService.updateCache(
          selectedId,
          firewallRules: firewall.$1,
          firewallEnabled: firewall.$2,
        );
        break;
      case RefreshScope.docker:
        final docker = await client.fetchDocker(server.remoteServerId);
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
      kernelVersion: cache?.systemInfo?.kernelVersion,
      uptime: cache?.systemInfo?.uptime,
    );
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
    final key = '${group.sourceHostIp}:${group.sourcePort}';
    return _shareClients.putIfAbsent(
      key,
      () => ShareClient(
        baseUri: Uri.parse('http://${group.sourceHostIp}:${group.sourcePort}'),
      ),
    );
  }

  @override
  void dispose() {
    _dbRefreshTimer?.cancel();
    _sshEngine.dispose();
    unawaited(_shareListenerService.stop());
    _sshManager.disconnect();
    for (final manager in _aiSessionManagers.values) {
      manager.disconnect();
    }
    super.dispose();
  }
}

extension on Iterable<SharedGroupRecord> {
  SharedGroupRecord? get firstOrNull => isEmpty ? null : first;
}
