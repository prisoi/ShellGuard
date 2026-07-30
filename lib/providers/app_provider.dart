import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/refresh_scope.dart';
import '../core/ssh_engine.dart';
import '../core/ssh_manager.dart';
import '../models/cache_data.dart';
import '../models/server.dart';
import '../services/ai_assistant_service.dart';
import '../services/cache_service.dart';
import '../services/llm_service.dart';
import '../services/storage_service.dart';

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

class AppProvider extends ChangeNotifier {
  static const int freeServerLimit = 10;

  List<Server> _servers = [];
  Server? _selectedServer;
  bool _isLoading = false;
  String _errorMessage = '';
  final SshManager _sshManager = SshManager();
  final StorageService _storageService = StorageService();
  late final CacheService _cacheService;
  late final SshEngine _sshEngine;
  late final LlmService _llmService;
  late final AiAssistantService _aiAssistantService;
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

  List<Server> get servers => _servers;
  Server? get selectedServer => _selectedServer;
  bool get isConnected {
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
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _servers = await _storageService.loadServers();
      _groups = await _storageService.loadGroups();
      final selectedId = await _storageService.loadSelectedServer();

      if (_groups.isEmpty) {
        _groups = ['默认分组'];
      }

      if (selectedId != null) {
        for (final server in _servers) {
          if (server.id == selectedId) {
            _selectedServer = server;
            break;
          }
        }
      } else if (_servers.isNotEmpty) {
        _selectedServer = _servers.first;
      }

      if (_selectedServer != null) {
        _currentCache = await _cacheService.getCache(_selectedServer!.id);
      }
      _llmProviders = await _storageService.loadLlmProviderConfigs();
      await _loadAiSessions(notify: false);
      _sshEngine.start();
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
    _activeAiSessionId = null;
    _sshEngine.rememberServer(server);
    await _storageService.saveSelectedServer(server.id);
    await _storageService.addUsageEvent(serverId: server.id, pageKey: 'server_switch');
    _currentCache = await _cacheService.getCache(server.id);
    await _loadAiSessions(notify: false);
    notifyListeners();
    await requestRefreshIfStale(_scopeForCurrentScreen(), reason: 'server-switch');
  }

  Future<bool> connectToServer() async {
    if (_selectedServer == null) {
      _errorMessage = '请先选择服务器';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _errorMessage = '';
    notifyListeners();

    final success = await _sshManager.connect(_selectedServer!);

    if (success) {
      await _updateSelectedServerOnlineStatus(true);
      _sshEngine.rememberServer(_selectedServer!);
      await _sshEngine.ensureConnected(_selectedServer!);
      await requestRefreshNow(RefreshScope.dashboard, reason: 'manual-connect');
      await reloadServers(notify: false);
      await reloadSelectedServerCache(notify: false);
    } else {
      _errorMessage = _sshManager.errorMessage ?? '连接失败';
      await _updateSelectedServerOnlineStatus(false);
    }

    _isLoading = false;
    notifyListeners();
    return success;
  }

  Future<bool> ensureTerminalConnection() async {
    if (_selectedServer == null) {
      _errorMessage = '请先选择服务器';
      notifyListeners();
      return false;
    }

    if (_sshManager.isConnected &&
        _sshManager.currentServer?.id == _selectedServer!.id) {
      return true;
    }

    final success = await _sshManager.connect(_selectedServer!);
    if (success) {
      _errorMessage = '';
      await _updateSelectedServerOnlineStatus(true);
    } else {
      _errorMessage = _sshManager.errorMessage ?? '连接失败';
      await _updateSelectedServerOnlineStatus(false);
    }
    notifyListeners();
    return success;
  }

  void disconnect() {
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
    if (_selectedServer == null) {
      return;
    }

    await _storageService.saveOperationLog(
      OperationLog(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        command: command,
        serverId: _selectedServer!.id,
        serverName: _selectedServer!.name,
        timestamp: DateTime.now(),
        result: result,
      ),
    );
  }

  Future<List<OperationLog>> loadRecentLogs({int limit = 50}) async {
    return _storageService.loadRecentOperationLogs(
      serverId: _selectedServer?.id,
      limit: limit,
    );
  }

  Future<void> reloadSelectedServerCache({bool notify = true}) async {
    if (_selectedServer == null) {
      return;
    }
    _currentCache = await _cacheService.getCache(_selectedServer!.id);
    if (notify) {
      notifyListeners();
    }
  }

  Future<void> reloadServers({bool notify = true}) async {
    _servers = await _storageService.loadServers();
    _groups = await _storageService.loadGroups();
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
    if (_selectedServer == null) {
      return;
    }
    _currentScreen = scope.key;
    await _storageService.addUsageEvent(serverId: _selectedServer!.id, pageKey: scope.key);
    await reloadSelectedServerCache(notify: false);
    notifyListeners();
    await requestRefreshIfStale(scope, reason: 'page-enter', filePath: filePath);
  }

  Future<void> requestRefreshIfStale(
    RefreshScope scope, {
    required String reason,
    String? filePath,
  }) async {
    if (_selectedServer == null) {
      return;
    }
    final serverId = _selectedServer!.id;
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
    if (_selectedServer == null) {
      return;
    }
    final serverId = _selectedServer!.id;
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
    final currentServerId = _selectedServer?.id;
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
      if (_selectedServer?.id != serverId) {
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

  @override
  void dispose() {
    _dbRefreshTimer?.cancel();
    _sshEngine.dispose();
    _sshManager.disconnect();
    for (final manager in _aiSessionManagers.values) {
      manager.disconnect();
    }
    super.dispose();
  }
}
